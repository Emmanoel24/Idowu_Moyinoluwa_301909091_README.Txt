# SQL vs. NoSQL — comparison for the PassPoint case study

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Portfolio:** 4 — NoSQL and Advanced Data Models

This document compares the **relational (PostgreSQL)** model used in Portfolios 1–3 with the **document (MongoDB)** model used in Portfolio 4, in the context of the PassPoint passport appointment system. It is not a general-purpose "SQL vs. NoSQL" essay — every point below is grounded in a specific PassPoint workload.

---

## 1. The PassPoint workloads, side by side

| Workload | Best fit | Why |
|---|---|---|
| Offices, counters, service types, slots, applicants, appointments, payments, status history, collections. | **PostgreSQL (relational)** | Strong schema, ACID, foreign keys, UNIQUE / partial UNIQUE / CHECK constraints, triggers, complex joins, aggregations across millions of rows. The appointment-booking flow needs `UNIQUE (slot_id)` and a partial `UNIQUE (applicant_id, service_id) WHERE status NOT IN (terminal)` — these are *exactly* what a relational DB is built for. |
| Uploaded documents (birth certificate, NIN slip, old passport, photo, affidavit). | **MongoDB (document)** | Five different shapes in one collection. Each document type has its own required fields (a birth certificate has `registration_number`, an affidavit has `court_name`, etc.). Forcing all five shapes into one SQL table means either a wide table with mostly-NULL columns (poor normalisation, no useful index) or five separate tables joined at every read (five joins for every appointment). MongoDB lets each document be its own shape and still live in one collection, while the `$jsonSchema` validator enforces the per-type required fields. |
| Reporting: free slots, appointments per office per month, no-show rate, revenue per service type, busiest days and times. | **PostgreSQL** | These are heavy GROUP BY / window-function / range-scan workloads. PostgreSQL's planner, B-tree indexes and `EXPLAIN ANALYZE` give the kind of cost-based optimisation MongoDB's aggregation framework does not match for relational workloads. |
| Per-document verification audit trail (officer notes, reject reasons, verified_at timestamps). | **MongoDB** | The audit trail is naturally an array of small sub-documents attached to each uploaded document. Embedding it in the same MongoDB document means one read gets the document + its full audit trail, no join needed. |
| Status history of an appointment (BOOKED → CONFIRMED → … → COLLECTED). | **PostgreSQL** | The lifecycle is the *core* transactional state of the system. It needs a `CHECK` on the valid transitions, a partial UNIQUE on active (applicant, service), and a trigger to enforce payment-before-confirm. All of these are relational tools. |
| Ad-hoc exploration of why a particular document type is rejected more in one office than another. | **MongoDB** | The aggregation pipeline `$group` by `document_type` + `reject_reason` is one stage; the equivalent SQL needs a 5-table UNION to handle the per-type sub-document columns. |

**Conclusion:** PassPoint is a **polyglot-persistence** system. The **transactional core (slots, appointments, payments, status, collections)** lives in PostgreSQL because it needs ACID, strong constraints and complex joins. The **document store (uploaded documents + their verification audit trail)** lives in MongoDB because the documents have heterogeneous shapes that the document model handles natively. The two stores are joined by `appointment_id` (a UUID stored as text in MongoDB, matching `appointment.appointment_id` in PostgreSQL).

---

## 2. Concrete trade-offs observed in this portfolio

| Dimension | PostgreSQL (P1–P3) | MongoDB (P4) |
|---|---|---|
| Schema enforcement | DDL: `CHECK`, `UNIQUE`, partial `UNIQUE`, FK, triggers — all server-side, always enforced. | `$jsonSchema` validator with conditional `if/then` blocks for per-type required fields. Less expressive than SQL (no FK to another collection) but enough for shape validation. |
| Atomicity | Full ACID, multi-statement transactions, `BEGIN/COMMIT/ROLLBACK`, `SELECT … FOR UPDATE`. | Document-level atomicity (one document write is atomic). Multi-document transactions exist in MongoDB 4+ but are heavier; we do not need them for the upload workload. |
| Joins | Native, optimised by the planner, supported by B-tree indexes. | `$lookup` exists but is heavier than a SQL join and is best avoided. The PassPoint design avoids it by storing `office_code` redundantly on each document (denormalised for read performance). |
| Indexing | B-tree (default), partial indexes, expression indexes, GIN/GIST. We demonstrated before/after `EXPLAIN ANALYZE` in P2. | B-tree, compound indexes, partial indexes. We demonstrated COLLSCAN → IXSCAN in P4. The optimiser is simpler than PostgreSQL's — there is no cost-based choice between index scans and seq scans; MongoDB picks the index that matches the query shape. |
| Concurrency model | MVCC with snapshot isolation; serialisable via SSI; row-level locks with `FOR UPDATE`. We demonstrated race conditions + fixes in P3. | Document-level optimistic concurrency via `_id` + version field; pessimistic locks via `db.collection.findOneAndUpdate()` with `$inc` on a version field. Less granular than row-level SQL locks. |
| Schema evolution | `ALTER TABLE` requires a rewrite for some changes (e.g. changing a column type); backward-compatible adds are cheap. | Adding a new field is free (no migration); removing a field needs a multi-document update; changing a field's shape needs application-level handling of both shapes during the transition. |
| Reporting | SQL GROUP BY / window functions / CTEs / materialised views. P2 demonstrated 7 such queries. | Aggregation pipeline (`$match`, `$group`, `$bucket`, `$facet`, `$lookup`). Powerful but more verbose than SQL for relational reporting. |
| Suitability for PassPoint | Slots / appointments / payments / status / collections — **excellent**. | Uploaded documents + audit trail — **excellent**. |
| Suitability for the *other* workload | Reporting on uploaded documents needs 5-table UNIONs — **poor**. | Booking a slot transactionally needs application-level UNIQUE enforcement — **poor**. |

---

## 3. The data-joining problem

The two stores are joined by `appointment_id` (UUID stored as text in MongoDB). The system never does an *atomic* cross-store join — instead:

1. PostgreSQL is the source of truth for the appointment and its lifecycle.
2. When an applicant uploads a document, the API writes a MongoDB document with the `appointment_id` (already created in PostgreSQL by `book_slot()`).
3. The reporting layer (e.g. "show me all rejected documents for appointments in Lagos last month") does a two-step lookup: first PostgreSQL returns the appointment_ids, then MongoDB returns the documents for those appointment_ids. This is the standard polyglot pattern; it avoids distributed transactions, which are expensive and operationally fragile.

If strict cross-store consistency were required (e.g. "an appointment cannot be CONFIRMED until all its documents are APPROVED"), the rule would be enforced in the **application layer**, reading both stores in a critical section. PassPoint does not need this — the rule "documents must be APPROVED before biometric capture" is enforced at the *capture* step, not at the *booking* step, so the cross-store check happens once at capture time, not on every booking.

---

## 4. Summary

PassPoint uses PostgreSQL for the transactional core (slots, appointments, payments, status, collections) and MongoDB for the uploaded documents and their verification audit trail. Each store is used for what it does best: PostgreSQL for ACID transactions, strong constraints, joins and relational reporting; MongoDB for heterogeneous documents with per-type shapes. The two are joined by `appointment_id`. This is the standard polyglot-persistence pattern and is the right answer for this case study. Forcing the entire system into one store would mean either (a) five separate SQL tables for the document types and a five-way join on every read, or (b) trying to enforce `UNIQUE (slot_id)` and `payment_before_confirm` in MongoDB, which lacks partial UNIQUE indexes and triggers — both choices are worse than the polyglot one.
