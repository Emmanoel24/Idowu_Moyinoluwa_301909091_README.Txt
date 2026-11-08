# Cloud architecture for PassPoint — distributed/cloud exercise (Portfolio 5)

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Case study:** PassPoint (passport appointment slots)
**Regulatory baseline:** Nigeria Data Protection Act (NDPA) 2023.

This document describes the production cloud architecture for PassPoint: where the data lives, how it is replicated, what consistency/availability trade-off we choose, how personal data is encrypted and access-controlled, and how the system survives the rush when new appointment slots are released. It is grounded in the same PassPoint schema used by Portfolios 1–4 — every component below has a direct counterpart in the SQL/MongoDB code already submitted.

---

## 1. Deployment topology

```
                   ┌──────────────────────────────────────────────┐
                   │  AWS Lagos region (af-west-1 — simulated)    │
                   │                                              │
                   │  ┌────────────────────┐                      │
                   │  │  Application tier  │  (ECS Fargate / EKS) │
                   │  │  PassPoint API     │  autoscaling 2..20   │
                   │  └─────────┬──────────┘                      │
                   │            │                                 │
                   │   ┌────────┴─────────┐                       │
                   │   │ PostgreSQL 16    │   PRIMARY (read-write)│
                   │   │ passpoint        │   monthly partitions  │
                   │   │ (slot, appt, pay)│                       │
                   │   └────────┬─────────┘                       │
                   │            │ WAL stream (async)              │
                   │   ┌────────┴─────────┐                       │
                   │   │ MongoDB 8 shard  │   uploaded documents  │
                   │   │ passpoint.docs   │   (5 document types)  │
                   │   └──────────────────┘                       │
                   │                                              │
                   └──────────────┬───────────────────────────────┘
                                  │ async streaming replication
                                  │ (cross-region, < 1 s lag)
                   ┌──────────────┴───────────────────────────────┐
                   │  AWS Abuja region (simulated)                │
                   │  ┌────────────────────┐                      │
                   │  │ PostgreSQL 16      │   READ REPLICA       │
                   │  │ (read-only)        │   DR + read-scaling  │
                   │  └────────────────────┘                      │
                   │  ┌────────────────────┐                      │
                   │  │ S3 (encrypted)     │   daily snapshots    │
                   │  │ /passpoint-backups │   + WAL archive      │
                   │  └────────────────────┘                      │
                   └──────────────────────────────────────────────┘
```

Both regions are **inside Nigeria**. Personal data (applicant names, dates of birth, hashed NINs, uploaded documents) **never leaves Nigerian territory**, as the NDPA 2023 requires for personal data of Nigerian residents (the Act restricts cross-border transfer of personal data to countries with adequate protection; keeping it inside Nigeria is the simplest and safest compliance posture).

---

## 2. CAP theorem — what PassPoint chooses

The CAP theorem says a distributed system can guarantee at most two of {Consistency, Availability, Partition tolerance}. Because network partitions **can** happen (a fiber cut between Lagos and Abuja is a real possibility), partition tolerance is non-negotiable — we cannot give it up. The choice is therefore between **CP** (sacrifice availability during a partition) and **AP** (sacrifice strong consistency).

**PassPoint chooses AP** for the cross-region pair:

- The **primary** in Lagos is the source of truth and is strongly consistent within itself (single-node PostgreSQL = C).
- The **Abuja replica** is a *streaming async* replica: a few hundred milliseconds behind. Reads on the replica can see slightly stale data; writes are rejected.
- During a partition between Lagos and Abuja, both regions stay **available**: Lagos keeps accepting writes; Abuja keeps serving stale reads from its local copy. When the partition heals, the replica catches up from the WAL backlog.

This is the right trade-off for a passport office because:

- The cost of a 200 ms replica lag is negligible — nobody gets hurt if the dashboard shows "5 appointments booked today" instead of "6" for a few hundred milliseconds.
- The cost of *unavailability* (the Abuja office cannot show the appointment list at all because the Lagos primary is unreachable) is much higher — applicants queue at the door, staff cannot work.
- The truly consistency-critical operations (booking a slot, paying a fee) happen **on the primary only**, so they are strongly consistent within the Lagos region.

For the rare operation that needs cross-region consistency (e.g. moving an appointment from one office to another during a failover), the application uses a synchronous `SELECT … FOR UPDATE` on the primary and accepts a brief failure window if the primary is unreachable — this is acceptable because such operations are rare and human-driven, not user-facing.

---

## 3. Sync vs. async replication — the trade-off

| Aspect | Synchronous (SYNC) | Asynchronous (ASYNC) — PassPoint's choice |
|---|---|---|
| Write latency on primary | High (primary waits for the replica to flush WAL before COMMIT returns) — typically 10–50 ms cross-region. | Low — primary returns COMMIT as soon as the local WAL is flushed; replica follows. ~1 ms local. |
| Data loss on primary failure | None — every committed transaction is guaranteed to be on the replica. | Small — the last few transactions (typically < 1 second's worth) may be lost. |
| Availability during a partition | If the replica is unreachable, writes on the primary **block** (or fail) until the partition heals — sacrifices availability. | Primary keeps accepting writes; replica falls behind; both stay available. |
| Operational complexity | Higher — needs careful tuning of `synchronous_standby_names`, failover code, and quorum management. | Lower — standard streaming replication; failover is `pg_promote()` on the replica. |
| Right for PassPoint? | **No** — passport bookings are not financial transactions; a 200 ms replica lag and the rare lost booking (which the applicant can retry) are far cheaper than blocking every Lagos write while waiting for Abuja. | **Yes** — see the CAP choice above. |

**Practical rule of thumb:** if the system can tolerate a 1-second RPO (Recovery Point Objective — the maximum acceptable data loss) and a 1-minute RTO (Recovery Time Objective — the maximum acceptable downtime), async replication is the right choice. PassPoint's RPO target is 5 seconds (the replica is at most 5 s behind in the worst case; usually < 1 s), and its RTO target is 10 minutes (a manual `pg_promote()` of the Abuja replica). Both are easily met with async streaming replication.

---

## 4. Encryption and access control for personal data

The PassPoint schema stores three categories of personal data:

1. **Direct identifiers**: applicant name, email, phone, date of birth, gender; collector name and relation.
2. **Special-category identifiers**: the **national ID number (NIN)** of the applicant and of the person collecting the passport.
3. **Biometric-adjacent data**: the uploaded documents (birth certificate, NIN slip, old passport, photo, affidavit) which themselves contain identifiers and photos.

Each category has a different protection level under NDPA 2023:

### 4.1 Encryption at rest

| Layer | Mechanism |
|---|---|
| PostgreSQL data files | Encrypted at the EBS volume level with AWS KMS-managed keys (the `aws:ebs` volume is encrypted; PostgreSQL itself does not need TDE). Key rotation every 90 days. |
| MongoDB data files | Same — EBS-level KMS encryption. |
| S3 backups | SSE-KMS (server-side encryption with KMS-managed keys). |
| WAL archive | S3 SSE-KMS. |

### 4.2 Encryption in transit

| Channel | Mechanism |
|---|---|
| Application → PostgreSQL | TLS 1.3 (`sslmode=verify-full`). The certificate is pinned to the application's CA bundle. |
| Application → MongoDB | TLS 1.3 (`tls=true&tlsAllowInvalidCertificates=false`). |
| Primary → replica (streaming replication) | TLS 1.3 with `sslmode=verify-full` and certificate verification. |
| Application → S3 (backups) | HTTPS (TLS 1.3). |

### 4.3 The NIN — hashed, not encrypted

The NIN is stored **only as a SHA-256 hash** (`applicant.nin_hash`, `collection.collector_id_hash`). Hashing is one-way: even if the database leaks, the plaintext NIN cannot be recovered without brute-forcing 10¹¹ possibilities (feasible but slow, and mitigated further by per-application salt in production). Encryption would require key management and would still leak the plaintext if the key leaked; hashing is the safer choice for an identifier that is never needed in plaintext after onboarding.

### 4.4 Access control (IAM + database roles)

| Principal | What it can do | What it cannot do |
|---|---|---|
| `passpoint_app` (application IAM role, PostgreSQL `app_rw`) | SELECT/INSERT/UPDATE on all tables in `passpoint`; cannot DROP, cannot ALTER. | Cannot read `payment.reference`, cannot read raw `payment.amount_ngn` (column-level privilege revoked), cannot DROP. |
| `passpoint_officer` (passport officer, PostgreSQL `officer_ro`) | SELECT on applicant/appointment/payment/collection (for the office they belong to — enforced by row-level security). | Cannot read `nin_hash` (column revoked), cannot INSERT/UPDATE/DELETE. |
| `passpoint_dba` (DBA, PostgreSQL superuser-equivalent) | Everything except reading plaintext NIN — but plaintext NIN is never stored, so this is moot. | Cannot grant its own role to others (no `CREATEROLE`). |
| `passpoint_auditor` (read-only auditor) | SELECT on `application_status_history`, `payment`, `collection` only. | Cannot read `applicant`, `slot`, `appointment` directly. |
| `replicator` (replication role) | `REPLICATION` privilege only. | No DML on user tables. |

Row-level security (RLS) ensures an officer in the **Ikoyi office** can only see Ikoyi applicants/appointments, not Alausa's. The policy joins `appointment → slot → office` and checks `office_id = current_setting('app.office_id')::uuid`.

---

## 5. Handling the rush when new slots open

PassPoint's biggest operational stress is the moment new slots are released (e.g. the first Monday of every month at 09:00 Lagos time, when next month's calendar opens). Demand spikes 100× within seconds. Three mechanisms absorb the spike:

### 5.1 Partition pruning — the rush hits only the current month's partition

`appointment` is partitioned by month (`partition.sql`). When applicants book into next month's slots, only the `appointment_p5_<next-month>` partition receives writes. The primary's INSERT workload is concentrated on **one** small partition (a few hundred thousand rows), not the entire multi-year table (millions of rows). Index maintenance, WAL generation, and lock contention all scale with the size of the partition being written to, not the whole table.

### 5.2 Queue-based writes — the application tier does not write directly to PostgreSQL

The application tier (ECS Fargate / EKS, autoscaling 2 → 20 instances) accepts booking requests from applicants and pushes them onto an Amazon SQS queue. A separate worker pool (autoscaling 1 → 10) consumes the queue and calls `book_slot()` on the primary. This decouples the *acceptance* of a request (sub-100 ms response to the applicant) from the *processing* of it (the `book_slot()` call, which may take longer if the primary is busy).

- If the primary is saturated, the queue grows but applicants still get "your request is queued" within 100 ms.
- The worker pool scales horizontally; each worker holds its own PostgreSQL connection from a PgBouncer pool (max 100 server-side connections).
- Failed `book_slot()` calls (slot already taken, payment failed) are not retried automatically — they go to a dead-letter queue and the applicant is notified by email/SMS to retry.

### 5.3 Elastic capacity — autoscaling + read replica

- **Application tier** autoscales on CPU > 60% and queue depth > 1000, up to 20 instances.
- **Worker tier** autoscales on queue depth > 100, up to 10 instances.
- **Primary PostgreSQL** is a `db.r6g.xlarge` (4 vCPU, 32 GB RAM) — large enough for the steady-state load, with a pre-warmed `db.r6g.2xlarge` replica on standby in the Lagos region that can be promoted within 60 seconds if the primary fails.
- **Abuja replica** is `db.r6g.large` — cheaper, async, used for read-scaling of the management dashboard and for disaster recovery.

### 5.4 Slot-release atomicity

When the operations team releases next month's slots, they run a single `INSERT INTO slot … SELECT …` that creates ~32 000 slot rows (4 offices × 2 counters × 16 slots/day × ~22 weekdays/month × 3 services). This is one transaction — it either commits all 32 000 rows or none. Applicants cannot book until the COMMIT lands, which avoids the "half the slots visible, the other half not" race that a row-by-row insert would create.

---

## 6. Disaster recovery and backups

| Mechanism | Frequency | Retention | Purpose |
|---|---|---|---|
| Streaming replication to Abuja | Continuous | n/a | Hot standby for DR and read-scaling. |
| `pg_basebackup` of primary to S3 | Daily 02:00 Lagos | 14 days | Full backup for point-in-time recovery. |
| WAL archive to S3 | Continuous | 14 days | Enables point-in-time recovery to any second in the last 14 days. |
| MongoDB `mongodump` to S3 | Daily 03:00 Lagos | 14 days | Full backup of uploaded documents. |
| Cross-region snapshot copy (Lagos → Abuja) | Daily 04:00 Lagos | 7 days | Even if the Lagos region is lost entirely, the latest daily snapshot is in Abuja. |

**RPO** (Recovery Point Objective): 5 seconds (async replication lag).
**RTO** (Recovery Time Objective): 10 minutes (manual `pg_promote()` of the Abuja replica + DNS switch).

---

## 7. NDPA 2023 compliance posture

The Nigeria Data Protection Act 2023 requires, among other things:

1. **Lawful basis and purpose limitation** — PassPoint collects personal data only for the purpose of booking a passport appointment and processing the application; the data is not used for any other purpose.
2. **Data minimisation** — PassPoint stores only the data needed: name, contact, DOB, gender, hashed NIN, the uploaded documents. It does not collect religion, political opinion, or other special-category data not needed for the service.
3. **Storage limitation** — Personal data is retained for 7 years after the last appointment (the statutory limitation period for passport-related records), then automatically purged by a scheduled job that drops the relevant monthly partition.
4. **Cross-border transfer restriction** — Personal data is stored **only** in the Lagos and Abuja regions of AWS, both inside Nigeria. No cross-border transfer to non-adequate countries.
5. **Security safeguards** — Encryption at rest (KMS), encryption in transit (TLS 1.3), hashed NIN, IAM-based access control, RLS, audit trail in `application_status_history`.
6. **Data subject rights** — Applicants can request access, correction, erasure (subject to the 7-year retention), and portability via the PassPoint support API, which reads their data from PostgreSQL and MongoDB.
7. **Breach notification** — CloudWatch alarms on unusual access patterns; any confirmed breach is notified to the Nigeria Data Protection Commission (NDPC) and to affected applicants within 72 hours, as required by the Act.

---

## 8. Summary

PassPoint's distributed/cloud architecture uses a PostgreSQL primary in Lagos (with monthly-partitioned `appointment`, async streaming replication to an Abuja read replica), a MongoDB shard for uploaded documents, KMS encryption at rest, TLS 1.3 in transit, IAM-based access control with row-level security, and a queue-based write path for the slot-release rush. The system chooses **AP** over CP for the cross-region pair (because availability matters more than a 200 ms replica lag), **async** over sync replication (because the latency cost of synchronous cross-region writes is much higher than the small RPO), and **partitioning by month** so the rush hits only the current month's partition. Personal data stays inside Nigeria (NDPA 2023), the NIN is stored only as a SHA-256 hash, and every access is logged in `application_status_history` for audit.
