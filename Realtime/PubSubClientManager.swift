/*
Copyright (c) 2019-present, salesforce.com, inc. All rights reserved.

Redistribution and use of this software in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
* Redistributions of source code must retain the above copyright notice, this list of conditions
and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of
conditions and the following disclaimer in the documentation and/or other materials provided
with the distribution.
* Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
endorse or promote products derived from this software without specific prior written
permission of salesforce.com, inc.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

/// Manages the shared gRPC client for Salesforce Pub/Sub API with authentication and schema caching
@MainActor
class PubSubClientManager {
    static let shared = PubSubClientManager()
    
    private var grpcClient: GRPCClient?
    private var schemaCache: [String: String] = [:]
    
    private init() {}
    
    /// Get or create the shared gRPC client instance
    func getClient() throws -> GRPCClient {
        if let existingClient = grpcClient {
            return existingClient
        }
        
        // Create new client with HTTP/2 transport
        let client = GRPCClient(
            transport: try .http2NIOPosix(
                target: .dns(host: "api.pubsub.salesforce.com", port: 443),
                config: .defaults(transportSecurity: .tls)
            ),
            interceptors: [SalesforcePubSubAuthInterceptor()]
        )
        
        grpcClient = client
        return client
    }
    
    /// Get Avro schema by schema ID, using cache when possible
    func getSchema(schemaId: String) async throws -> String {
        // Check cache first (critical for performance - 1.2s without cache vs 0.01s with cache)
        if let cachedSchema = schemaCache[schemaId] {
            print("📦 PubSubClientManager: Schema cache HIT for \(schemaId)")
            return cachedSchema
        }
        
        print("🔍 PubSubClientManager: Schema cache MISS for \(schemaId), fetching from server...")
        
        // Fetch from server
        let client = try getClient()
        
        var schemaRequest = Eventbus_V1_SchemaRequest()
        schemaRequest.schemaID = schemaId
        
        let response = try await client.unary(
            request: ClientRequest.Single(
                message: schemaRequest,
                metadata: [:]
            ),
            descriptor: MethodDescriptor(service: "eventbus.v1.PubSub", method: "GetSchema"),
            serializer: ProtobufSerializer<Eventbus_V1_SchemaRequest>(),
            deserializer: ProtobufDeserializer<Eventbus_V1_SchemaInfo>()
        )
        
        let schemaInfo = try response.message
        let schemaJSON = schemaInfo.schemaJSON
        
        // Cache for future use
        schemaCache[schemaId] = schemaJSON
        print("💾 PubSubClientManager: Cached schema for \(schemaId) (length: \(schemaJSON.count))")
        
        return schemaJSON
    }
    
    /// Clear the schema cache (useful for testing or memory management)
    func clearSchemaCache() {
        schemaCache.removeAll()
        print("🗑️ PubSubClientManager: Schema cache cleared")
    }
    
    /// Close the gRPC client connection
    func closeClient() async {
        if let client = grpcClient {
            await client.run()
            grpcClient = nil
            print("🔌 PubSubClientManager: gRPC client closed")
        }
    }
}

/// Interceptor to inject Salesforce authentication headers into every gRPC request
struct SalesforcePubSubAuthInterceptor: ClientInterceptor {
    func intercept<Input: Sendable, Output: Sendable>(
        request: ClientRequest<Input>,
        context: ClientContext,
        next: @Sendable (ClientRequest<Input>, ClientContext) async throws -> ClientResponse<Output>
    ) async throws -> ClientResponse<Output> {
        var modifiedRequest = request
        
        // Get credentials from auth manager
        guard let credentials = SalesforcePubSubAuth.shared.credentials else {
            print("❌ SalesforcePubSubAuthInterceptor: No valid credentials available")
            throw GRPCError.AuthenticationFailed
        }
        
        // Add required Salesforce Pub/Sub API headers
        modifiedRequest.metadata["accesstoken"] = credentials.accessToken
        modifiedRequest.metadata["instanceurl"] = credentials.instanceURL
        modifiedRequest.metadata["tenantid"] = credentials.tenantID
        
        // Call next interceptor or final handler
        return try await next(modifiedRequest, context)
    }
}

/// Custom gRPC errors
enum GRPCError: Error, LocalizedError {
    case AuthenticationFailed
    case SchemaNotFound
    case ConnectionFailed
    
    var errorDescription: String? {
        switch self {
        case .AuthenticationFailed:
            return "Failed to authenticate with Salesforce Pub/Sub API. Please ensure you are logged in."
        case .SchemaNotFound:
            return "Schema not found for the requested ID."
        case .ConnectionFailed:
            return "Failed to connect to Salesforce Pub/Sub API."
        }
    }
}

/// Protocol Buffer serializer
struct ProtobufSerializer<Message: SwiftProtobuf.Message>: MessageSerializer {
    func serialize(_ message: Message) throws -> [UInt8] {
        return try Array(message.serializedData())
    }
}

/// Protocol Buffer deserializer
struct ProtobufDeserializer<Message: SwiftProtobuf.Message>: MessageDeserializer {
    func deserialize(_ serializedMessageBytes: [UInt8]) throws -> Message {
        return try Message(serializedData: Data(serializedMessageBytes))
    }
}

