# Normalisation notes — PassPoint schema (3NF)

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Portfolio:** 1 — Database Design and Modelling

This document explains why every table in `schema.sql` is in **Third Normal Form (3NF)**, and how the schema avoids the common normalisation pitfalls (partial dependencies, transitive dependencies, repeated groups) that 1NF and 2NF alone do not remove.

---

## 1. Definitions used

A relation R is in:

- **1NF** if every attribute holds an atomic value (no repeating groups, no arrays in a cell).
- **2NF** if R is in 1NF **and** every non-prime attribute is fully functionally dependent on the whole primary key (no partial dependency — relevant when the key is composite).
- **3NF** if R is in 2NF **and** no non-prime attribute is transitively dependent on the primary key. Equivalently: for every non-trivial functional dependency X → Y in R, either X is a superkey **or** Y is a prime attribute (a column that participates in some candidate key). This is the "nothing but the key" rule.

A practical test: "Every non-key column must depend on the key, the whole key, and nothing but the key."

---

## 2. Candidate keys and functional dependencies per table

| Table | Primary key | Other candidate keys (UKs) | Non-key attributes that depend ONLY on the PK |
|---|---|---|---|
| `office` | `office_id` | `office_code` | `name, city, address, is_active, created_at` |
| `counter` | `counter_id` | `(office_id, counter_no)` | `label, is_active` |
| `service_type` | `service_id` | `code` | `name, base_fee_ngn, processing_days, requires_old_passport, requires_affidavit` |
| `slot` | `slot_id` | `(office_id, counter_id, slot_date, start_time)` | `service_id, end_time, is_open` |
| `applicant` | `applicant_id` | `nin_hash`, `email` | `first_name, last_name, phone, date_of_birth, gender, created_at` |
| `appointment` | `appointment_id` | `slot_id` (UNIQUE) | `applicant_id, service_id, status, reschedule_count, booked_at, updated_at` |
| `payment` | `payment_id` | `appointment_id` (UNIQUE), `reference` | `amount_ngn, channel, payment_status, paid_at, confirmed_at, created_at` |
| `application_status_history` | `history_id` | none (append-only) | `appointment_id, from_status, to_status, actor, note, changed_at` |
| `collection` | `collection_id` | `appointment_id` (UNIQUE) | `collected_by, collector_relation, collector_id_hash, collected_at` |

All dependencies are on a single-column surrogate key (`uuid`) or, for `counter` / `slot`, on a composite key whose non-key columns depend on the **whole** composite (not just part of it). Therefore no partial dependencies exist → 2NF holds for every table.

No non-key column in any table determines another non-key column transitively through the PK. For example, `office.city` does **not** determine `office.address` (two offices in Lagos have different addresses), so there is no `city → address` transitive dependency. Likewise `payment.payment_status` does not determine `payment.confirmed_at` (a payment can be `CONFIRMED` with any `confirmed_at`), and `appointment.status` does not determine `appointment.reschedule_count` (a `CONFIRMED` appointment may have 0, 1 or 2 reschedules). Therefore no transitive dependencies exist → 3NF holds for every table.

---

## 3. Why BCNF is **almost** reached, and where we deliberately stop

Boyce-Codd Normal Form (BCNF) requires every non-trivial FD X → Y to have X as a superkey. The schema above satisfies BCNF for every table **except** `application_status_history`, where the dependency `appointment_id → (current status)` lives in `appointment`, not in the history table. The history table is itself BCNF (it only stores the audit trail), but the *logical* FD that "the current status of an appointment is a single value" is enforced by the trigger `trg_status_order`, not by a decomposition. This is intentional: storing the current status in `appointment` gives O(1) reads for the dashboard, while the history table gives the full audit trail. This trade-off is standard in event-sourced designs and is acceptable at 3NF.

---

## 4. Per-table 3NF argument

### 4.1 `office`
PK `office_id`. Non-key columns describe the office and only the office. `office_code` is a candidate key (UNIQUE), not a transitive dependency target. **3NF.**

### 4.2 `counter`
PK `counter_id`, composite UK `(office_id, counter_no)`. `label` and `is_active` depend on a specific counter, not on `office_id` alone or `counter_no` alone — so the composite UK is the right granularity. No partial dependency. **3NF.**

### 4.3 `service_type`
PK `service_id`. `base_fee_ngn`, `processing_days`, `requires_old_passport`, `requires_affidavit` are all facts about the service type, and nothing else. The fee depends only on the service, not on the office or applicant — this is why the fee is **not** copied into `appointment` or `payment`; it is looked up at payment time (see §5). **3NF.**

### 4.4 `slot`
PK `slot_id`. Composite UK `(office_id, counter_id, slot_date, start_time)` identifies one slot. `end_time` is computed from `start_time` (and stored for query convenience — it is a derived column, not a transitive dependency on the PK). `service_id` describes which service the slot is offered for (a counter at Ikoyi may serve only FRESH applicants on Mondays, only RENEWAL on Tuesdays). `is_open` is a status flag of the slot. No non-key attribute transitively determines another. **3NF.**

### 4.5 `applicant`
PK `applicant_id`. `nin_hash` and `email` are both UNIQUE — they are candidate keys in their own right, so any FD ending in them is fine (they are prime attributes). `first_name`, `last_name`, `phone`, `date_of_birth`, `gender` are facts about the applicant. **Crucially the NIN itself is never stored** — only its SHA-256 hash, so the plaintext NIN cannot be a transitive-dependency leak. **3NF.**

### 4.6 `appointment`
PK `appointment_id`. `slot_id` is UNIQUE — it is a candidate key, so the FD `slot_id → appointment_id` does not violate BCNF/3NF (slot_id is prime). `service_id` is a FK reference (the service requested), not a transitive dependency of `applicant_id` or `slot_id`. `status`, `reschedule_count`, `booked_at`, `updated_at` are all facts about the appointment. **3NF.**

### 4.7 `payment`
PK `payment_id`. `appointment_id` and `reference` are both UNIQUE candidate keys, hence prime. `amount_ngn` is the amount **actually paid** for this appointment — it is **not** copied verbatim from `service_type.base_fee_ngn`, because fees may change over time or be discounted, and the payment row must record what was charged on the day. `payment_status`, `paid_at`, `confirmed_at`, `channel` are all facts about one specific payment. No transitive dependency. **3NF.**

### 4.8 `application_status_history`
PK `history_id` (bigserial). Append-only audit trail. Every column depends only on the audit row, not on a transitive chain. `appointment_id` is a FK; the FD `appointment_id → current_status` lives in `appointment` (see §3), not here. **3NF.**

### 4.9 `collection`
PK `collection_id`. `appointment_id` is UNIQUE candidate key. `collected_by`, `collector_relation`, `collector_id_hash`, `collected_at` are facts about the collection event. `collector_id_hash` follows the same hashing rule as `applicant.nin_hash` (no plaintext national ID of the collector either). **3NF.**

---

## 5. Normalisation choices worth calling out

1. **The fee lives in `service_type`, not in `appointment`.** A denormalised design would copy the fee into the appointment for "fast reporting". We do not do this: `payment.amount_ngn` records the amount actually paid (which may differ from the current catalogue fee after a price change), and `service_type.base_fee_ngn` is the current catalogue price. Reporting joins `payment → appointment → service_type` to reconcile the two. This avoids the classic transitive dependency `appointment_id → service_id → base_fee_ngn`.

2. **The current status lives in `appointment`, the history lives in `application_status_history`.** This is a controlled, deliberate denormalisation for read performance — the dashboard reads "current status" 100× more often than it reads history. The history table is the source of truth for the audit trail; the trigger `trg_audit_status_change` keeps the two in sync. This is standard practice and does not violate 3NF (3NF governs each table independently; cross-table redundancy is a matter of physical design, not normal form).

3. **NIN is stored as a hash, not as the plaintext or as an encrypted value.** Hashing is one-way: even if the database leaks, the plaintext NIN cannot be recovered without brute-forcing 11-digit numbers (10¹¹ possibilities, which is feasible but slow, and mitigated by salting at the application layer in production). Encryption would require key management and would still leak the plaintext if the key leaked; hashing is the safer choice for an immutable identifier that is never needed in plaintext after onboarding.

4. **`slot.end_time` is stored, not computed on read.** This is a derived column (`end_time = start_time + 30 min`) and is enforced by the `slot_time_check` CHECK constraint. Storing it makes queries like "give me all slots that overlap 10:15" trivial (range predicate on `start_time` and `end_time`) and indexable. This is a denormalisation for performance, not a normalisation issue.

5. **`collection.collector_id_hash`** follows the same hashing rule as `applicant.nin_hash`. The person collecting the passport (sometimes a parent, spouse or agent) must also present an ID, and that ID is also hashed.

---

## 6. Summary

Every table in the PassPoint schema is in 3NF. The only controlled denormalisations are (a) storing `appointment.status` separately from the history table (read performance, kept in sync by a trigger) and (b) storing `slot.end_time` as a derived column (query convenience, enforced by a CHECK). No partial or transitive dependencies exist in any table. The schema therefore satisfies the normalisation expectation of MIT 8103 Portfolio 1.
