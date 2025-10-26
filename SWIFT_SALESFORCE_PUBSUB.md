# **Integrating iOS Applications with Salesforce Pub/Sub: A Definitive Guide to gRPC and Avro in Swift**

## **Executive Summary**

This report provides an exhaustive technical guide for iOS and Swift developers tasked with integrating the Salesforce Pub/Sub API. It delivers a comprehensive analysis of the required technologies—gRPC for communication and Apache Avro for data serialization—and offers definitive recommendations for the most suitable libraries within the Swift ecosystem. The guide covers the entire implementation lifecycle, from initial project setup and code generation to advanced production-level concerns such as connection management, error handling, and stream reliability. By following this report, developers will be equipped to build a robust, performant, and maintainable client capable of subscribing to and publishing events from the Salesforce platform.

## **Introduction: Deconstructing the Salesforce Pub/Sub API Architecture**

This section will establish the foundational knowledge required to understand the API's design and its implications for a Swift client.

### **The Modernization of Salesforce Eventing**

The Salesforce Pub/Sub API represents a strategic architectural evolution, moving beyond legacy, HTTP/1.1-based protocols like CometD, which powers the older Streaming API. This new API is engineered for high-performance, scalable, and real-time event-driven integrations. It provides a single, unified interface for a trifecta of critical operations: publishing events, subscribing to event streams, and retrieving event schemas. This consolidation simplifies development by eliminating the need to interact with disparate REST and Streaming APIs for different aspects of event handling.

### **Core Technologies: gRPC and Apache Avro**

The performance and efficiency of the Pub/Sub API are rooted in its choice of two foundational open-source technologies: gRPC and Apache Avro.

#### **gRPC as the Transport Layer**

Salesforce selected gRPC as the Remote Procedure Call (RPC) framework for the Pub/Sub API to leverage its significant performance advantages over traditional REST-based communication. gRPC's architecture is built upon HTTP/2, which enables features critical for real-time data streaming:

* **Multiplexing:** Multiple RPC calls can operate concurrently over a single TCP connection, reducing connection overhead and improving network resource utilization.  
* **Binary Protocol:** Protocol Buffers, gRPC's default Interface Definition Language (IDL), are serialized into a compact binary format, leading to smaller payloads and faster transmission compared to text-based formats like JSON.  
* **Bidirectional Streaming:** gRPC natively supports long-lived, bidirectional streams where both the client and server can send a sequence of messages to each other independently. This is the mechanism that powers the Pub/Sub API's Subscribe and PublishStream functionalities.

For an iOS client, this means the entire communication model is dictated by the gRPC framework, from connection establishment to method invocation and stream management.

#### **Avro as the Serialization Format**

While gRPC uses Protocol Buffers to define the API service contract and the structure of its request and response messages, the actual event data payload is serialized using a different technology: Apache Avro. The payload field within the gRPC messages is an opaque binary blob encoded in the Avro format.  
Salesforce chose Avro for its distinct advantages in large-scale, event-driven systems:

* **Compact Binary Format:** Like Protobuf, Avro produces a small binary footprint, which is efficient for high-throughput event streaming.  
* **Rich Schema Definition:** Avro schemas are defined in JSON, providing a flexible and human-readable way to describe complex data structures.  
* **Schema Evolution:** Avro's most powerful feature is its robust support for schema evolution. It defines clear rules for how schemas can change over time (e.g., adding or removing fields) while maintaining backward and forward compatibility between producers and consumers. This is essential in an enterprise environment where event structures can evolve independently of client application release cycles.

### **The API Contract: pubsub\_api.proto Deep Dive**

The canonical definition of the Pub/Sub API service is contained within the pubsub\_api.proto file, which is publicly available in a Salesforce GitHub repository. This file defines the PubSub service and its four primary RPC methods, which form the complete set of operations a client can perform. Understanding these methods and their corresponding gRPC call types is the first step in designing a client application.  
**Table 1: Salesforce Pub/Sub API RPC Methods**

| RPC Method | gRPC Type | Request Message | Response Message | Primary Function & Key Insight |
| :---- | :---- | :---- | :---- | :---- |
| GetTopic | Unary | TopicRequest | TopicInfo | Retrieves topic metadata, including the crucial schema\_id for the latest event schema. This is the first step in the subscription process. |
| GetSchema | Unary | SchemaRequest | SchemaInfo | Retrieves the full Avro schema as a JSON string, using a schema\_id. This schema is mandatory for decoding event payloads. |
| Subscribe | Bidirectional Streaming | FetchRequest (stream) | FetchResponse (stream) | Establishes a long-lived connection to receive a stream of events. The client sends FetchRequests to control the flow of events (pull-based model). |
| Publish | Unary | PublishRequest | PublishResponse | Publishes a batch of one or more events in a single request-response cycle. |
| PublishStream | Bidirectional Streaming | PublishRequest (stream) | PublishResponse (stream) | Establishes a long-lived connection to publish a high-throughput stream of events. |

The API's design presents a clear workflow. A client wishing to subscribe must first perform two unary calls (GetTopic and GetSchema) to prepare for deserialization, and then initiate a long-lived bidirectional stream (Subscribe) to receive events. This multi-step process necessitates a client architecture capable of handling both simple request-response patterns and complex, persistent stream management.  
This architecture leads to a crucial realization for developers: building a Swift client for the Salesforce Pub/Sub API is not a single-library problem but a **two-library problem**. An effective solution requires the selection and integration of two distinct and unrelated technologies: a gRPC client library to handle the transport and RPC mechanics, and an Avro serialization library to handle the decoding of event payloads. These technologies are separate open-source projects with their own ecosystems and, as this report will show, their maturity and stability are not equal within the Swift ecosystem. This reality frames the entire challenge, necessitating separate, deep-dive analyses to select the best tool for each job.

## **Part I: Selecting the gRPC Framework for Swift**

This section provides a detailed analysis of the gRPC library landscape for Swift, culminating in a definitive recommendation for all new iOS projects.

### **The Evolution of gRPC in Swift: A Tale of Two Libraries**

The gRPC implementation for Swift has undergone a significant architectural evolution, resulting in two distinct major versions. Understanding their differences is critical for making an informed technology choice.

#### **grpc-swift (v1): The Legacy Library**

The original grpc-swift library provided the first official support for the protocol in the Swift language. Its architecture is based on a wrapper around the core gRPC C-library (grpc-core), which is the foundation for gRPC implementations in many languages. For concurrency, it was built upon SwiftNIO, Apple's low-level networking framework, and exposed an API based on callbacks and EventLoopFuture objects. While functional, this approach required developers to manage complex callback chains for asynchronous operations, a pattern that has been largely superseded in modern Swift.  
Crucially, this version is now officially in "maintenance mode." The project maintainers will only apply bug fixes and security patches, with no new feature development. Support for new versions of Swift will also diminish over time, making it an unsuitable choice for new, long-term projects.

#### **grpc-swift-2: The Modern, Idiomatic Choice**

Announced in early 2025, grpc-swift-2 represents a complete rethinking of the library, designed from the ground up for modern Swift development. It discards the C-library wrapper in favor of a pure Swift implementation built directly on top of SwiftNIO. This native architecture brings several key advantages:

* **First-Class Concurrency:** The most significant improvement is its full embrace of modern Swift Concurrency. The entire API is designed around async/await, which allows developers to write asynchronous networking code that reads like synchronous, sequential logic. This dramatically simplifies implementation, improves readability, and reduces the likelihood of common concurrency bugs compared to the callback-based model of v1.  
* **Improved Performance and Debugging:** A native Swift implementation is easier to debug and profile using standard Xcode tools. It also eliminates the performance overhead and potential interoperability friction associated with bridging between Swift and a C-library.  
* **Active Development:** As the current major version, grpc-swift-2 is actively developed and supported by engineers from Apple and the broader gRPC community, ensuring it will remain compatible with future language features and receive ongoing enhancements.

### **Comparative Analysis and Recommendation**

When comparing the two versions, grpc-swift-2 emerges as the unequivocally superior choice for any new project. The following table summarizes the key decision-making criteria.  
**Table 2: grpc-swift Version Comparison**

| Feature | grpc-swift (v1) | grpc-swift-2 | Recommendation & Rationale |
| :---- | :---- | :---- | :---- |
| **Architecture** | Wrapper around gRPC C-core | Native Swift, built on SwiftNIO | **grpc-swift-2**: A native implementation is easier to debug, offers better performance, and avoids potential interoperability issues with a C-library. |
| **Concurrency Model** | Callback-based (EventLoopFuture) | Modern Swift Concurrency (async/await) | **grpc-swift-2**: async/await is the idiomatic standard for modern Swift, leading to cleaner, more readable, and less error-prone code than nested callbacks. |
| **Maintenance Status** | Maintenance mode (bug/security fixes only) | Actively developed, current major version | **grpc-swift-2**: Choosing an actively developed library is critical for long-term project health, ensuring access to new features and compatibility with future Swift versions. |
| **Ease of Use** | Steeper learning curve for those unfamiliar with SwiftNIO | More expressive and seamless developer experience | **grpc-swift-2**: The API design is more intuitive for the average Swift developer, lowering the barrier to entry. |

### **The grpc-swift-2 Modular Ecosystem**

Another advantage of the modern library is its modular design. It is distributed as a collection of distinct Swift Packages, allowing developers to include only the components necessary for their application, which helps to keep the app's binary size smaller. The core packages relevant for a Salesforce Pub/Sub API client are:

* **grpc/grpc-swift-2:** This is the core package that provides the fundamental runtime abstractions and types, such as GRPCClient, RPCError, and the protocols for defining services. Its main product is the GRPCCore library.  
* **grpc/grpc-swift-nio-transport:** This package contains the high-performance client and server transport implementations built on SwiftNIO. For an iOS client, this provides the networking backbone for communicating with the Salesforce endpoint over HTTP/2. Its product is the GRPCNIOTransportHTTP2 library.  
* **grpc/grpc-swift-protobuf:** This package provides the integration with Apple's SwiftProtobuf library. It includes the protoc plugin required to generate the Swift client code from the pubsub\_api.proto file. Its product is GRPCProtobuf.

The adoption of grpc-swift-2 is not merely a dependency update but a paradigm shift that affects application architecture. The library's design is deeply integrated with Swift's Structured Concurrency model. In the v1 library, a developer could hold a reference to a streaming call object (e.g., ClientStreamingCall) as a class property and send messages on that stream from anywhere in the application in an unstructured manner.  
This is no longer possible in grpc-swift-2. The APIs for client-streaming and bidirectional-streaming RPCs are designed as closures that provide a "writer" or stream object whose lifetime is scoped to that closure. When the closure returns, the stream is automatically closed. This design enforces that long-running network operations are managed within a well-defined, structured Task context.  
For the Salesforce Pub/Sub API's Subscribe method, this has significant architectural implications. The entire logic for handling the bidirectional stream—sending FetchRequest messages and iterating over incoming FetchResponse messages—must be encapsulated within a single, long-running Task. If other parts of the application need to send a new FetchRequest on this stream (for example, to request more events), they cannot call a method on a stored object directly. Instead, they must communicate with the running Task, typically by feeding data into an AsyncStream that the Task is consuming. This enforces a clearer data flow and resource management model but requires developers to architect their client differently than they might have with older, unstructured concurrency patterns.

## **Part II: Navigating the Apache Avro Library Landscape in Swift**

This section provides a critical analysis of the available Apache Avro libraries for Swift, addressing the significant challenge of finding a reliable solution for this core dependency.

### **The State of Avro in the Swift Ecosystem**

A thorough investigation reveals a stark contrast between the gRPC and Avro ecosystems for Swift. While gRPC is well-supported with a modern, actively developed library, the same cannot be said for Avro. The Apache Software Foundation, which stewards the Avro project, does not provide an official implementation for the Swift language. The official Avro website and its primary source code repository list supported languages such as Java, Python, C\#, and C++, but Swift is conspicuously absent.  
This absence forces iOS developers to rely on third-party, community-maintained libraries, which introduces a level of risk and requires careful evaluation of their maturity, feature set, and maintenance status.

### **Market Analysis of Available Libraries**

The search for a viable Avro library in Swift yields a very limited set of options.

#### **BlueSteel**

The BlueSteel library, once part of the "Cleanroom Project" from Gilt Tech, is quickly identifiable as an obsolete and unusable option for any modern iOS project. Its documentation and CocoaPods specification explicitly state that it is compatible with **Swift 2.2** and requires Xcode 7.3 or higher. Given that modern development requires recent versions of Swift (e.g., Swift 5.6+ for grpc-swift concurrency features), BlueSteel is architecturally and syntactically incompatible and must be dismissed from consideration.

#### **SwiftAvroCore**

The primary and effectively only viable candidate for handling Avro serialization in a modern Swift application is SwiftAvroCore. An analysis of its repository and design reveals several key characteristics:

* **Modern Swift Compatibility:** The library is written for Swift 5 and supports Avro specification 1.8.2 and later, making it technically compatible with current development environments.  
* **Integration with Codable:** A significant design advantage of SwiftAvroCore is its deep integration with Swift's native Codable protocol. Instead of requiring developers to implement a custom conversion protocol, it allows standard Codable structs to be encoded to and decoded from the Avro binary format. This is a highly idiomatic approach that reduces boilerplate and integrates seamlessly with common Swift data modeling patterns.  
* **Self-Contained and Lightweight:** The library is designed to be portable and has no external dependencies other than the standard Foundation framework. This makes it easy to add to a project without introducing a complex dependency graph.  
* **Low Maintenance Activity:** The most significant concern with SwiftAvroCore is its maintenance status. It is a community project driven largely by a single contributor. As of late 2025, the last significant code update was approximately a year prior, and the project has a relatively low number of stars and forks on GitHub, suggesting limited community adoption and support.

### **Comparative Analysis and Recommendation**

The choice of an Avro library is less a comparison of options and more an assessment of the single available candidate.  
**Table 3: Swift Avro Library Evaluation**

| Criterion | BlueSteel | SwiftAvroCore | Recommendation & Rationale |
| :---- | :---- | :---- | :---- |
| **Swift Compatibility** | Swift 2.2 | Swift 5 | **SwiftAvroCore**: It is the only option compatible with modern Swift projects. BlueSteel is unusable. |
| **API Design** | Custom AvroValueConvertible protocol | Standard Codable protocol | **SwiftAvroCore**: Integration with Codable is highly idiomatic and requires less boilerplate, fitting naturally into modern Swift data models. |
| **Maintenance Status** | Abandoned (part of the inactive "Cleanroom Project") | Low activity; last major update \~1 year ago | **SwiftAvroCore (with caution)**: While not actively bustling with development, it is functional with modern Swift. The risk of it becoming unmaintained must be accepted. |
| **Dependencies** | Not specified, but legacy | Foundation only | **SwiftAvroCore**: Its lack of external dependencies makes it lightweight and easy to integrate. |

### **Recommendation and Risk Mitigation Strategy**

Based on this analysis, the only pragmatic recommendation is to use **SwiftAvroCore**. However, this recommendation comes with a strong and necessary advisory regarding the associated risks. For any production application, especially within an enterprise context, relying on a community-supported library with low maintenance activity for a mission-critical function like data serialization is a significant technical liability. The primary risks include:

1. **Lack of Support:** If bugs are discovered or if the library fails to handle edge cases in the Avro specification, there is no guarantee of a timely fix.  
2. **Future Incompatibility:** The library may break with future releases of the Swift language or Xcode, and without an active maintainer, the development team would be responsible for patching it.  
3. **Security:** Unmaintained code does not receive security audits or patches for potential vulnerabilities.

To address these risks, a proactive mitigation strategy is essential. It is strongly recommended that any team adopting SwiftAvroCore for a production system should:

1. **Fork the Repository:** Create a private fork of the SwiftAvroCore GitHub repository. This gives the team full control over the codebase, allowing them to apply patches, fix bugs, and ensure its continued compatibility with their toolchain.  
2. **Invest in Thorough Testing:** Implement a comprehensive suite of unit and integration tests specifically for the Avro deserialization logic. These tests should use known-good Avro binary payloads and schemas obtained directly from the Salesforce API to validate that SwiftAvroCore correctly decodes them into the expected Swift structs. This test suite will serve as a critical regression guard against any changes made to the forked library or updates to the Salesforce API's event schemas.

By accepting ownership of the library's maintenance, a development team can confidently leverage its functionality while insulating their project from the risks of relying on an unsupported open-source dependency.

## **Part III: Comprehensive Implementation Guide for iOS**

This section provides a step-by-step guide for implementing a Salesforce Pub/Sub API client in a Swift-based iOS application, integrating the recommended libraries and best practices.

### **Step 1: Project Setup and Code Generation**

The foundation of a gRPC client is the code generated from the service's .proto file. This process requires specific command-line tools.

#### **Tooling Installation**

The gRPC code generation process relies on protoc, the Protocol Buffer compiler, and two Swift-specific plugins. The most straightforward way to install these on macOS is via Homebrew.  
Open a terminal and run the following command:  
`brew install swift-protobuf grpc-swift`

This command installs protoc itself, along with protoc-gen-swift (for generating Protobuf message types) and protoc-gen-grpc-swift (for generating the gRPC client stub code).

#### **Obtaining the Proto File**

The next step is to obtain the API definition file. Download the pubsub\_api.proto file from the official Salesforce pub-sub-api GitHub repository. It is essential to use this official file as it is the single source of truth for the service contract.

#### **Generating Swift Code**

With the tools installed and the .proto file downloaded, you can now generate the required Swift source files. Navigate to the directory containing pubsub\_api.proto in your terminal and execute the following command. It is recommended to output the generated files into a dedicated subdirectory within your Xcode project, such as Generated/.  
`protoc pubsub_api.proto \`  
  `--proto_path=. \`  
  `--swift_out=./Generated/ \`  
  `--grpc-swift_out=Client=true,Server=false:./Generated/`

This command performs two actions:

1. \--swift\_out: Invokes the protoc-gen-swift plugin to create pubsub\_api.pb.swift. This file contains the Swift struct definitions corresponding to the message types in the .proto file (e.g., TopicRequest, FetchResponse).  
2. \--grpc-swift\_out: Invokes the protoc-gen-grpc-swift plugin to create pubsub\_api.grpc.swift. This file contains the client-side code, including a protocol defining the service (Eventbus\_v1\_PubSubClientProtocol) and an async client implementation (Eventbus\_v1\_PubSubAsyncClient) that you will use to make RPC calls. The Client=true,Server=false option ensures that only client-side code is generated.

#### **Adding to Xcode Project**

Finally, integrate the generated code and required packages into your Xcode project:

1. **Add Generated Files:** Drag the Generated folder containing the two new Swift files into your Xcode project navigator. Ensure that "Copy items if needed" is checked and that the files are added to your application's target.  
2. **Add Swift Package Dependencies:** In Xcode, go to File \> Add Packages... and add the following packages using their GitHub URLs:  
   * https://github.com/grpc/grpc-swift-2.git (for grpc-swift-2)  
   * https://github.com/lynixliu/SwiftAvroCore (for SwiftAvroCore)

Your project is now set up with the necessary dependencies and the generated API client code.

### **Step 2: Authentication and gRPC Client Configuration**

All calls to the Salesforce Pub/Sub API must be authenticated. This is accomplished by providing an OAuth 2.0 access token and other session information as metadata with each gRPC request.

#### **OAuth 2.0 Authentication**

Before interacting with the API, your application must obtain a valid OAuth 2.0 access token from Salesforce. The specifics of implementing an OAuth flow are extensive, but for a native iOS app, the **OAuth 2.0 User-Agent Flow** or **Web Server Flow** are appropriate choices. This involves setting up a "Connected App" in your Salesforce org, which will provide you with a Consumer Key (Client ID).  
To simplify this process in Swift, using a dedicated library such as OAuthSwift is highly recommended. It provides helpers for constructing the authorization URL, handling the callback, and exchanging the authorization code for an access token.  
Once the flow is complete, you will have three critical pieces of information:

1. The **Access Token**.  
2. The **Instance URL** (e.g., https://your-instance.my.salesforce.com).  
3. The **Organization ID** (Tenant ID).

These credentials must be sent with every gRPC request. Failure to provide valid authentication metadata is a common source of errors, resulting in an UNAUTHENTICATED status.

#### **Configuring the GRPCClient and Authentication Interceptor**

For performance, a single, long-lived GRPCClient instance should be created and shared throughout the application's lifecycle. This object manages the underlying HTTP/2 connection pool. A clean and reusable way to attach authentication headers to every outgoing request is to use a ClientInterceptor.  
Here is an example of setting up a shared client and an interceptor to handle authentication:  
`import GRPCCore`  
`import GRPCNIOTransportHTTP2`

`// A class to hold authentication credentials.`  
`// This should be populated after a successful OAuth flow.`  
`class SalesforceAuthManager {`  
    `static let shared = SalesforceAuthManager()`  
    `var accessToken: String?`  
    `var instanceURL: String?`  
    `var tenantID: String?`  
`}`

`// An interceptor to add Salesforce auth headers to each request.`  
`struct SalesforceAuthInterceptor: ClientInterceptor {`  
    `func intercept<Input, Output>(`  
        `request: ClientRequest<Input>,`  
        `context: ClientContext,`  
        `next: (ClientRequest<Input>, ClientContext) async throws -> ClientResponse<Output>`  
    `) async throws -> ClientResponse<Output> {`  
        `var context = context`  
          
        `// Add required metadata headers.`  
        `if let token = SalesforceAuthManager.shared.accessToken {`  
            `context.metadata["accesstoken"] = token`  
        `}`  
        `if let url = SalesforceAuthManager.shared.instanceURL {`  
            `context.metadata["instanceurl"] = url`  
        `}`  
        `if let tenant = SalesforceAuthManager.shared.tenantID {`  
            `context.metadata["tenantid"] = tenant`  
        `}`  
          
        `return try await next(request, context)`  
    `}`  
`}`

`// A singleton to manage the shared gRPC client.`  
`class GRPCClientManager {`  
    `static let shared = GRPCClientManager()`  
    `let client: GRPCClient`

    `private init() {`  
        `do {`  
            `// Configure the transport to connect to the Salesforce global endpoint.`  
            `let transport = try GRPCNIOTransport.HTTP2.Client(`  
                `target:.host("api.pubsub.salesforce.com", port: 443),`  
                `transportSecurity:.tls(),`  
                `eventLoopGroup:.singleton`  
            `)`

            `// Create the client with the auth interceptor in its pipeline.`  
            `self.client = GRPCClient(`  
                `transport: transport,`  
                `interceptors:`  
            `)`  
        `} catch {`  
            `fatalError("Failed to initialize gRPC client: \(error)")`  
        `}`  
    `}`  
`}`

This setup ensures that every RPC call made using GRPCClientManager.shared.client will automatically have the necessary authentication headers attached.

### **Step 3: The Full Subscription and Event Reception Lifecycle**

With the client configured, you can now implement the full sequence of operations to subscribe to an event stream. This entire process should be wrapped in a single async function, ideally managed by a long-running Task to handle the persistent stream.  
The following example demonstrates subscribing to a custom Platform Event named My\_Event\_\_e.  
`import GRPCCore`

`func subscribeToSalesforceEvents() async {`  
    `let grpcClient = GRPCClientManager.shared.client`  
    `let pubsubClient = Eventbus_v1_PubSubAsyncClient(wrapping: grpcClient)`  
    `let topicName = "/event/My_Event__e"`

    `do {`  
        `// 1. Get the schema ID for the topic.`  
        `print("Fetching topic info for \(topicName)...")`  
        `let topicRequest = Eventbus_v1_TopicRequest.with { $0.topicName = topicName }`  
        `let topicInfo = try await pubsubClient.getTopic(topicRequest)`  
        `let schemaId = topicInfo.schemaID`  
        `print("Received schema ID: \(schemaId)")`

        `// 2. Get the Avro schema JSON using the schema ID.`  
        `print("Fetching schema for ID: \(schemaId)...")`  
        `let schemaRequest = Eventbus_v1_SchemaRequest.with { $0.schemaID = schemaId }`  
        `let schemaInfo = try await pubsubClient.getSchema(schemaRequest)`  
        `let avroSchemaJSON = schemaInfo.schemaJSON`  
        `print("Successfully fetched Avro schema.")`

        `// 3. Initiate the bidirectional 'subscribe' stream.`  
        `let subscription = pubsubClient.subscribe()`

        `// 4. Send the initial FetchRequest to start receiving events.`  
        `// This establishes the topic for the stream and requests the first batch.`  
        `print("Sending initial FetchRequest...")`  
        `let initialFetchRequest = Eventbus_v1_FetchRequest.with {`  
            `$0.topicName = topicName`  
            `$0.numRequested = 5 // Request an initial batch of 5 events.`  
        `}`  
        `try await subscription.requestStream.send(initialFetchRequest)`

        `// 5. Asynchronously iterate over the response stream from the server.`  
        `print("Waiting for events...")`  
        `for try await response in subscription.responseStream {`  
            `// Check for keepalive messages (empty event batch)`  
            `if response.events.isEmpty && response.hasLatestReplayID {`  
                `print("Received keepalive message. Latest replay ID: \(response.latestReplayID)")`  
                `continue`  
            `}`  
              
            `print("Received \(response.events.count) events.")`  
            `for receivedEvent in response.events {`  
                `let payload = receivedEvent.event.payload`  
                `let replayId = receivedEvent.replayID`  
                  
                `// --- Deserialization logic (from Step 4) goes here ---`  
                `// For now, just print the payload size.`  
                `print("  - Event received with payload size: \(payload.count) bytes. Replay ID: \(replayId)")`  
            `}`  
              
            `// After processing a batch, you can request more events.`  
            `// This demonstrates the client-controlled flow control.`  
            `let subsequentFetchRequest = Eventbus_v1_FetchRequest.with {`  
                `$0.numRequested = 10 // Request another 10 events.`  
            `}`  
            `try await subscription.requestStream.send(subsequentFetchRequest)`  
        `}`

    `} catch let error as RPCError {`  
        `print("gRPC Error during subscription: \(error.code) - \(error.message)")`  
        `// Implement retry logic here (see Part IV).`  
    `} catch {`  
        `print("An unexpected error occurred: \(error)")`  
    `}`  
`}`

This function demonstrates the complete flow: two initial unary calls to get the schema, followed by the initiation of a bidirectional stream. The client sends FetchRequest messages to pull events from the server, and the for try await loop processes incoming FetchResponse messages asynchronously.

### **Step 4: Deserializing the Avro Payload with SwiftAvroCore**

The final and most critical step is to decode the binary payload received in each event. This requires the Avro schema (as a JSON string) fetched in the previous step and the SwiftAvroCore library.  
First, define a Swift struct that conforms to Decodable and matches the structure of your Salesforce Platform Event. Field names in the struct must match the name attributes in the Avro schema.  
`// Define a Swift struct matching the Platform Event's fields.`  
`// This must conform to Decodable to work with SwiftAvroCore.`  
`struct MyEventPayload: Decodable {`  
    `let CreatedDate: Double // Avro 'long' with 'timestamp-millis' logicalType maps to a numeric type`  
    `let CreatedById: String`  
    `let My_Custom_Field__c: String? // Use optional for fields that may not be present`  
`}`

Now, integrate the deserialization logic into the event processing loop from Step 3\.  
`import SwiftAvroCore`

`// Inside the 'for try await' loop from Step 3...`  
`for receivedEvent in response.events {`  
    `let payload = receivedEvent.event.payload`  
    `let replayId = receivedEvent.replayID`  
      
    `do {`  
        `// 1. Create an instance of the Avro handler.`  
        `let avro = Avro()`  
          
        `// 2. Decode the JSON schema string into a Schema object.`  
        `// This should be done once and cached for the schemaId.`  
        `let schema = try avro.decodeSchema(schema: avroSchemaJSON)`  
          
        `// 3. Decode the binary payload into your Codable Swift struct.`  
        `let decodedPayload: MyEventPayload = try avro.decode(from: payload, with: schema)`  
          
        `print("  - Successfully decoded event! Replay ID: \(replayId)")`  
        `print("    Custom Field Value: \(decodedPayload.My_Custom_Field__c?? "N/A")")`  
          
    `} catch {`  
        `print("  - Failed to decode Avro payload for replay ID \(replayId): \(error)")`  
        `// Handle deserialization errors, e.g., by logging or skipping the event.`  
    `}`  
`}`

This code snippet completes the integration. It uses SwiftAvroCore to first parse the schema string provided by Salesforce into an internal Schema representation. It then uses this schema object to decode the raw binary payload directly into an instance of the MyEventPayload struct, leveraging Swift's powerful Codable infrastructure.  
For Change Data Capture (CDC) events, be aware that some fields like changedFields are encoded as a space-efficient bitmap. The logic to decode these bitmaps must be ported from Salesforce's official Java or Python examples, as it is a platform-specific encoding convention rather than a standard Avro feature.

## **Part IV: Advanced Topics and Production Best Practices**

Moving from a working prototype to a production-ready application requires addressing reliability, performance, and error handling. This section covers advanced topics essential for building a robust Salesforce Pub/Sub API client.

### **gRPC Connection Management**

The underlying transport for gRPC is a persistent HTTP/2 connection capable of handling many concurrent RPCs (streams). Creating a new TCP connection and performing a TLS handshake for every RPC call is highly inefficient and will lead to poor performance and high resource consumption.  
Therefore, the best practice is to **create a single, long-lived GRPCClient instance that is shared across the entire application** for all communication with a given Salesforce endpoint. This instance should be initialized once when the application starts and reused for all subsequent RPC calls, regardless of the service or method being called.  
The GRPCNIOTransportHTTP2 transport used by grpc-swift-2 automatically manages a pool of connections. When you create a GRPCClient, you are creating a handle to this managed pool. You do not need to implement your own connection pooling logic; simply reusing the client instance is sufficient. The singleton pattern shown in the GRPCClientManager example in Part III is an effective way to implement this practice.

### **Stream Reliability and Keepalive**

Long-lived streaming connections, such as the one established by the Subscribe RPC, are vulnerable to premature termination by network intermediaries like proxies, load balancers, or NAT gateways. These devices often have idle timeout policies that will close a TCP connection if no data is transferred for a certain period (e.g., 5 minutes).  
To combat this, gRPC utilizes the HTTP/2 PING frame mechanism for **keepalive**. The client can be configured to periodically send a PING frame to the server. If the server responds with a PING acknowledgment, the connection is considered active, and idle timeouts are reset. The Salesforce Pub/Sub API server also sends its own keepalive messages in the form of an empty FetchResponse to keep the stream alive from its end.  
In grpc-swift, keepalive is configured on the client's transport. The grpc-swift (v1) documentation provides guidance on this, and the principles apply to v2's transport configuration. It is critical to configure this for the Subscribe stream.  
When configuring the GRPCNIOTransport, you can specify keepalive parameters. A sensible configuration might be to send a ping every 1-5 minutes.  
`// Example of keepalive configuration on the transport`  
`let keepalive = ClientConnectionKeepalive(`  
    `interval:.minutes(1), // Ping the server every minute`  
    `timeout:.seconds(10)  // Wait 10 seconds for the ping ack`  
`)`

`let transport = try GRPCNIOTransport.HTTP2.Client(`  
    `target:.host("api.pubsub.salesforce.com", port: 443),`  
    `transportSecurity:.tls(),`  
    `eventLoopGroup:.singleton,`  
    `keepalive: keepalive`  
`)`

It is important not to set the keepalive interval too aggressively (e.g., every few seconds), as some servers may interpret this as a denial-of-service attack and terminate the connection.

### **Error Handling and Retry Strategy**

Network connections are inherently unreliable, and RPC calls can fail for various transient reasons. A production client must be able to handle these failures gracefully and retry operations when appropriate.

#### **Handling RPCError**

In grpc-swift-2, all async RPC methods throw a typed RPCError upon failure. This error object contains valuable information for diagnostics and recovery :

* code: A GRPCCore.Status.Code enum value (e.g., .unavailable, .invalidArgument).  
* message: A descriptive error message from the server.  
* metadata: The response metadata (trailers) sent by the server with the error.

#### **Inspecting Salesforce-Specific Error Codes**

Salesforce provides additional, more specific error information in the error's metadata (trailers). The custom error code is attached under the key "error-code". Inspecting this value is crucial for implementing intelligent retry logic, as it provides more context than the general gRPC status code.  
For example, a gRPC status of .unavailable might be accompanied by a Salesforce error code of sfdc.platform.eventbus.grpc.service.unavailable, confirming a temporary server-side issue that is a good candidate for a retry.

#### **Implementing an Exponential Backoff Retry Strategy**

For transient errors, such as .unavailable or .resourceExhausted, the client should not retry immediately, as this can exacerbate server load. The recommended approach is an **exponential backoff** strategy, where the delay between retries increases exponentially with each failed attempt.  
Here is a conceptual Swift implementation for a retry mechanism around an async function:  
`func withRetries<T>(`  
    `maxAttempts: Int = 5,`  
    `initialDelay: Duration =.seconds(1),`  
    `maxDelay: Duration =.seconds(60),`  
    `multiplier: Double = 2.0,`  
    `operation: () async throws -> T`  
`) async throws -> T {`  
    `var currentAttempt = 1`  
    `var currentDelay = initialDelay`

    `while true {`  
        `do {`  
            `return try await operation()`  
        `} catch let error as RPCError {`  
            `// Only retry on specific transient error codes.`  
            `guard [.unavailable,.resourceExhausted].contains(error.code), currentAttempt < maxAttempts else {`  
                `throw error // Not a retriable error or max attempts reached.`  
            `}`

            `print("Attempt \(currentAttempt) failed with code \(error.code). Retrying in \(currentDelay)...")`  
              
            `// Apply jitter to avoid thundering herd problem.`  
            `let jitter = Duration.seconds(Double.random(in: -0.1...0.1))`  
            `try await Task.sleep(for: currentDelay + jitter)`

            `// Increase delay for next attempt.`  
            `currentAttempt += 1`  
            `let nextDelayInSeconds = Double(currentDelay.components.seconds) * multiplier`  
            `currentDelay =.seconds(min(nextDelayInSeconds, Double(maxDelay.components.seconds)))`  
        `}`  
    `}`  
`}`

`// Usage:`  
`// try await withRetries {`  
`//     try await subscribeToSalesforceEvents()`  
`// }`

This wrapper can be used to make the initial subscribeToSalesforceEvents call more resilient. When retrying a Subscribe call, it is essential to use the last successfully processed replayId to avoid receiving duplicate events. Errors like .invalidArgument (often caused by a corrupted or expired replay ID) should not be retried automatically; they indicate a logical error that needs to be addressed.

### **Avro Schema Evolution Best Practices**

Avro's strength is schema evolution, but the client application must be designed to handle it correctly to avoid runtime deserialization failures.

* **Do Not Hardcode Schemas:** The Avro schema for a given event topic can change. A client must not bundle a static .avsc file or hardcode a schema string. The correct practice is to always follow the GetTopic \-\> GetSchema flow to fetch the schema dynamically.  
* **Cache Schemas by ID:** The schema\_id uniquely identifies a version of a schema. A client should maintain an in-memory cache mapping schema\_id to the parsed Schema object. When an event arrives, its schema\_id can be checked against the cache. If a new ID is encountered, the client should pause processing for that topic and execute the GetSchema RPC to fetch and cache the new schema before proceeding.  
* **Design Codable Structs for Forward Compatibility:** To ensure that your app does not crash when a new field is added to an event, declare properties in your Swift Codable struct as Optional. When SwiftAvroCore encounters a field in the Avro payload that does not exist in the Swift struct, Codable's decoding mechanism will simply ignore it. Conversely, if a new field is added to the Salesforce event, making the corresponding property in your Swift struct optional will prevent decoding from failing if your app receives an older event that is missing that field.  
* **Avoid Breaking Changes:** Be aware of what constitutes a breaking change in Avro. Renaming a field or changing its type in a non-compatible way will cause deserialization to fail. While these changes are managed on the Salesforce side, understanding them helps in diagnosing deserialization errors.

## **Conclusion and Strategic Recommendations**

The Salesforce Pub/Sub API offers a powerful, modern mechanism for building event-driven iOS applications. A successful integration hinges on the correct selection and implementation of two key technologies: gRPC and Apache Avro.  
The analysis provides clear and definitive recommendations for Swift developers:

1. **For gRPC, grpc-swift-2 is the mandatory choice.** Its native Swift architecture, reliance on the modern async/await concurrency model, and active development status make it the only viable, production-ready option. Its predecessor, grpc-swift (v1), is in maintenance mode and should not be used for new projects.  
2. **For Apache Avro, SwiftAvroCore is the only functional library available in the Swift ecosystem.** Its integration with the native Codable protocol provides an idiomatic and developer-friendly API. However, its status as a community-maintained project with low development activity presents a significant dependency risk for enterprise applications.

Therefore, the final strategic outlook for teams building this integration is twofold. First, embrace the modern architecture of grpc-swift-2, including its enforcement of Structured Concurrency, to build a clean and maintainable networking layer. Second, mitigate the risks associated with the Avro dependency by taking ownership of it: fork the SwiftAvroCore repository, establish a comprehensive test suite based on actual Salesforce payloads, and be prepared to maintain it internally.  
By following this dual strategy—adopting the stable, modern gRPC framework while proactively managing the less mature Avro component—iOS development teams can confidently build robust, high-performance, and resilient applications that leverage the full power of the Salesforce Pub/Sub API.

#### **Works cited**

1\. Get Started | Pub/Sub API \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/intro.html 2\. gRPC, https://grpc.io/ 3\. Pub/Sub API as a gRPC API \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/grpc-api.html 4\. Core concepts, architecture and lifecycle \- gRPC, https://grpc.io/docs/what-is-grpc/core-concepts/ 5\. Pub/Sub API Features \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/pub-sub-features.html 6\. Event Data Serialization with Apache Avro | Use Pub/Sub API \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/event-avro-serialization.html 7\. Avro vs Protobuf: A Comparison of Two Popular Data Serialization Formats \- Wallarm, https://lab.wallarm.com/what/avro-vs-protobuf/ 8\. Schema Evolution and Compatibility for Schema Registry on Confluent Platform, https://docs.confluent.io/platform/current/schema-registry/fundamentals/schema-evolution.html 9\. Sample project to get started with the Pub/Sub API \- GitHub, https://github.com/forcedotcom/pub-sub-api 10\. Apache Avro, https://avro.apache.org/ 11\. NIO-based gRPC Swift \- Pitches, https://forums.swift.org/t/nio-based-grpc-swift/29396 12\. gRPC-Swift on CocoaPods.org, https://cocoapods.org/pods/gRPC-Swift 13\. The Swift language implementation of gRPC. \- GitHub, https://github.com/grpc/grpc-swift 14\. Introducing gRPC Swift 2, https://swift.org/blog/grpc-swift-2/ 15\. Swift | gRPC, https://grpc.io/docs/languages/swift/ 16\. grpc/grpc-swift-2 \- GitHub, https://github.com/grpc/grpc-swift-2 17\. gRPC Swift NIO Transport \- GitHub, https://github.com/grpc/grpc-swift-nio-transport 18\. gRPC Swift protobuf \- GitHub, https://github.com/grpc/grpc-swift-protobuf 19\. Releases · grpc/grpc-swift-protobuf \- GitHub, https://github.com/grpc/grpc-swift-protobuf/releases 20\. ClientStreaming in V2 \- gRPC Swift, https://forums.swift.org/t/clientstreaming-in-v2/80076 21\. Apache Avro is a data serialization system. \- GitHub, https://github.com/apache/avro 22\. BlueSteel on CocoaPods.org, https://cocoapods.org/pods/BlueSteel 23\. GitHub topics: codable | Ecosyste.ms: Repos, https://repos.ecosyste.ms/hosts/GitHub/topics/codable 24\. An implementation of Apache AVRO in swift 4+ \- SwiftNIO, https://forums.swift.org/t/an-implementation-of-apache-avro-in-swift-4/17305 25\. lynixliu/SwiftAvroCore: An implementation of Apache Avro ... \- GitHub, https://github.com/lynixliu/SwiftAvroCore 26\. gRPC and Server Side Swift: Getting Started \- Kodeco, https://www.kodeco.com/30342883-grpc-and-server-side-swift-getting-started 27\. Generate Code from the Proto File | Get Started | Pub/Sub API | Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/generate-code-proto-file.html 28\. OAuth Authorization Flows \- Salesforce Help, https://help.salesforce.com/s/articleView?language=en\_US\&id=remoteaccess\_oauth\_flows.htm\&type=5 29\. Authorize Apps with OAuth \- Salesforce Help, https://help.salesforce.com/s/articleView?id=xcloud.remoteaccess\_authenticate.htm\&language=en\_US\&type=5 30\. OAuth 2.0 Web Server Flow for Web App Integration \- Salesforce Help, https://help.salesforce.com/s/articleView?id=xcloud.remoteaccess\_oauth\_web\_server\_flow.htm\&language=en\_US\&type=5 31\. Salesforce OAuth2 Made Easy For Native iOS Apps | Salesforce ..., https://developer.salesforce.com/blogs/2015/03/salesforce-oauth-made-easy-native-ios-apps 32\. Handle Errors \- Pub/Sub API \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/handling-errors.html 33\. Salesforce PubSub API rejecting access token \- Stack Overflow, https://stackoverflow.com/questions/77819146/salesforce-pubsub-api-rejecting-access-token 34\. Transport Client and Authentication Interceptors in gRPC Swift v2, https://forums.swift.org/t/transport-client-and-authentication-interceptors-in-grpc-swift-v2/81342 35\. Pub/Sub API RPC Method Reference \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/references/methods/subscribe-rpc.html 36\. Pub/Sub API \- GetSchema RPC Method \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/references 37\. Step 5: Write Code That Publishes a Platform Event Message | Quick ..., https://developer.salesforce.com/docs/platform/pub-sub-api/guide/qs-publish.html 38\. Serialize and Deserialize Avro in Swift \- SSOJet, https://ssojet.com/serialize-and-deserialize/serialize-and-deserialize-avro-in-swift 39\. Event Deserialization Considerations | Use Pub/Sub API \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/event-deserialization-considerations.html 40\. GRPC Connection Management in Golang \- Stack Overflow, https://stackoverflow.com/questions/56067076/grpc-connection-management-in-golang 41\. Setup for establishing connection(s) in a multi-service client application using v2 · Issue \#2211 · grpc/grpc-swift \- GitHub, https://github.com/grpc/grpc-swift/issues/2211 42\. Keepalive \- gRPC, https://grpc.io/docs/guides/keepalive/ 43\. StreamingClientResponse · grpc-swift documentation \- Swiftinit, https://swiftinit.org/docs/grpc-swift/grpccore/streamingclientresponse 44\. Retry Long-Lived RPC Calls After an Error Occurs | Use Pub/Sub API \- Salesforce Developers, https://developer.salesforce.com/docs/platform/pub-sub-api/guide/retry-rpc-calls.html 45\. Transient fault handling with gRPC retries \- Microsoft Learn, https://learn.microsoft.com/en-us/aspnet/core/grpc/retries?view=aspnetcore-9.0 46\. Retry | gRPC, https://grpc.io/docs/guides/retry/ 47\. PubSub API Error subscribing from a replay Id \- Trailhead \- Salesforce, https://trailhead.salesforce.com/trailblazer-community/feed/0D54V00007T4IAfSAN 48\. Best Practices for Evolving Schemas in Schema Registry \- Solace Docs, https://docs.solace.com/Schema-Registry/schema-registry-best-practices.htm 49\. Schema Evolution in Data Pipelines: Tools, Versioning & Zero-Downtime, https://dataengineeracademy.com/module/best-practices-for-managing-schema-evolution-in-data-pipelines/