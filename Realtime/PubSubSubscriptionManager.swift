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
import Combine
import GRPCCore
import SwiftAvroCore

/// Manages the long-lived Pub/Sub API subscription to OpportunityChangeEvent
@MainActor
class PubSubSubscriptionManager: ObservableObject {
    static let shared = PubSubSubscriptionManager()
    
    @Published var connectionStatus: PubSubConnectionStatus = .disconnected
    @Published var lastUpdateTime: Date?
    
    private var subscriptionTask: Task<Void, Never>?
    private var latestReplayId: Data?
    private var cachedSchemaJSON: String?
    
    // Event callback for CDC events
    var onEventReceived: ((OpportunityChangeEventPayload) -> Void)?
    
    private init() {}
    
    /// Connect to the Pub/Sub API and start receiving events
    func connect() {
        // Cancel any existing subscription
        disconnect()
        
        print("🔌 PubSubSubscriptionManager: Starting connection...")
        connectionStatus = .connecting
        
        subscriptionTask = Task {
            do {
                try await subscribeToOpportunityChanges()
            } catch {
                print("❌ PubSubSubscriptionManager: Connection failed - \(error)")
                await MainActor.run {
                    connectionStatus = .disconnected
                }
                
                // Retry after delay
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                connect() // Retry
            }
        }
    }
    
    /// Disconnect from the Pub/Sub API
    func disconnect() {
        print("🔌 PubSubSubscriptionManager: Disconnecting...")
        subscriptionTask?.cancel()
        subscriptionTask = nil
        connectionStatus = .disconnected
    }
    
    /// Main subscription logic
    private func subscribeToOpportunityChanges() async throws {
        let topicName = "/data/OpportunityChangeEvent"
        let client = try await PubSubClientManager.shared.getClient()
        
        print("📡 PubSubSubscriptionManager: Fetching topic info for \(topicName)...")
        
        // Step 1: Get topic info to retrieve schema ID
        var topicRequest = Eventbus_V1_TopicRequest()
        topicRequest.topicName = topicName
        
        let topicResponse = try await client.unary(
            request: ClientRequest.Single(message: topicRequest, metadata: [:]),
            descriptor: MethodDescriptor(service: "eventbus.v1.PubSub", method: "GetTopic"),
            serializer: ProtobufSerializer<Eventbus_V1_TopicRequest>(),
            deserializer: ProtobufDeserializer<Eventbus_V1_TopicInfo>()
        )
        
        let schemaId = try topicResponse.message.schemaID
        print("📡 PubSubSubscriptionManager: Schema ID: \(schemaId)")
        
        // Step 2: Get schema (with caching)
        if cachedSchemaJSON == nil {
            cachedSchemaJSON = try await PubSubClientManager.shared.getSchema(schemaId: schemaId)
            print("📡 PubSubSubscriptionManager: Schema fetched and cached (length: \(cachedSchemaJSON?.count ?? 0))")
        }
        
        // Step 3: Start bidirectional Subscribe stream
        print("📡 PubSubSubscriptionManager: Starting Subscribe stream...")
        
        try await client.bidirectionalStreaming(
            request: ClientRequest.Stream(
                metadata: [:]
            ) { writer in
                // Send initial FetchRequest
                var fetchRequest = Eventbus_V1_FetchRequest()
                fetchRequest.topicName = topicName
                fetchRequest.replayPreset = .latest
                fetchRequest.numRequested = 1
                
                print("📤 PubSubSubscriptionManager: Sending initial FetchRequest")
                try await writer.write(fetchRequest)
                
                // Keep the writer open for future requests
                // In a more complete implementation, we'd handle flow control here
                try await Task.sleep(nanoseconds: .max) // Keep alive
            },
            descriptor: MethodDescriptor(service: "eventbus.v1.PubSub", method: "Subscribe"),
            serializer: ProtobufSerializer<Eventbus_V1_FetchRequest>(),
            deserializer: ProtobufDeserializer<Eventbus_V1_FetchResponse>()
        ) { responseStream in
            // Update connection status
            await MainActor.run {
                connectionStatus = .connected
            }
            
            print("📥 PubSubSubscriptionManager: Receiving response stream...")
            
            // Process incoming FetchResponse messages
            for try await response in responseStream {
                try await handleFetchResponse(response)
            }
        }
    }
    
    /// Handle incoming FetchResponse
    private func handleFetchResponse(_ response: Eventbus_V1_FetchResponse) async throws {
        // Store replay ID
        if response.hasLatestReplayID {
            latestReplayId = response.latestReplayID
        }
        
        // Check if this is a keepalive (empty events)
        if response.events.isEmpty {
            print("💓 PubSubSubscriptionManager: Keepalive received")
            return
        }
        
        // Process events
        print("📥 PubSubSubscriptionManager: Received \(response.events.count) event(s)")
        
        for consumerEvent in response.events {
            let eventPayload = consumerEvent.event.payload
            let eventReplayId = consumerEvent.replayID
            
            print("📦 PubSubSubscriptionManager: Processing event (payload size: \(eventPayload.count) bytes)")
            
            // Decode Avro payload
            guard let schemaJSON = cachedSchemaJSON else {
                print("❌ PubSubSubscriptionManager: No cached schema available")
                continue
            }
            
            do {
                let decodedEvent = try decodeAvroPayload(eventPayload, schemaJSON: schemaJSON)
                
                // Update last update time
                await MainActor.run {
                    lastUpdateTime = Date()
                }
                
                // Notify callback
                await MainActor.run {
                    onEventReceived?(decodedEvent)
                }
                
                print("✅ PubSubSubscriptionManager: Event decoded successfully")
                
            } catch {
                print("❌ PubSubSubscriptionManager: Failed to decode Avro payload - \(error)")
            }
        }
    }
    
    /// Decode Avro payload using SwiftAvroCore
    private func decodeAvroPayload(_ payload: Data, schemaJSON: String) throws -> OpportunityChangeEventPayload {
        let avro = Avro()
        
        // Decode schema
        let schema = try avro.decodeSchema(schema: schemaJSON)
        
        // Decode binary payload
        let decodedEvent: OpportunityChangeEventPayload = try avro.decode(from: payload, with: schema)
        
        return decodedEvent
    }
}

