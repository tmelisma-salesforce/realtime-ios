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
import SalesforceSDKCore
import Combine

struct Opportunity: Identifiable, Decodable, Equatable {
    var id: String { Id }
    let Id: String
    var Name: String
    var Amount: Double?
    var StageName: String?
    var CloseDate: String?
    let Account: AccountRelation?
    
    // Change tracking properties (not from API)
    var changedFields: Set<String> = []
    var lastUpdated: Date?
    var justChanged: Bool = false
    
    struct AccountRelation: Decodable, Equatable {
        let Name: String?
    }
    
    // Custom CodingKeys to exclude change tracking properties from decoding
    enum CodingKeys: String, CodingKey {
        case Id, Name, Amount, StageName, CloseDate, Account
    }
    
    // Equatable conformance (for comparing opportunities)
    static func == (lhs: Opportunity, rhs: Opportunity) -> Bool {
        return lhs.Id == rhs.Id
    }
}

struct OpportunityResponse: Decodable {
    var totalSize: Int
    var done: Bool
    var records: [Opportunity]
}


class OpportunitiesListModel: ObservableObject {
    @Published var opportunities: [Opportunity] = []
    
    private var opportunitiesCancellable: AnyCancellable?
    
    func fetchOpportunities() {
        print("📋 OpportunitiesListModel: Starting fetchOpportunities()")
        let request = RestClient.shared.request(forQuery: "SELECT Id, Name, StageName, Amount, CloseDate, Account.Name FROM Opportunity ORDER BY CloseDate DESC LIMIT 100", apiVersion: nil)
        
        print("📋 OpportunitiesListModel: Sending REST API request")
        opportunitiesCancellable = RestClient.shared.publisher(for: request)
            .receive(on: RunLoop.main)
            .tryMap({ (response) -> Data in
                print("📋 OpportunitiesListModel: Received response from API")
                return response.asData()
            })
            .decode(type: OpportunityResponse.self, decoder: JSONDecoder())
            .map({ (record) -> [Opportunity] in
                print("📋 OpportunitiesListModel: Decoded \(record.records.count) opportunities")
                return record.records
            })
            .catch( { error -> Just<[Opportunity]> in
                print("❌ OpportunitiesListModel: Error fetching opportunities - \(error)")
                return Just([])
            })
            .assign(to: \.opportunities, on: self)        
    }
    
    @MainActor
    func fetchOpportunitiesAsync() async {
        print("🔄 OpportunitiesListModel: Starting async fetch with minimum 2-second display")
        let startTime = Date()
        
        await withCheckedContinuation { continuation in
            print("📋 OpportunitiesListModel: Initiating REST API call")
            let request = RestClient.shared.request(forQuery: "SELECT Id, Name, StageName, Amount, CloseDate, Account.Name FROM Opportunity ORDER BY CloseDate DESC LIMIT 100", apiVersion: nil)
            
            opportunitiesCancellable = RestClient.shared.publisher(for: request)
                .receive(on: RunLoop.main)
                .tryMap({ (response) -> Data in
                    print("📋 OpportunitiesListModel: Received response from Salesforce API")
                    return response.asData()
                })
                .decode(type: OpportunityResponse.self, decoder: JSONDecoder())
                .map({ (record) -> [Opportunity] in
                    print("📋 OpportunitiesListModel: Successfully decoded \(record.records.count) opportunities")
                    return record.records
                })
                .catch( { error -> Just<[Opportunity]> in
                    print("❌ OpportunitiesListModel: Error occurred - \(error.localizedDescription)")
                    return Just([])
                })
                .sink { [weak self] opportunities in
                    print("📋 OpportunitiesListModel: Updating opportunities list")
                    self?.opportunities = opportunities
                    continuation.resume()
                }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("⏱️ OpportunitiesListModel: Data fetch completed in \(String(format: "%.2f", elapsed)) seconds")
        
        if elapsed < 2.0 {
            let remainingTime = 2.0 - elapsed
            print("⏳ OpportunitiesListModel: Waiting additional \(String(format: "%.2f", remainingTime)) seconds to reach minimum 2-second display")
            try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
        }
        
        print("✅ OpportunitiesListModel: Refresh complete, dismissing pull-to-refresh indicator")
    }
}

