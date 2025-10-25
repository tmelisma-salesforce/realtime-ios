# Salesforce Pub/Sub API Architecture

> Complete technical architecture for implementing a Salesforce Pub/Sub API client in any language.  
> This document is language-agnostic and based on real implementation and observed behavior.

---

## Table of Contents

1. [Overview](#overview)
2. [Authentication Flow](#authentication-flow)
3. [gRPC Connection](#grpc-connection)
4. [Bidirectional Streaming Protocol](#bidirectional-streaming-protocol)
5. [Message Formats](#message-formats)
6. [Flow Control](#flow-control)
7. [Event Processing](#event-processing)
8. [Timing and Behavior](#timing-and-behavior)
9. [Allocations and Limits](#allocations-and-limits)
10. [Implementation Checklist](#implementation-checklist)

---

## Overview

### System Architecture

```
┌─────────────┐                                  ┌──────────────────┐
│   Client    │                                  │   Salesforce     │
│   (Your     │                                  │   Pub/Sub API    │
│   App)      │                                  │   Server         │
└──────┬──────┘                                  └────────┬─────────┘
       │                                                  │
       │  1. OAuth 2.0 Authentication (HTTPS)            │
       │─────────────────────────────────────────────────>│
       │                                                  │
       │<─────────────────────────────────────────────────│
       │  Access Token, Instance URL, Org ID             │
       │                                                  │
       │  2. gRPC Connection (TLS on port 7443)          │
       │─────────────────────────────────────────────────>│
       │                                                  │
       │  3. Subscribe RPC Call (bidirectional stream)   │
       │─────────────────────────────────────────────────>│
       │                                                  │
       │  4. Send FetchRequest #1 ────────────────────>  │
       │                                                  │
       │           <──── Send FetchResponse (keepalive) ─┤
       │                                                  │
       │  5. Send FetchRequest #2 ────────────────────>  │
       │                                                  │
       │           <──── Send FetchResponse (with event)─┤
       │                                                  │
       │  6. GetSchema RPC Call (unary) ──────────────>  │
       │                                                  │
       │           <──── Schema JSON ────────────────────┤
       │                                                  │
       │  7. Send FetchRequest #3 ────────────────────>  │
       │                                                  │
       │                    ... continues ...             │
```

### Key Components

1. **OAuth Client** - Handles authentication
2. **gRPC Client** - Manages connection and RPC calls
3. **Protocol Buffer Handler** - Serializes/deserializes messages
4. **Avro Decoder** - Decodes event payloads
5. **Flow Control** - Manages request/response cycles
6. **Event Processor** - Processes decoded events

---

## Authentication Flow

### Step 1: OAuth 2.0 Client Credentials

**Endpoint:** `https://{your-domain}.my.salesforce.com/services/oauth2/token`

**Method:** `POST`

**Headers:**
```
Content-Type: application/x-www-form-urlencoded
```

**Body (form-urlencoded):**
```
grant_type=client_credentials
client_id={YOUR_CLIENT_ID}
client_secret={YOUR_CLIENT_SECRET}
```

**Observed Timing:** ~0.4-0.6 seconds

**Success Response (200 OK):**
```json
{
  "access_token": "00Dxx0000001gER!AR8AQF...",
  "signature": "...",
  "scope": "api web full refresh_token",
  "instance_url": "https://your-domain.my.salesforce.com",
  "id": "https://login.salesforce.com/id/{orgId}/{userId}",
  "token_type": "Bearer",
  "issued_at": "1234567890123"
}
```

**Response Keys:**
- `access_token` - Required for all API calls (length: ~112 chars)
- `instance_url` - Your Salesforce instance URL
- `id` - URL containing organization ID and user ID
- `token_type` - Always "Bearer"
- `issued_at` - Token creation timestamp

### Step 2: Extract Organization ID

Parse the `id` field URL to extract the organization ID:

**Format:** `https://login.salesforce.com/id/{ORG_ID}/{USER_ID}`

**Example:** `https://login.salesforce.com/id/00Dxx0000001gERXXX/005xx000001AbCDEFG`

**Parsing:**
1. Split by `/`
2. Array index -2 (second to last) = Org ID: `00Dxx0000001gERXXX`
3. Array index -1 (last) = User ID: `005xx000001AbCDEFG`

**Required for gRPC:** You need:
- `accesstoken` - The access token
- `instanceurl` - The instance URL
- `tenantid` - The organization ID (from parsed `id` field)

### Authentication Alternatives

**Pub/Sub API supports multiple auth methods:**

1. **OAuth 2.0 Client Credentials** (recommended for server-to-server)
   - Used in this implementation
   - No user interaction required
   - Best for backend services and integrations

2. **OAuth 2.0 with other flows** (web apps, mobile apps)
   - Authorization Code flow
   - Device flow
   - JWT Bearer flow
   - Any flow that provides an access token works!

3. **Username/Password** (simplest, but less secure)
   - Get session ID via SOAP login
   - Use session ID as `accesstoken`
   - Not recommended for production

**All methods provide the same three required values:**
- Access token (or session ID)
- Instance URL
- Org ID (tenant ID)

---

## gRPC Connection

### Connection Details

**Endpoints:**

Global Endpoint (default):
```
api.pubsub.salesforce.com:{port}
```

Europe (Frankfurt) Endpoint (for data privacy compliance):
```
api.deu.pubsub.salesforce.com:{port}
```

**Ports:** Use either `443` or `7443` (both supported)

**Protocol:** gRPC over TLS/HTTPS

**Transport:** HTTP/2

**Certificate:** Use system CA certificates (standard SSL/TLS verification)

**Concurrent Stream Limit:** Maximum 1,000 concurrent RPC streams per HTTP/2 connection

### Protocol Buffer Definition

The API uses Protocol Buffers. You need to generate client code from:

**Proto File:** `pubsub_api.proto`

**Source:** https://github.com/forcedotcom/pub-sub-api

**Key Services:**
- `PubSub.Subscribe` - Bidirectional streaming RPC
- `PubSub.GetSchema` - Unary RPC (request/response)
- `PubSub.GetTopic` - Unary RPC (request/response)

### gRPC Metadata (Headers)

Every RPC call must include these metadata headers:

```
accesstoken: {YOUR_ACCESS_TOKEN}
instanceurl: {YOUR_INSTANCE_URL}
tenantid: {YOUR_ORG_ID}
```

**iOS/Swift Note:** In gRPC-Swift, these are added as custom metadata to each call.

---

## Bidirectional Streaming Protocol

### The Subscribe RPC

**Method:** `PubSub.Subscribe`

**Type:** Bidirectional streaming (client sends stream, server sends stream)

**Purpose:** Subscribe to a topic and receive real-time events

### Message Flow

The Subscribe call establishes a long-lived bidirectional stream:

```
Client Stream → FetchRequest → FetchRequest → FetchRequest → ...
                     ↓              ↓              ↓
Server Stream → FetchResponse → FetchResponse → FetchResponse → ...
```

### FetchRequest Message

**Sent by:** Client

**Purpose:** Request events from the server

**Message Structure:**
```protobuf
message FetchRequest {
  string topic_name = 1;           // e.g., "/data/OpportunityChangeEvent"
  ReplayPreset replay_preset = 2;  // LATEST, EARLIEST, or CUSTOM
  bytes replay_id = 3;              // Used with CUSTOM replay
  int32 num_requested = 4;          // Number of events to request
}
```

**Example Values:**
```
topic_name: "/data/OpportunityChangeEvent"
replay_preset: LATEST (enum value 0)
num_requested: 1
```

**ReplayPreset Enum:**
- `LATEST` (0) - Start from latest events (most common)
- `EARLIEST` (1) - Start from earliest available
- `CUSTOM` (2) - Start from specific replay_id

### FetchResponse Message

**Sent by:** Server

**Purpose:** Deliver events or keepalive messages

**Message Structure:**
```protobuf
message FetchResponse {
  repeated ConsumerEvent events = 1;  // Array of events (can be empty)
  bytes latest_replay_id = 2;         // Latest replay ID for resumption
  int32 pending_num_requested = 3;     // Number of pending requests
  RpcError rpc_error = 4;              // Error info if applicable
}
```

**Two Types of Responses:**

1. **Event Response** (`events.length > 0`):
   ```
   events: [ConsumerEvent]  // Contains actual event data
   latest_replay_id: b'\x00\x00\x00\x00\x00Z\x94\xf0\x00\x00'
   pending_num_requested: 0
   ```

2. **Keepalive Response** (`events.length == 0`):
   ```
   events: []  // Empty array
   latest_replay_id: b'\x00\x00\x00\x00\x00Z\x94\xec\x00\x00'
   pending_num_requested: 1
   ```

### ConsumerEvent Message

**Contained in:** FetchResponse.events[]

**Structure:**
```protobuf
message ConsumerEvent {
  EventInfo event = 1;       // The actual event data
  bytes replay_id = 2;        // Unique replay ID for this event
}

message EventInfo {
  bytes payload = 1;          // Avro-encoded event data
  string schema_id = 2;       // Schema ID to decode payload
  // ... other fields
}
```

**Example:**
```
event.payload: <328 bytes of Avro-encoded data>
event.schema_id: "KxC1P8xW4-iTJxZQ6PlZpw"
replay_id: b'\x00\x00\x00\x00\x00Z\x94\xf0\x00\x00'
```

---

## Message Formats

### Topic Names

**Format:** `/{type}/{name}`

**Examples:**
- Change Data Capture: `/data/OpportunityChangeEvent`
- Platform Events: `/event/MyCustomEvent__e`
- All CDC events: `/data/ChangeEvents`
- Custom channel: `/data/MyChannel__chn`

### Replay IDs

**Format:** Binary bytes (typically 10 bytes)

**Example:** `b'\x00\x00\x00\x00\x00Z\x94\xf0\x00\x00'`

**Purpose:** 
- Track position in event stream
- Resume from specific point if disconnected
- Always store latest replay ID from each FetchResponse

**Usage:**
```
To resume from last event:
  replay_preset = CUSTOM
  replay_id = <stored replay ID>
```

### Schema IDs

**Format:** String identifier

**Example:** `"KxC1P8xW4-iTJxZQ6PlZpw"`

**Purpose:** Identifies the Avro schema for decoding the event payload

**Lookup:** Use `GetSchema` RPC to fetch the schema JSON

---

## Flow Control

### The Request-Response Cycle

**Critical Rule:** You must send a new FetchRequest AFTER receiving each FetchResponse.

**Observed Pattern:**
```
Time: 10:56:55.860
  → Send FetchRequest #1 (num_requested: 1)

Time: 10:57:03.014  
  ← FetchRequest generator ready for next request (but blocked)

Time: 10:57:21.698 (18.7 seconds later)
  ← Receive FetchResponse #1 (with event)
  → IMMEDIATELY release lock
  → Send FetchRequest #2 (num_requested: 1)

Time: 10:57:21.699 (1ms later)
  ← FetchRequest generator ready for next request (but blocked)
```

### Semaphore Pattern (Flow Control)

Use a semaphore/lock to control the request cycle:

**Initialization:**
```
semaphore = Semaphore(value: 1)  // Initially unlocked
```

**Request Thread/Generator:**
```
loop {
  wait_for_semaphore()           // Block until released
  create_fetch_request()
  send_to_server()
}
```

**Response Handler:**
```
for each response from server {
  release_semaphore()           // ALWAYS release first
  
  if response.has_events {
    process_events()
  } else {
    // Keepalive - do nothing
  }
  
  store_replay_id(response.latest_replay_id)
}
```

**Critical Points:**
1. ALWAYS release semaphore for BOTH event and keepalive responses
2. Release BEFORE processing events (to allow next request to be queued)
3. Initial semaphore value is 1 (unlocked) to allow first request

### Why This Pattern?

Without proper flow control:
- ❌ Sending too many requests → Server may throttle or reject
- ❌ Not sending requests → No events received
- ❌ Not handling keepalives → Deadlock (observed bug in initial implementation)

With semaphore:
- ✅ Exactly one outstanding request at a time
- ✅ New request sent immediately after response
- ✅ No deadlocks from keepalives

---

## Event Processing

### Step 1: Receive FetchResponse

When a FetchResponse arrives with events (`events.length > 0`):

```
FetchResponse {
  events: [
    ConsumerEvent {
      event: EventInfo {
        payload: <328 bytes>
        schema_id: "KxC1P8xW4-iTJxZQ6PlZpw"
      }
      replay_id: <binary>
    }
  ]
  latest_replay_id: <binary>
}
```

### Step 2: Fetch Schema

**Make a separate GetSchema RPC call:**

**Method:** `PubSub.GetSchema` (unary RPC)

**Request:**
```protobuf
message SchemaRequest {
  string schema_id = 1;  // e.g., "KxC1P8xW4-iTJxZQ6PlZpw"
}
```

**Response:**
```protobuf
message SchemaResponse {
  string schema_json = 1;  // Avro schema as JSON string (10,127 chars)
  string schema_id = 2;
}
```

**Observed Timing:** ~1.0-1.2 seconds

**⚠️ CRITICAL: Schema Caching Strategy**

**DO NOT call GetSchema for every event!** This is a major performance killer.

**Best Practice:**
```
1. Fetch schema once and cache by schema_id
2. On each event, check if you have the schema cached
3. Only call GetSchema if schema_id is new
4. Schemas rarely change (only when admin modifies event definition)
5. When schema changes, schema_id changes automatically
```

**Cache Implementation Pattern:**
```swift
var schemaCache: [String: AvroSchema] = [:]

func getSchema(schemaId: String) async throws -> AvroSchema {
  // Check cache first
  if let cached = schemaCache[schemaId] {
    return cached
  }
  
  // Not cached - fetch from server
  let response = try await client.getSchema(schemaId)
  let schema = parseAvroSchema(response.schema_json)
  
  // Cache for future use
  schemaCache[schemaId] = schema
  return schema
}
```

**Why Caching Matters:**
- 🐌 Without cache: 1-1.2s per event
- ⚡ With cache: 0.01s per event (100x faster!)
- Schemas are stable and change infrequently
- Schema ID changes when admin updates event definition

### Step 3: Decode Avro Payload

**Input:**
- Schema JSON (from GetSchema)
- Binary payload (from event.payload)

**Process:**
1. Parse schema JSON using Avro library
2. Create binary decoder with payload bytes
3. Decode using schema to get structured data

**iOS/Swift Note:** Use `BlueSteel` or `Avro` Swift library

**Example Schema Structure:**
```json
{
  "type": "record",
  "name": "OpportunityChangeEvent",
  "fields": [
    {
      "name": "ChangeEventHeader",
      "type": {
        "type": "record",
        "fields": [
          {"name": "entityName", "type": "string"},
          {"name": "recordIds", "type": {"type": "array", "items": "string"}},
          {"name": "changeType", "type": "string"},
          ...
        ]
      }
    },
    {"name": "StageName", "type": ["null", "string"]},
    {"name": "Amount", "type": ["null", "double"]},
    ...
  ]
}
```

### Step 4: Process Decoded Event

**Decoded Structure:**
```json
{
  "ChangeEventHeader": {
    "entityName": "Opportunity",
    "recordIds": ["006xx000000AbCDEFG"],
    "changeType": "UPDATE",
    "transactionKey": "0006e261-c967-31c3-f492-0ea68f20d733",
    "sequenceNumber": 1,
    "commitTimestamp": 1761415040000,
    "commitUser": "005xx000001AbCDEFG",
    "changedFields": ["0xA0060140"]
  },
  "StageName": "Proposal/Quote",
  "Probability": 75.0,
  "LastModifiedDate": 1761415040000,
  ...
}
```

**ChangeEventHeader Fields:**
- `entityName` - Object type (e.g., "Opportunity")
- `recordIds` - Array of affected record IDs
- `changeType` - CREATE, UPDATE, DELETE, UNDELETE
- `changeOrigin` - Source of change
- `transactionKey` - Unique transaction identifier
- `commitTimestamp` - Milliseconds since epoch
- `commitUser` - User who made the change
- `changedFields` - Bitmap of changed fields (needs decoding)
- `nulledFields` - Bitmap of fields set to null (needs decoding)

**Field Bitmaps:**
The `changedFields` and `nulledFields` are hex-encoded bitmaps that indicate which fields changed.
Decoding these requires bitwise operations and field mapping (advanced topic).

---

## Timing and Behavior

### Observed Timings from Real Implementation

**OAuth Authentication:**
- Request time: 0.4-0.6 seconds
- Token length: 112 characters
- Token format: `00Dxx0000001gER!AR8AQ...`

**gRPC Connection:**
- Connection establishment: < 0.1 seconds (typically instant)
- First Subscribe call: < 0.1 seconds

**Event Delivery:**
- Time from FetchRequest to FetchResponse with event: 18.7 seconds (observed)
- This varies based on when changes occur in Salesforce

**Keepalive Timing:**
- Keepalives arrive when no events are pending
- No fixed interval observed (server-driven)
- Always has empty events array

**Schema Fetch:**
- GetSchema RPC time: 1.0-1.2 seconds
- Schema size: ~10,127 characters
- Schema is stable - cache it!

**Avro Decoding:**
- Decode time: ~0.01 seconds (very fast)
- Payload size: 300-500 bytes typically

### Keepalive Behavior

**Purpose:** Keepalives confirm the subscription is active when no events are occurring.

**Two Types of Keepalives:**

1. **Server-Initiated Keepalives:**
   - Sent within **270 seconds** when pending events exist but no new events are available
   - Contains empty events array
   - Contains latest replay_id (may be advanced position in stream)
   - Keeps subscription stream alive

2. **Client-Initiated Keepalives:**
   - **Critical:** If no pending events (`pending_num_requested == 0`), client MUST send new FetchRequest within **60 seconds**
   - Failure to do so → stream closes → must call Subscribe again
   - Always monitor `pending_num_requested` value!

**Characteristics:**
```
FetchResponse {
  events: []                          // Empty!
  latest_replay_id: <binary>          // Still provided (save this!)
  pending_num_requested: 1            // If > 0, server sends keepalives
                                      // If == 0, YOU must send request within 60s!
}
```

**Action Required:**
1. Release semaphore (to send next FetchRequest)
2. **ALWAYS save replay_id** from keepalives (even if advanced)
3. Check `pending_num_requested`:
   - If 0: Send new FetchRequest within 60 seconds
   - If > 0: Server handles keepalives, you can wait
4. Update UI (optional - show "subscription active")
5. Do NOT process events (array is empty)

**Common Bugs:**
- ❌ Forgetting to release semaphore on keepalives → deadlock!
- ❌ Not sending FetchRequest when `pending_num_requested == 0` → stream closes after 60s
- ❌ Not saving replay_id from keepalives → miss events on reconnect

---

## Allocations and Limits

### Subscribe / FetchRequest Limits

**Maximum Events per Subscribe Call:**
- Hard limit: **100 events** across all FetchRequests
- If you request more than 100, server treats it as 100
- This limit is per Subscribe call (can have multiple Subscribe calls)

**Recommended num_requested:**
- For single-event processing: `num_requested = 1` (simplest flow control)
- For batch processing: `num_requested = 10-100` (requires complex flow control)
- Balance between throughput and processing capacity

**Event Delivery:**
- Server can deliver in one or multiple FetchResponses
- Each response ≤ 3 MB total size
- Track `pending_num_requested` to know how many events are queued

### Session Timeout

**OAuth Access Token Expiration:**
- Default: 2 hours of inactivity (can be customized in Connected App or profile)
- Subscribe stream: Token timeout doesn't matter! Keepalives keep connection alive indefinitely
- Other RPCs: Complete quickly, so timeout rarely an issue
- Best practice: Refresh token on AUTH_ERROR and reconnect

**Stream Keepalive Requirements:**
- If `pending_num_requested == 0`: Send FetchRequest within 60 seconds or stream closes
- If `pending_num_requested > 0`: Server sends keepalives within 270 seconds

### Message Size Limits

**Publishing (not covered in this doc, but good to know):**
- Single event: Maximum 1 MB
- Batch publish request: Maximum 3 MB total (below 4 MB gRPC limit)
- Recommended: No more than 200 events per publish request

**Subscribing:**
- Each FetchResponse: Maximum 3 MB
- Events automatically split across multiple responses if needed
- No limit on individual event size in FetchResponse

### Concurrent Connections

**gRPC HTTP/2 Connection:**
- Maximum 1,000 concurrent RPC streams per connection
- Each Subscribe, GetSchema, GetTopic call counts as one stream
- After 1,000, new RPCs queue until others complete
- **Recommendation:** Use separate gRPC channels for high-volume scenarios

**Multiple Subscriptions:**
- Can have multiple Subscribe calls from same client
- Each subscription has independent flow control
- Each subscription counts toward concurrent stream limit

### Replay ID Storage

**Replay ID Retention:**
- Events retained in event bus: **3 days**
- After 3 days, replay ID becomes invalid
- Use `EARLIEST` preset if you've been disconnected > 3 days
- Store replay IDs as **bytes** (opaque, not always numbers)

**Best Practice:**
```
- Save replay_id from EVERY FetchResponse (events and keepalives)
- Persist to disk/database periodically
- Use most recent replay_id when reconnecting
- Advanced replay_id in keepalive is better than old event replay_id
```

---

## Implementation Checklist

### Phase 1: Authentication
- [ ] Implement OAuth 2.0 Client Credentials POST request
- [ ] Parse JSON response
- [ ] Extract `access_token`, `instance_url`, and `id` fields
- [ ] Parse organization ID from `id` URL
- [ ] Store credentials securely
- [ ] Handle authentication errors (401, 400, network errors)

### Phase 2: gRPC Setup
- [ ] Add gRPC library to project (gRPC-Swift for iOS)
- [ ] Generate Swift code from `pubsub_api.proto`
- [ ] Create secure gRPC channel to `api.pubsub.salesforce.com:7443`
- [ ] Configure TLS/SSL with system certificates
- [ ] Create PubSub service stub

### Phase 3: Subscribe Implementation
- [ ] Create metadata headers (accesstoken, instanceurl, tenantid)
- [ ] Implement Subscribe bidirectional stream
- [ ] Create FetchRequest generator/stream
- [ ] Implement semaphore for flow control
- [ ] Send initial FetchRequest with:
  - topic_name
  - replay_preset: LATEST
  - num_requested: 1

### Phase 4: Response Handling
- [ ] Receive FetchResponse messages in loop
- [ ] Release semaphore IMMEDIATELY for every response
- [ ] Check if response has events (`events.count > 0`)
- [ ] Handle keepalive responses (empty events array)
- [ ] Store latest_replay_id for each response
- [ ] Track session statistics (events, keepalives, requests)

### Phase 5: Event Processing
- [ ] Extract schema_id from event
- [ ] Make GetSchema RPC call
- [ ] Cache schemas by schema_id
- [ ] Decode Avro payload using schema
- [ ] Parse decoded JSON
- [ ] Extract ChangeEventHeader
- [ ] Process event data in UI

### Phase 6: Error Handling
- [ ] Handle gRPC errors (UNAVAILABLE, DEADLINE_EXCEEDED, etc.)
- [ ] Handle authentication expiration (refresh token)
- [ ] Handle network disconnections (reconnect with replay)
- [ ] Handle schema fetch failures (retry)
- [ ] Handle Avro decode failures (log and skip)

### Phase 7: Advanced Features
- [ ] Implement replay from specific replay_id
- [ ] Support multiple topics simultaneously
- [ ] Batch event processing (num_requested > 1)
- [ ] Decode bitmap fields (changedFields, nulledFields)
- [ ] Background processing
- [ ] Offline queueing

---

## iOS/Swift Specific Notes

### Required Libraries

```swift
// Package.swift dependencies
.package(url: "https://github.com/grpc/grpc-swift.git", from: "1.0.0")
.package(url: "https://github.com/linkedin/swift-avro", from: "0.0.1")
// Or use BlueSteel for Avro
```

### Code Generation

```bash
# Generate Swift gRPC code from proto
protoc pubsub_api.proto \
  --swift_out=. \
  --grpc-swift_out=.
```

### gRPC Metadata in Swift

```swift
let callOptions = CallOptions(
  customMetadata: HPACKHeaders([
    ("accesstoken", accessToken),
    ("instanceurl", instanceURL),
    ("tenantid", orgID)
  ])
)
```

### Bidirectional Streaming in Swift

```swift
let call = client.subscribe(callOptions: callOptions)

// Send FetchRequests
Task {
  for await _ in semaphore.stream {
    let request = FetchRequest.with {
      $0.topicName = "/data/OpportunityChangeEvent"
      $0.replayPreset = .latest
      $0.numRequested = 1
    }
    try await call.requestStream.send(request)
  }
}

// Receive FetchResponses
for try await response in call.responseStream {
  semaphore.signal()  // Release immediately
  
  if !response.events.isEmpty {
    // Process events
  }
}
```

### SwiftUI Integration

```swift
@MainActor
class PubSubViewModel: ObservableObject {
  @Published var events: [OpportunityEvent] = []
  @Published var isConnected = false
  @Published var lastUpdate: Date?
  
  private var grpcChannel: GRPCChannel?
  private var subscriptionTask: Task<Void, Never>?
  
  func connect() async {
    // Setup gRPC, authenticate, subscribe
  }
  
  func disconnect() {
    subscriptionTask?.cancel()
  }
}
```

---

## Common Pitfalls

### 1. Semaphore Deadlock
**Problem:** Not releasing semaphore for keepalive responses  
**Solution:** ALWAYS release semaphore for every FetchResponse

### 2. Schema Refetch
**Problem:** Fetching schema for every event (slow!)  
**Solution:** Cache schemas by schema_id in memory

### 3. Missing Metadata
**Problem:** Forgetting to add gRPC metadata headers  
**Solution:** Add to all RPC calls, not just Subscribe

### 4. Token Expiration
**Problem:** Access token expires, calls fail  
**Solution:** Monitor for AUTH errors, re-authenticate

### 5. Replay ID Loss
**Problem:** Not storing replay_id, can't resume  
**Solution:** Persist latest_replay_id (UserDefaults, Database)

### 6. Batch Processing
**Problem:** Setting num_requested > 1 without adjusting semaphore logic  
**Solution:** Semaphore pattern works best with num_requested = 1

---

## Testing Strategy

### Unit Tests
- OAuth token parsing
- gRPC metadata construction
- Avro schema parsing
- Replay ID storage/retrieval

### Integration Tests
- Connect to Pub/Sub API
- Send FetchRequest
- Receive keepalive
- Process real event (requires Salesforce org)

### Manual Testing
1. Run app
2. Verify connection
3. Make change in Salesforce
4. Verify event received
5. Check event data accuracy

### Monitoring
Track these metrics:
- Events received per minute
- Keepalives per minute
- Average event processing time
- Schema cache hit rate
- Connection uptime

---

## Additional Resources

- **Proto File:** https://github.com/forcedotcom/pub-sub-api/blob/main/pubsub_api.proto
- **Salesforce Docs:** https://developer.salesforce.com/docs/platform/pub-sub-api/overview
- **gRPC Swift:** https://github.com/grpc/grpc-swift
- **Avro Swift:** https://github.com/linkedin/swift-avro

---

## Summary

**Key Points to Remember:**

1. **OAuth first** - Get access token, instance URL, and org ID
2. **gRPC metadata** - Add three headers to every call
3. **Bidirectional streaming** - Subscribe is a long-lived stream
4. **Flow control** - Use semaphore, one outstanding request
5. **Keepalives** - Empty responses, release semaphore!
6. **Schema caching** - Don't fetch schema repeatedly
7. **Avro decoding** - Use Avro library with fetched schema
8. **Replay IDs** - Store them for resumption

**Architecture Pattern:**
```
Authenticate → Connect → Subscribe → [Request → Response Loop] → Process Events
```

This architecture enables real-time, scalable event streaming from Salesforce to any client platform.

