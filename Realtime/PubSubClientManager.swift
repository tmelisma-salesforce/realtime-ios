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

/// Manages gRPC client connection and schema caching for Salesforce Pub/Sub API
///
/// NOTE: This implementation is structured for grpc-swift-2 integration.
/// The generated client code exists in `Realtime/Generated/pubsub_api.grpc.swift`.
/// Full gRPC implementation requires:
/// 1. Add pubsub_api.grpc.swift to Xcode project target
/// 2. Use Eventbus_V1_PubSub.Client<Transport> for RPC calls
/// 3. Configure HTTP/2 transport with TLS to api.pubsub.salesforce.com:7443
/// 4. Implement auth interceptor for metadata headers
///
/// See IMPLEMENTATION_STATUS.md Phase 7 for complete integration guide.
@MainActor
class PubSubClientManager {
    static let shared = PubSubClientManager()
    
    private var schemaCache: [String: String] = [:]
    
    // Salesforce Pub/Sub API endpoint
    private let pubSubHost = "api.pubsub.salesforce.com"
    private let pubSubPort = 7443
    
    private init() {}
    
    // MARK: - Schema Cache Management
    
    /// Get Avro schema by schema ID, using cache when possible
    func getSchema(schemaId: String) -> String? {
        return schemaCache[schemaId]
    }
    
    /// Cache a schema
    func cacheSchema(schemaId: String, schemaJSON: String) {
        schemaCache[schemaId] = schemaJSON
        print("💾 PubSubClientManager: Cached schema for \(schemaId) (length: \(schemaJSON.count))")
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
}

/// Custom gRPC errors
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
