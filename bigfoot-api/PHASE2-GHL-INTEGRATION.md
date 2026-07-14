# Phase 3 — GoHighLevel (GHL) CRM Integration Plan

> ⚠️ **RELABELED (July 2026): this is the PHASE 3 plan, not Phase 2.**
> Phase 2 is the **QuickBooks-native Sales Orders + Shop BOMs** work —
> see `BIGFOOT_PHASE2_BUILD_PLAN.md` and `BIGFOOT_PHASE2_PLAN (1).pdf`
> in the repo root. CRM comes AFTER Phase 2 is piloted, because the
> Phase 2 configurator IS the Phase 3 quote engine — building CRM first
> means building the configurator twice. (The filename still says
> "PHASE2" for git-history continuity; treat the contents as Phase 3.)
>
> **Status:** Planning. Nothing in this document is implemented yet.
> Reviewers: please flag any business assumption that doesn't match
> reality before engineering starts.

---

## Table of contents

- [0. Executive summary](#0-executive-summary)
- [1. Why GHL and not something else](#1-why-ghl-and-not-something-else)
- [2. Open questions for stakeholders (decide before building)](#2-open-questions-for-stakeholders-decide-before-building)
- [3. Domain mapping — Bigfoot ↔ GHL](#3-domain-mapping--bigfoot--ghl)
- [4. Target architecture](#4-target-architecture)
- [5. Authentication & API access](#5-authentication--api-access)
- [6. Sync model & conflict resolution](#6-sync-model--conflict-resolution)
- [7. Webhook receiver design](#7-webhook-receiver-design)
- [8. SMS strategy — Twilio vs GHL](#8-sms-strategy--twilio-vs-ghl)
- [9. Data model changes (new tables + columns)](#9-data-model-changes-new-tables--columns)
- [10. New endpoints & background jobs](#10-new-endpoints--background-jobs)
- [11. Mobile-app impact](#11-mobile-app-impact)
- [12. Security & compliance](#12-security--compliance)
- [13. Operational concerns](#13-operational-concerns)
- [14. Testing strategy](#14-testing-strategy)
- [15. Implementation roadmap (8 milestones)](#15-implementation-roadmap-8-milestones)
- [16. Effort & cost estimate](#16-effort--cost-estimate)
- [17. Rollout plan](#17-rollout-plan)
- [18. Risks & mitigations](#18-risks--mitigations)
- [19. Non-goals (explicitly out of scope)](#19-non-goals-explicitly-out-of-scope)
- [Appendix A. GHL entity reference (what we'll use)](#appendix-a-ghl-entity-reference-what-well-use)
- [Appendix B. Required env vars + secrets](#appendix-b-required-env-vars--secrets)
- [Appendix C. Sample API contracts](#appendix-c-sample-api-contracts)

---

## 0. Executive summary

In Phase 2 we integrate **GoHighLevel (GHL)** with the existing Bigfoot
Trailers platform so that:

1. **Every customer in Bigfoot is automatically a contact in GHL**, with
   their orders, deliveries, and conversation history visible from a
   single CRM view.
2. **Every trailer is an opportunity in a sales pipeline**, moving
   automatically through stages as production progresses: *Lead → Quoted
   → Sold → In Production → QC → Ready for Delivery → Delivered*.
3. **Customer SMS** (today: Twilio direct) is routed through GHL's
   conversations system so sales/office staff have a unified inbox and
   marketing can run automated drip campaigns.
4. **GHL becomes the lead-capture front door** — website forms,
   calendars (showroom visits, factory tours), and ad campaigns feed
   leads into GHL, which then sync into our database when they become
   real customers.
5. Reporting in GHL (sales funnel, conversion rates, response times) is
   driven by real production data from the API.

**This document plans Phase 2. It is not a final design** — sections 2
and 17 surface the decisions a stakeholder needs to make before
engineering begins.

**Estimated scope:** 4–6 weeks of one engineer's time end-to-end,
deployable behind a feature flag in incremental milestones.

---

## 1. Why GHL and not something else

We assume GHL is already the chosen CRM, but for completeness — here's
why it fits this business:

| Need | GHL fit |
|---|---|
| Contact + opportunity (pipeline) management | First-class, mature |
| SMS to customers (factory pickup, delivery updates) | Built-in, unified inbox |
| Automated follow-ups (review requests, finance reminders) | Workflow builder |
| Lead capture from website / ads | Forms, funnels, calendars |
| Multi-user staff inbox (sales sees the same convo as office) | Built-in |
| Custom fields (SO number, model, build status) | Supported |
| Webhooks + REST API (so we can integrate) | Yes — both inbound and outbound |
| Reasonable cost at one-business scale | Yes (single sub-account on the agency tier) |

**Alternative considered:** building this in HubSpot or Salesforce. Both
work, but cost 5–10× more per month at our user count, and the SMS
unification story is weaker.

---

## 2. Open questions for stakeholders (decide before building)

Engineering shouldn't start until these are answered. Each one
materially changes the design.

### Account architecture

- **2.1** Do we have an **existing GHL account** for Bigfoot Trailers,
  or do we provision a new one? *(If existing — what tier?)*
- **2.2** Will Bigfoot Trailers be its own **sub-account under an agency
  account**, or a **standalone account**? (Sub-account = OAuth Marketplace
  app; standalone = simpler Location API key.)
- **2.3** Who manages GHL day-to-day (sales? office? owner?) — this
  drives the UI defaults and notification rules.

### Feature scope

- **2.4** Which GHL features do we actually want active?
  - [ ] Contacts + Opportunities (must-have)
  - [ ] Conversations (SMS) — *required to unify customer comms*
  - [ ] Calendars (showroom visits, factory tours)
  - [ ] Workflows / Automations (drip campaigns, reminders)
  - [ ] Forms & funnels (website lead capture)
  - [ ] Reputation Mgmt (review requests after delivery)
  - [ ] Memberships / Communities (not applicable; skip)
  - [ ] Email marketing (sales newsletters)
- **2.5** Do we want **two-way sync** of customers (edit in GHL =
  reflected in Bigfoot) or **one-way** (Bigfoot is source of truth, GHL
  is read-only mirror)? *(Two-way is much more complex.)*

### Twilio coexistence

- **2.6** Do we **replace Twilio entirely** with GHL's SMS, **keep
  Twilio for transactional only** (trailer-complete, driver-en-route,
  delivery-complete) and use GHL for marketing/conversations, or **keep
  both fully**?
- **2.7** Do we want **inbound SMS** (customer replies) to feed into GHL
  conversations? (Today the system is fire-and-forget outbound only.)

### Data ownership

- **2.8** When a customer's email changes in GHL, does Bigfoot's
  database update automatically, or does it ignore that change?
- **2.9** When a trailer enters production in Bigfoot, does GHL's
  opportunity stage move automatically? (Default answer: yes.)
- **2.10** When sales marks an opportunity "Sold" in GHL, does that
  create the trailer in Bigfoot, or does the trailer have to be created
  in Bigfoot first?

### Lead → customer transition

- **2.11** How does a **lead in GHL** become a **customer in Bigfoot**?
  - **Option A**: When sales fills in a "convert to order" action in
    GHL, our API receives a webhook and creates the customer.
  - **Option B**: When office staff create a trailer in Bigfoot's mobile
    app and pick a GHL contact via search, the contact is "promoted" to
    a customer.
  - **Option C**: Both.

### Compliance & privacy

- **2.12** Is the customer list subject to **TCPA** (US SMS consent
  rules) or **CASL** (Canada)? — affects whether we need explicit opt-in
  tracking before any SMS.
- **2.13** Should customer records be **purgeable on request** (right to
  be forgotten)? — affects whether we hard-delete from both systems or
  soft-delete.

---

## 3. Domain mapping — Bigfoot ↔ GHL

This is the meat. Each row defines a sync relationship.

### 3.1 Entities

| Bigfoot entity | GHL entity | Sync direction | Source of truth |
|---|---|---|---|
| `customers` (end_user, dealer) | **Contact** | Bigfoot → GHL (outbound on create/update) | Bigfoot |
| `customers` (stock_location) | *(not synced)* | n/a | Bigfoot |
| `trailers` | **Opportunity** (in pipeline "Production") | Bigfoot → GHL on state change | Bigfoot |
| Trailer `sale_status` change | Opportunity **stage** | Bigfoot → GHL | Bigfoot |
| `users` (sales, owner) | GHL **user** (mapped, not synced) | Manual mapping | GHL |
| `sms_log` outbound | GHL **Conversation message** | Either via Twilio-as-GHL or direct GHL Conversations API | Depends on §8 decision |
| Inbound customer SMS | GHL **Conversation** + Bigfoot `inbound_messages` (new table) | GHL → Bigfoot on webhook | GHL |
| `deliveries` (status changes) | Opportunity stage + GHL **custom event** | Bigfoot → GHL | Bigfoot |
| GHL Lead (form submission) | New `leads` table in Bigfoot | GHL → Bigfoot on webhook | GHL |

### 3.2 Field mapping — Customer → GHL Contact

| Bigfoot `customer` column | GHL Contact field |
|---|---|
| `id` | Stored in custom field `bigfoot_customer_id` (for back-reference) |
| `name` | `firstName` + `lastName` (split on first space) |
| `company` | `companyName` |
| `customerType` (end_user / dealer) | Custom field `customer_type` |
| `smsPhone` | `phone` |
| `email` *(if added in future)* | `email` |
| `smsOptOut` | `dnd: true` (Do Not Disturb) |
| `stockLocationId` | Custom field `stock_location_code` |
| `createdAt` | Custom field `bigfoot_created_at` (for audit) |
| All trailers (count, latest SO) | Contact tags (`has_trailer:SO-1001`, `loyal:5+_orders`) |

### 3.3 Field mapping — Trailer → GHL Opportunity

| Bigfoot `trailer` column | GHL Opportunity field |
|---|---|
| `id` | Custom field `bigfoot_trailer_id` |
| `soNumber` | `name` (e.g. "SO-1001 — 14K XP") |
| `customerId` | `contactId` (FK to GHL contact created from this customer) |
| `trailerModel.displayName` | Custom field `trailer_model` |
| `sizeFt`, `color`, `optionsNotes` | Custom field `trailer_specs` (JSON-ish text) |
| `status` (production status) | Maps to **pipeline stage** (see below) |
| `saleStatus` | Maps to opportunity **status** (open/won/lost) |
| `createdAt` | Custom field `order_date` |
| Final delivery date | Custom field `delivered_date` (set on delivery complete) |

### 3.4 Pipeline stage mapping

GHL pipelines are configurable. We create one pipeline named **"Trailer
Production"** with these stages:

| Bigfoot `trailer.status` | GHL pipeline stage | Opportunity status |
|---|---|---|
| (lead, pre-trailer) | "New Lead" | Open |
| (lead, quoted) | "Quoted" | Open |
| `pending_production` | "Sold — Awaiting Production" | Won (but opp stays open) |
| `in_production` | "In Production" | Open |
| `ready_for_delivery` | "Ready for Delivery" | Open |
| `in_transit` | "Out for Delivery" | Open |
| `delivered` | "Delivered" | Won — closed |
| `on_hold` | "On Hold" | Open |

**Note**: GHL opportunity statuses are `open | won | lost | abandoned`.
We mark the opportunity Won and *closed* only when actually delivered.
Lost = customer cancelled before production.

### 3.5 SMS message mapping

Each outbound `sms_log` row writes a message into the GHL contact's
conversation thread (so sales sees "the system sent the customer this
text at 3:14pm").

| Bigfoot `sms_log` field | GHL Conversation message field |
|---|---|
| `messageBody` | `message` |
| `smsType` | Tag on the message (`trailer_complete`, etc) |
| `sentAt` | Conversation timestamp |
| `twilioSid` / GHL message id | Stored back in `sms_log.external_id` |

---

## 4. Target architecture

### 4.1 New module: `GhlModule`

A new feature module at [`bigfoot-api/src/modules/ghl/`](src/modules/ghl/)
containing:

- `ghl.module.ts` — DI wiring
- `ghl.service.ts` — high-level orchestrator (sync customer, sync trailer)
- `ghl-api.client.ts` — typed HTTP client over GHL REST API
- `ghl-auth.service.ts` — OAuth token refresh, key vault
- `ghl-webhook.controller.ts` — receives inbound webhooks
- `ghl-mapping.ts` — pure functions for Bigfoot ↔ GHL transformations
- `dto/` — typed payloads for webhooks
- Processors:
  - `ghl-outbound.processor.ts` — BullMQ worker draining a queue of
    sync events (customer.upsert, trailer.update, etc) to GHL
  - `ghl-webhook-replay.processor.ts` — retries failed webhook
    deliveries (saved to DB) on a schedule

### 4.2 Event-driven outbound sync

```
┌──────────────────────────────────────────────────────────────────┐
│  TrailersService.create(...)                                     │
│     │                                                             │
│     │  After DB commit:                                          │
│     │    this.events.emit('trailer.created', { trailerId })      │
│     ▼                                                             │
│  Internal event bus (Nest EventEmitter2)                          │
│     │                                                             │
│     │  GhlSyncListener picks it up:                               │
│     │    BullMQ.enqueue('ghl-sync', { type: 'trailer.upsert',    │
│     │                                  bigfootId: ... })         │
│     ▼                                                             │
│  ghl_sync_queue (Redis-backed BullMQ)                            │
│     │                                                             │
│     │  GhlOutboundProcessor pulls jobs:                          │
│     │    - Load Bigfoot entity                                    │
│     │    - Map to GHL payload                                     │
│     │    - Look up ghl_sync_state for ext id                      │
│     │    - PUT or POST to GHL API                                 │
│     │    - Save ext id + status to ghl_sync_state                 │
│     │    - On rate limit: backoff, retry                          │
│     ▼                                                             │
│  GoHighLevel REST API                                            │
└──────────────────────────────────────────────────────────────────┘
```

**Why event-driven and queued, not synchronous?**

- A failing GHL API call must never roll back a Bigfoot DB write
  (creating a trailer succeeds even if GHL is down).
- GHL rate limits will throttle bursts — backpressure goes into Redis,
  not into the HTTP request.
- Replays after outage are trivial — the queue picks up where it left
  off.

### 4.3 Webhook receiver (inbound)

```
GHL fires webhook ─► POST /v1/ghl/webhooks/<event>
                       │
                       │  GhlWebhookController:
                       │    1. Verify HMAC signature (header)
                       │    2. INSERT into ghl_webhook_events (raw payload + headers)
                       │    3. Acknowledge 200 immediately
                       ▼
                    Background processor reads ghl_webhook_events
                       │
                       │  Per event type:
                       │    - contact.update → upsert into Bigfoot customer
                       │    - opportunity.stageChange → log only (Bigfoot is source of truth for trailer status)
                       │    - conversation.message.received → INSERT inbound_messages, notify staff via push
                       │    - form.submitted → INSERT into leads table
                       ▼
                    Mark event row as processed (success/failure + retry count)
```

**Why store-then-process pattern?**

- GHL retries failed webhooks up to a finite number of times. We want
  to ACK 200 fast so they don't retry, then process at our own pace.
- Replay-ability: if a bug in mapping logic loses data, we re-run the
  processor against `ghl_webhook_events` rows we've already received.
- Audit: every external state change has a recorded source.

### 4.4 Where things run

No new infrastructure required for Phase 2:

| Component | Where it runs |
|---|---|
| GhlModule (API client, service) | Inside the API container — same droplet, same image |
| GhlOutboundProcessor | In-process BullMQ worker — same droplet |
| GhlWebhookController | Inside the API container, exposed via existing Caddy |
| `ghl_sync_state`, `ghl_webhook_events`, `leads`, `inbound_messages` | Managed PostgreSQL, new tables |

GHL itself is a SaaS — no infra on our side.

---

## 5. Authentication & API access

GHL has two API tracks:

### 5.1 Option A — **Location API Key** (v1, simpler)

- Generate one API key per location in GHL settings.
- Bearer-style: `Authorization: Bearer <key>` on every request.
- No refresh, no OAuth dance.
- **Constraint**: works only on the single GHL location it was issued
  for. Fine if Bigfoot Trailers is a single location.
- v1 API is more limited (some endpoints exist only in v2).

### 5.2 Option B — **OAuth 2.0 Marketplace App** (v2, fuller)

- Create a developer "marketplace app" in GHL.
- App handles OAuth installs across multiple locations.
- Access tokens expire (~1 hour), refresh tokens auto-rotate.
- Required for v2 API features (richer Conversations, richer Calendars).
- **More setup**, especially if Bigfoot Trailers' GHL account is a
  sub-account under an agency.

### 5.3 Recommendation

Start with **Option A (Location API Key)** unless we know we'll need v2
features (notably the modern Conversations API and Workflow triggers).
Migrating from A → B later is mostly a swap of the auth header logic.

### 5.4 Token storage

- API key (or OAuth tokens) live in `/opt/bigfoot/.env.production`
  (chmod 600, same pattern as Twilio/Firebase).
- Loaded once at boot by `GhlAuthService`.
- For OAuth: refresh token rotation persists to DB (encrypted column).

---

## 6. Sync model & conflict resolution

### 6.1 Source-of-truth rules

We default to **"Bigfoot wins"** for operational data and **"GHL wins"**
for marketing data. Spelled out:

| Field | Source of truth |
|---|---|
| `customer.name`, `phone`, `email`, `company` | **GHL** (sales edits there) — Bigfoot syncs from GHL on `contact.update` webhook |
| `customer.smsOptOut` (DND) | **GHL** (managed via inbox UI) |
| `customer.customerType`, `stockLocationId` | **Bigfoot** (internal classification) |
| `trailer.*` (everything) | **Bigfoot** (production data, immutable from GHL) |
| Opportunity stage | **Bigfoot** (driven by production status) |
| Opportunity custom fields | **Bigfoot** (one-way push) |
| Conversation messages (outbound) | **Bigfoot** sends, GHL mirrors |
| Conversation messages (inbound) | **GHL** (customer replies arrive there first) |

### 6.2 Idempotency

Every outbound sync uses **upsert semantics**:

- First call for a Bigfoot customer: POST to GHL → store the returned
  `ghl_contact_id` in `ghl_sync_state`.
- Subsequent calls: PUT to that `ghl_contact_id`.

If `ghl_sync_state` has no row but GHL already has the contact (because
of a manual import or a previous sync that lost local state), we
**search GHL by `bigfoot_customer_id` custom field first** and adopt
the existing record.

### 6.3 Conflict resolution policy

When Bigfoot tries to push and GHL has been edited since our last sync:

- **Mergeable** (different fields edited): merge — Bigfoot pushes its
  changes only, leaves GHL-only fields alone.
- **Same field, different values**: **Bigfoot wins** by default
  (operational data), **except** for the fields in §6.1 where GHL wins.
- **Log every override** in `ghl_sync_state.last_conflict` for audit.

---

## 7. Webhook receiver design

### 7.1 Endpoints

| Path | Trigger in GHL | What we do |
|---|---|---|
| `POST /v1/ghl/webhooks/contact-update` | Contact edited in GHL | Upsert Bigfoot customer (§6.1 rules) |
| `POST /v1/ghl/webhooks/contact-delete` | Contact deleted in GHL | Mark Bigfoot customer as `deleted_in_ghl_at` (don't auto-delete trailers) |
| `POST /v1/ghl/webhooks/conversation-message` | Inbound SMS/email from customer | INSERT into `inbound_messages`, push-notify office staff |
| `POST /v1/ghl/webhooks/form-submitted` | Website lead form filled out | INSERT into `leads` table, push-notify sales |
| `POST /v1/ghl/webhooks/opportunity-stage-change` | Stage changed manually in GHL | Log only — Bigfoot is source of truth for trailer status |

### 7.2 Signature verification

GHL signs each webhook with HMAC-SHA256 using a shared secret. Header:
`x-wh-signature`. Verification before accepting any payload — non-
matching signatures → 401, log + alert.

```ts
const expected = createHmac('sha256', GHL_WEBHOOK_SECRET)
  .update(rawBody)
  .digest('hex');
if (timingSafeEqual(received, expected) === false) {
  throw new AppError(ErrorCode.UNAUTHORIZED, 'Invalid webhook signature');
}
```

### 7.3 Idempotency

Every webhook carries a unique `eventId` from GHL. We store it in
`ghl_webhook_events.external_event_id` with a UNIQUE index — duplicate
deliveries return 200 with no work done.

---

## 8. SMS strategy — Twilio vs GHL

Three options, pick one in §2.6:

### 8.1 Option A — Full replacement (Twilio out)

Move every outbound SMS to GHL's Conversations API. Decommission
Twilio in our code.

| Pros | Cons |
|---|---|
| One bill, one inbox | Vendor lock-in on SMS gateway |
| Sales sees all comms history in one place | GHL SMS pricing per-segment is higher than Twilio direct |
| Inbound replies handled automatically | Migration risk during cutover |

### 8.2 Option B — Hybrid (recommended default)

Keep Twilio for **transactional** (trailer-complete, en-route,
delivered) — these are time-critical and we already trust the queue.
Use GHL for **conversational/marketing** (review requests, follow-ups,
inbound replies).

| Pros | Cons |
|---|---|
| Transactional latency stays low | Two SMS pipes to maintain |
| Marketing benefits from GHL's automation | Customer sees two "from" numbers unless they share Twilio number |

### 8.3 Option C — Keep Twilio, mirror to GHL only as display

Twilio sends as today. After send, the API also writes a "shadow" message
into GHL's contact conversation thread so sales can see history. No
inbound integration.

| Pros | Cons |
|---|---|
| Zero migration risk | Inbound replies still invisible to staff |
| Sales gets visibility | Most "GHL value" left on the table |

**My recommendation:** **Option B**, with all outbound SMS sharing the
**same phone number** (registered as a GHL "from" number that points
at the existing Twilio number) so customers don't see two numbers.

### 8.4 Twilio number portability

GHL lets you connect an existing Twilio sub-account so the SMS still
goes via Twilio infrastructure but appears in GHL's inbox. This is the
seamless path — no number change for customers.

---

## 9. Data model changes (new tables + columns)

All additions are non-destructive; the existing schema stays as-is.

### 9.1 New tables

```prisma
// External sync state per Bigfoot entity
model GhlSyncState {
  id              BigInt   @id @default(autoincrement())
  entityType      String   @db.VarChar(40)        // 'customer' | 'trailer'
  entityId        BigInt
  ghlExternalId   String   @db.VarChar(60)        // GHL's id
  lastSyncedAt    DateTime
  lastConflict    Json?                            // dict of field-level overrides
  syncErrorCount  Int      @default(0)
  syncErrorLast   String?
  createdAt       DateTime @default(now())

  @@unique([entityType, entityId])
  @@index([ghlExternalId])
}

// Inbound webhook log
model GhlWebhookEvent {
  id              BigInt   @id @default(autoincrement())
  externalEventId String   @unique @db.VarChar(80)
  eventType       String   @db.VarChar(60)
  payload         Json
  signature       String?  @db.VarChar(200)
  receivedAt      DateTime @default(now())
  processedAt     DateTime?
  status          String   @db.VarChar(20)        // 'pending' | 'processed' | 'failed'
  retryCount      Int      @default(0)
  errorMessage    String?

  @@index([status])
  @@index([eventType, receivedAt])
}

// Pre-customer leads from GHL forms
model Lead {
  id                BigInt   @id @default(autoincrement())
  ghlContactId      String   @db.VarChar(60)
  name              String   @db.VarChar(200)
  phone             String?  @db.VarChar(40)
  email             String?  @db.VarChar(200)
  source            String?  @db.VarChar(100)     // 'website-form' | 'fb-ad' | etc
  interestedModel   String?  @db.VarChar(100)
  notes             String?
  assignedToUserId  BigInt?  // sales person
  status            String   @db.VarChar(40)      // 'new' | 'contacted' | 'qualified' | 'converted' | 'lost'
  convertedToCustomerId BigInt?
  createdAt         DateTime @default(now())
  updatedAt         DateTime @updatedAt

  assignedTo        User?     @relation(fields: [assignedToUserId], references: [id])
  convertedTo       Customer? @relation(fields: [convertedToCustomerId], references: [id])

  @@index([status, createdAt])
  @@index([assignedToUserId])
}

// Inbound messages from customers (via GHL Conversations)
model InboundMessage {
  id              BigInt   @id @default(autoincrement())
  customerId      BigInt?
  ghlContactId    String   @db.VarChar(60)
  ghlMessageId    String   @unique @db.VarChar(80)
  channel         String   @db.VarChar(20)        // 'sms' | 'email' | 'whatsapp'
  messageBody     String
  receivedAt      DateTime
  readAt          DateTime?
  readByUserId    BigInt?

  customer        Customer? @relation(fields: [customerId], references: [id])

  @@index([customerId, receivedAt])
  @@index([readAt])
}
```

### 9.2 New columns on existing tables

```prisma
model Customer {
  // ... existing fields ...
  ghlContactId      String?  @unique @db.VarChar(60)
  ghlLastSyncedAt   DateTime?
  smsOptOut         Boolean  @default(false)      // already exists; surfaced for GHL DND mapping
  deletedInGhlAt    DateTime?
}

model Trailer {
  // ... existing fields ...
  ghlOpportunityId  String?  @unique @db.VarChar(60)
  ghlLastSyncedAt   DateTime?
}

model SmsLog {
  // ... existing fields ...
  ghlMessageId      String?  @db.VarChar(80)      // if mirrored to GHL conversation
  channel           String   @default("twilio") @db.VarChar(20)  // 'twilio' | 'ghl'
}
```

All `Ghl*` columns are nullable — pre-Phase-2 rows remain valid.

---

## 10. New endpoints & background jobs

### 10.1 Public webhook endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/v1/ghl/webhooks/contact-update` | HMAC signature | Sync GHL contact → Bigfoot customer |
| `POST` | `/v1/ghl/webhooks/contact-delete` | HMAC signature | Mark contact deleted |
| `POST` | `/v1/ghl/webhooks/conversation-message` | HMAC signature | Inbound message |
| `POST` | `/v1/ghl/webhooks/form-submitted` | HMAC signature | New lead |
| `POST` | `/v1/ghl/webhooks/opportunity-stage-change` | HMAC signature | Stage moved manually in GHL (log only) |

All marked `@Public()` (no JWT) — signature is the auth.

### 10.2 Internal admin endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/v1/admin/ghl/sync-customer/:id` | Owner | Manually re-sync a Bigfoot customer to GHL (recovery tool) |
| `POST` | `/v1/admin/ghl/sync-trailer/:id` | Owner | Manually re-sync a trailer |
| `POST` | `/v1/admin/ghl/backfill` | Owner | Bulk-sync every customer + trailer to GHL (one-shot, idempotent) |
| `GET` | `/v1/admin/ghl/webhook-events` | Owner | List recent webhook events for debugging |
| `POST` | `/v1/admin/ghl/webhook-events/:id/replay` | Owner | Re-process a failed webhook |

### 10.3 New BullMQ processors

| Processor | Trigger | Interval / behaviour |
|---|---|---|
| `GhlOutboundProcessor` | Push to queue on Bigfoot entity change | Drains queue continuously; retries with exponential backoff on rate limits |
| `GhlWebhookProcessor` | Reads from `ghl_webhook_events WHERE status='pending'` | Every 30 seconds |
| `GhlReconciliationProcessor` | Sweep for state drift | Once daily — re-syncs anything with `last_synced_at` > 24h old and stale-flagged |

### 10.4 New domain events (internal)

Emit from existing services on commit:

| Event | Emitted by | GHL action |
|---|---|---|
| `customer.created` | CustomersService.create | POST GHL contact, store ext id |
| `customer.updated` | CustomersService.update | PUT GHL contact |
| `customer.smsOptOut.changed` | CustomersService.update | PUT GHL contact DND flag |
| `trailer.created` | TrailersService.create | POST GHL opportunity in "Sold — Awaiting Production" stage |
| `trailer.statusChanged` | various | PUT GHL opportunity stage |
| `trailer.deleted` | TrailersService.deleteTrailer | DELETE GHL opportunity |
| `sms.sent` | SmsService (after Twilio success) | POST GHL conversation message |

Implementation: NestJS `EventEmitter2` module. Each event triggers a
queue job, not direct GHL API call — keeps the user-facing request
latency-stable.

---

## 11. Mobile-app impact

### 11.1 New mobile screens

| Screen | Purpose | Phase |
|---|---|---|
| **Leads inbox** | Sales sees `leads` table assigned to them; can convert to customer + trailer | 2.6 |
| **Customer detail → Conversations tab** | History of SMS exchanges from `sms_log` + `inbound_messages` | 2.5 |
| **Customer detail → "Open in GHL"** | Deep-links to the GHL contact page in browser/app | 2.3 |
| **Unread badge** | Number of unread inbound messages assigned to the user | 2.5 |

### 11.2 Mobile API additions

| Method | Path | What it returns |
|---|---|---|
| `GET` | `/v1/leads` | Paginated list of leads (filterable by status, assignee) |
| `GET` | `/v1/leads/:id` | Lead detail |
| `POST` | `/v1/leads/:id/convert` | Promote lead → customer; optionally start a trailer |
| `POST` | `/v1/leads/:id/assign` | Reassign lead to a sales user |
| `GET` | `/v1/customers/:id/conversations` | Unified outbound + inbound message timeline |
| `POST` | `/v1/customers/:id/conversations` | Send a new SMS (via Twilio + mirror to GHL) |
| `GET` | `/v1/inbound-messages?unread=true` | Mobile badge feed |

### 11.3 Mobile auth scope

No new auth flow — same JWT. New roles aren't needed; `sales` and
`office` already exist and gate these screens.

---

## 12. Security & compliance

### 12.1 What we send to GHL

Minimum-necessary principle. We send:

- Customer name, phone, email, company
- Trailer SO number, model, basic specs
- Order date, delivery date
- SMS message bodies (already going to Twilio, so adding GHL doesn't
  expand exposure)

We **do not** send:

- Customer's pricing/financial info (payment terms, total amount paid)
- Internal staff identifiers beyond a user-id reference
- Internal QC notes (failure modes, defects) — these are sensitive

### 12.2 Webhook security

- HMAC signature verification on every payload
- Webhook secret rotated whenever a GHL admin user leaves
- Webhook URLs include `/ghl/` path; Caddy rate-limits this prefix to
  100/min to prevent abuse

### 12.3 TCPA / opt-in tracking

If §2.12 requires it: add an `sms_consent` JSON column on `customer`:

```jsonc
{ "consented": true, "consentedAt": "2026-01-01T...", "source": "order-form-2026" }
```

Every outbound SMS path checks `sms_consent.consented === true` and the
GHL contact has `dnd: false`. Inbound STOP messages flip both.

### 12.4 GDPR / right-to-be-forgotten

If §2.13 requires it: `DELETE /v1/customers/:id` (already exists for
owner role) also enqueues `customer.deleted` → DELETE the GHL contact.
Audit log records the deletion in both systems.

### 12.5 Secrets handling

- GHL API key + webhook secret in `.env.production` only.
- GitHub Actions secrets for any CI-side GHL ops (probably none in
  Phase 2 — sync is runtime, not deploy-time).
- No secrets in logs (the API client redacts auth headers).

---

## 13. Operational concerns

### 13.1 Rate limits

GHL's REST API rate limits (as of 2026):

- 100 requests / 10 seconds per location
- 200,000 requests / day per location

Our worst case (full backfill of, say, 500 customers + 1500 trailers)
is 2000 requests. At ~10/sec well within limits.

**Implementation**: GhlOutboundProcessor uses a token-bucket limiter
(50 req/10s, leaving headroom). On 429, exponential backoff 1s → 30s.

### 13.2 Monitoring

New `/health` checks (degrades gracefully — GHL down ≠ API down):

```jsonc
{
  "checks": {
    "database": { ... },
    "redis":    { ... },
    "ghl":      { "status": "ok|degraded|down", "lastSuccessfulSyncAt": "..." }
  }
}
```

`ghl.status` is `degraded` if there are unprocessed webhook events older
than 5 minutes, or sync queue depth > 100.

DO Monitoring alert policies (new):
- Webhook event backlog > 100 for 10 min
- Sync queue depth > 200 for 15 min
- Last successful GHL API call > 30 min ago

### 13.3 Cost tracking

| Cost item | Estimate |
|---|---|
| GHL subscription (single sub-account) | $97–297/mo depending on tier (Starter / Unlimited / Pro) |
| GHL SMS (if migrated) | $0.0157/segment outgoing (vs Twilio direct $0.0079) |
| Twilio (if kept) | Existing, unchanged |
| Engineering | ~$15k–25k one-time for 4–6 weeks |

GHL SMS is ~2× Twilio direct, but unified inbox is worth it for staff
productivity. **At ~500 SMS/month, the SMS premium is ~$5/mo — noise
compared to the sub.**

### 13.4 Vendor lock-in posture

Our data stays in our Postgres. GHL is a *mirror* + *workflow engine*,
not the source of truth (per §6.1). If we needed to switch CRMs in the
future, the migration is:

1. Stop GhlOutboundProcessor
2. Write a similar `OtherCrmOutboundProcessor`
3. Backfill into the new CRM from our Postgres

No customer-facing impact during the swap.

### 13.5 Backup / disaster recovery

- GHL has its own backups; we don't need to back up GHL state.
- `ghl_sync_state`, `ghl_webhook_events`, `leads`, `inbound_messages`
  are in Postgres and covered by the existing daily backup + PITR.
- After a Postgres restore from a point in time:
  - `ghl_sync_state` is stale. The reconciliation processor (§10.3)
    catches up within 24h.
  - `ghl_webhook_events` may have rows we already processed. We've
    designed processing to be idempotent so this is fine.

---

## 14. Testing strategy

### 14.1 Unit tests

- `ghl-mapping.ts` — pure functions, fully tested
- `ghl-api.client.ts` — mocked HTTP, all happy + error paths
- `GhlOutboundProcessor` — mocked queue + client; assert event-driven
  side effects
- `GhlWebhookController` — mocked DB; assert signature verification +
  event storage
- Webhook processor — for each event type, table of inputs → expected
  DB side effects

### 14.2 Integration tests

A **GHL sandbox account** (free or cheap) lets us run real API calls
in CI for critical paths:

- Create a Bigfoot customer → assert GHL contact exists
- Update a Bigfoot trailer → assert opportunity stage moves
- Send a fake inbound SMS via GHL test webhook → assert
  `inbound_messages` row exists

Wrapped behind `INTEGRATION_TESTS=ghl` env flag so they don't run on
every commit (slow + uses sandbox quota).

### 14.3 Webhook replay testing

A test helper takes a stored `ghl_webhook_events` row from production
and replays it through the processor — useful for reproducing reported
bugs without involving GHL.

### 14.4 Load testing

Before go-live: simulate the backfill (500 customers + 1500 trailers in
~5 minutes) and confirm:
- No rate-limit failures (or graceful backoff)
- Queue drains in expected time
- No `ghl_sync_state` collisions

---

## 15. Implementation roadmap (8 milestones)

Each milestone is independently shippable behind a feature flag. The
flag (`GHL_SYNC_ENABLED=true`) gates *all* outbound calls so we can run
the system in shadow mode (storing events without sending) until we
flip the switch.

### M1 — Discovery & GHL setup (3 days)

- [ ] Resolve all open questions in §2
- [ ] Provision GHL account / sub-account; create the **Trailer
      Production** pipeline with stages from §3.4
- [ ] Define custom fields on Contact + Opportunity
- [ ] Generate API key (or set up OAuth marketplace app)
- [ ] Create a sandbox account for testing

**Deliverable**: configured GHL ready to receive data; decision doc
appended here.

### M2 — Foundation: module, client, auth (4 days)

- [ ] Create `GhlModule`, `GhlApiClient`, `GhlAuthService`
- [ ] Add `.env.production` entries (Appendix B)
- [ ] `EnvValidation` updates so missing GHL config fails fast in prod
- [ ] First end-to-end smoke test: hit `GET /contacts/?limit=1` against
      sandbox, log response

**Deliverable**: server can talk to GHL.

### M3 — DB schema + mapping (3 days)

- [ ] Prisma schema changes from §9
- [ ] `prisma db push` against staging
- [ ] `ghl-mapping.ts` pure functions with unit tests
- [ ] DB migration safe to run with feature flag off (additive only)

**Deliverable**: schema in place, no behaviour change.

### M4 — Outbound sync: customers (4 days)

- [ ] EventEmitter wired; emit `customer.created` / `updated`
- [ ] `GhlOutboundProcessor` handles customer events end-to-end
- [ ] Idempotency via `ghl_sync_state`
- [ ] Rate limiting + retry with backoff
- [ ] `/v1/admin/ghl/backfill` endpoint
- [ ] **Shadow-mode default**: writes to `ghl_sync_state` but doesn't
      actually call GHL until flag flips

**Deliverable**: behind `GHL_SYNC_ENABLED=true`, customer changes
appear in GHL contacts.

### M5 — Outbound sync: trailers + opportunities (4 days)

- [ ] `trailer.created` event → create GHL opportunity in correct stage
- [ ] `trailer.statusChanged` event → move stage
- [ ] `trailer.deleted` → delete GHL opportunity
- [ ] Backfill existing trailers via the admin endpoint
- [ ] Tests covering every stage transition

**Deliverable**: trailers appear in GHL pipeline; stages move
automatically.

### M6 — Inbound webhooks (5 days)

- [ ] Configure webhook URLs in GHL → our endpoints
- [ ] `GhlWebhookController` with HMAC verification
- [ ] `ghl_webhook_events` storage + ACK 200
- [ ] `GhlWebhookProcessor` for each event type:
  - `contact.update` → upsert Bigfoot customer (only the GHL-wins
    fields per §6.1)
  - `conversation.message.received` → INSERT `inbound_messages` + push
    to assigned staff
  - `form.submitted` → INSERT `leads` + push to sales
- [ ] Replay endpoint for failed events
- [ ] Tests including signature failure paths

**Deliverable**: customer reactions to SMS appear in our system;
website leads land in our DB.

### M7 — SMS routing + conversations (4 days, dependent on §2.6 decision)

- [ ] **If Option A (full GHL)**: replace `SmsService.sendById` with a
      GHL Conversations API call; deprecate Twilio path
- [ ] **If Option B (hybrid)**: keep Twilio for transactional; add
      `mirrorToGhlConversation` step after Twilio success; route
      inbound replies via GHL webhook
- [ ] **If Option C (Twilio + mirror)**: mirror only; no inbound
- [ ] Customer detail → Conversations API (`GET
      /v1/customers/:id/conversations`)
- [ ] Mobile screen for unified inbox

**Deliverable**: staff can see customer SMS history.

### M8 — Leads + mobile UI + reporting (5 days)

- [ ] Mobile: Leads inbox screen
- [ ] Mobile: Lead → convert to customer flow
- [ ] Mobile: Conversations timeline on customer detail
- [ ] Mobile: Unread badge in nav
- [ ] GHL workflow setup: "Trailer delivered" → schedule review-request
      SMS 7 days later (configured in GHL, no code)
- [ ] Reporting: pipeline conversion rate in GHL dashboards

**Deliverable**: sales has a complete lead-to-delivery loop in GHL +
mobile.

---

## 16. Effort & cost estimate

### 16.1 Engineering

| Milestone | Days | Notes |
|---|---|---|
| M1 Discovery | 3 | Includes a stakeholder workshop |
| M2 Foundation | 4 | |
| M3 Schema + mapping | 3 | |
| M4 Customer sync | 4 | |
| M5 Trailer sync | 4 | |
| M6 Webhooks | 5 | Most complex; covers all inbound event types |
| M7 SMS | 4 | Option-dependent |
| M8 Mobile + leads | 5 | Requires Flutter changes + new APK builds |
| Buffer + integration | 5 | Unknowns + GHL quirks |
| **Total** | **~37 days** (~7 weeks for one engineer; ~4 weeks for two) | |

### 16.2 Operational

| Item | Monthly cost |
|---|---|
| GHL subscription | $97 (Starter) — $297 (Unlimited) |
| GHL SMS premium (~500/mo) | ~$5 |
| No new infrastructure | $0 |

Phase 2 adds **$100–300/month operational cost**, all in GHL fees.

---

## 17. Rollout plan

### 17.1 Shadow → canary → full

1. **Week 1** of go-live: `GHL_SYNC_ENABLED=false`, but writes to
   `ghl_sync_state` happen — we can observe what *would* sync.
2. **Week 2**: flag flipped to `true` for **internal-test customers
   only** (filter in code: emit events only for customers whose id is
   in a small allowlist).
3. **Week 3**: full enablement; backfill endpoint run by an owner.
4. **Week 4**: webhook subscriptions turned on in GHL — inbound flow
   active.

### 17.2 Twilio cutover (if §2.6 = Option A)

Only after Phase 2.7 lands:

1. Deploy with both pipes active (Twilio + GHL).
2. Configure GHL to route via the existing Twilio sub-account so
   numbers don't change.
3. Cut new outbound calls to GHL by env flag (`SMS_BACKEND=ghl`).
4. Keep Twilio queue draining for 7 days to clear any in-flight SMS.
5. Decommission `SmsService`'s Twilio direct path.

### 17.3 Rollback

Each milestone's feature flag can be flipped independently. If GHL
becomes a problem post-launch:

- Flip `GHL_SYNC_ENABLED=false`
- API keeps working unchanged
- `ghl_sync_state` retains last-known state for when sync is re-enabled

---

## 18. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| GHL outage during heavy usage | Low | Medium (sales blind) | Queue + offline mode; webhook events backfill on recovery |
| Rate-limit storms during backfill | Medium | Low | Token-bucket limiter in client; chunked backfill |
| Data drift between systems | Medium | Medium | Daily reconciliation processor; admin re-sync tools |
| Webhook signature key leaked | Low | High (replay attacks) | Rotation playbook; alert on signature failures |
| GHL pricing increase mid-project | Medium | Low | Cancel + alternative CRMs exist; data is portable |
| Mobile work delays Phase 2 by 2-3 weeks | Medium | Low | Backend ships independently; mobile is M8 only |
| TCPA non-compliance issue | Low | High (regulatory) | Consent tracking column added in §12.3 if §2.12 confirms |
| Sub-account → standalone migration needed mid-flight | Low | Medium | Auth abstraction in `GhlAuthService` makes this a config swap |

---

## 19. Non-goals (explicitly out of scope)

To keep scope tight, Phase 2 **does not** include:

- Migrating Firebase push notifications into GHL (we keep FCM)
- Replacing the audit log with GHL activity logs
- Building a sales quoting tool (orders still come in via existing
  sales flow; GHL just tracks them)
- Multi-currency support (USD only)
- Multi-language SMS (English only)
- Internal staff chat (use Slack/equivalent; GHL conversations are
  customer-facing only)
- iOS/Android push notifications for GHL events (we use existing
  notification module + add new types; we don't introduce GHL's mobile
  app dependency)
- Replacing Bigfoot's own user accounts with GHL users (Bigfoot users
  stay as-is; GHL has its own user system, mapped 1:1 for ownership of
  leads/opportunities)

---

## Appendix A. GHL entity reference (what we'll use)

| GHL entity | API resource | Purpose for Bigfoot |
|---|---|---|
| **Contact** | `/contacts/` | One per Bigfoot customer (and one per lead) |
| **Opportunity** | `/opportunities/` | One per Bigfoot trailer (sold or being built) |
| **Pipeline** | `/pipelines/` | One named "Trailer Production"; stages from §3.4 |
| **Custom Field** | `/locations/{id}/customFields/` | Pre-create on Contact + Opportunity (see §3.2, §3.3) |
| **Conversation** | `/conversations/` | Tied to a contact; holds all SMS in/out |
| **Message** | `/conversations/messages` | Individual SMS records |
| **Form** | `/forms/` | Website forms (created in GHL UI) |
| **Webhook subscription** | `/webhooks/` | Where we register our `/v1/ghl/webhooks/*` endpoints |
| **Workflow** | (configured in GHL UI, no API) | Drip campaigns, review requests, finance reminders |
| **Calendar** | `/calendars/` | Showroom visits, factory tours |
| **User** | `/users/` | GHL staff accounts; mapped to Bigfoot users for "assigned to" |

GHL entities NOT used by Phase 2:

- Funnels, memberships, sites, surveys, communities, blog,
  affiliate manager, reputation (initial scope skips these — can be
  added later without code changes if the GHL admin enables them)

---

## Appendix B. Required env vars + secrets

Additions to `.env.production` (Phase 2 only — not yet active):

```bash
# ---- GoHighLevel (Phase 2) ---------------------------------------------------
GHL_SYNC_ENABLED=false                # master kill-switch
GHL_API_KEY=                          # Location API key (Option A)
# OR
GHL_OAUTH_CLIENT_ID=                  # Marketplace app (Option B)
GHL_OAUTH_CLIENT_SECRET=
GHL_OAUTH_REFRESH_TOKEN=              # Initial token; refreshed automatically

GHL_LOCATION_ID=                      # The location/sub-account id
GHL_PIPELINE_ID=                      # "Trailer Production" pipeline id (set after M1)
GHL_PIPELINE_STAGES_JSON='{...}'      # Map of stage names → stage ids (set after M1)
GHL_WEBHOOK_SECRET=                   # HMAC shared secret for signature verification

# Optional, only if SMS routes through GHL (M7)
SMS_BACKEND=twilio                    # 'twilio' | 'ghl' | 'hybrid'
```

`EnvValidation` updates:

- If `NODE_ENV=production` AND `GHL_SYNC_ENABLED=true`, require:
  `GHL_API_KEY` (or OAuth set), `GHL_LOCATION_ID`, `GHL_PIPELINE_ID`,
  `GHL_WEBHOOK_SECRET`.
- If `SMS_BACKEND=ghl`, require GHL config above.

---

## Appendix C. Sample API contracts

### C.1 Outbound: create a contact

```http
POST https://services.leadconnectorhq.com/contacts/
Authorization: Bearer <key>
Version: 2021-07-28
Content-Type: application/json

{
  "firstName": "John",
  "lastName":  "Doe",
  "phone":     "+15555550100",
  "email":     null,
  "companyName": null,
  "locationId": "{GHL_LOCATION_ID}",
  "customField": {
    "bigfoot_customer_id":  "42",
    "customer_type":        "end_user",
    "stock_location_code":  null
  },
  "tags": ["bigfoot-synced"]
}
```

### C.2 Outbound: move opportunity stage

```http
PUT https://services.leadconnectorhq.com/opportunities/{opportunityId}
Authorization: Bearer <key>
Version: 2021-07-28
Content-Type: application/json

{
  "pipelineStageId": "{stageId-for-In-Production}",
  "status":          "open"
}
```

### C.3 Inbound: contact.update webhook

```http
POST /v1/ghl/webhooks/contact-update
Content-Type: application/json
x-wh-signature: <hmac-sha256-of-body>
x-wh-event-id:   evt_abc123
x-wh-timestamp:  1748000000

{
  "type":      "ContactUpdate",
  "eventId":   "evt_abc123",
  "locationId":"loc_xyz",
  "contactId": "ctc_456",
  "changedFields": ["phone", "email"],
  "contact": {
    "id":       "ctc_456",
    "firstName":"John",
    "lastName": "Doe",
    "phone":    "+15555550999",
    "email":    "john@example.com",
    "customField": { "bigfoot_customer_id": "42" }
  }
}
```

Our handler:

1. Verify HMAC (header vs body + `GHL_WEBHOOK_SECRET`)
2. INSERT `ghl_webhook_events` row, status='pending'
3. Return 200
4. Background processor reads pending, applies updates per §6.1 (phone
   + email come from GHL).

### C.4 Inbound: conversation message

```http
POST /v1/ghl/webhooks/conversation-message
{
  "type":         "InboundMessage",
  "eventId":      "evt_msg_789",
  "locationId":   "loc_xyz",
  "conversationId":"conv_222",
  "contactId":    "ctc_456",
  "messageId":    "msg_999",
  "channel":      "SMS",
  "direction":    "inbound",
  "body":         "When will my trailer be ready?",
  "createdAt":    "2026-05-24T10:15:00Z"
}
```

Our handler:

1. Verify HMAC
2. Lookup `customer.id` via `ghl_contact_id` index
3. INSERT `inbound_messages`
4. Lookup the trailer associated with this customer (most-recent
   non-delivered), find its assigned production manager / sales user
5. Emit `notifications.send(['sales', 'office'], { type: 'inbound_sms', ... })`
6. WebSocket emit `notification:new` to those users
7. Return 200

---

*This is a planning document. Update it after M1 (discovery) with
resolved decisions, and again after each milestone with actual
behaviour vs plan.*
