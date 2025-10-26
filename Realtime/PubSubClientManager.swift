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
import GRPCProtobuf

/// Manages gRPC client connection and RPC calls to Salesforce Pub/Sub API
@available(iOS 18.0, *)
@MainActor
class PubSubClientManager {
    static let shared = PubSubClientManager()
    
    private var grpcClient: GRPCClient<HTTP2ClientTransport.Posix>?
    private var pubsubClient: Eventbus_V1_PubSub.Client<HTTP2ClientTransport.Posix>?
    private var schemaCache: [String: String] = [:]
    
    // Salesforce Pub/Sub API endpoint
    private let pubSubHost = "api.pubsub.salesforce.com"
    private let pubSubPort = 7443
    
    private init() {}
    
    // MARK: - Client Setup
    
    /// Initialize the gRPC client with authentication
    func setupClient() async throws {
        guard let credentials = SalesforcePubSubAuth.shared.credentials else {
            throw PubSubError.authenticationFailed
        }
        
        print("🔧 PubSubClientManager: Setting up gRPC client")
        print("   Instance: \(credentials.instanceURL)")
        print("   Tenant: \(credentials.tenantID)")
        
        // Create HTTP/2 transport with TLS
        let transport = try HTTP2ClientTransport.Posix(
            target: .dns(host: pubSubHost, port: pubSubPort),
            transportSecurity: .tls
        )
        
        // Create gRPC client with auth interceptor
        let client = GRPCClient(
            transport: transport,
            interceptors: [AuthInterceptor(credentials: credentials)]
        )
        
        grpcClient = client
        
        // Create Pub/Sub API client using generated code
        pubsubClient = Eventbus_V1_PubSub.Client(wrapping: client)
        
        print("✅ PubSubClientManager: gRPC client initialized")
    }
    
    /// Get the Pub/Sub API client, initializing if needed
    func getClient() async throws -> Eventbus_V1_PubSub.Client<HTTP2ClientTransport.Posix> {
        if let client = pubsubClient {
            return client
        }
        
        try await setupClient()
        
        guard let client = pubsubClient else {
            throw PubSubError.clientNotInitialized
        }
        
        return client
    }
    
    // MARK: - RPC Methods
    
    /// Get topic information including schema ID
    func getTopic(topicName: String) async throws -> Eventbus_V1_TopicInfo {
        print("📡 PubSubClientManager: Getting topic info for \(topicName)")
        
        let client = try await getClient()
        
        // Create request
        var request = Eventbus_V1_TopicRequest()
        request.topicName = topicName
        
        // Make unary RPC call using generated convenience method
        let topicInfo = try await client.getTopic(request)
        
        print("✅ PubSubClientManager: Topic info received")
        print("   Schema ID: \(topicInfo.schemaID)")
        print("   Can Subscribe: \(topicInfo.canSubscribe)")
        
        return topicInfo
    }
    
    /// Get Avro schema by schema ID (with caching)
    func getSchemaInfo(schemaId: String) async throws -> String {
        // Check cache first
        if let cached = schemaCache[schemaId] {
            print("💾 PubSubClientManager: Using cached schema for \(schemaId)")
            return cached
        }
        
        print("📡 PubSubClientManager: Fetching schema from server for \(schemaId)")
        
        let client = try await getClient()
        
        // Create request
        var request = Eventbus_V1_SchemaRequest()
        request.schemaID = schemaId
        
        // Make unary RPC call using generated convenience method
        let schemaInfo = try await client.getSchema(request)
        let schemaJSON = schemaInfo.schemaJson
        
        // Cache it
        schemaCache[schemaId] = schemaJSON
        print("✅ PubSubClientManager: Schema fetched and cached (\(schemaJSON.count) bytes)")
        
        return schemaJSON
    }
    
    // MARK: - Schema Cache Management
    
    /// Get cached schema (returns nil if not cached)
    func getCachedSchema(schemaId: String) -> String? {
        return schemaCache[schemaId]
    }
    
    /// Check if schema is cached
    func hasSchema(schemaId: String) -> Bool {
        return schemaCache[schemaId] != nil
    }
    
    /// Clear the schema cache
    func clearSchemaCache() {
        schemaCache.removeAll()
        print("🗑️ PubSubClientManager: Schema cache cleared")
    }
    
    /// Shutdown the gRPC client
    func shutdown() async {
        print("🔌 PubSubClientManager: Shutting down gRPC client")
        grpcClient = nil
        pubsubClient = nil
    }
}

// MARK: - Auth Interceptor

/// Injects Salesforce authentication headers into every gRPC request
@available(iOS 18.0, *)
private struct AuthInterceptor: ClientInterceptor {
    let credentials: (accessToken: String, instanceURL: String, tenantID: String)
    
    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: @Sendable (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        // Add authentication headers
        var metadata = request.metadata
        metadata.addString(credentials.accessToken, forKey: "accesstoken")
        metadata.addString(credentials.instanceURL, forKey: "instanceurl")
        metadata.addString(credentials.tenantID, forKey: "tenantid")
        
        var modifiedRequest = request
        modifiedRequest.metadata = metadata
        
        // Forward to next interceptor/transport
        return try await next(modifiedRequest, context)
    }
}

// MARK: - Custom Errors

enum PubSubError: Error, LocalizedError {
    case authenticationFailed
    case schemaNotFound
    case connectionFailed
    case clientNotInitialized
    case invalidResponse
    case avroDecodingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Failed to authenticate with Salesforce Pub/Sub API. Please ensure you are logged in."
        case .schemaNotFound:
            return "Schema not found for the requested ID."
        case .connectionFailed:
            return "Failed to connect to Salesforce Pub/Sub API."
        case .clientNotInitialized:
            return "gRPC client not initialized."
        case .invalidResponse:
            return "Invalid response from server."
        case .avroDecodingFailed(let detail):
            return "Failed to decode Avro payload: \(detail)"
        }
    }
}
