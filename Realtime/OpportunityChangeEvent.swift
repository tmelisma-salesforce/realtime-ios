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

/// Represents the Change Data Capture event payload for Opportunity changes
/// CDC events include ALL schema fields, but only changed fields have non-null values
struct OpportunityChangeEventPayload: Decodable {
    let ChangeEventHeader: ChangeEventHeader
    
    // Opportunity fields - all optional because CDC only includes changed fields
    let Name: String?
    let StageName: String?
    let Amount: Double?
    let CloseDate: String?
    let Probability: Double?
    
    // System fields (ignore these for change detection)
    let LastModifiedDate: Int64?
    let AccountId: String?  // Ignored - we never update Account from CDC
    
    /// Get the set of changed field names (non-null fields, excluding system fields)
    func getChangedFieldNames() -> Set<String> {
        var changedFields: Set<String> = []
        
        // Check each displayed field
        if Name != nil {
            changedFields.insert("Name")
        }
        if StageName != nil {
            changedFields.insert("StageName")
        }
        if Amount != nil {
            changedFields.insert("Amount")
        }
        if CloseDate != nil {
            changedFields.insert("CloseDate")
        }
        
        // Note: We explicitly ignore AccountId changes per requirements
        // Account.Name is not included in CDC events, only AccountId
        
        return changedFields
    }
}

/// Change Data Capture event header containing metadata about the change
struct ChangeEventHeader: Decodable {
    let entityName: String
    let recordIds: [String]
    let changeType: String  // UPDATE, CREATE, DELETE, UNDELETE
    let commitTimestamp: Int64
    let commitUser: String
    let transactionKey: String?
    let sequenceNumber: Int?
    
    /// Change type enum for easier handling
    enum ChangeType: String {
        case update = "UPDATE"
        case create = "CREATE"
        case delete = "DELETE"
        case undelete = "UNDELETE"
    }
    
    /// Parsed change type
    var parsedChangeType: ChangeType? {
        return ChangeType(rawValue: changeType)
    }
    
    /// First record ID (most common case)
    var recordId: String? {
        return recordIds.first
    }
}

