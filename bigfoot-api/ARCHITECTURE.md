# Bigfoot Trailers — Backend Architecture

A complete reference of the production management system: what we built, where
it runs, how each layer works, and the reasoning behind every significant
design decision.

> **Audience.** New engineers joining the team, ops handlers, auditors,
> stakeholders who want to understand what they're paying for.
>
> **Scope.** This document covers the backend (NestJS API + PostgreSQL +
> Redis + DO Spaces + Twilio + Firebase) and the deployment topology. The
> Flutter mobile app is referenced where it intersects the API but is not
> documented here.

---

## Table of contents

- [0. Executive summary](#0-executive-summary)
- [1. System topology](#1-system-topology)
- [2. Technology stack](#2-technology-stack)
- [3. Request lifecycle — a worked example](#3-request-lifecycle--a-worked-example)
- [4. Module structure](#4-module-structure)
- [5. Domain model — the trailer's life](#5-domain-model--the-trailers-life)
  - [5.1 The 12-step workflow per series](#51-the-12-step-workflow-per-series)
  - [5.2 Production step state machine](#52-production-step-state-machine)
  - [5.3 QC inspection state machine](#53-qc-inspection-state-machine)
  - [5.4 Trailer status transitions](#54-trailer-status-transitions)
  - [5.5 Delivery types and batch lifecycle](#55-delivery-types-and-batch-lifecycle)
  - [5.6 Payroll calculation formula](#56-payroll-calculation-formula)
  - [5.7 Stall detection rules](#57-stall-detection-rules)
  - [5.8 The full delete cascade chain](#58-the-full-delete-cascade-chain)
- [6. Layer-by-layer walkthrough](#6-layer-by-layer-walkthrough)
  - [6.1 Edge — Caddy + TLS](#61-edge--caddy--tls)
  - [6.2 Authentication](#62-authentication)
  - [6.3 Authorization](#63-authorization)
  - [6.4 Validation](#64-validation)
  - [6.5 Error handling](#65-error-handling)
  - [6.6 Logging & observability](#66-logging--observability)
  - [6.7 Audit trail](#67-audit-trail)
  - [6.8 Rate limiting](#68-rate-limiting)
  - [6.9 Database layer](#69-database-layer)
  - [6.10 Storage layer](#610-storage-layer)
  - [6.11 Background jobs](#611-background-jobs)
  - [6.12 External integrations — SMS & push](#612-external-integrations--sms--push)
  - [6.13 WebSocket gateway](#613-websocket-gateway)
  - [6.14 Testing strategy](#614-testing-strategy)
  - [6.15 Real-time event catalog](#615-real-time-event-catalog)
  - [6.16 Mobile-API contract conventions](#616-mobile-api-contract-conventions)
- [7. Data integrity discipline](#7-data-integrity-discipline)
- [8. CI/CD pipeline](#8-cicd-pipeline)
- [9. Security posture](#9-security-posture)
- [10. Operational runbook](#10-operational-runbook)
- [11. Design decisions & trade-offs](#11-design-decisions--trade-offs)
- [Appendix A. File map](#appendix-a-file-map)
- [Appendix B. Environment variables](#appendix-b-environment-variables)
- [Appendix C. Key endpoints](#appendix-c-key-endpoints)
- [Appendix D. Database schema overview](#appendix-d-database-schema-overview)
- [Appendix E. Complete `ErrorCode` reference](#appendix-e-complete-errorcode-reference)
- [Appendix F. Notification & SMS catalog](#appendix-f-notification--sms-catalog)
- [Appendix G. Database enum reference](#appendix-g-database-enum-reference)
- [Appendix H. BullMQ processor schedule & behaviour](#appendix-h-bullmq-processor-schedule--behaviour)
- [Appendix I. Glossary](#appendix-i-glossary)

---

## 0. Executive summary

Bigfoot Trailers' backend runs the entire shop-floor operation of a single
trailer manufacturer: from the moment a sales order lands, through 12 stages
of production, multiple QC inspections, points-based payroll, and a delivery
batch to the customer's yard. A NestJS API is the source of truth; a Flutter
mobile app is the thin client used by workers, QC inspectors, managers,
drivers, and office staff.

**One droplet, one managed database, one Redis cache, one object-storage
bucket.** This is deliberate. The workload is a single factory — tens of
concurrent users, dozens of new trailers per week. The system is built for
*reliability* and *operational simplicity*, not for hyperscale traffic.

| Metric | Value |
|---|---|
| Production env | DigitalOcean droplet (2 vCPU / 4 GB / 120 GB NVMe, NYC3) |
| Database | DO Managed PostgreSQL 17 (private VPC, daily backups + PITR) |
| API requests | Currently <100 RPS sustained |
| Code | ~165 TypeScript files in `src/`, 33 test specs |
| Tests | 396 unit tests, all passing |
| Modules | 12 feature modules + cross-cutting infrastructure |
| Deploy pipeline | GitHub Actions → GHCR → SSH `docker compose up -d` (~4 min) |
| Mobile app | Flutter, signed arm64-v8a APKs via Firebase App Distribution |

---

## 1. System topology

### 1.1 Where everything runs

```
┌───────────────────────────────────────────────────────────────────────────┐
│                              Internet                                     │
│              (workers' phones, QC tablets, office browsers)               │
└────────────────────────────┬──────────────────────────────────────────────┘
                             │ HTTPS
                             ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ DigitalOcean Cloud Firewall (perimeter)                                   │
│   Inbound: 80 (HTTP→redirect), 443 (HTTPS), 22 from operator IPs only     │
└────────────────────────────┬──────────────────────────────────────────────┘
                             ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                                                                           │
│  DROPLET — bigfoot-trailers-production · NYC3 · 2 vCPU / 4 GB / 120 GB    │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  UFW host firewall (defence in depth) — same rules as Cloud FW     │  │
│  │  fail2ban — 3 SSH failures = 24h ban                               │  │
│  │  unattended-upgrades — automatic security patches                   │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌───────────────── Docker network "bigfoot" (internal only) ─────────┐   │
│  │                                                                    │   │
│  │   caddy ─── reverse_proxy api:3000                                 │   │
│  │     │  - Let's Encrypt auto-renewal                                │   │
│  │     │  - HSTS 1y + preload, CSP, X-Frame-Options DENY              │   │
│  │     │  - HTTP→HTTPS 308, /.env probes return 404                   │   │
│  │     │  - 10 MB body cap                                            │   │
│  │     ▼                                                              │   │
│  │   api ──── NestJS image from ghcr.io                               │   │
│  │     │  - Runs as non-root appuser (uid 1001)                       │   │
│  │     │  - Bound to internal network only, NEVER to host             │   │
│  │     │  - Pulls /etc/ssl/do-pg-ca.crt (read-only volume)            │   │
│  │     │                                                              │   │
│  │     ├──► BullMQ jobs ─► redis ── internal only                     │   │
│  │     │                                                              │   │
│  │     ├──► Prisma adapter-pg ─► DO Managed PostgreSQL                │   │
│  │     │                          (TLS verify-full via DO CA cert)    │   │
│  │     │                                                              │   │
│  │     ├──► S3 client ──────► DO Spaces (HTTPS)                       │   │
│  │     ├──► Twilio API ─────► SMS                                     │   │
│  │     └──► Firebase Admin ─► Push notifications                      │   │
│  │                                                                    │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
                             │
                             │ Private VPC (10.108.0.0/24)
                             ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  DO Managed PostgreSQL 17 cluster                                         │
│    - Trusted Sources = this droplet only                                  │
│    - Public endpoint disabled in practice (no IP allowlisted)             │
│    - Daily automated backups + 7-day point-in-time recovery               │
│    - TLS certificate signed by DO's project CA (we validate against it)   │
└───────────────────────────────────────────────────────────────────────────┘

  DO Spaces (NYC3)              Twilio API           Firebase Cloud Messaging
  ▲ photos + SO PDFs             ▲ SMS to customers   ▲ push to staff phones
  └ private bucket               └ lazy-loaded        └ lazy-loaded
```

### 1.2 Components and their resource budget

| Component | Where | Why there |
|---|---|---|
| Caddy 2 | Inside droplet, Docker | TLS + reverse proxy + HTTP/3. One config file, automatic Let's Encrypt. Sits in front of the API; nothing else listens publicly. |
| NestJS API | Inside droplet, Docker | Stateless app process. Multiple instances = nothing more than docker-compose scale (if/when needed). |
| Redis 7 | Inside droplet, Docker | BullMQ queue state + cache. Ephemeral — losing it = jobs rebuild on next interval. Co-hosting saves $15/mo vs Managed Redis. |
| PostgreSQL 17 | DigitalOcean Managed | Single source of truth for payroll, production, QC. Durability is non-negotiable, hence managed. |
| Object storage | DigitalOcean Spaces | Photos and SO PDFs. Mobile uploads bypass the API via pre-signed URLs. |
| SMS gateway | Twilio (cloud) | Outbound texts to drivers + customers. Lazy-loaded; the app starts cleanly even without creds. |
| Push gateway | Firebase Cloud Messaging | Push notifications to staff phones. Lazy-loaded; same behaviour as Twilio. |

### 1.3 Where data lives at rest

| Data | Storage | Encrypted at rest |
|---|---|---|
| Operational data (trailers, users, QC, payroll) | Managed Postgres | Yes (DO-managed) |
| Refresh tokens (hashed) | Managed Postgres `refresh_tokens` table | Yes |
| Audit log | Managed Postgres `audit_log` table (append-only) | Yes |
| Job state (BullMQ queues, locks) | Redis (in droplet) | No — ephemeral, rebuildable |
| Photos, SO PDFs | DO Spaces (private bucket) | Yes (DO-managed) |
| Secrets | `/opt/bigfoot/.env.production` (chmod 600) | No — Linux file perms; rotated via deploy user |
| TLS certs | Caddy `caddy_data` volume | No — public certs |

---

## 2. Technology stack

| Layer | Choice | Version | Why we picked it |
|---|---|---|---|
| Runtime | Node.js | 20 LTS | Long support, native ESM, mature ecosystem |
| Framework | NestJS | 10.x | Module + dependency injection matches our domain split (12 feature modules). Guards, interceptors, and pipes give clean cross-cutting layers. TypeScript end-to-end. |
| ORM | Prisma | 7.x | Type-safe queries, schema-as-code, runtime adapter swap (we use `adapter-pg` instead of the Rust engine for plain Node TLS control). |
| DB driver adapter | `@prisma/adapter-pg` | 7.x | Plain node-pg under the hood, so SSL config is standard `pg.Pool` shape. Required for our `ssl: { ca, rejectUnauthorized: true }` setup. |
| Database | PostgreSQL | 17 | Strong FK integrity, transactions, JSONB for audit values, mature backups in DO Managed. |
| Cache + queues | Redis | 7-alpine | Smallest reliable Redis. BullMQ uses it for job state. |
| Job queue | BullMQ | 5.x | Reliable, well-maintained, no external broker. |
| Object storage SDK | `@aws-sdk/client-s3` v3 | 3.x | DO Spaces is S3-compatible; AWS SDK works as-is. |
| Auth | `@nestjs/jwt` + `passport-jwt` | latest | JWT access + refresh tokens. |
| Validation | `class-validator` + `class-transformer` | latest | Decorator-driven DTO validation runs in a global pipe. |
| Edge proxy | Caddy | 2-alpine | Auto Let's Encrypt, HTTP/3, modern defaults. One file of config. |
| Container runtime | Docker + Compose | 24+ | Same image runs in dev and prod; compose orchestrates. |
| CI/CD | GitHub Actions | — | Native to the repo; free for our scale; secrets management built in. |
| Image registry | GitHub Container Registry | — | Free for private repos, scoped per-repo, authenticates with `GITHUB_TOKEN`. |
| External SMS | Twilio | — | Reliable, paid only when used. |
| External push | Firebase Cloud Messaging | — | Free for our volume; works for both Android and iOS. |
| Domain / DNS | DuckDNS (currently) | — | Free subdomain + Let's Encrypt support; placeholder until a real domain is registered. |

---

## 3. Request lifecycle — a worked example

A QC inspector taps "Submit Inspection" on their phone. Here is every layer
that touches the request, in order:

```
1. Mobile POSTs https://bigfoot-trailers.duckdns.org/v1/qc/inspections
       Headers: Authorization: Bearer <jwt>, Content-Type: application/json
       Body: { productionStepId, checklistResults: [...], result: "pass" }

2. DO Cloud Firewall: passes (port 443 is open)

3. Droplet UFW: passes (port 443 is allowed)

4. Caddy (in container):
   - Terminates TLS
   - Adds X-Real-IP, X-Forwarded-For, X-Forwarded-Proto headers
   - Applies HSTS + CSP + frame-deny response headers
   - reverse_proxy → api:3000

5. NestJS bootstrap (main.ts) has already configured:
   - GlobalPrefix "v1" (so /v1/qc/inspections is the route)
   - Helmet (extra security headers)
   - CORS (allowlist from env)
   - Global pipes, filters, interceptors

6. Middleware chain (runs before guards):
   - RequestLoggerMiddleware  ── records method, URL, IP, user_id
   - SanitizeMiddleware       ── strips __proto__, constructor keys

7. Global guards (order: Throttler → JWT → Roles):
   - ThrottlerGuard           ── 100 req/min default (configurable)
   - JwtAuthGuard             ── verifies signature, then
       JwtStrategy.validate() ── re-fetches user from DB to check isActive
                                  attaches { sub, email, role, departmentId }
                                  to request.user
   - RolesGuard               ── checks @Roles('qc_inspector') metadata
                                  against request.user.role

8. ValidationPipe runs:
   - DTO (SubmitInspectionDto) validated by class-validator
   - Unknown fields stripped, type-coerced, range/format checks applied
   - On failure: 400 with detailed error list

9. Controller (qc.controller.ts → POST /qc/inspections):
   - Pulls @CurrentUser() user
   - Calls QcService.submitInspection(dto, user.sub)

10. Service (qc.service.ts → submitInspection):
    - Validates the production step exists and is currently active
    - Validates the step belongs to a QC department
    - Validates every active checklist item has a result
       (throws AppError(QC_CHECKLIST_INCOMPLETE) if not)
    - Validates "fail" path has rework target + fail notes
    - Opens prisma.$transaction({ ... }):
        a. INSERT qc_inspections row
        b. INSERT qc_inspection_items rows (one per checklist result)
        c. INSERT qc_photos rows
        d. On pass:
           - UPDATE production_step status = completed
           - UPDATE next production_step status = active
           - On final QC pass: queue trailer_complete SMS to customer
        e. On fail:
           - UPDATE production_step rework_count++
           - Reset the rework target step (delegated to ReworkRoutingService)
           - INSERT push_notifications for production_manager

11. Service returns the inspection result

12. Interceptors fire on the way out:
    - LoggingInterceptor      ── logs status + latency + user
    - ResponseEnvelopeInterceptor ── wraps result in { success, data, meta }

13. Caddy adds gzip/zstd encoding, returns 200 to the phone

14. Background: a BullMQ job picks up the queued SMS and ships it to Twilio
    within ~60 seconds.
```

Any uncaught error along this path is converted to a consistent JSON
response by `GlobalExceptionFilter` (see §6.5).

---

## 4. Module structure

Each module is a self-contained slice: controller (HTTP boundary), service
(business logic), DTOs (validation), tests. Modules import siblings only via
public service exports; circular imports are prevented by NestJS's module
system.

| Module | Purpose | Key endpoints |
|---|---|---|
| **Auth** | Login, refresh-token rotation, push-token registration | `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `PATCH /auth/push-token` |
| **Users** | User CRUD with role-based authz | `GET /users`, `POST /users`, `PATCH /users/:id`, `DELETE /users/:id` |
| **Trailers** | Trailer lifecycle, workflow generation, add-ons, QB PDF, history, delete | `POST /trailers`, `GET /trailers/:id`, `PATCH /trailers/:id`, `DELETE /trailers/:id`, `GET /trailers/:id/steps`, `GET /trailers/:id/history`, `POST /trailers/:id/qb-pdf` |
| **Production** | Department queues, step completion, jump-to-step | `GET /production/queues/:deptCode`, `POST /production/steps/:id/complete`, `POST /production/steps/:id/jump` |
| **QC** | Checklist management, inspection submission, rework routing, customer SMS | `GET /qc/checklist`, `POST /qc/inspections`, `GET /qc/inspections/:id`, `POST /qc/inspections/:id/send-sms` |
| **Payroll** | Points configuration, dollar rates, weekly payroll records, locking | `GET /payroll/point-values`, `POST /payroll/point-values`, `GET /payroll/weekly-report/:date`, `POST /payroll/lock/:date` |
| **Deliveries** | Single deliveries, factory pickups, batch deliveries, driver tracking, location receipts | `POST /deliveries`, `POST /deliveries/batches`, `POST /deliveries/:id/depart`, `POST /deliveries/:id/complete`, `POST /location-receipts` |
| **Customers** | Customer CRUD with optional trailer cascade | `POST /customers`, `GET /customers`, `DELETE /customers/:id?cascadeTrailers=true` |
| **Locations** | Factory + remote yards | `GET /locations` |
| **Notifications** | Push + SMS dispatch, worker messages, notification history | `GET /notifications`, `POST /notifications/messages`, `DELETE /notifications/:id` |
| **Storage** | Pre-signed upload/download URLs, file-type validation | `POST /storage/presign`, `GET /storage/presign/:key` |
| **Admin** | Workflow config, audit log, trailer models, weekly production reports | `GET /admin/workflow-templates`, `GET /admin/departments`, `PATCH /admin/departments/:id`, `GET /admin/trailer-models`, `GET /admin/weekly-production/:date`, `POST /admin/weekly-production/:date/lock` |
| **Jobs** | BullMQ processors (no HTTP endpoints — runs in-process) | n/a |

Plus three **infrastructure modules** that aren't feature-shaped:

| Infra module | Purpose |
|---|---|
| `PrismaModule` | Global module exporting a singleton `PrismaService` — the DB client |
| `HealthModule` | `GET /health` — checks DB + Redis connectivity, returns degraded if either is down |
| `Common` | Decorators (`@Public`, `@Roles`, `@CurrentUser`), guards (JwtAuth, Roles), filters, interceptors, middleware, errors (AppError + ErrorCode), pipes |

---

## 5. Domain model — the trailer's life

```
        Customer places SO
                │
                ▼
       POST /trailers
       (TrailersService.create)
                │
                │  - Validates SO uniqueness
                │  - Validates trailer_model + customer FKs
                │  - INSERT trailer
                │  - Auto-generates 12 production_steps
                │    from workflow_templates filtered by series
                │  - INSERT audit_log
                ▼
        Step 1 active ──► Worker completes (POST /production/steps/:id/complete)
                            │  - Awards points to the worker
                            │  - Activates the next step
                            │  - Notifies QC if the next step is QC
                            ▼
        QC step active ──► Inspector submits inspection
                            │   pass  ──► Step done, next step active
                            │   fail  ──► rework_count++
                            │            Routes back to the failed dept
                            │            Notifies production_manager
                            ▼
                          ... (12 steps total)
                            ▼
        FINAL_QC pass ──► Queue trailer_complete SMS to customer
                            │
                            ▼
        Status: ready_for_delivery ──► Added to a delivery batch
                            │
                            ▼
        Driver marks departed ──► Customer SMS "driver en route"
                            │
                            ▼
        Driver marks delivered ──► Trailer.status = delivered
                                    │
                                    ▼
                                  Done.
```

### Key invariants (enforced in code, not trusted)

| Invariant | Where enforced |
|---|---|
| A trailer is always in exactly one active production step | Step completion swaps the active flag inside a transaction |
| Every active QC checklist item must be answered before submission | `QC_CHECKLIST_INCOMPLETE` thrown if `missingItems.length > 0` |
| Every step completion awards points (never silently skipped) | Points row written inside the step-complete transaction |
| Trailer can't be deleted if customer still references it without `cascadeTrailers=true` | Customer delete check |
| Refresh tokens are single-use; reuse triggers full revocation | AuthService refresh path |
| A trailer's deletion removes all related photos + PDF from Spaces immediately | TrailersService.deleteTrailer (we added this); orphan-cleanup is the safety net |

### 5.1 The 12-step workflow per series

Every new trailer is auto-assigned 12 production steps in `production_steps`,
generated by [`WorkflowGeneratorService.generateSteps()`](src/modules/trailers/workflow-generator.service.ts).
The blueprint is rows in `workflow_templates` filtered by the trailer's series.

All four series share the same backbone of **alternating production +
QC** — 5 production departments and 5 mid-process QC checkpoints, then
a final WOOD step, then FINAL_QC. Only two slots differ between series.

| Step | XP | Yeti | Deck Over | Gooseneck / Dump |
|----:|---|---|---|---|
| 1 | XP_JIG | YETI_JIG | DO_JIG | GN_WELD |
| 2 | **QC_1** | **QC_1** | **QC_1** | **QC_1** |
| 3 | XP_FIN | YETI_FIN | DO_FIN | GN_FIN |
| 4 | **QC_2** | **QC_2** | **QC_2** | **QC_2** |
| 5 | PAINT_PREP | PAINT_PREP | PAINT_PREP | PAINT_PREP |
| 6 | **QC_3** | **QC_3** | **QC_3** | **QC_3** |
| 7 | PAINT_A | PAINT_A | PAINT_A | **PAINT_B** |
| 8 | **QC_4** | **QC_4** | **QC_4** | **QC_4** |
| 9 | WIRE | WIRE | WIRE | **HYDRAULICS** |
| 10 | **QC_5** | **QC_5** | **QC_5** | **QC_5** |
| 11 | WOOD | WOOD | WOOD | WOOD |
| 12 | **FINAL_QC** | **FINAL_QC** | **FINAL_QC** | **FINAL_QC** |

**Why two slots differ:** dump and gooseneck units carry hydraulics
hardware (slot 9) and use a different paint booth (PAINT_B vs PAINT_A) for
their primer-coat schedule.

**Why this is data and not code:** workflow_templates is a regular table.
Adding a new series, swapping a step, or inserting a new QC checkpoint is
a single seed update + `DB · Seed (manual)` workflow run — no code change.

### 5.2 Production step state machine

Each row in `production_steps` is in exactly one of four states:

```
   ┌─────────────────────────────────────────────────────────────────────┐
   │                                                                     │
   │   ┌──────────┐   start          ┌──────────┐   worker completes     │
   │   │ waiting  │ ───────────────► │ active   │ ───────────────────┐   │
   │   └──────────┘                  └──────────┘                    │   │
   │        ▲                              ▲                         │   │
   │        │                              │ QC fails routes back    │   │
   │        │                              │ ────────────────────┐   ▼   │
   │        │ next-after-rework            │                     │ ┌──────────┐
   │        │ activation                   └──────── rework ◄────┘ │ complete │
   │        │                                                      └──────────┘
   │   ┌──────────┐                                                          │
   │   │ rework   │ ◄────────── inspector picks this dept as rework target   │
   │   └──────────┘             (rework_count++, status flips to rework)     │
   │                                                                          │
   └──────────────────────────────────────────────────────────────────────────┘
```

| Status | Meaning | Allowed transitions |
|---|---|---|
| `waiting` | Step exists but isn't the trailer's current step | → `active` (when previous step completes) |
| `active` | The current step; worker can complete or QC can fail | → `complete` (worker action) or → `rework` (QC fails downstream and routes back) |
| `complete` | Worker finished; points awarded; downstream step now active | Terminal under normal flow; can be reverted by manager (audit-logged) |
| `rework` | This step was the rework target of a failed QC further downstream; reopens for worker to redo | → `active` then → `complete` |

**Hard rules enforced in code (services, not just DB):**

1. Only **one** step per trailer is `active` at any time — `submitInspection`
   and `completeStep` swap the active flag inside a transaction.
2. Completing a step that isn't `active` throws `STEP_NOT_ACTIVE`.
3. Step reversal (un-completing) is allowed only by the worker who
   completed it or a production manager — otherwise
   `STEP_REVERSAL_NOT_AUTHORIZED`.
4. A step with `status='rework'` doesn't award points when completed — its
   point value is zero by design (`REWORK_POINTS_MUST_BE_ZERO` guards
   anyone trying to set non-zero points on a rework completion).
5. Stall detector flags any step that has been `active` longer than the
   department's `stallThresholdHours` (default 48h, configurable per dept).

### 5.3 QC inspection state machine

QC inspections are *append-only* — a new row per attempt. The `attemptNumber`
column tracks retries on the same step.

```
                                                  ┌─────────────────────────┐
                                                  │  Inspector submits      │
                                                  │  POST /qc/inspections   │
                                                  └────────────┬────────────┘
                                                               ▼
                                              ┌──────────────────────────────┐
                                              │  Validate:                   │
                                              │   - step is active           │
                                              │   - step is a QC dept        │
                                              │   - all active checklist     │
                                              │     items have a result      │
                                              │   - inspector role check     │
                                              └────────────┬─────────────────┘
                                                           ▼
                                       ┌───────────────────┴────────────────────┐
                                       │                                        │
                              result = pass                          result = fail
                                       │                                        │
                                       ▼                                        ▼
   ┌─────────────────────────────────────────┐   ┌────────────────────────────────────────────┐
   │ INSERT qc_inspection (result=pass)      │   │ Validate fail requires:                    │
   │ INSERT qc_inspection_items (per ans)    │   │   - rework_target_department_id present    │
   │ INSERT qc_photos (per uploaded)         │   │   - fail_notes present                     │
   │ UPDATE production_step → complete       │   │ ReworkRoutingService.routeRework():        │
   │ UPDATE next step → active               │   │   - Validate target dept is in workflow    │
   │ (if next is QC: emit qc_ready push)     │   │   - production_step.rework_count++         │
   │ (if FINAL_QC: queue trailer_complete    │   │   - Reset target step's completion + assn  │
   │   SMS to customer)                      │   │   - INSERT push (qc_fail) → prod_manager   │
   └─────────────────────────────────────────┘   └────────────────────────────────────────────┘
```

**Checklist completeness check.** Before accepting a submission, the service
queries `qc_checklist_items` for the inspection's department + the trailer's
series + the trailer's installed addons (e.g., a winch addon enables
winch-specific checklist items via `requires_addon_key`). Every active
item must appear in the submission, or `QC_CHECKLIST_INCOMPLETE` fires with
the missing item ids in the error details.

**Upstream worker self-checks** pre-populate the QC checklist with results
the upstream worker already recorded (`production_step_checks`), so QC
inspectors don't re-enter the same data. Inspectors override as needed.

**Customer SMS on FINAL_QC pass.** The trailer-complete SMS is *queued*
inside the same transaction (`sms_log` row with `status='queued'`); the
`SmsQueueProcessor` (§6.11) drains it to Twilio within ~1 minute. Idempotent
— a duplicate FINAL_QC pass for the same trailer doesn't re-queue if
already sent.

### 5.4 Trailer status transitions

```
   pending_production
          │ workflow generation completes
          ▼
   in_production ◄─────────────────────────────────────┐
          │                                             │
          │ all 12 steps complete + FINAL_QC pass      │
          ▼                                             │
   ready_for_delivery                                   │
          │                                             │
          │ added to delivery batch + driver departs    │
          ▼                                             │
   in_transit                                           │
          │                                             │
          ├──── driver marks delivered ────► delivered  │
          │                                             │
          └──── delivery cancelled / batch              │
                cleared without delivery ──────────────►│ (back to ready_for_delivery)

   on_hold  ◄──── any state can be put on hold by a manager
                  (handled by trailer.update; doesn't affect production)
```

| Status | Mobile UI surface | Who can act |
|---|---|---|
| `pending_production` | Briefly visible while workflow is generated | n/a |
| `in_production` | Appears in department queues | Workers + QC inspector |
| `ready_for_delivery` | Appears in delivery-batch picker, factory pickup list | Transport manager + driver |
| `in_transit` | Driver dashboard shows en-route trailers | Driver (mark delivered / failed) |
| `delivered` | Final state; appears in delivery history | Owner only can delete |
| `on_hold` | Pinned in dashboards | Owner / production manager |

### 5.5 Delivery types and batch lifecycle

Four delivery types model the four real-world ways a trailer leaves the
factory:

| `DeliveryType` | Meaning | Triggers customer SMS? |
|---|---|---|
| `factory_pickup` | Customer comes to Mulberry to pick up | No (customer is there) |
| `stack_to_dealer` | Driver hauls to a dealer's lot in a batch | Yes (driver_en_route + delivery_complete) |
| `stack_to_location` | Driver hauls to another Bigfoot yard (Jax, VA, GA, TAL) | No (internal transfer; LocationReceipt handles confirmation) |
| `single_pull` | One driver, one trailer, ad-hoc dispatch | Yes |

**Delivery batches** group multiple deliveries to the same destination into
one dispatch. State machine:

```
   building ──► scheduled ──► in_transit ──► complete
      │            │              │              ▲
      │            │              │              │
      │            │              │              └─ driver marks all
      │            │              │                 deliveries delivered
      │            │              └─ driver marks batch departed
      │            │                 (sets all child deliveries to in_transit
      │            │                  + sends driver_en_route SMS for each)
      │            └─ transport manager schedules driver + departure window
      └─ trailers being added/removed (only state where mutation is allowed)
```

A `BATCH_NOT_BUILDING` error fires on any mutation to a batch that isn't
in `building` state — once scheduled, the manifest is frozen.

### 5.6 Payroll calculation formula

Payroll is **points × dollar rate, per worker per week**.

```
  points_awarded(worker, week) =
      Σ over completed production_steps in [week_start, week_start + 7d):
          point_values[step.trailerModel.id][step.department.id]
            if step.status = 'complete' and step.completedByUserId = worker
            and step.rework_count = 0  ←  rework steps award zero

  earnings(worker, week) =
      Σ over completed steps:
          point_values[model][dept]  ×  dept_dollar_rates[dept]
```

Concretely:

| Table | Purpose |
|---|---|
| `point_values` | `(trailerModelId, departmentId) → points` (e.g. XP_14K + XP_JIG = 5.0 pts) |
| `dept_dollar_rates` | `(departmentId, effectiveFrom) → $/point` (e.g. XP_JIG = $8/point) |
| `payroll_records` | One row per `(userId, weekStartDate, departmentId)` summarising totalPoints + totalEarnings |

**Weekly report generation.** `ReportGeneratorProcessor` runs Sunday at
00:05 UTC, builds the previous week's rows via upsert. **Lockable** by an
owner via `POST /payroll/lock/:date` — once locked, no further edits to
that week's records (`PAYROLL_WEEK_LOCKED` error on attempted mutations).

**Week boundaries.** Weeks always start on Sunday. `INVALID_WEEK_START`
fires if any payroll endpoint is called with a non-Sunday date.

**QC departments earn zero.** By design — `createPointValue` rejects with
`BAD_REQUEST` if you try to assign a point value to a QC department.
Inspectors are salaried, not paid per inspection.

### 5.7 Stall detection rules

`StallDetectorProcessor` runs every 15 minutes. For each `production_step`
in `active` status:

```
  if (now - step.startedAt) > step.department.stallThresholdHours:
      INSERT stall_alerts (one per day per step to avoid spam)
      ENQUEUE push notification → all production_manager users
                                  notificationType = trailer_stalled
```

`stallThresholdHours` defaults to **48 hours** but is per-department editable
by an owner (faster-moving departments like QC have shorter thresholds;
PAINT_PREP allows longer because of cure times). One alert per step per
day prevents the dashboard from drowning in noise.

### 5.8 The full delete cascade chain

A trailer participates in 11 child tables. Deleting it requires an
**ordered** transaction to satisfy FK constraints, plus a snapshot of
storage keys for post-commit S3 cleanup:

```
  1.  Snapshot storage keys (qc_photos.storageKey,
                             delivery_photos.storageKey via delivery.trailerId,
                             trailer.qbSoPdfStorageKey)
  2.  Open transaction:
        a. DELETE stall_alerts            WHERE trailerId = ?
        b. DELETE push_notifications      WHERE trailerId = ?
        c. DELETE sms_log                 WHERE trailerId = ?
        d. DELETE location_receipts       WHERE trailerId = ?
        e. DELETE deliveries              WHERE trailerId = ?
           └─ cascade: delivery_photos cascade automatically (FK Cascade)
           └─ cascade: signatures cascade automatically
        f. DELETE worker_messages         WHERE trailerId = ?
        g. DELETE qc_photos               WHERE trailerId = ?
        h. DELETE qc_inspections          WHERE trailerId = ?
           └─ cascade: qc_inspection_items, qc_step_checks
        i. DELETE production_steps        WHERE trailerId = ?
           └─ cascade: production_step_checks
        j. DELETE trailer                 WHERE id = ?
           └─ cascade: trailer_addons (FK Cascade)
  3.  Commit
  4.  Promise.allSettled(storage.deleteObject(key) for each snapshot key)
       └─ Failures logged but not thrown; orphan-cleanup catches in ≤24h
```

The exact same chain runs (over many trailers in one tx) for **customer
delete with `cascadeTrailers=true`** — see [customers.service.ts](src/modules/customers/customers.service.ts).
For **delivery delete** the chain is shorter (just deliveryPhotos + the
delivery itself); same snapshot-then-cleanup pattern.

---

## 6. Layer-by-layer walkthrough

### 6.1 Edge — Caddy + TLS

**File**: [bigfoot-api/Caddyfile](Caddyfile)

Caddy is the only public listener. It owns ports 80 and 443. Inside the
Docker network it speaks plain HTTP to the API on `api:3000`. The API
container exposes 3000 only on the internal network — `netstat` on the
droplet shows nothing else listening publicly.

**What Caddy enforces:**

- TLS certificate for `$DOMAIN`, auto-fetched and auto-renewed from Let's
  Encrypt. Persistent state in the `caddy_data` Docker volume.
- HTTP→HTTPS 308 redirect (no plain-HTTP API access).
- **HSTS** `max-age=31536000; includeSubDomains; preload` — one year, with
  the preload flag so browsers can be hard-coded to refuse downgrade.
- **X-Content-Type-Options: nosniff** — kills MIME sniffing attacks.
- **X-Frame-Options: DENY** — no embedding in iframes (clickjacking
  defence).
- **Permissions-Policy: geolocation=(), microphone=(), camera=()** —
  pre-emptively denies sensor APIs we don't use.
- **Server header stripped** — no fingerprinting our version.
- `/.env`, `/.git/*`, `/wp-admin*`, `/wp-login*` and similar probes return
  404 immediately, never reach the API.
- gzip + zstd compression.
- Body cap 10 MB matching the API's `express.json({ limit: '10mb' })`.

**Health check path** `/health` is excluded from Nest's global prefix `/v1`
so monitors and curl can hit `https://<domain>/health` directly.

### 6.2 Authentication

**Files**: [auth.service.ts](src/modules/auth/auth.service.ts),
[jwt.strategy.ts](src/modules/auth/jwt.strategy.ts),
[jwt-auth.guard.ts](src/common/guards/jwt-auth.guard.ts)

**Token model:**

| Token | Lifetime | Purpose | Storage |
|---|---|---|---|
| Access (JWT) | 15 minutes | Authorise API calls | Phone keychain |
| Refresh | 7 days | Get a new access + refresh pair | Phone keychain + DB (hashed) |

**Login flow** (`POST /auth/login`):

1. Look up user by email.
2. If not found → `UNAUTHORIZED` ("Invalid email or password"). Same error
   for wrong password, so we don't leak which emails exist.
3. If `!user.isActive` → `FORBIDDEN` ("Account has been deactivated").
4. `bcrypt.compare(password, user.passwordHash)` — fails → `UNAUTHORIZED`.
5. Issue an access JWT (15 min) and a refresh token (random 48-byte
   base64url, hashed before persisting).
6. Return `{ accessToken, refreshToken, expiresIn }`.

**Refresh flow** (`POST /auth/refresh`):

1. Hash the presented refresh token and look it up in `refresh_tokens`.
2. Not found → `UNAUTHORIZED`.
3. If `revokedAt != null` → **reuse detected**. We assume the token was
   stolen, revoke every active token for that user, and respond
   `UNAUTHORIZED`. Real user re-logs in next; thief is locked out.
4. If `expiresAt < now` → `UNAUTHORIZED` ("Refresh token has expired").
5. If `!user.isActive` → `FORBIDDEN`.
6. Mark the current token revoked, issue a new pair.

**JwtStrategy.validate():**

Re-fetches the user from the DB on **every authenticated request** to check
`isActive`. This is one extra DB query per request (cheap, indexed by PK),
but it gives instant deactivation — admins flipping a user inactive don't
have to wait 15 minutes for the JWT to expire.

**The `@Public()` decorator** marks endpoints that skip auth: `/health`,
`/auth/login`, `/auth/refresh`, `/auth/logout`. The JwtAuthGuard checks
this metadata via Reflector.

**Password hashing:** bcrypt with 12 rounds (handled in UsersService on
create/update and AuthService on seed).

### 6.3 Authorization

**Files**: [roles.guard.ts](src/common/guards/roles.guard.ts),
[roles.decorator.ts](src/common/decorators/roles.decorator.ts)

Nine roles, hierarchical but enforced explicitly per endpoint:

| Role | Capabilities |
|---|---|
| `owner` | Full admin (delete trailers/customers, lock payroll, manage users, assign owner role) |
| `production_manager` | Same as owner except can't assign owner role, can't delete |
| `transport_manager` | Manages drivers + delivery batches |
| `qc_inspector` | Submits QC inspections (covers all 6 QC departments — one inspector per factory) |
| `worker` | Completes production steps in their assigned department |
| `driver` | Marks deliveries departed + delivered |
| `sales` | Creates trailers + customers |
| `office` | Read-only-ish, customer support |
| `customer` | (Reserved — not currently used in mobile) |

`@Roles('owner', 'production_manager')` on a controller method gates the
endpoint. `RolesGuard` reads the role from the JWT and matches. If the
endpoint has no `@Roles()`, any authenticated user passes (this catches
"forgot to add roles" bugs at code review, not at runtime).

Some endpoints layer **business-rule authz** on top of role checks:

- Update user: any role can update *themselves* (name, phone, password
  only); only owner/production_manager can edit other users; only owner can
  assign the owner role; can't deactivate yourself; can't delete the last
  active owner.
- Delete trailer / delete customer with cascade: `owner` only.

### 6.4 Validation

**File**: [validation.pipe.ts](src/common/pipes/validation.pipe.ts)

Global `ValidationPipe`:

```ts
{
  transform: true,                 // body → DTO instance with type coercion
  whitelist: true,                 // strip unknown fields silently
  forbidNonWhitelisted: false,     // we silently strip rather than 400
  forbidUnknownValues: true,       // reject base-object validation bypass
  transformOptions: { enableImplicitConversion: true },
}
```

Every endpoint takes a typed DTO with `class-validator` decorators
(`@IsString`, `@IsInt`, `@IsEnum`, `@Min`, `@Max`, `@IsOptional`, etc).
Validation runs **before** the controller method, so handlers never see
malformed input.

Storage uploads add a second layer: extension + MIME type validation in
`StorageService.generateUploadUrl` (see §6.10).

### 6.5 Error handling

**Files**: [app-error.ts](src/common/errors/app-error.ts),
[error-codes.ts](src/common/errors/error-codes.ts),
[http-exception.filter.ts](src/common/filters/http-exception.filter.ts)

**Every error in the app is an `AppError`** — never a raw NestJS exception,
never a thrown string. Each `AppError` carries:

- A typed `ErrorCode` (e.g. `STEP_NOT_ACTIVE`, `QC_CHECKLIST_INCOMPLETE`,
  `PAYROLL_WEEK_LOCKED`, `SO_NUMBER_EXISTS`) — clients can switch on this
  programmatically.
- A human-readable message — clients can show it to users without
  translation.
- An HTTP status mapped from the code (e.g. `NOT_FOUND` → 404,
  `STEP_NOT_ACTIVE` → 409).

```ts
throw new AppError(ErrorCode.STEP_NOT_ACTIVE,
  `QC step ${dto.productionStepId} is not currently active (status: ${step.status})`);
```

`GlobalExceptionFilter` catches everything and emits a uniform response:

```json
{
  "success": false,
  "error": {
    "code": "STEP_NOT_ACTIVE",
    "message": "QC step 12 is not currently active (status: waiting)",
    "statusCode": 409
  },
  "meta": { "timestamp": "...", "path": "/v1/qc/inspections", "method": "POST" }
}
```

**Prisma errors** are translated:
- P2002 (unique violation) → `SO_NUMBER_EXISTS`-style `CONFLICT` (409)
- P2003 (FK violation) → `BAD_REQUEST` with a human-readable foreign-key
  description
- P2025 (record not found) → `NOT_FOUND`

**Unhandled internal errors** become `INTERNAL_ERROR` (500) with a generic
message — stack traces never reach the client. The full error including
stack is logged server-side.

**Why this matters.** Mobile clients pattern-match on `error.code`. We can
rename `message` strings without breaking the app, and the app can show
appropriate UI per code (e.g. specific retry behaviour for
`STEP_NOT_ACTIVE` vs blocking dialog for `PAYROLL_WEEK_LOCKED`).

### 6.6 Logging & observability

**Files**: [logging.interceptor.ts](src/common/interceptors/logging.interceptor.ts),
[request-logger.middleware.ts](src/common/middleware/request-logger.middleware.ts)

Two layers of request logging:

1. **`RequestLoggerMiddleware`** runs before guards — captures *every*
   request including 401s and 429s, before auth has a chance to short-
   circuit. Logs method, URL, status, duration, user id (if present).
2. **`LoggingInterceptor`** runs after handlers — captures the same plus
   any thrown error. Latency measurements are taken from the start of this
   interceptor, so they reflect just the handler+pipeline work.

Both write to `console` via Nest's `Logger`. In production these are
captured by `docker logs` and rotate automatically.

The Health endpoint at `/health` returns:

```json
{
  "success": true,
  "data": {
    "status": "ok",
    "uptime": 86.4,
    "timestamp": "...",
    "checks": {
      "database": { "status": "ok", "latencyMs": 12 },
      "redis":    { "status": "ok", "latencyMs": 3 }
    }
  }
}
```

`status` is `degraded` if either dependency is down. Used by the CI
deploy's health check loop (30× over 150s) and by uptime monitors.

### 6.7 Audit trail

**Files**: [audit-log.service.ts](src/modules/admin/audit-log.service.ts),
[audit-log.interceptor.ts](src/modules/admin/audit-log.interceptor.ts)

`AuditLogInterceptor` watches every HTTP `POST | PATCH | PUT | DELETE` on
resource paths (e.g. `/v1/trailers/:id`). For each request:

- Parses the entity type + id from the URL path
- Captures the request body (sanitised)
- Captures the response body (for `POST` to extract a generated id)
- Captures user id (from JWT) + client IP
- Fire-and-forget INSERT into `audit_log`

The audit log is **append-only** — no delete or update endpoint. Used for
"who did what when" investigations. Schema is intentionally simple:

```
audit_log
├── id (bigint, PK)
├── user_id (FK → users.id, nullable for system actions)
├── entity_type (varchar)  e.g. "trailer", "qc_inspection"
├── entity_id   (bigint)
├── action      (varchar)  CREATE | UPDATE | DELETE
├── old_values  (jsonb, nullable)
├── new_values  (jsonb, nullable)
├── ip_address  (varchar, nullable)
└── created_at  (timestamptz, default now())
```

### 6.8 Rate limiting

**Source**: `app.module.ts` — `ThrottlerModule.forRoot(...)` + global
`ThrottlerGuard`

| Scope | Rule |
|---|---|
| Global default | 100 requests per 60s per IP |
| `POST /auth/login` | 5 requests per 60s per IP |

The login throttle is the brute-force defence — five guesses per minute
makes password cracking infeasible. Other rate-limited endpoints can be
added with `@Throttle({ default: { ttl, limit } })` on a controller method.

### 6.9 Database layer

**Files**: [prisma.service.ts](src/prisma/prisma.service.ts),
[prisma/schema.prisma](prisma/schema.prisma)

#### Connection setup

We use `@prisma/adapter-pg` instead of Prisma's default Rust engine. This
lets us configure plain Node `pg.Pool` options — specifically, a custom
TLS configuration for DO's private CA.

```ts
const caPath = process.env.DATABASE_SSL_CA_PATH;   // /etc/ssl/do-pg-ca.crt
const ssl = caPath
  ? { ca: readFileSync(caPath, 'utf8'), rejectUnauthorized: true }
  : undefined;
const adapter = new PrismaPg({ connectionString, ...(ssl && { ssl }) });
```

**Key TLS facts:**

- The DB cert is signed by DO's per-project CA (not a public CA).
- The CA cert is downloaded from the DO panel once and lives at
  `/opt/bigfoot/do-pg-ca.crt` on the host, mounted read-only into the
  container.
- The `DATABASE_URL` does **not** contain `?sslmode=...`. node-pg's URL
  parser would otherwise build a competing `ssl` config that overrides
  ours. SSL is fully driven by the `ssl` constructor object.
- `rejectUnauthorized: true` + the explicit CA means chain validation is
  strict. We do not bypass cert validation under any circumstance.

#### Schema migrations

Schema is managed in `prisma/schema.prisma`. On every container start the
entrypoint runs:

```sh
npx prisma db push --accept-data-loss
```

…followed by every SQL file in `prisma/sql-patches/*.sql` (idempotent —
patches use `IF NOT EXISTS`).

This means:

- **Additive schema changes** (new column, new table, new index) deploy
  automatically when the new image starts.
- **Destructive changes** (drop column, rename) are caught at PR review.
  `--accept-data-loss` lets them through in production — be careful.
- **Complex DDL** that Prisma can't express (CHECK constraints, partial
  indexes, trigger functions) goes in `sql-patches/`.

#### Transactions

Every mutation that spans more than one table runs inside
`prisma.$transaction(async (tx) => { ... })`. The pattern:

```ts
await this.prisma.$transaction(async (tx) => {
  await tx.qcInspection.create({ ... });
  await tx.qcInspectionItem.createMany({ ... });
  await tx.productionStep.update({ ... });
  await tx.smsLog.create({ ... });
});
```

If any step throws, the whole thing rolls back — there's no such thing as
a half-completed inspection. **All multi-row deletes use the same
pattern** (see §6.10 for how storage deletes interact with this).

#### Connection pool

Default node-pg pool sizing (max 10 connections per process). For our load
this is comfortable; if we ever need more we'd tune via `pg.Pool` options
in the adapter constructor.

### 6.10 Storage layer

**Files**: [storage.service.ts](src/modules/storage/storage.service.ts),
[storage.controller.ts](src/modules/storage/storage.controller.ts),
[orphan-cleanup.processor.ts](src/modules/jobs/orphan-cleanup.processor.ts)

#### Pre-signed URLs

Mobile clients **upload directly to Spaces** — bytes never pass through
our server. Flow:

1. `POST /storage/presign { fileType, trailerId, fileName }` → server
   validates file_type and extension, looks up the trailer's SO number,
   returns:
   ```json
   { "uploadUrl": "https://...?X-Amz-Signature=...",
     "storageKey": "qc/SO-1001/<uuid>.jpg",
     "expiresIn": 900, "maxSizeBytes": 10485760, "contentType": "image/jpeg" }
   ```
2. Client `PUT`s the file bytes directly to `uploadUrl` (15-minute expiry).
3. Client `POST`s back to the relevant business endpoint with the
   `storageKey` (e.g. `POST /qc/inspections` includes
   `photos: [{ storageKey: "qc/SO-1001/..." }]`).

**Validation in `generateUploadUrl`:**

- File type ∈ `{qc_photo, delivery_photo, so_pdf, damage_photo}`.
- Extension ∈ `{jpg, jpeg, png, webp, pdf}`.
- Extension matches file type (so_pdf requires .pdf; everything else
  requires a photo extension).
- Trailer ID exists (we throw `NOT_FOUND` if not).

#### Storage path layout

```
{prefix}/{SO_NUMBER}/{uuid}.{ext}

qc/SO-1001/abc123.jpg          ← QC photo for trailer SO-1001
delivery/SO-1001/def456.png    ← Proof-of-delivery photo
so-pdf/SO-1001/ghi789.pdf      ← QuickBooks SO PDF
damage/SO-1001/jkl012.jpg      ← Damage report photo
```

The SO number is looked up from the trailer at presign time, so the path
encodes meaning. Operators browsing the bucket can see "all files for
SO-1001" in one folder.

**Schema-level invariant**: trailer.soNumber is `String @unique @db.VarChar(30)`,
sanitised via `/[^A-Za-z0-9._-]/g → "_"` before going into the path.

#### Bucket configuration

- **Private** — no public-read ACL. All access via signed URLs.
- **No CDN** — pre-signed URLs would lose cache key stability (signature in
  query string), and CDN caching of mutable private files risks staleness
  after deletes.
- Region matches the droplet's metro (NYC3).

#### Asset deletion — inline + cleanup

When a trailer, delivery, batch, or customer-with-cascade is deleted, the
service does the following:

1. **Before** the DB transaction: snapshot every `storageKey` that will be
   orphaned by the cascade (qcPhotos for this trailer, deliveryPhotos via
   delivery FK, trailer.qbSoPdfStorageKey).
2. Run the DB transaction.
3. **After** the DB commits: call
   `StorageService.deleteObjects(keys)`, which does
   `Promise.allSettled(...)` over individual `DeleteObjectCommand` calls.
4. Failures are **logged but not thrown** — `orphan-cleanup.processor`
   sweeps any survivors within 24 hours.

This ordering is deliberate. If S3 dies, the user's delete still succeeds
(DB-wise) and gets cleaned up later. If we did S3 first and DB rollback
happened, we'd have lost files referenced by surviving rows.

#### Orphan cleanup processor

Runs every 24 hours. For each prefix (`qc`, `delivery`, `so-pdf`,
`damage`):

1. `LIST` all objects with that prefix.
2. Query the relevant table for rows whose `storageKey` ∈ the listed
   objects.
3. For every object **not** in the result set, `DELETE` it.

Belt and braces: even if the inline cleanup misses something (S3 transient
failure, deploy hot-swap during a delete), the daily processor catches it
within a day.

### 6.11 Background jobs

**File**: [bigfoot-api/src/modules/jobs/](src/modules/jobs/)

Four processors, all in-process (no separate worker dyno). Each registers
a `setInterval` in `OnModuleInit`. Single-flight guard via a `processing`
boolean to prevent overlap if a run is slow.

| Processor | Interval | What it does |
|---|---|---|
| `StallDetectorProcessor` | 15 min | Finds production steps whose `active` duration exceeds the department's `stallThresholdHours`. Inserts `stall_alerts` rows; emits push notifications to production managers. |
| `SmsQueueProcessor` | 1 min | Drains `sms_log` rows in `queued` state. Sends via Twilio, marks `sent` with `twilio_sid` on success, `failed` on error. Handles up to 50 per tick. |
| `ReportGeneratorProcessor` | Weekly Sunday 00:05 | Builds the weekly payroll records: joins completed production steps × point values × dollar rates × user → upserts `payroll_records` for the week. |
| `OrphanCleanupProcessor` | 24 hours | See §6.10. |

**Why not a separate worker process?** Operational complexity isn't worth it
at our scale. The jobs are lightweight, and running them in the API
process gives us shared DB pool + shared logger + one set of metrics.

**Redis** is only required for BullMQ queue *state* (job hashes, locks).
Currently the processors run on `setInterval` directly, not via BullMQ
queue objects — but Redis is configured so we can switch to push-based
job dispatch (e.g. delayed reminders) without adding infrastructure.

### 6.12 External integrations — SMS & push

**Files**: [push.service.ts](src/modules/notifications/push.service.ts),
[sms.service.ts](src/modules/notifications/sms.service.ts)

Both clients are **lazy-loaded** with minimal structural interfaces. The
imports happen only at `onModuleInit` and only if credentials are
configured. If `firebase-admin` or `twilio` is missing, or if creds are
empty, the service logs a warning and silently no-ops on send — the API
still boots and runs.

This is deliberate: dev environments don't need real creds, and
production can roll out without breakage if (say) a Firebase outage
prevents init.

#### Push (Firebase Cloud Messaging)

```ts
interface FirebaseAdmin {
  apps?: unknown[];
  initializeApp(config: { credential: unknown }): void;
  credential: { cert(serviceAccount: Record<string, string>): unknown };
  messaging(): FirebaseMessaging;
}
```

`PushService.send(payload)`:

1. INSERT a row into `push_notifications` (audit + history).
2. Look up recipient users' `push_token` from DB.
3. Call `firebase.messaging().send(...)` for each token.
4. Catch FCM errors with `code === "messaging/registration-token-not-registered"`
   or `"messaging/invalid-registration-token"` → clear the bad token from
   the DB. Other errors are logged.

#### SMS (Twilio)

```ts
interface TwilioClient {
  messages: { create(opts: { to, from?, body }): Promise<{ sid: string }>; };
}
```

`SmsService.queueSms(payload)` writes to `sms_log` as `queued`. The
`SmsQueueProcessor` (§6.11) drains the queue.

`SmsService.sendImmediately(id)` is used for "send customer SMS now" from
the QC dispatch flow.

### 6.13 WebSocket gateway

**Path**: `/ws` (no global prefix, served directly by the NestJS WS adapter)

Used for real-time UI updates from server → client:

- New QC inspection assigned
- Production step status changed
- Delivery status changed
- New worker message

The mobile app keeps a persistent connection with auto-reconnect and
exponential backoff. The gateway authenticates with the JWT passed in the
connection handshake.

Server-side, gateways emit events from services after relevant mutations
(e.g. `qc.service.ts` after `submitInspection` succeeds).

### 6.14 Testing strategy

**File map**: 33 spec files alongside the code they test
(`*.service.spec.ts`, `*.controller.spec.ts`). Plus integration helpers in
[`test/helpers/`](test/helpers/).

#### Unit tests (the bulk — 396 currently passing)

Each service test mocks:
- **`PrismaService`** with a `jest.fn()` per method actually called
  (`trailer.findUnique`, `qcInspection.create`, etc.)
- **External services** (`StorageService`, `NotificationsService`,
  `WorkflowGeneratorService`) with minimal stubs
- **`$transaction`** with an implementation that calls back with a mock
  `tx` object exposing the same fn shapes — so the real-code path through
  the transaction runs against mocks identical to outside-tx mocks

This gives us **fast, deterministic feedback** without spinning up a real
DB. The trade-off is that we don't catch genuine SQL bugs in unit tests —
which is what the integration test helper is for.

#### Error-assertion convention (post-migration)

Tests assert on the **`errorCode`**, not the message string nor the
exception class:

```ts
await expect(service.submitInspection(dto, userId)).rejects.toMatchObject({
  errorCode: ErrorCode.QC_CHECKLIST_INCOMPLETE,
});
```

This pins the **typed code** (the API contract), not the wording. Message
strings can be reworded without breaking tests; renaming the code is a
deliberate, find-all-callers operation.

#### Test data + fixtures

- Mocked Prisma rows are inlined per test for readability (no shared
  fixture file — tests fail in isolation, not in cascade).
- `BigInt`s are spelled `BigInt(123)` everywhere — Prisma returns bigints
  for ID columns and tests must match.

#### Coverage gates

Currently no `--coverage` threshold in CI; the goal is *meaningful*
coverage, not high-percentage coverage. Critical paths (auth, payroll,
QC submission, delete cascades) all have dedicated test files.

#### Linting (also a deploy gate)

`npm run lint` runs `eslint` over `{src,apps,libs,test}/**/*.ts` with
`--fix`. Production sources are strict; `*.spec.ts` files relax
`@typescript-eslint/no-explicit-any` via an override so jest mocks don't
fight the linter.

### 6.15 Real-time event catalog

The WebSocket gateway emits server-side events when state changes that the
mobile UI should react to without polling. All events go through the
`/ws` namespace; the client subscribes on connect.

| Event | Trigger | Payload | Recipients |
|---|---|---|---|
| `production:step:active` | A step becomes active (after upstream completion) | `{ trailerId, stepId, departmentCode }` | Workers assigned to that department |
| `production:step:completed` | A worker completes a step | `{ trailerId, stepId, completedByUserId }` | Production manager dashboards |
| `production:step:rework` | A step is routed back as rework | `{ trailerId, stepId, departmentCode, reworkCount }` | Worker assigned + production manager |
| `qc:inspection:submitted` | QC submits an inspection | `{ trailerId, stepId, result, attemptNumber }` | Production manager; relevant worker on fail |
| `qc:ready` | Trailer arrives at a QC step | `{ trailerId, stepId, departmentCode }` | QC inspector |
| `delivery:status:changed` | Driver action changes delivery status | `{ deliveryId, trailerId, status }` | Transport manager + driver assigned |
| `trailer:stalled` | Stall detector finds a stuck step | `{ trailerId, stepId, hoursActive }` | Production manager |
| `notification:new` | Any push notification was generated | `{ notificationId, type, title }` | The recipient user (so the bell icon updates) |

Authentication happens at handshake: the JWT goes in the connection URL
query string. The gateway verifies it via the same `JwtStrategy` and
attaches `user` to the socket.

### 6.16 Mobile-API contract conventions

#### Response envelope

Every API response — success or error — is wrapped in a uniform shape by
`ResponseEnvelopeInterceptor` + `GlobalExceptionFilter`:

```jsonc
// Success
{
  "success": true,
  "data": <the actual response>,
  "meta": {
    "timestamp": "2026-05-24T09:45:44.369Z",
    "path": "/v1/auth/login",
    "method": "POST"
  }
}

// Error
{
  "success": false,
  "error": {
    "code": "QC_CHECKLIST_INCOMPLETE",
    "message": "Missing checklist results for items: 12, 17, 23",
    "statusCode": 400,
    "details": { "missingItemIds": [12, 17, 23] }   // optional
  },
  "meta": { "timestamp": "...", "path": "...", "method": "..." }
}
```

This lets the mobile client write **one error handler** that pattern-
matches on `error.code` and never worries about HTTP status quirks per
endpoint.

#### Pagination

Endpoints returning lists accept `page` (1-indexed) and `limit`
(default 25, max 100) and return:

```jsonc
{
  "success": true,
  "data": {
    "items": [...],
    "total": 1234,
    "page": 1,
    "limit": 25,
    "pages": 50
  }
}
```

#### IDs and BigInts

PostgreSQL `BIGSERIAL` PKs (e.g. `users.id`, `trailers.id`) become
JavaScript `bigint`s in Prisma. They're serialised to JSON as **numbers**
via the `BigInt.prototype.toJSON` polyfill in [main.ts](src/main.ts).

Mobile MUST be tolerant of bigint-ranges if any id ever exceeds 2^53 (won't
happen for years at our volume, but worth noting). Numeric ids in URL
params are pipe-coerced to `BigInt` by handlers via `ParseIntPipe` +
explicit `BigInt(id)`.

#### Date conventions

- All API timestamps are **ISO 8601 with timezone** (UTC by default).
- "Week start" parameters in payroll endpoints are **`YYYY-MM-DD` strings**
  representing a Sunday in the API's timezone.

#### Idempotency conventions (where it matters)

Endpoints that have natural idempotency keys are idempotent without
client-side help:

- `POST /storage/presign` — returns a fresh URL each call; the *object*
  isn't created until the client PUTs.
- `POST /auth/logout` — succeeds even if the refresh token was already
  revoked (no-op).
- `PATCH /auth/push-token` — overwrites whatever's stored.

Endpoints that aren't naturally idempotent and don't have a safe retry
pattern (e.g. `POST /qc/inspections`, `POST /trailers`) rely on the
client not retrying on 2xx. The mobile app implements explicit retry
only on network/5xx failures, not 4xx.

---

## 7. Data integrity discipline

Five rules we follow without exception:

1. **Every multi-table mutation is wrapped in `prisma.$transaction`.** A
   half-completed inspection is structurally impossible.
2. **FKs use `onDelete: Cascade` where the child is conceptually owned by
   the parent** (delivery → deliveryPhoto). `Restrict` everywhere else
   (trailer → customer requires explicit cascade flag in code).
3. **Soft-removal beats hard-removal for catalogue rows.** Trailer models
   marked `isActive = false` stay in the DB so historical trailers
   referencing them keep their FK — only the dropdown filters them out.
4. **Refresh-token reuse triggers full revocation.** If a token is presented
   that's already marked revoked, we assume theft and kill every active
   session for that user.
5. **TLS to the database is verify-full.** No `rejectUnauthorized: false`,
   no `accept_invalid_certs` URL params, no shortcuts. The DO CA cert is
   downloaded once, mounted into the container, and validated against on
   every connection.

---

## 8. CI/CD pipeline

### 8.1 Three workflows in [.github/workflows/](../.github/workflows/)

#### `api-deploy.yml` — push to main → production

**Trigger**: push to `main` touching `bigfoot-api/**` or the workflow file
itself, or manual `workflow_dispatch` with optional `skip_tests` toggle.

**Jobs** (run in series; failure of one halts the rest):

1. **Lint & Test** — `npm ci`, `npx prisma generate`, `npm run lint`,
   `npm test --ci`. All 396 tests must pass. ~1 min.
2. **Build & Push Image** — `docker buildx build` → push to
   `ghcr.io/<owner>/<repo>/bigfoot-api:sha-<commit>` and
   `:latest`. Layer cache lives in GHA cache (`type=gha`). ~2 min cold,
   ~20s with cache.
3. **Deploy to Production** — Gated by GitHub `production` environment
   (manual approval can be enabled in repo settings). Steps:
   - SCP `docker-compose.prod.yml` and `Caddyfile` to droplet (`/opt/bigfoot/`)
   - SSH to droplet, login to GHCR with the workflow's `GITHUB_TOKEN`,
     `docker compose pull api`, `docker compose up -d --remove-orphans`
   - `docker image prune -f`
   - Record the deployed SHA at `/opt/bigfoot/.deployed-sha` (for rollback)
   - Curl `https://<domain>/health` 30× over 150s — fail the deploy if
     never green.

**Concurrency**: `concurrency: { group: api-deploy-prod, cancel-in-progress: false }`
ensures deploys don't race.

#### `db-seed.yml` — manual seeding

**Trigger**: `workflow_dispatch` with `script` input (choice:
`seed | seed-trailer-catalog | seed-test-trailers`).

**What it does**: SSHes to the droplet and runs
`docker exec bigfoot-api-api-1 npx -y -p tsx@4 tsx prisma/<script>.ts`.
Idempotent — every operation in every seed is a Prisma `upsert` keyed by a
stable column (email, code, etc).

#### `android-distribute.yml` — manual Android build

**Trigger**: `workflow_dispatch` with optional release notes.

**What it does**: Builds a signed `arm64-v8a` production APK with the
upload-keystore (stored as base64 secret), distributes via Firebase App
Distribution to the `employees` tester group, and uploads the APK as a
workflow artifact for 14 days.

The build's `API_BASE_URL` is set from the `DEPLOY_DOMAIN` repo variable
— the same source of truth as the API deploy.

### 8.2 Rollback

```bash
# On the droplet, as deploy:
cd /opt/bigfoot/bigfoot-api
cat /opt/bigfoot/.deployed-sha   # current SHA
export IMAGE_TAG=sha-<previous-sha>
docker compose --env-file /opt/bigfoot/.env.production \
  -f docker-compose.prod.yml up -d
```

The previously-deployed SHA is recorded automatically by every successful
deploy, so rollback never requires hunting in `git log`.

---

## 9. Security posture

| Layer | Control |
|---|---|
| **Network — perimeter** | DO Cloud Firewall: SSH (22) restricted to operator IPs only; 80 + 443 open to all; everything else closed. |
| **Network — host** | UFW with identical rules (defence in depth). |
| **Network — DB** | Managed PG Trusted Sources = this droplet only. Private VPC endpoint used in `DATABASE_URL`. Public endpoint exists but no IP is allowlisted. |
| **SSH** | Key-only auth, root login disabled, dedicated CI key separate from operator key, fail2ban (3 fails / 24h ban). |
| **App process** | Runs as non-root `appuser` (uid 1001) inside the container. Bound to internal Docker network; `expose: 3000` not `ports`. |
| **TLS — client to API** | Let's Encrypt cert, auto-renewed by Caddy. HSTS 1y + preload. HTTP→HTTPS 308 redirect. |
| **TLS — API to DB** | verify-full against DO's actual CA cert. No shortcuts. |
| **TLS — API to Spaces, Twilio, Firebase** | Standard public-CA validation via Node's default trust store. |
| **Auth** | JWT 15m access + 7d refresh with rotation + reuse detection. Bcrypt 12-round password hashing. |
| **Authz** | RolesGuard + per-route `@Roles()`. Business-rule checks layered on top in services. |
| **Validation** | class-validator on every DTO, ValidationPipe global, sanitize middleware before validators. |
| **Throttling** | 100/min global, 5/min on login. |
| **Brute-force** | fail2ban on SSH, ThrottlerGuard on login, refresh-token reuse detection. |
| **Headers** | Helmet at app layer + Caddy on top: HSTS, CSP, X-Content-Type-Options, X-Frame-Options DENY, Permissions-Policy. |
| **Secrets** | Only on droplet at `/opt/bigfoot/.env.production` (chmod 600, owner deploy). Never committed. Never in CI logs. Never in Docker images. CI secrets in GitHub Encrypted Secrets. |
| **Supply chain** | Every deploy traceable to a commit SHA via the image tag; lint + 396 tests must pass before any image is built. |
| **Patching** | unattended-upgrades on the host applies Ubuntu security updates daily. |
| **Backups** | Managed PG daily backups + 7-day PITR. Weekly droplet snapshots ($6.40/mo). |
| **Audit trail** | Every POST/PATCH/PUT/DELETE recorded in `audit_log` (append-only). |
| **Recovery** | Rollback by image tag. DB restore from PITR. Spaces is regional with DO's durability guarantees. |

---

## 10. Operational runbook

### 10.1 Deploy

Just `git push origin main` (touching `bigfoot-api/**`). Done.

### 10.2 Re-seed the database

GitHub UI: **Actions → "DB · Seed (manual)" → Run workflow → choose script**.
Idempotent — safe to run repeatedly.

### 10.3 View logs

```bash
ssh deploy@<droplet-ip>
cd /opt/bigfoot/bigfoot-api
docker compose -f docker-compose.prod.yml logs -f api caddy
```

### 10.4 Restart the API

```bash
docker compose -f docker-compose.prod.yml restart api
```

### 10.5 Update env vars

```bash
sudo -u deploy nano /opt/bigfoot/.env.production
docker compose -f docker-compose.prod.yml up -d
```

`up -d` will recreate the api container because the env file changed.

### 10.6 Rollback to a previous deploy

See §8.2.

### 10.7 Check what's deployed

```bash
docker inspect bigfoot-api-api-1 --format '{{.Image}}'
cat /opt/bigfoot/.deployed-sha
```

### 10.8 Trigger an Android build

```powershell
gh workflow run "Android — Build & Distribute" --repo <owner>/<repo> --ref main `
  --field release_notes="What changed in this build"
```

Distributes via Firebase App Distribution to the `employees` tester group.

### 10.9 Add a new user

Two options:

1. **API**: `POST /v1/users` with admin JWT.
2. **DB seed**: Add to `prisma/seed.ts` → re-run via the DB Seed workflow.
   Idempotent — won't duplicate.

### 10.10 Pull a Postgres backup

DO Panel → Databases → cluster → Backups → restore to a new cluster (DO
doesn't allow in-place restore; you spin up a fork). Then point a staging
API at the fork to dig into historical data.

---

## 11. Design decisions & trade-offs

| Decision | What we picked | What we gave up | Why |
|---|---|---|---|
| Single droplet vs Kubernetes | Single droplet | Auto-scaling, multi-AZ HA | One factory, <100 users. K8s overhead would dominate the workload. |
| Managed PG vs self-hosted | Managed | $15/mo + slightly less control | Payroll data; backups and PITR aren't optional. |
| Managed Redis vs self-hosted | Self-hosted (in droplet) | DO automatic failover | Redis holds only ephemeral job state. Saves $15/mo without risk. |
| In-process jobs vs separate worker | In-process | Independent scaling | Light workload + operational simplicity beats theoretical scale headroom. |
| Custom typed errors vs framework exceptions | `AppError` + `ErrorCode` | A few extra lines per throw | Clients pattern-match on stable codes; messages can be reworded without breaking clients. |
| `prisma db push` + sql-patches vs migrations | push + patches | Auto-generated rollback scripts | Schema is small; destructive changes are PR-reviewed; full DB backups cover us. |
| Pre-signed URLs vs server-proxied uploads | Pre-signed | Server can't validate file bytes mid-upload | Bandwidth, memory, and failure modes all win. Validation runs at presign time (extension, type, size cap). |
| SO-number Spaces paths vs trailer-id | SO numbers | One extra DB lookup per presign | Bucket folders are human-readable; support can navigate. |
| Inline asset cleanup + orphan processor | Both | A tiny bit more code | Inline = immediate user-visible effect; processor = safety net for failures. |
| `verify-full` TLS to DB | Strict validation against DO CA | A bit of setup (download cert + mount) | Cert validation shortcuts are a slippery slope; non-negotiable per our security stance. |
| DuckDNS instead of paid domain | Free | Less professional URL | Stopgap until a real domain is registered; everything else is in place to switch in 5 minutes. |
| Single QC inspector role | One inspector covers QC_1..5 + FINAL_QC | Per-department QC user accounts | Matches the actual factory org chart; simpler permissions. |
| Build APK per ABI, arm64-v8a only | One target | Older 32-bit Android devices | All staff phones are 64-bit; smaller APK; faster distribution. |

---

## Appendix A. File map

```
bigfoot-api/
├── Dockerfile                       # Multi-stage build, runs as non-root appuser
├── docker-compose.yml               # Local dev: postgres + redis + api
├── docker-compose.prod.yml          # Production: caddy + api + redis (no postgres)
├── docker-entrypoint.sh             # prisma db push + sql-patches → start API
├── Caddyfile                        # TLS termination + security headers
├── DEPLOYMENT.md                    # Step-by-step deploy runbook
├── ARCHITECTURE.md                  # ← this file
├── package.json
├── .env.example                     # Dev env template
├── .env.production.example          # Production env template
│
├── prisma/
│   ├── schema.prisma                # ORM schema (~40 models)
│   ├── db-client.ts                 # Shared PrismaClient factory for scripts
│   ├── seed.ts                      # Base seed: locations, models, departments, users
│   ├── seed-trailer-catalog.ts      # Extra trailer models + ready trailers
│   ├── seed-test-trailers.ts        # 6 test trailers for batch-delivery testing
│   └── sql-patches/                 # Idempotent DDL Prisma can't express
│
├── src/
│   ├── main.ts                      # NestJS bootstrap, Helmet, CORS, Swagger
│   ├── app.module.ts                # Root module: 12 features + global guards
│   │
│   ├── common/
│   │   ├── config/env.validation.ts # Fail-fast env validation at boot
│   │   ├── decorators/              # @Public, @Roles, @CurrentUser
│   │   ├── errors/                  # AppError + ErrorCode + filter
│   │   ├── filters/http-exception.filter.ts
│   │   ├── guards/                  # JwtAuthGuard, RolesGuard
│   │   ├── health/                  # /health endpoint
│   │   ├── interceptors/            # Logging + ResponseEnvelope
│   │   ├── middleware/              # RequestLogger, Sanitize
│   │   └── pipes/validation.pipe.ts
│   │
│   ├── prisma/
│   │   ├── prisma.module.ts         # Global module
│   │   └── prisma.service.ts        # PrismaClient w/ TLS-validated DO PG
│   │
│   └── modules/
│       ├── auth/                    # JWT, refresh rotation, push token
│       ├── users/                   # User CRUD with authz
│       ├── trailers/                # Lifecycle, workflow, addons, delete cascade
│       ├── production/              # Step completion, queues
│       ├── qc/                      # Inspections, rework, customer SMS
│       ├── payroll/                 # Point values, dollar rates, weekly lock
│       ├── deliveries/              # Single + batch + factory pickup
│       ├── customers/               # CRUD + cascade
│       ├── locations/               # Factory + remote yards
│       ├── notifications/           # Push + SMS + messages + WS
│       ├── storage/                 # Pre-signed URLs, S3 helpers
│       ├── admin/                   # Workflow config, audit log, reports
│       └── jobs/                    # 4 BullMQ processors
│
└── test/
    └── helpers/                     # Test DB + auth helpers (integration tests)
```

---

## Appendix B. Environment variables

All variables are validated at boot by [env.validation.ts](src/common/config/env.validation.ts).
Missing required values or the literal `JWT_SECRET` placeholder cause the
API to refuse to start.

| Variable | Required? | Notes |
|---|---|---|
| `NODE_ENV` | Yes | `production` enables prod-only env checks + disables Swagger |
| `PORT` | No (default 3000) | Internal port the API listens on |
| `API_PREFIX` | No (default `v1`) | Global URL prefix |
| `DOMAIN` | Yes (prod) | Caddy serves TLS for this hostname |
| `DATABASE_URL` | Yes | PG connection string. Must NOT include `?sslmode=...` (overrides our ssl config) |
| `DATABASE_SSL_CA_PATH` | Yes (prod) | Path to DO Managed PG CA cert inside the container |
| `REDIS_HOST` | Yes | Usually `redis` (Docker service name) |
| `REDIS_PORT` | No (default 6379) | |
| `JWT_SECRET` | Yes | ≥32 chars; the placeholder string is rejected |
| `JWT_ACCESS_EXPIRY` | No (default `15m`) | |
| `JWT_REFRESH_EXPIRY` | No (default `7d`) | |
| `CORS_ORIGINS` | Yes (prod) | Comma-separated list. Localhost only allowed in dev. |
| `DO_SPACES_ENDPOINT` | Yes (prod) | e.g. `https://nyc3.digitaloceanspaces.com` |
| `DO_SPACES_REGION` | Yes (prod) | e.g. `nyc3` |
| `DO_SPACES_BUCKET` | Yes (prod) | |
| `DO_SPACES_ACCESS_KEY` | Yes (prod) | |
| `DO_SPACES_SECRET_KEY` | Yes (prod) | |
| `DO_SPACES_CDN_URL` | No | Leave blank (CDN disabled by design) |
| `TWILIO_ACCOUNT_SID` | Yes (prod) | Placeholder OK if SMS not in use |
| `TWILIO_AUTH_TOKEN` | Yes (prod) | |
| `TWILIO_PHONE_NUMBER` | Yes (prod) | |
| `FIREBASE_PROJECT_ID` | Yes (prod) | |
| `FIREBASE_CLIENT_EMAIL` | Yes (prod) | |
| `FIREBASE_PRIVATE_KEY` | Yes (prod) | Newlines escaped as `\n`; un-escaped at runtime |
| `THROTTLE_TTL` | No (default 60000ms) | Window for rate limiter |
| `THROTTLE_LIMIT` | No (default 100) | Requests per window |
| `IMAGE_TAG` | No (default `latest`) | Overridden by CI to a specific commit SHA |

---

## Appendix C. Key endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness + DB/Redis check (excluded from `/v1` prefix) |
| POST | `/v1/auth/login` | Email + password → JWT pair |
| POST | `/v1/auth/refresh` | Refresh token → new JWT pair (rotation) |
| POST | `/v1/auth/logout` | Revoke a refresh token |
| PATCH | `/v1/auth/push-token` | Register / update FCM token |
| GET | `/v1/users` | List users (admin) |
| POST | `/v1/users` | Create user (owner/PM only) |
| PATCH | `/v1/users/:id` | Update user (self for limited fields, owner/PM for all) |
| DELETE | `/v1/users/:id` | Soft delete (deactivate) |
| GET | `/v1/trailers` | List trailers (paginated, filterable) |
| POST | `/v1/trailers` | Create trailer + auto-generate workflow |
| GET | `/v1/trailers/:id` | Trailer detail with model, customer, current step |
| PATCH | `/v1/trailers/:id` | Update color, notes, hot flag, priority, etc |
| DELETE | `/v1/trailers/:id` | Owner-only cascade delete (DB + Spaces) |
| GET | `/v1/trailers/:id/steps` | Production step list for trailer |
| GET | `/v1/trailers/:id/history` | Steps + QC inspections + deliveries + audit log |
| POST | `/v1/trailers/:id/qb-pdf` | Attach QuickBooks SO PDF |
| GET | `/v1/production/queues/:deptCode` | Active queue for a department |
| POST | `/v1/production/steps/:id/complete` | Worker marks step done; awards points |
| GET | `/v1/qc/checklist` | Filter checklist items for a series + trailer addons |
| POST | `/v1/qc/inspections` | Submit QC inspection (pass advances, fail routes back) |
| POST | `/v1/qc/inspections/:id/send-sms` | Send the FINAL_QC pass customer SMS |
| GET | `/v1/payroll/weekly-report/:date` | Weekly payroll roll-up |
| POST | `/v1/payroll/lock/:date` | Owner locks payroll for a week |
| POST | `/v1/deliveries` | Create single delivery |
| POST | `/v1/deliveries/batches` | Create delivery batch |
| POST | `/v1/deliveries/:id/depart` | Driver marks delivery in transit + customer SMS |
| POST | `/v1/deliveries/:id/complete` | Driver marks delivery delivered |
| POST | `/v1/location-receipts` | Remote location confirms received |
| POST | `/v1/storage/presign` | Get pre-signed PUT URL |
| GET | `/v1/storage/presign/:key` | Get pre-signed GET URL |
| GET | `/v1/admin/trailer-models` | Active trailer-model dropdown (filtered by isActive) |
| GET | `/v1/admin/weekly-production/:date` | Weekly production report |
| WebSocket | `/ws` | Real-time push to mobile clients |

---

## Appendix D. Database schema overview

~40 tables. The major ones:

| Table | Purpose |
|---|---|
| `users` | Email, password hash, role, primary department, primary location, isActive |
| `refresh_tokens` | Hashed refresh tokens, expiry, revoked-at |
| `audit_log` | Append-only: user_id, entity_type, entity_id, action, old/new values, IP |
| `customers` | Customer records (regular customers + stock-build pseudo-customers) |
| `locations` | Factory + remote yards (Mulberry, Jacksonville, etc) |
| `trailer_models` | Catalog of models for the create-trailer dropdown (isActive) |
| `trailers` | Main entity: SO number, model, customer, location, status, addons FK, QB PDF key |
| `trailer_addons` | Per-trailer add-on metadata (winch, tongue box, etc) |
| `departments` | 20 production + QC departments with completion type + stall threshold |
| `workflow_templates` | Per-series 12-step blueprint (one per series × step ordering) |
| `production_steps` | Per-trailer instances of workflow steps with status + active/done |
| `qc_checklist_items` | Per-department + per-series checklist items (configurable) |
| `qc_inspections` | One per inspection submission (pass/fail, inspector, attempt number) |
| `qc_inspection_items` | Per-checklist-item result rows |
| `qc_photos` | Storage keys for inspection photos |
| `production_step_checks` | Upstream worker self-checks (pre-populate QC checklist) |
| `point_values` | Points per (model, department) — feeds payroll |
| `dept_dollar_rates` | $ per point per department — feeds payroll |
| `payroll_records` | Per (user, week) summary with locked flag |
| `deliveries` | Single, factory-pickup, stack-to-dealer, stack-to-location |
| `delivery_batches` | Groups deliveries together for a single dispatch |
| `delivery_photos` | Storage keys for proof-of-delivery + damage photos |
| `location_receipts` | Remote-location confirmation of trailer arrival |
| `sms_log` | Outbound SMS queue + delivery state |
| `push_notifications` | Outbound push queue + delivery state |
| `worker_messages` | Free-text messages between staff about a trailer |
| `stall_alerts` | Stall-detector job output |

Generated diagram on demand via `npx prisma generate` if you need a visual
ERD; the canonical source is [prisma/schema.prisma](prisma/schema.prisma).

---

## Appendix E. Complete `ErrorCode` reference

Every error the API can throw, sorted by HTTP status. Mobile pattern-matches
on `error.code`; messages are reworded freely without breaking clients.

| Code | HTTP | Default message | Where thrown |
|---|---|---|---|
| `STEP_NOT_ACTIVE` | 400 | Cannot complete a step that is not currently active | Production / QC services when step.status ≠ active |
| `STEP_ALREADY_COMPLETE` | 400 | Step has already been marked complete | Production service on duplicate complete |
| `REWORK_POINTS_MUST_BE_ZERO` | 400 | Rework steps cannot award points | Production service on completing a rework step with non-zero points |
| `QC_PHOTO_REQUIRED` | 400 | At least one photo is required per QC inspection | QC submitInspection (when configured for photo-required dept) |
| `QC_CHECKLIST_INCOMPLETE` | 400 | All checklist items must be answered before submission | QC submitInspection — missing item ids in `details.missingItemIds` |
| `QC_INVALID_REWORK_TARGET` | 400 | The rework target department is not in this trailer's workflow | ReworkRoutingService |
| `QC_REWORK_TARGET_REQUIRED` | 400 | A rework target department must be selected when the QC result is a fail | QC submitInspection with result=fail |
| `QC_ONLY_INSPECTOR` | 400 | Only a QC inspector or production manager can submit QC inspections | QC submitInspection |
| `CUSTOMER_LOCKED` | 400 | Cannot change customer after QuickBooks invoice has been created | Trailers update |
| `PAYROLL_WEEK_LOCKED` | 400 | Payroll for this week has already been locked | Payroll mutations on locked weeks |
| `INVALID_WEEK_START` | 400 | The week start date must be a Sunday | Any payroll endpoint with non-Sunday date |
| `DELIVERY_NOT_DISPATCHABLE` | 400 | Trailer is not in ready_for_delivery status | Batches addTrailers / Deliveries actions on wrong-state trailers/deliveries |
| `BATCH_NOT_BUILDING` | 400 | Cannot modify a batch that is not in building status | Batches update on non-building batch |
| `LOCATION_RECEIPT_WRONG_LOCATION` | 400 | Receiving user's location does not match delivery destination | LocationReceipts create |
| `PRESIGN_INVALID_FILE_TYPE` | 400 | The requested file type is not a permitted upload category | Storage presign — bad fileType or wrong extension for type |
| `BAD_REQUEST` | 400 | Invalid request | Generic / fallthrough for input validation |
| `UNAUTHORIZED` | 401 | Authentication required | Auth login/refresh, JwtStrategy validate |
| `FORBIDDEN` | 403 | You do not have permission to perform this action | Users service (self-only updates, deactivation rules), Auth (deactivated user login) |
| `STEP_REVERSAL_NOT_AUTHORIZED` | 403 | Only the completing worker or a production manager can reverse a step | Production reverseStep |
| `NOT_FOUND` | 404 | The requested resource was not found | Any service's `findUnique → null` path |
| `SO_NUMBER_EXISTS` | 409 | A trailer with this SO number already exists | Trailers create / update; Prisma P2002 unique-violation translation |
| `TOO_MANY_REQUESTS` | 429 | Too many requests — please try again later | ThrottlerGuard |
| `INTERNAL_ERROR` | 500 | An unexpected error occurred | Caught by GlobalExceptionFilter for anything not an AppError |

Source of truth: [src/common/errors/error-codes.ts](src/common/errors/error-codes.ts).

---

## Appendix F. Notification & SMS catalog

Every push and SMS the system sends — when, who triggers it, who gets it.

### Push notifications (`notification_type_enum`)

| Type | Trigger | Recipients | Title pattern |
|---|---|---|---|
| `qc_fail` | QC inspector submits result=fail | All production managers; worker assigned to the rework target step | "QC failed: SO-XXXX" |
| `qc_ready` | A production step completes and the next step is a QC department | The QC inspector (single user covering all QC) | "Ready for QC: SO-XXXX" |
| `trailer_stalled` | Stall detector finds a step `active` past department threshold | All production managers | "Trailer stalled: SO-XXXX" |
| `worker_message` | A user sends a free-text message about a trailer | The intended recipient (`toUserId`) | "Message from [sender]" |
| `payment_not_collected` | Driver marks delivery complete without recording payment | Office + owner | "Payment not collected: SO-XXXX" |
| `delivery_complete` | Driver marks delivery delivered | Office + owner | "Delivery complete: SO-XXXX" |

All push notifications are also **persisted** in `push_notifications` so
the mobile app's bell-icon history works even without FCM delivery — a
WebSocket `notification:new` event updates the badge in real time.

### Outbound SMS (`sms_type_enum`)

| Type | Trigger | Recipient | Body |
|---|---|---|---|
| `trailer_complete` | FINAL_QC pass | Customer (`customer.smsPhone`, if `smsOptOut=false`) | "Your trailer SO-XXXX is ready for pickup at Bigfoot Trailers Mulberry." |
| `driver_en_route` | Driver marks delivery departed (non-pickup types) | Customer | "Your trailer SO-XXXX is en route. ETA ~[h]h." |
| `delivery_complete` | Driver marks delivery delivered | Customer | "Your trailer SO-XXXX has been delivered." |

SMS sending is queued (`sms_log` table, `status='queued'`) and drained by
the `SmsQueueProcessor` ~1 min interval. The `sms_log` table is also the
audit trail for outbound SMS — every send (success or failure) leaves a
row with the Twilio SID for tracing.

### Lazy initialisation

Both Firebase and Twilio are **lazy-loaded** in their respective services
(`PushService.onModuleInit`, `SmsService.onModuleInit`). If creds are
missing or the SDK fails to load, the service logs a warning and queues
operations *no-op*. The API still boots and serves requests — only the
side effect is skipped. This is intentional for dev environments and for
graceful degradation in production.

---

## Appendix G. Database enum reference

All enums defined in [`prisma/schema.prisma`](prisma/schema.prisma).

```
TrailerSeries          xp | yeti | deck_over | gooseneck_dump
TrailerStatus          pending_production | in_production | ready_for_delivery
                       | in_transit | delivered | on_hold
TrailerSaleStatus      available | sale_pending | sold
ProductionStepStatus   waiting | active | complete | rework
QcResult               pass | fail
QcSeriesScope          xp | yeti | deck_over | gooseneck_dump | all
DeptCompletionType     one_tap | qc_checklist
UserRole               owner | production_manager | transport_manager
                       | qc_inspector | worker | sales | driver | office
CustomerType           end_user | dealer | stock_location
DeliveryType           factory_pickup | stack_to_dealer | stack_to_location | single_pull
DeliveryStatus         scheduled | in_transit | delivered | failed
DeliveryBatchStatus    building | scheduled | in_transit | complete
BatchType              dealer | bf_location
PhotoType              proof_of_delivery | damage
PaymentMethod          cashiers_check | debit | cash
SmsType                trailer_complete | driver_en_route | delivery_complete
SmsStatus              queued | sent | delivered | failed
NotificationType       qc_fail | qc_ready | trailer_stalled | worker_message
                       | payment_not_collected | delivery_complete
```

All enums use PostgreSQL native enums (`@@map("..._enum")`) so values are
constrained at the storage layer, not just in app code. Adding a new value
requires a Prisma schema change + `prisma db push` — automatic via the
container entrypoint.

---

## Appendix H. BullMQ processor schedule & behaviour

All four processors live in [`src/modules/jobs/`](src/modules/jobs/) and
run inside the API process via `setInterval` registered in `OnModuleInit`.
Each has a `processing: boolean` single-flight guard so a slow run can't
overlap with the next tick.

### `StallDetectorProcessor`

| Aspect | Value |
|---|---|
| File | [stall-detector.processor.ts](src/modules/jobs/stall-detector.processor.ts) |
| Interval | 15 minutes |
| Idempotency | One `stall_alerts` row per `(step_id, day)` — duplicate inserts swallowed |
| Side effects | INSERT into `stall_alerts`; push notification to all production managers |
| Failure mode | Logs error, increments retry-on-next-tick (no DLQ — by design, stalls re-fire next interval) |

**Query**: `SELECT production_step.* WHERE status='active' AND (now() - started_at) > department.stall_threshold_hours * interval '1 hour'`.

### `SmsQueueProcessor`

| Aspect | Value |
|---|---|
| File | [sms-queue.processor.ts](src/modules/jobs/sms-queue.processor.ts) |
| Interval | 1 minute |
| Idempotency | Drains rows in `status='queued'`; transitions to `sent`/`failed` so each row is processed at most once |
| Batch size | 50 per tick |
| Failure mode | Failed rows logged with Twilio error; orphan stays in `status='queued'` if Twilio itself is down (will retry next tick) |

### `ReportGeneratorProcessor`

| Aspect | Value |
|---|---|
| File | [report-generator.processor.ts](src/modules/jobs/report-generator.processor.ts) |
| Interval | Weekly Sunday 00:05 UTC |
| Idempotency | Upsert per `(user_id, week_start_date, department_id)` — safe to re-run |
| Output | INSERT/UPDATE rows in `payroll_records` |
| Lock check | Skips weeks already marked `is_locked=true` |

### `OrphanCleanupProcessor`

| Aspect | Value |
|---|---|
| File | [orphan-cleanup.processor.ts](src/modules/jobs/orphan-cleanup.processor.ts) |
| Interval | 24 hours |
| Idempotency | Re-listing Spaces is idempotent; deleting an already-deleted key is a no-op |
| Behaviour | For each prefix (`qc/`, `delivery/`, `so-pdf/`, `damage/`): list objects, query DB for referenced keys, DELETE the difference |
| Safety | Per-key try/catch — one S3 hiccup doesn't kill the run; logged warning, next tick retries |

### Why in-process rather than separate workers?

For our workload:

- **Concurrency**: All four processors combined do well under 1 req/sec
  of work. They don't compete meaningfully with the HTTP request handlers.
- **Operational simplicity**: One process to deploy, one log stream, one
  set of metrics, one container to restart.
- **Shared state**: Same DB pool, same Prisma client, same Logger format,
  same error-handling conventions.

If load ever justified separation, the migration is mechanical:
extract the processors into a separate Nest application that depends on
the same modules, deploy as a second `worker` container in
`docker-compose.prod.yml`, point at the same Redis. No code changes
inside the processors themselves.

---

## Appendix I. Glossary

| Term | Meaning in this codebase |
|---|---|
| **SO** | Sales Order. The natural unique key for a trailer (`SO-1001`, etc). Stored as `trailer.soNumber`. |
| **Series** | One of four trailer product lines: XP, Yeti, Deck Over, Gooseneck/Dump. Each series has its own 12-step workflow blueprint and series-specific QC checklist items. |
| **Step** | A row in `production_steps`. One trailer has exactly 12 steps after creation, generated from `workflow_templates`. |
| **Active step** | The single step per trailer with `status='active'`. The only step a worker can complete or a QC inspector can submit against. |
| **Rework** | When a QC inspection fails, the inspector picks a previous department as the rework target. That earlier step gets `status='rework'`, `rework_count++`, and the worker re-does it. Completing a rework step awards zero points. |
| **Addon** | A trailer extra (winch, tongue box, etc) recorded in `trailer_addons`. Some QC checklist items are gated on addon presence (`requires_addon_key`). |
| **Batch** | A `delivery_batch` row grouping multiple deliveries that ship together to the same destination. |
| **Stock build** | A trailer with no customer assigned — built on spec to sit at a stock yard. Uses a stock-location pseudo-customer. |
| **Stack** | A delivery type where multiple trailers are "stacked" on one truck — `stack_to_dealer` or `stack_to_location`. |
| **Pickup** | Customer-initiated retrieval at the factory; no driver/SMS involved. `DeliveryType.factory_pickup`. |
| **Self-check** | A worker recording a quick checklist result during their step so the downstream QC inspector starts with that result pre-populated. Stored in `production_step_checks`. |
| **Stall** | A production step that has been `active` longer than its department's `stall_threshold_hours`. Surfaced via `stall_alerts` + push to production manager. |
| **Lock (payroll)** | An owner action that freezes a week's `payroll_records` from further edits. Enforced via `PAYROLL_WEEK_LOCKED` error. |
| **Final QC** | The 12th step (`FINAL_QC`). Passing it sets the trailer to `ready_for_delivery` and triggers the customer trailer-complete SMS. |
| **Workflow template** | A row in `workflow_templates` mapping `(series, step_order) → department`. The blueprint copied into `production_steps` on trailer create. |
| **Trusted Sources** | DigitalOcean Managed Database firewall rule allowing only specific IPs/droplets to connect. We allowlist only this droplet. |
| **Pre-signed URL** | A short-lived (15 min) S3 URL with embedded HMAC signature, letting a client PUT or GET an object without API credentials. Mobile uploads use these to bypass our server. |

---

*This document mirrors the state of the system as deployed. Update it as
the architecture changes.*
