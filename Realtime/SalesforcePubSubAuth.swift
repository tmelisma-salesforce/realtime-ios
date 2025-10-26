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

/// Manages authentication credentials for Salesforce Pub/Sub API
class SalesforcePubSubAuth {
    static let shared = SalesforcePubSubAuth()
    
    private init() {}
    
    /// OAuth access token for API authentication
    var accessToken: String? {
        return UserAccountManager.shared.currentUserAccount?.credentials.accessToken
    }
    
    /// Salesforce instance URL (e.g., https://your-domain.my.salesforce.com)
    var instanceURL: String? {
        return UserAccountManager.shared.currentUserAccount?.credentials.instanceUrl?.absoluteString
    }
    
    /// Organization ID (tenant ID) from user account identity
    var tenantID: String? {
        // Access org ID directly from account identity
        // See: https://forcedotcom.github.io/SalesforceMobileSDK-iOS/Documentation/SalesforceSDKCore/html/Classes/SFUserAccountIdentity.html
        return UserAccountManager.shared.currentUserAccount?.accountIdentity.orgId
    }
    
    /// Check if all required credentials are available
    var hasValidCredentials: Bool {
        return accessToken != nil && instanceURL != nil && tenantID != nil
    }
    
    /// Get all credentials as a tuple (for convenience)
    var credentials: (accessToken: String, instanceURL: String, tenantID: String)? {
        guard let token = accessToken,
              let instance = instanceURL,
              let tenant = tenantID else {
            return nil
        }
        return (token, instance, tenant)
    }
}

