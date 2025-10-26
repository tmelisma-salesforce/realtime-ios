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
/// IMPORTANT: ALL fields must be defined in the EXACT order they appear in the Avro schema
struct OpportunityChangeEventPayload: Codable {
    let ChangeEventHeader: ChangeEventHeader
    
    // Standard Opportunity fields (in schema order) - all optional
    let AccountId: String?
    let RecordTypeId: String?
    let IsPrivate: Bool?
    let Name: String?
    let Description: String?
    let StageName: String?
    let Amount: Double?
    let Probability: Double?
    let ExpectedRevenue: Double?
    let TotalOpportunityQuantity: Double?
    let CloseDate: Int64?
    let OpportunityType: String?  // "Type" is a Swift keyword, so renamed
    let NextStep: String?
    let LeadSource: String?
    let IsClosed: Bool?
    let IsWon: Bool?
    let ForecastCategory: String?
    let ForecastCategoryName: String?
    let CurrencyIsoCode: String?
    let CampaignId: String?
    let HasOpportunityLineItem: Bool?
    let IsSplit: Bool?
    let Pricebook2Id: String?
    let OwnerId: String?
    let Territory2Id: String?
    let IsExcludedFromTerritory2Filter: Bool?
    let CreatedDate: Int64?
    let CreatedById: String?
    let LastModifiedDate: Int64?
    let LastModifiedById: String?
    let LastStageChangeDate: Int64?
    let ContactId: String?
    let SourceId: String?
    let PartnerAccountId: String?
    let SyncedQuoteId: String?
    let ContractId: String?
    let LastAmountChangedHistoryId: String?
    let LastCloseDateChangedHistoryId: String?
    
    // Custom fields (in schema order) - all optional
    let External_ID__c: String?
    let db_days_CloseDate__c: Double?
    let CloseDate_TODAY__c: Double?
    let SDO_Pardot_Is_B2BMA_Plus_Data__c: Bool?
    let SDO_Quip_Close_Plan_Quip__c: String?
    let SDO_Sales_Discount__c: Double?
    let SDO_Sales_Partner_Owner__c: String?
    let SDO_Sales_Primary_Contact__c: String?
    let SDO_Sales_Reason_Lost__c: String?
    let SDO_Sales_Stalled_Opportunity__c: Bool?
    let SDO_Sales_Winning_Competitor__c: String?
    let SDO_Sales_Status_Value__c: String?
    let DateTimeCreated__c: Int64?
    let ED_Leading_Causes__c: String?
    let ED_Outcome__c: Double?
    let ED_Prescription__c: String?
    let Exec_Meeting__c: Bool?
    let Interactive_Demo__c: Bool?
    let ED_Close_Date_Delta__c: Double?
    let ED_Predicted_Close_Date__c: Int64?
    let Products__c: String?
    let SDO_Service_Case__c: String?
    let SDO_SFS_Work_Order__c: String?
    let SBQQ__AmendedContract__c: String?
    let SBQQ__Contracted__c: Bool?
    let SBQQ__CreateContractedPrices__c: Bool?
    let SBQQ__OrderGroupID__c: String?
    let SBQQ__Ordered__c: Bool?
    let SBQQ__PrimaryQuote__c: String?
    let SBQQ__QuotePricebookId__c: String?
    let SBQQ__Renewal__c: Bool?
    let SBQQ__RenewedContract__c: String?
    let sbaa__ApprovalStatus__c: String?
    let sbaa__ApprovalStep__c: Double?
    let sbaa__Approver__c: String?
    let sbaa__StepApproved__c: Bool?
    let sbaa__SubmittedDate__c: Int64?
    let sbaa__SubmittedUser__c: String?
    let ApprovalStatus__c: String?
    let DB_Amount__c: Double?
    let DB_Days__c: Double?
    let SDO_MAPS_Dataset_Split__c: Double?
    let SDO_MAPS_Tag_Opportunity__c: String?
    let SDO_Sales_Competitor__c: String?
    let SDO_Sales_Complete_ROI_Analysis__c: Bool?
    let SDO_Sales_Contract_Terms__c: String?
    let SDO_Sales_Project_Budgeted__c: Bool?
    let SDO_Sales_Project_Manager_Contact__c: String?
    let LastActivityDate__c: Int64?
    let LastModifiedDate__c: Int64?
    let analyticsdemo_batch_id__c: String?
    
    // Custom CodingKeys to handle Swift reserved keywords
    enum CodingKeys: String, CodingKey {
        case ChangeEventHeader
        case AccountId, RecordTypeId, IsPrivate, Name, Description, StageName
        case Amount, Probability, ExpectedRevenue, TotalOpportunityQuantity
        case CloseDate
        case OpportunityType = "Type"  // Map Swift property to Avro field name
        case NextStep, LeadSource, IsClosed, IsWon
        case ForecastCategory, ForecastCategoryName, CurrencyIsoCode
        case CampaignId, HasOpportunityLineItem, IsSplit, Pricebook2Id
        case OwnerId, Territory2Id, IsExcludedFromTerritory2Filter
        case CreatedDate, CreatedById, LastModifiedDate, LastModifiedById
        case LastStageChangeDate, ContactId, SourceId, PartnerAccountId
        case SyncedQuoteId, ContractId
        case LastAmountChangedHistoryId, LastCloseDateChangedHistoryId
        case External_ID__c, db_days_CloseDate__c, CloseDate_TODAY__c
        case SDO_Pardot_Is_B2BMA_Plus_Data__c, SDO_Quip_Close_Plan_Quip__c
        case SDO_Sales_Discount__c, SDO_Sales_Partner_Owner__c
        case SDO_Sales_Primary_Contact__c, SDO_Sales_Reason_Lost__c
        case SDO_Sales_Stalled_Opportunity__c, SDO_Sales_Winning_Competitor__c
        case SDO_Sales_Status_Value__c, DateTimeCreated__c
        case ED_Leading_Causes__c, ED_Outcome__c, ED_Prescription__c
        case Exec_Meeting__c, Interactive_Demo__c
        case ED_Close_Date_Delta__c, ED_Predicted_Close_Date__c
        case Products__c, SDO_Service_Case__c, SDO_SFS_Work_Order__c
        case SBQQ__AmendedContract__c, SBQQ__Contracted__c
        case SBQQ__CreateContractedPrices__c, SBQQ__OrderGroupID__c
        case SBQQ__Ordered__c, SBQQ__PrimaryQuote__c
        case SBQQ__QuotePricebookId__c, SBQQ__Renewal__c
        case SBQQ__RenewedContract__c, sbaa__ApprovalStatus__c
        case sbaa__ApprovalStep__c, sbaa__Approver__c
        case sbaa__StepApproved__c, sbaa__SubmittedDate__c
        case sbaa__SubmittedUser__c, ApprovalStatus__c
        case DB_Amount__c, DB_Days__c
        case SDO_MAPS_Dataset_Split__c, SDO_MAPS_Tag_Opportunity__c
        case SDO_Sales_Competitor__c, SDO_Sales_Complete_ROI_Analysis__c
        case SDO_Sales_Contract_Terms__c, SDO_Sales_Project_Budgeted__c
        case SDO_Sales_Project_Manager_Contact__c
        case LastActivityDate__c, LastModifiedDate__c
        case analyticsdemo_batch_id__c
    }
    
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
/// Fields MUST match the Avro schema order exactly for proper decoding
struct ChangeEventHeader: Codable {
    let entityName: String
    let recordIds: [String]
    let changeType: String  // UPDATE, CREATE, DELETE, UNDELETE (actually an enum in schema)
    let changeOrigin: String
    let transactionKey: String
    let sequenceNumber: Int
    let commitTimestamp: Int64
    let commitNumber: Int64
    let commitUser: String
    let nulledFields: [String]
    let diffFields: [String]
    let changedFields: [String]
    
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

