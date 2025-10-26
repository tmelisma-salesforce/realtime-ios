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

struct MainTabView: View {
    var body: some View {
        TabView {
            OpportunitiesListView()
                .tabItem {
                    Label("Traditional", systemImage: "list.bullet")
                }
            
            RealtimeView()
                .tabItem {
                    Label("Realtime", systemImage: "bolt.fill")
                }
        }
    }
}

struct RealtimeView: View {
    @StateObject private var viewModel = RealtimeOpportunitiesModel()
    @State private var isPulsing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status indicator at top
                ConnectionStatusView(
                    status: viewModel.connectionStatus,
                    lastUpdateTime: viewModel.lastUpdateTime
                )
                .padding(.vertical, 8)
                
                // Opportunities list
                List {
                    ForEach(viewModel.opportunities) { opportunity in
                        OpportunityRowView(opportunity: opportunity, isPulsing: $isPulsing)
                    }
                }
                .listStyle(.plain)
                .animation(.spring(), value: viewModel.opportunities)
            }
            .navigationBarTitle(Text("Realtime"), displayMode: .inline)
            .onAppear {
                viewModel.initialize()
                // Start pulsing animation
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

/// Row view for a single opportunity with field highlighting
struct OpportunityRowView: View {
    let opportunity: Opportunity
    @Binding var isPulsing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Name
            HighlightableText(
                text: opportunity.Name,
                isChanged: opportunity.changedFields.contains("Name"),
                isPulsing: isPulsing
            )
            .font(.headline)
            
            HStack(spacing: 10) {
                // Account Name
                if let accountName = opportunity.Account?.Name {
                    Text(accountName)
                        .font(.subheadline)
                } else {
                    Text("No Account")
                        .font(.subheadline)
                }
                
                // Stage Name
                if let stageName = opportunity.StageName {
                    Text("•")
                    HighlightableText(
                        text: stageName,
                        isChanged: opportunity.changedFields.contains("StageName"),
                        isPulsing: isPulsing
                    )
                    .font(.subheadline)
                }
            }
            
            HStack(spacing: 10) {
                // Amount
                if let amount = opportunity.Amount {
                    HighlightableText(
                        text: String(format: "$%.2f", amount),
                        isChanged: opportunity.changedFields.contains("Amount"),
                        isPulsing: isPulsing
                    )
                    .font(.subheadline)
                }
                
                // Close Date
                if let closeDate = opportunity.CloseDate {
                    if opportunity.Amount != nil {
                        Text("•")
                    }
                    HighlightableText(
                        text: closeDate,
                        isChanged: opportunity.changedFields.contains("CloseDate"),
                        isPulsing: isPulsing
                    )
                    .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Text view with permanent pulsing highlight for changed fields
struct HighlightableText: View {
    let text: String
    let isChanged: Bool
    let isPulsing: Bool
    
    var body: some View {
        Text(text)
            .padding(.horizontal, isChanged ? 6 : 0)
            .padding(.vertical, isChanged ? 2 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(isChanged ? 0.2 : 0))
                    .opacity(isPulsing && isChanged ? 0.3 : 0.6)
            )
            .animation(.easeInOut(duration: 2), value: isPulsing)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}

