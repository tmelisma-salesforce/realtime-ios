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

/// Manages the long-lived Pub/Sub API subscription to OpportunityChangeEvent
/// TODO: Full gRPC implementation - currently stubbed for UI development
@MainActor
class PubSubSubscriptionManager: ObservableObject {
    static let shared = PubSubSubscriptionManager()
    
    @Published var connectionStatus: PubSubConnectionStatus = .disconnected
    @Published var lastUpdateTime: Date?
    
    private var subscriptionTask: Task<Void, Never>?
    
    // Event callback for CDC events
    var onEventReceived: ((OpportunityChangeEventPayload) -> Void)?
    
    private init() {}
    
    /// Connect to the Pub/Sub API and start receiving events
    func connect() {
        print("🔌 PubSubSubscriptionManager: Connecting... (stubbed)")
        connectionStatus = .connecting
        
        // TODO: Implement actual gRPC connection
        // For now, simulate connection
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                connectionStatus = .connected
                lastUpdateTime = Date()
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
}
