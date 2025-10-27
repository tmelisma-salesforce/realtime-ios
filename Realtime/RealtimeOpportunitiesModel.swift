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
import SwiftUI
import Combine
import SalesforceSDKCore

/// View model for the realtime opportunities list with CDC event handling
@available(iOS 18.0, *)
@MainActor
class RealtimeOpportunitiesModel: ObservableObject {
    @Published var opportunities: [Opportunity] = []
    @Published var connectionStatus: PubSubConnectionStatus = .disconnected
    @Published var lastUpdateTime: Date?
    
    private var opportunityMap: [String: Int] = [:] // ID -> index mapping for fast lookup
    private let subscriptionManager = PubSubSubscriptionManager.shared
    private var opportunitiesCancellable: AnyCancellable?
    private var statusCancellable: AnyCancellable?
    private var lastUpdateCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    /// Initialize the view model and start receiving events
    func initialize() {
        print("🚀 RealtimeOpportunitiesModel: Initializing...")
        
        // Subscribe to connection status changes
        statusCancellable = subscriptionManager.$connectionStatus
            .receive(on: RunLoop.main)
            .assign(to: \.connectionStatus, on: self)
        
        lastUpdateCancellable = subscriptionManager.$lastUpdateTime
            .receive(on: RunLoop.main)
            .assign(to: \.lastUpdateTime, on: self)
        
        // Set up CDC event callback
        subscriptionManager.onEventReceived = { [weak self] event in
            Task { @MainActor in
                self?.handleChangeEvent(event)
            }
        }
        
        // Fetch initial data from REST API
        fetchInitialOpportunities()
        
        // Start network monitoring
        subscriptionManager.startNetworkMonitoring()
        
        // Start Pub/Sub subscription
        subscriptionManager.connect()
    }
    
    /// Cleanup when leaving the Realtime tab
    func cleanup() {
        print("🧹 RealtimeOpportunitiesModel: Cleaning up...")
        subscriptionManager.stopNetworkMonitoring()
        subscriptionManager.disconnect()
    }
    
    /// Fetch initial opportunities list via REST API (same as traditional view)
    private func fetchInitialOpportunities() {
        print("📋 RealtimeOpportunitiesModel: Fetching initial opportunities via REST API...")
        
        let request = RestClient.shared.request(
            forQuery: "SELECT Id, Name, StageName, Amount, CloseDate, Account.Name FROM Opportunity ORDER BY CloseDate DESC LIMIT 100",
            apiVersion: nil
        )
        
        opportunitiesCancellable = RestClient.shared.publisher(for: request)
            .receive(on: RunLoop.main)
            .tryMap({ response -> Data in
                return response.asData()
            })
            .decode(type: OpportunityResponse.self, decoder: JSONDecoder())
            .map({ record -> [Opportunity] in
                print("📋 RealtimeOpportunitiesModel: Decoded \(record.records.count) opportunities")
                return record.records
            })
            .catch({ error -> Just<[Opportunity]> in
                print("❌ RealtimeOpportunitiesModel: Error fetching opportunities - \(error)")
                return Just([])
            })
            .sink { [weak self] opportunities in
                self?.opportunities = opportunities
                self?.rebuildOpportunityMap()
            }
    }
    
    /// Handle incoming CDC event
    private func handleChangeEvent(_ event: OpportunityChangeEventPayload) {
        print("🔔 RealtimeOpportunitiesModel: Handling CDC event - \(event.ChangeEventHeader.changeType)")
        
        guard let recordId = event.ChangeEventHeader.recordId else {
            print("⚠️ RealtimeOpportunitiesModel: No record ID in event")
            return
        }
        
        switch event.ChangeEventHeader.parsedChangeType {
        case .update:
            handleUpdate(recordId: recordId, event: event)
        case .create:
            handleCreate(recordId: recordId, event: event)
        case .delete:
            handleDelete(recordId: recordId)
        case .undelete:
            handleCreate(recordId: recordId, event: event) // Treat undelete like create
        case .none:
            print("⚠️ RealtimeOpportunitiesModel: Unknown change type: \(event.ChangeEventHeader.changeType)")
        }
    }
    
    /// Handle UPDATE event
    private func handleUpdate(recordId: String, event: OpportunityChangeEventPayload) {
        print("🔄 RealtimeOpportunitiesModel: UPDATE event for \(recordId)")
        
        guard let index = opportunityMap[recordId] else {
            print("⚠️ RealtimeOpportunitiesModel: Opportunity not found in list, skipping")
            return
        }
        
        let changedFields = event.getChangedFieldNames()
        print("📝 RealtimeOpportunitiesModel: Changed fields: \(changedFields)")
        print("   BEFORE UPDATE: Name=\(opportunities[index].Name), StageName=\(opportunities[index].StageName ?? "nil"), Amount=\(opportunities[index].Amount?.description ?? "nil")")
        
        // Update fields directly in the array
        if let name = event.Name {
            print("   → Updating Name: '\(opportunities[index].Name)' → '\(name)'")
            opportunities[index].Name = name
        }
        if let stageName = event.StageName {
            print("   → Updating StageName: '\(opportunities[index].StageName ?? "nil")' → '\(stageName)'")
            opportunities[index].StageName = stageName
        }
        if let amount = event.Amount {
            print("   → Updating Amount: \(opportunities[index].Amount?.description ?? "nil") → \(amount)")
            opportunities[index].Amount = amount
        }
        if let closeDateMillis = event.CloseDate {
            let date = Date(timeIntervalSince1970: TimeInterval(closeDateMillis) / 1000.0)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let newCloseDate = formatter.string(from: date)
            print("   → Updating CloseDate: '\(opportunities[index].CloseDate ?? "nil")' → '\(newCloseDate)'")
            opportunities[index].CloseDate = newCloseDate
        }
        
        // Track changed fields
        opportunities[index].changedFields.formUnion(changedFields)
        opportunities[index].lastUpdated = Date()
        opportunities[index].justChanged = true
        
        print("   AFTER UPDATE: Name=\(opportunities[index].Name), StageName=\(opportunities[index].StageName ?? "nil"), Amount=\(opportunities[index].Amount?.description ?? "nil")")
        
        // Now move to top
        let updatedOpportunity = opportunities.remove(at: index)
        
        withAnimation(.spring()) {
            opportunities.insert(updatedOpportunity, at: 0)
            rebuildOpportunityMap()
        }
        
        // Verify the update stuck
        print("   🔍 VERIFY: opportunities[0] after insert:")
        print("      Name=\(opportunities[0].Name), StageName=\(opportunities[0].StageName ?? "nil"), Amount=\(opportunities[0].Amount?.description ?? "nil")")
        print("      changedFields=\(opportunities[0].changedFields)")
        
        // Reset justChanged after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.opportunities.first?.Id == recordId {
                self.opportunities[0].justChanged = false
            }
        }
        
        print("✅ RealtimeOpportunitiesModel: Opportunity moved to top")
    }
    
    /// Handle CREATE event
    private func handleCreate(recordId: String, event: OpportunityChangeEventPayload) {
        print("✨ RealtimeOpportunitiesModel: CREATE event for \(recordId)")
        
        // Check if opportunity already exists (edge case: duplicate CREATE events)
        if opportunityMap[recordId] != nil {
            print("⚠️ RealtimeOpportunitiesModel: Opportunity already exists, treating as UPDATE")
            handleUpdate(recordId: recordId, event: event)
            return
        }
        
        // For CREATE events, fetch the full opportunity via REST API
        // (CDC may not include all fields like Account.Name)
        let request = RestClient.shared.request(
            forQuery: "SELECT Id, Name, StageName, Amount, CloseDate, Account.Name FROM Opportunity WHERE Id = '\(recordId)'",
            apiVersion: nil
        )
        
        RestClient.shared.publisher(for: request)
            .receive(on: RunLoop.main)
            .tryMap({ response -> Data in
                return response.asData()
            })
            .decode(type: OpportunityResponse.self, decoder: JSONDecoder())
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ RealtimeOpportunitiesModel: Failed to fetch new opportunity - \(error)")
                        // TODO (Phase 8): Add retry logic with exponential backoff
                        // TODO (Phase 8): Consider showing error state in UI or background retry
                        // For now, the opportunity will not appear until a manual refresh
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    
                    guard let newOpp = response.records.first else {
                        print("⚠️ RealtimeOpportunitiesModel: No opportunity found in CREATE response (may have been deleted)")
                        return
                    }
                    
                    var opportunity = newOpp
                    opportunity.changedFields = Set(["Name", "StageName", "Amount", "CloseDate"]) // All fields are new
                    opportunity.lastUpdated = Date()
                    opportunity.justChanged = true
                    
                    withAnimation(.spring()) {
                        self.opportunities.insert(opportunity, at: 0)
                        self.rebuildOpportunityMap()
                    }
                    
                    print("✅ RealtimeOpportunitiesModel: New opportunity added to top")
                }
            )
            .store(in: &cancellables)
    }
    
    /// Handle DELETE event
    private func handleDelete(recordId: String) {
        print("🗑️ RealtimeOpportunitiesModel: DELETE event for \(recordId)")
        
        guard let index = opportunityMap[recordId] else {
            print("⚠️ RealtimeOpportunitiesModel: Opportunity not found in list")
            return
        }
        
        withAnimation(.easeOut) {
            opportunities.remove(at: index)
            rebuildOpportunityMap()
        }
        
        print("✅ RealtimeOpportunitiesModel: Opportunity removed from list")
    }
    
    /// Rebuild the opportunity ID to index mapping
    private func rebuildOpportunityMap() {
        opportunityMap.removeAll()
        for (index, opp) in opportunities.enumerated() {
            opportunityMap[opp.Id] = index
        }
    }
}

