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

import SwiftUI

/// Glass UI status indicator showing connection status with traffic light colors
struct ConnectionStatusView: View {
    let status: PubSubConnectionStatus
    let lastUpdateTime: Date?
    
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            // Traffic light indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.5), radius: 4)
            
            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(status.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Show last update time if disconnected OR connecting
                if status != .connected, let lastUpdate = lastUpdateTime {
                    Text("Last updated: \(formatTimestamp(lastUpdate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .onAppear {
            currentTime = Date()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    /// Get color for current status
    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .disconnected:
            return .red
        }
    }
    
    /// Format timestamp as minutes ago
    private func formatTimestamp(_ date: Date) -> String {
        let minutes = Int(currentTime.timeIntervalSince(date)) / 60
        if minutes == 0 {
            return "0m ago"
        } else {
            return "\(minutes)m ago"
        }
    }
}

// MARK: - Preview

struct ConnectionStatusView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ConnectionStatusView(status: .connected, lastUpdateTime: Date())
            ConnectionStatusView(status: .connecting, lastUpdateTime: Date().addingTimeInterval(-30))
            ConnectionStatusView(status: .disconnected, lastUpdateTime: Date().addingTimeInterval(-300))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

