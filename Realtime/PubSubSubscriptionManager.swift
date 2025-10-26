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
import SwiftAvroCore
import GRPCCore

/// Manages the long-lived Pub/Sub API subscription to OpportunityChangeEvent
@available(iOS 18.0, *)
@MainActor
class PubSubSubscriptionManager: ObservableObject {
    static let shared = PubSubSubscriptionManager()
    
    @Published var connectionStatus: PubSubConnectionStatus = .disconnected
    @Published var lastUpdateTime: Date?
    
    private var subscriptionTask: Task<Void, Never>?
    private var latestReplayId: Data?
    private var cachedAvro: Avro?
    private var cachedSchemaId: String?
    
    private let topicName = "/data/OpportunityChangeEvent"
    
    // Event callback for CDC events
    var onEventReceived: ((OpportunityChangeEventPayload) -> Void)?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Connect to the Pub/Sub API and start receiving events
    func connect() {
        print("🔌 PubSubSubscriptionManager: Connecting to Pub/Sub API...")
        connectionStatus = .connecting
        
        // Cancel any existing subscription
        subscriptionTask?.cancel()
        
        // Start new subscription task
        subscriptionTask = Task { [weak self] in
            await self?.subscriptionLoop()
        }
    }
    
    /// Disconnect from the Pub/Sub API
    func disconnect() {
        print("🔌 PubSubSubscriptionManager: Disconnecting...")
        subscriptionTask?.cancel()
        subscriptionTask = nil
        connectionStatus = .disconnected
        latestReplayId = nil
    }
    
    // MARK: - Subscription Logic
    
    /// Main subscription loop - handles connection lifecycle and reconnection
    private func subscriptionLoop() async {
        while !Task.isCancelled {
            do {
                print("🚀 PubSubSubscriptionManager: Starting subscription")
                try await performSubscription()
            } catch {
                print("❌ PubSubSubscriptionManager: Subscription error - \(error)")
                await MainActor.run {
                    connectionStatus = .disconnected
                }
                
                // Exponential backoff retry (1s, 2s, 4s, 8s, max 30s)
                let retryDelay = min(30.0, pow(2.0, Double.random(in: 0...4)))
                print("⏳ PubSubSubscriptionManager: Retrying in \(Int(retryDelay))s...")
                
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
    }
    
    /// Perform the actual subscription with bidirectional streaming
    private func performSubscription() async throws {
        let clientManager = PubSubClientManager.shared
        
        // Step 1: Get topic info and schema
        print("📡 PubSubSubscriptionManager: Getting topic info...")
        let topicInfo = try await clientManager.getTopic(topicName: topicName)
        
        guard topicInfo.canSubscribe else {
            throw PubSubError.connectionFailed
        }
        
        print("📡 PubSubSubscriptionManager: Getting schema...")
        let schemaJSON = try await clientManager.getSchemaInfo(schemaId: topicInfo.schemaID)
        
        // Create Avro decoder with schema
        let avro = Avro()
        _ = try avro.decodeSchema(schema: schemaJSON)
        cachedAvro = avro
        cachedSchemaId = topicInfo.schemaID
        
        print("✅ PubSubSubscriptionManager: Schema loaded")
        
        await MainActor.run {
            connectionStatus = .connected
            lastUpdateTime = Date()
        }
        
        print("✅ PubSubSubscriptionManager: Connected!")
        
        // Step 2: Start bidirectional Subscribe stream
        print("📡 PubSubSubscriptionManager: Starting Subscribe stream...")
        
        let client = try await clientManager.getClient()
        
        // Use the generated client's subscribe method with bidirectional streaming
        try await client.subscribe(
            requestProducer: { writer in
                // Send FetchRequests
                try await self.sendFetchRequests(writer: writer)
            },
            onResponse: { responseStream in
                // Receive and process FetchResponses
                try await self.receiveFetchResponses(stream: responseStream)
            }
        )
    }
    
    /// Send FetchRequest messages to the server
    private func sendFetchRequests(writer: RPCWriter<Eventbus_V1_FetchRequest>) async throws {
        print("📤 PubSubSubscriptionManager: Starting FetchRequest sender")
        
        // Create initial FetchRequest
        var request = Eventbus_V1_FetchRequest()
        request.topicName = topicName
        request.numRequested = 1  // Request 1 event at a time (flow control)
        request.replayPreset = .latest  // Start from latest events
        
        // Send initial request
        try await writer.write(request)
        print("📤 PubSubSubscriptionManager: Sent initial FetchRequest")
        
        // Keep connection alive by sending periodic requests
        // The response handler will trigger when events arrive
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes keepalive
            
            // Send another request to keep stream alive
            var keepaliveRequest = Eventbus_V1_FetchRequest()
            keepaliveRequest.numRequested = 1
            try await writer.write(keepaliveRequest)
            print("📤 PubSubSubscriptionManager: Sent keepalive FetchRequest")
        }
    }
    
    /// Receive and process FetchResponse messages from the server
    private func receiveFetchResponses(stream: StreamingClientResponse<Eventbus_V1_FetchResponse>) async throws {
        print("📥 PubSubSubscriptionManager: Starting FetchResponse receiver")
        
        for try await response in stream.messages {
            // Store latest replay ID for reconnection
            if !response.latestReplayID.isEmpty {
                latestReplayId = response.latestReplayID
            }
            
            // Check if this is a keepalive (empty events array)
            if response.events.isEmpty {
                print("💓 PubSubSubscriptionManager: Received keepalive (pending: \(response.pendingNumRequested))")
                continue
            }
            
            // Process events
            print("📨 PubSubSubscriptionManager: Received \(response.events.count) event(s)")
            
            for consumerEvent in response.events {
                try await processEvent(consumerEvent)
            }
            
            // Update last update time
            await MainActor.run {
                lastUpdateTime = Date()
            }
        }
        
        print("⚠️ PubSubSubscriptionManager: Response stream ended")
    }
    
    /// Process a single CDC event
    private func processEvent(_ consumerEvent: Eventbus_V1_ConsumerEvent) async throws {
        guard let avro = cachedAvro else {
            throw PubSubError.schemaNotFound
        }
        
        let eventInfo = consumerEvent.event
        let payload = eventInfo.payload
        let replayId = consumerEvent.replayID
        
        print("📦 PubSubSubscriptionManager: Processing event")
        print("   Schema ID: \(eventInfo.schemaID)")
        print("   Payload size: \(payload.count) bytes")
        print("   Replay ID: \(replayId.hexString)")
        
        // Check if schema changed (should be rare)
        if eventInfo.schemaID != cachedSchemaId {
            print("⚠️ PubSubSubscriptionManager: Schema changed, fetching new schema...")
            let newSchemaJSON = try await PubSubClientManager.shared.getSchemaInfo(schemaId: eventInfo.schemaID)
            let newAvro = Avro()
            _ = try newAvro.decodeSchema(schema: newSchemaJSON)
            cachedAvro = newAvro
            cachedSchemaId = eventInfo.schemaID
        }
        
        // Decode Avro payload
        do {
            let decodedPayload: OpportunityChangeEventPayload = try avro.decode(from: payload)
            
            print("✅ PubSubSubscriptionManager: Decoded CDC event")
            print("   Change Type: \(decodedPayload.ChangeEventHeader.changeType)")
            print("   Record IDs: \(decodedPayload.ChangeEventHeader.recordIds)")
            
            // Call the event callback on MainActor
            await MainActor.run {
                onEventReceived?(decodedPayload)
            }
        } catch {
            print("❌ PubSubSubscriptionManager: Avro decode failed - \(error)")
            throw PubSubError.avroDecodingFailed(error.localizedDescription)
        }
    }
}

// MARK: - Data Extensions

extension Data {
    /// Convert Data to hex string for debugging
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
