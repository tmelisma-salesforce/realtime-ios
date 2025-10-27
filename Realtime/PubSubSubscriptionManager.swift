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
    // Note: No need to cache the schema separately - it's stored inside the Avro instance
    
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
            } catch PubSubError.authenticationFailed {
                print("❌ PubSubSubscriptionManager: Authentication failed - attempting token refresh...")
                await MainActor.run {
                    connectionStatus = .connecting
                }
                
                // Try to refresh token
                do {
                    try await PubSubClientManager.shared.refreshAccessToken()
                    print("✅ PubSubSubscriptionManager: Token refreshed, retrying immediately...")
                    
                    // Shutdown old client to force re-initialization with new token
                    await PubSubClientManager.shared.shutdown()
                    
                    // Retry immediately with new token
                    continue
                } catch {
                    print("❌ PubSubSubscriptionManager: Token refresh failed - \(error)")
                    await MainActor.run {
                        connectionStatus = .disconnected
                    }
                    
                    // Wait before retrying
                    let retryDelay = 10.0
                    print("⏳ PubSubSubscriptionManager: Retrying in \(Int(retryDelay))s...")
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
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
        print("   Topic name: \(topicName)")
        
        let topicInfo: Eventbus_V1_TopicInfo
        let schemaJSON: String
        
        do {
            topicInfo = try await clientManager.getTopic(topicName: topicName)
            print("   ✅ Got topic info successfully")
            
            guard topicInfo.canSubscribe else {
                print("   ❌ Topic does not allow subscription!")
                throw PubSubError.connectionFailed
            }
            print("   ✓ Topic allows subscription")
            
            print("📡 PubSubSubscriptionManager: Getting schema...")
            print("   Schema ID: \(topicInfo.schemaID)")
            schemaJSON = try await clientManager.getSchemaInfo(schemaId: topicInfo.schemaID)
            print("   ✅ Got schema successfully (\(schemaJSON.count) bytes)")
        } catch {
            print("❌ PubSubSubscriptionManager: Failed in performSubscription setup!")
            print("   Error type: \(type(of: error))")
            print("   Error: \(error)")
            print("   Localized: \(error.localizedDescription)")
            throw error
        }
        
        // Create Avro decoder with schema
        print("   → Decoding Avro schema...")
        print("   📋 Schema JSON length: \(schemaJSON.count) bytes")
        let avro = Avro()
        _ = avro.decodeSchema(schema: schemaJSON)  // Stores schema internally in avro.schema
        cachedAvro = avro
        cachedSchemaId = topicInfo.schemaID
        print("   ✓ Avro schema decoded and cached (stored inside Avro instance)")
        
        print("✅ PubSubSubscriptionManager: Schema loaded")
        
        await MainActor.run {
            connectionStatus = .connected
            lastUpdateTime = Date()
        }
        
        print("✅ PubSubSubscriptionManager: Connected!")
        
        // Step 2: Start bidirectional Subscribe stream
        print("📡 PubSubSubscriptionManager: Starting Subscribe stream...")
        
        let client = try await clientManager.getClient()
        print("   ✓ Got client for subscription")
        
        print("   → Starting bidirectional stream...")
        
        // Create AsyncStream for flow control (PUBSUB_GUIDE.md lines 387-435)
        // Response handler yields to signal request sender to send next FetchRequest
        let (responseSignal, signalContinuation) = AsyncStream.makeStream(of: Void.self)
        
        // Use the generated client's subscribe method with bidirectional streaming
        try await client.subscribe(
            requestProducer: { writer in
                // Send FetchRequests
                print("📤 PubSubSubscriptionManager: Request producer called")
                try await self.sendFetchRequests(writer: writer, responseSignal: responseSignal)
            },
            onResponse: { responseStream in
                // Receive and process FetchResponses
                print("📥 PubSubSubscriptionManager: Response handler called")
                try await self.receiveFetchResponses(stream: responseStream, signalContinuation: signalContinuation)
            }
        )
        print("⚠️ PubSubSubscriptionManager: subscribe() call completed (stream ended)")
    }
    
    /// Send FetchRequest messages to the server
    /// This uses an AsyncStream to coordinate with response handler (flow control)
    private func sendFetchRequests(
        writer: RPCWriter<Eventbus_V1_FetchRequest>,
        responseSignal: AsyncStream<Void>
    ) async throws {
        print("📤 PubSubSubscriptionManager: Starting FetchRequest sender")
        
        // Create initial FetchRequest
        var request = Eventbus_V1_FetchRequest()
        request.topicName = topicName
        request.numRequested = 1  // Request 1 event at a time (flow control)
        request.replayPreset = .latest  // Start from latest events
        
        // Send initial request
        try await writer.write(request)
        print("📤 PubSubSubscriptionManager: Sent initial FetchRequest (#1)")
        
        var requestCount = 1
        
        // FLOW CONTROL: Wait for response handler to signal, then send next request
        // This implements the pattern from PUBSUB_GUIDE.md lines 386-435
        for await _ in responseSignal {
            guard !Task.isCancelled else { break }
            
            requestCount += 1
            
            // Send next FetchRequest immediately after receiving response
            var nextRequest = Eventbus_V1_FetchRequest()
            nextRequest.numRequested = 1
            try await writer.write(nextRequest)
            print("📤 PubSubSubscriptionManager: Sent FetchRequest #\(requestCount) (after response)")
        }
        
        print("📤 PubSubSubscriptionManager: Request sender stopped")
    }
    
    /// Receive and process FetchResponse messages from the server
    private func receiveFetchResponses(
        stream: StreamingClientResponse<Eventbus_V1_FetchResponse>,
        signalContinuation: AsyncStream<Void>.Continuation
    ) async throws {
        print("📥 PubSubSubscriptionManager: Starting FetchResponse receiver")
        
        for try await response in stream.messages {
            // FLOW CONTROL: Signal request sender IMMEDIATELY (as per PUBSUB_GUIDE.md line 407)
            // This MUST happen before processing events to allow next request to be sent
            signalContinuation.yield()
            print("   ✓ Signaled request sender to send next FetchRequest")
            
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
        
        // Stream ended - finish the continuation
        signalContinuation.finish()
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
            _ = newAvro.decodeSchema(schema: newSchemaJSON)  // Stores internally
            cachedAvro = newAvro
            cachedSchemaId = eventInfo.schemaID
            print("   ✓ New schema cached in Avro instance")
        }
        
        // Decode Avro payload using the schema stored in the Avro instance
        // The decodeSchema() call above sets the schema internally in the Avro object
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
