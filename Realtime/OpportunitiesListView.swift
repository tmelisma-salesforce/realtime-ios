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

struct OpportunitiesListView: View {
    @ObservedObject var viewModel = OpportunitiesListModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.opportunities) { opportunity in
                VStack(alignment: .leading, spacing: 5) {
                    Text(opportunity.Name)
                        .font(.headline)
                    
                    HStack(spacing: 10) {
                        if let accountName = opportunity.Account?.Name {
                            Text(accountName)
                                .font(.subheadline)
                        } else {
                            Text("No Account")
                                .font(.subheadline)
                        }
                        
                        if let stageName = opportunity.StageName {
                            Text("•")
                            Text(stageName)
                                .font(.subheadline)
                        }
                    }
                    
                    HStack(spacing: 10) {
                        if let amount = opportunity.Amount {
                            Text(String(format: "$%.2f", amount))
                                .font(.subheadline)
                        }
                        
                        if let closeDate = opportunity.CloseDate {
                            if opportunity.Amount != nil {
                                Text("•")
                            }
                            Text(closeDate)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .refreshable {
                print("🔄 OpportunitiesListView: Pull-to-refresh triggered by user")
                await self.viewModel.fetchOpportunitiesAsync()
                print("✅ OpportunitiesListView: Pull-to-refresh completed")
            }
            .navigationBarTitle(Text("Opportunities"), displayMode: .inline)
        }
        .onAppear { 
            print("👁️ OpportunitiesListView: View appeared, loading initial data")
            self.viewModel.fetchOpportunities()
        }
    }
}

struct OpportunitiesList_Previews: PreviewProvider {
    static var previews: some View {
        OpportunitiesListView()
    }
}

