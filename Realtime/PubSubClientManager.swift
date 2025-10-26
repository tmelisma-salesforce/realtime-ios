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
import SalesforceSDKCore

/// Manages gRPC client connection and RPC calls to Salesforce Pub/Sub API
@available(iOS 18.0, *)
@MainActor
class PubSubClientManager {
    static let shared = PubSubClientManager()
    
    private var grpcClient: GRPCClient<HTTP2ClientTransport.Posix>?
    private var pubsubClient: Eventbus_V1_PubSub.Client<HTTP2ClientTransport.Posix>?
    private var schemaCache: [String: String] = [:]
    
    // CRITICAL: Task that runs the gRPC client
    // Based on official Swift.org gRPC Swift 2 docs, the client needs to be "run"
    // See: https://www.swift.org/blog/grpc-swift-2/
    private var clientRunTask: Task<Void, Never>?
    
    // Salesforce Pub/Sub API endpoint
    private let pubSubHost = "api.pubsub.salesforce.com"
    private let pubSubPort = 7443
    
    private init() {
        print("🏗️ PubSubClientManager: Instance created")
    }
    
    // MARK: - Client Setup
    
    /// Initialize the gRPC client with authentication
    func setupClient() async throws {
        // Verify credentials are available (early check for better error reporting)
        guard let credentials = SalesforcePubSubAuth.shared.credentials else {
            print("❌ PubSubClientManager: No credentials available!")
            throw PubSubError.authenticationFailed
        }
        
        print("🔧 PubSubClientManager: Setting up gRPC client")
        print("   Instance: \(credentials.instanceURL)")
        print("   Tenant: \(credentials.tenantID)")
        print("   Access Token Length: \(credentials.accessToken.count) chars")
        print("   Target: \(pubSubHost):\(pubSubPort)")
        print("   Note: Credentials will be fetched fresh on each request")
        
        do {
            // Create HTTP/2 transport with TLS
            print("   → Creating HTTP/2 transport...")
            let transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: pubSubHost, port: pubSubPort),
                transportSecurity: .tls
            )
            print("   ✓ Transport created")
            
            // Create gRPC client with auth interceptor
            // Note: AuthInterceptor fetches fresh credentials on each request
            print("   → Creating GRPCClient with AuthInterceptor...")
            let client = GRPCClient(
                transport: transport,
                interceptors: [AuthInterceptor()]
            )
            print("   ✓ GRPCClient created")
            
            // CRITICAL: Run the client in background Task
            // Without this, the client is created but never processes requests!
            // Source: GRPCClient.swift lines 46-56 and withGRPCClient implementation (lines 437-446)
            // The withGRPCClient helper does this internally, but we need a long-lived client
            print("   → Starting GRPCClient.runConnections() in background task...")
            clientRunTask = Task {
                do {
                    print("      🚀 GRPCClient.runConnections() task started")
                    try await client.runConnections()
                    print("      ⚠️ GRPCClient.runConnections() completed (client was shut down)")
                } catch {
                    print("      ❌ GRPCClient.runConnections() failed: \(error)")
                }
            }
            print("   ✓ GRPCClient.runConnections() task started")
            
            grpcClient = client
            
            // Create Pub/Sub API client using generated code
            print("   → Creating Pub/Sub API client...")
            pubsubClient = Eventbus_V1_PubSub.Client(wrapping: client)
            print("   ✓ Pub/Sub API client created")
            
            print("✅ PubSubClientManager: gRPC client initialized successfully")
        } catch {
            print("❌ PubSubClientManager: Failed to setup client!")
            print("   Error type: \(type(of: error))")
            print("   Error: \(error)")
            throw error
        }
    }
    
    /// Get the Pub/Sub API client, initializing if needed
    func getClient() async throws -> Eventbus_V1_PubSub.Client<HTTP2ClientTransport.Posix> {
        print("   → getClient() called")
        print("      Thread: \(Thread.current)")
        print("      pubsubClient exists: \(pubsubClient != nil)")
        
        if let client = pubsubClient {
            print("      ✓ Returning existing client")
            return client
        }
        
        print("      → Need to setup client first...")
        try await setupClient()
        
        guard let client = pubsubClient else {
            print("      ❌ setupClient() completed but pubsubClient is still nil!")
            throw PubSubError.clientNotInitialized
        }
        
        print("      ✓ Client setup complete, returning client")
        return client
    }
    
    // MARK: - RPC Methods
    
    /// Get topic information including schema ID
    func getTopic(topicName: String) async throws -> Eventbus_V1_TopicInfo {
        print("📡 PubSubClientManager: Getting topic info for \(topicName)")
        print("   Thread: \(Thread.current)")
        print("   Is MainActor: \(Thread.isMainThread)")
        
        let client = try await getClient()
        print("   ✓ Got client instance: \(type(of: client))")
        print("   ✓ Client memory address: \(Unmanaged.passUnretained(client as AnyObject).toOpaque())")
        
        // Create request
        var request = Eventbus_V1_TopicRequest()
        request.topicName = topicName
        print("   ✓ Created TopicRequest for: \(topicName)")
        print("   ✓ Request fields: topicName=\(request.topicName)")
        print("   → About to call client.getTopic(request)...")
        print("   → This should trigger AuthInterceptor...")
        
        // Add timeout to detect hangs
        let startTime = Date()
        
        return try await withThrowingTaskGroup(of: Eventbus_V1_TopicInfo.self) { group in
            print("   → TaskGroup created, adding RPC task...")
            
            // Task 1: Actual RPC call
            group.addTask {
                print("      🔹 RPC Task started on thread: \(Thread.current)")
                print("      🔹 About to call client.getTopic()...")
                
                do {
                    print("      🔹 Entering try block for client.getTopic()...")
                    let topicInfo = try await client.getTopic(request)
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("✅ PubSubClientManager: Topic info received after \(String(format: "%.2f", elapsed))s")
                    print("   Schema ID: \(topicInfo.schemaID)")
                    print("   Can Subscribe: \(topicInfo.canSubscribe)")
                    print("   Topic Name: \(topicInfo.topicName)")
                    print("   RPC ID: \(topicInfo.rpcID)")
                    return topicInfo
                } catch {
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("❌ PubSubClientManager: getTopic() threw error after \(String(format: "%.2f", elapsed))s!")
                    print("   Error type: \(type(of: error))")
                    print("   Error: \(error)")
                    print("   Localized: \(error.localizedDescription)")
                    throw error
                }
            }
            
            print("   → RPC task added, adding timeout task...")
            
            // Task 2: Timeout with progress indicators
            group.addTask {
                for i in 1...30 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    if i % 5 == 0 {
                        print("      ⏱️  Still waiting... \(i)s elapsed")
                    }
                }
                print("⏱️ PubSubClientManager: getTopic() TIMEOUT after 30s!")
                print("   This indicates the gRPC call is hanging/blocked")
                print("   The AuthInterceptor was never called!")
                throw PubSubError.connectionFailed
            }
            
            print("   → Timeout task added, waiting for first result...")
            
            // Return first result (either success or timeout)
            guard let result = try await group.next() else {
                print("   ❌ TaskGroup.next() returned nil!")
                throw PubSubError.connectionFailed
            }
            
            print("   ✓ Got result from TaskGroup, canceling other tasks...")
            
            // Cancel the other task
            group.cancelAll()
            return result
        }
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
        
        if let client = grpcClient {
            print("   → Calling beginGracefulShutdown() (signals runConnections() to complete)...")
            client.beginGracefulShutdown()
            print("   ✓ beginGracefulShutdown() called")
            
            // Wait for the runConnections task to complete
            if let runTask = clientRunTask {
                print("   → Waiting for GRPCClient.runConnections() task to complete...")
                await runTask.value
                print("   ✓ GRPCClient.runConnections() task completed")
            }
        }
        
        grpcClient = nil
        pubsubClient = nil
        clientRunTask = nil
        print("✅ PubSubClientManager: Shutdown complete")
    }
    
    // MARK: - Token Management
    
    /// Manually refresh the access token using Mobile SDK
    /// This wraps the callback-based SDK method in async/await
    /// Only called when we get an authentication error from PubSub API
    func refreshAccessToken() async throws {
        guard let currentUser = UserAccountManager.shared.currentUserAccount else {
            throw PubSubError.authenticationFailed
        }
        
        print("🔑 PubSubClientManager: Manually refreshing access token...")
        
        return try await withCheckedThrowingContinuation { continuation in
            // Use the SDK's refresh method with OAuthCredentials
            let success = UserAccountManager.shared.refresh(credentials: currentUser.credentials) { result in
                switch result {
                case .success(let (userAccount, authInfo)):
                    print("✅ PubSubClientManager: Token refresh succeeded for user: \(userAccount.accountIdentity.userId)")
                    print("   Auth info: \(authInfo)")
                    continuation.resume()
                    
                case .failure(let error):
                    print("❌ PubSubClientManager: Token refresh failed - \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            if !success {
                print("❌ PubSubClientManager: Failed to initiate token refresh")
                continuation.resume(throwing: PubSubError.authenticationFailed)
            }
        }
    }
}

// MARK: - Auth Interceptor

/// Injects Salesforce authentication headers into every gRPC request
/// Fetches fresh credentials from Mobile SDK on each request to ensure we always use current tokens
@available(iOS 18.0, *)
private struct AuthInterceptor: ClientInterceptor {
    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: @Sendable (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        print("🔐 AuthInterceptor: Intercepting request")
        print("   Method: \(context.descriptor)")
        
        // Fetch fresh credentials from Mobile SDK (in case token was refreshed)
        guard let credentials = SalesforcePubSubAuth.shared.credentials else {
            print("❌ AuthInterceptor: No credentials available!")
            throw PubSubError.authenticationFailed
        }
        
        print("   ✓ Got credentials")
        print("   Access Token: \(credentials.accessToken.prefix(20))...")
        print("   Instance URL: \(credentials.instanceURL)")
        print("   Tenant ID: \(credentials.tenantID)")
        
        // Add authentication headers with current token
        var metadata = request.metadata
        metadata.addString(credentials.accessToken, forKey: "accesstoken")
        metadata.addString(credentials.instanceURL, forKey: "instanceurl")
        metadata.addString(credentials.tenantID, forKey: "tenantid")
        
        var modifiedRequest = request
        modifiedRequest.metadata = metadata
        
        print("   ✓ Added auth headers to metadata")
        print("   → Forwarding to next interceptor/transport...")
        
        do {
            let response = try await next(modifiedRequest, context)
            print("   ✅ AuthInterceptor: Got response from transport")
            return response
        } catch {
            print("   ❌ AuthInterceptor: Transport threw error!")
            print("      Error type: \(type(of: error))")
            print("      Error: \(error)")
            throw error
        }
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
