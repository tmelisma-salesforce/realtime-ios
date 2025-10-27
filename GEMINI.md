# GEMINI.md: Project Overview and Development Guide

## Project Overview

This is a native iOS application written in Swift that demonstrates a real-time integration with the Salesforce platform using the Pub/Sub API. The application subscribes to Salesforce events (e.g., Change Data Capture events or Platform Events) and displays them in real-time.

The core of the application is a robust client for the Salesforce Pub/Sub API, built with modern Swift practices.

### Key Technologies

*   **Swift:** The application is written entirely in Swift.
*   **Salesforce Mobile SDK for iOS:** Used for authentication (OAuth 2.0) and managing user sessions.
*   **gRPC (grpc-swift):** The project uses a modern, `async/await`-based gRPC client (`grpc-swift-2`) to communicate with the Salesforce Pub/Sub API. This is the transport layer for receiving events.
*   **Apache Avro (SwiftAvroCore):** Event payloads from the Pub/Sub API are serialized using Avro. The project uses a third-party library to decode these binary payloads into Swift structs.
*   **CocoaPods:** Used for managing iOS dependencies, particularly the Salesforce Mobile SDK.

### Architecture

The application follows a clean, modern architecture:

*   **`PubSubClientManager.swift`:** A singleton class that acts as the central hub for all Pub/Sub API communication. It manages the lifecycle of the gRPC client, handles connection setup, and provides methods for subscribing to topics and fetching schemas.
*   **`AuthInterceptor`:** A gRPC client interceptor that automatically injects the required Salesforce authentication metadata (`accesstoken`, `instanceurl`, `tenantid`) into every outgoing RPC call.
*   **`SWIFT_SALESFORCE_PUBSUB.md` & `PUBSUB_GUIDE.md`:** These are exhaustive internal documentation files that serve as the primary technical guides for the project's architecture. They detail the entire Pub/Sub API flow, from authentication to event deserialization. **Any developer working on this project should consider these required reading.**

## Building and Running

### 1. Prerequisites

*   Xcode
*   CocoaPods (`sudo gem install cocoapods`)
*   A Salesforce org with a "Connected App" configured for mobile OAuth.

### 2. Install Dependencies

The project uses CocoaPods to integrate the Salesforce Mobile SDK.

```bash
# From the project root directory
pod install
```

This will create a `Realtime.xcworkspace` file.

### 3. Open and Run

*   Open the project in Xcode using the **`Realtime.xcworkspace`** file (do not use the `.xcodeproj` file).
*   Select a target device or simulator.
*   Run the application (Cmd+R).

The app will launch and present a Salesforce login screen. You must log in to a Salesforce org to authorize the app.

## Development Conventions

### Code Generation (gRPC)

The gRPC client code is generated from the `pubsub_api.proto` file. If you need to regenerate the code (e.g., after updating the `.proto` file), use the following command (requires `protoc` and `grpc-swift` to be installed, e.g., via Homebrew):

```bash
protoc pubsub_api.proto \
  --proto_path=. \
  --swift_out=./Realtime/Generated/ \
  --grpc-swift_out=Client=true,Server=false:./Realtime/Generated/
```

### Concurrency

The project uses modern Swift Concurrency (`async/await`). All asynchronous operations, especially the long-lived gRPC streams, are managed within `Task`s.

### Dependency Management

*   **Salesforce SDK:** The Salesforce Mobile SDK is referenced via `package.json` and integrated into the project via the `install.js` script and CocoaPods (`Podfile`).
*   **Other iOS Pods:** The `Podfile` manages all other dependencies.

### Authentication

Authentication is handled by the Salesforce Mobile SDK. The `PubSubClientManager` and its `AuthInterceptor` are responsible for extracting the necessary credentials (`accessToken`, `instanceUrl`, `orgId`) from the SDK and applying them to gRPC calls.

### Documentation

The project contains extremely detailed markdown files (`SWIFT_SALESFORCE_PUBSUB.md` and `PUBSUB_GUIDE.md`) that explain the "why" and "how" of the implementation. These are the first place to look for answers about the architecture and the Pub/Sub API.
