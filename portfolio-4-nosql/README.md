# Portfolio 4 — NoSQL and Advanced Data Models

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Case study:** PassPoint (passport appointment slots) · **Database:** `passpoint.documents` (MongoDB 8)
**MIT 8103 study sessions covered:** Sessions 9–10 (NoSQL families, document stores, schema-on-read vs. schema validation, aggregation framework, trade-offs vs. RDBMS).

---

## What this portfolio demonstrates

When an applicant books a passport appointment, they upload **different documents depending on the service type**. A fresh-applicant uploads a **birth certificate**, an **NIN slip** and a **photo**; a renewal applicant uploads the **old passport data page**, an **NIN slip** and a **photo**; a replacement applicant adds an **affidavit** of loss on top of those. Each document type has different fields, different verification steps, and different officer notes. This is a textbook **heterogeneous-document** workload — exactly what MongoDB's document model is built for.

This portfolio contains:

1. **`schema_validation.js`** — a MongoDB JSON Schema (`$jsonSchema`) validator attached to the `passpoint.documents` collection. It enforces:
   - the common required fields (`appointment_id`, `office_code`, `document_type`, `uploaded_at`, `verification.status`, `officer_notes[]`),
   - the per-document-type **conditional fields** (e.g. `birth_certificate.registration_number` is required when `document_type = "birth_certificate"`; `old_passport.passport_number` is required when `document_type = "old_passport_data_page"`, etc.),
   - the verification status enum (`PENDING / APPROVED / REJECTED / NEEDS_RESUBMISSION`).
2. **`seed_docs.py`** — a bulk generator that produces **40 000+ documents** spread across the five document types, with realistic per-type fields, verification outcomes, officer notes, and timestamps relative to today.
3. **`aggregations.js`** — two aggregation pipelines the operations team actually needs:
   - **Rejection reasons per document type** — `$group` by `document_type` and `verification.reject_reason`, count, sort descending.
   - **Average verification time per office** — `$group` by `office_code`, average of `verification.verified_at - uploaded_at` in minutes.
4. **`index_demo.js`** — runs an aggregation both **before** and **after** creating an index on `{ office_code: 1, uploaded_at: -1 }`. The BEFORE plan shows a `COLLSCAN`; the AFTER plan shows an `IXSCAN`. The execution stats (`totalDocsExamined`, `executionTimeMillis`) are pasted into `[paste real output here]` placeholders.
5. **`sql_vs_nosql.md`** — a short comparison of when the SQL model from P1–P3 is the right tool, and when the MongoDB document model is, with a PassPoint-specific recommendation.

---

## Files in this folder

| File | Purpose |
|---|---|
| `schema_validation.js` | MongoDB JSON Schema validator with per-document-type conditional fields. |
| `seed_docs.py` | Bulk generator: 40 000+ documents across 5 document types. |
| `aggregations.js` | Two aggregation pipelines (rejection reasons, avg verification time) + before/after `explain()` for the index demo. |
| `index_demo.js` | The COLLSCAN → IXSCAN demo, isolated for clarity. |
| `sql_vs_nosql.md` | Short SQL vs. NoSQL comparison for the PassPoint case study. |
| `run_p4.sh` | Drops the collection, applies the validator, seeds the documents, runs the aggregations + the index demo. |
| `README.md` | This file. |

---

## Exact Codespaces commands (after `setup.sh`)

```bash
chmod +x portfolio-4-nosql/run_p4.sh
./portfolio-4-nosql/run_p4.sh

# (optional) inspect the schema validator and collection stats:
mongosh --quiet passpoint --eval 'db.documents.metadata()'
mongosh --quiet passpoint --eval 'db.documents.stats()'
mongosh --quiet passpoint --eval 'db.documents.countDocuments({})'
```

MongoDB is started by `setup.sh` on `127.0.0.1:27017` with no auth (Codespaces dev environment).

---

## What to screenshot (evidence)

1. **Schema validation in action** — the output of `mongosh --quiet passpoint --eval 'db.documents.metadata()'` showing the `$jsonSchema` validator.
2. **A rejected insert** — try inserting a document missing a required conditional field; MongoDB returns an error mentioning the schema. Paste this into `[paste real output here]`.
3. **Seed output** — the line `inserted N documents` where N ≥ 40 000.
4. **Aggregation 1 output** — the rejection-reasons-per-document-type result.
5. **Aggregation 2 output** — the avg-verification-time-per-office result.
6. **Index demo BEFORE** — the `explain()` output showing `stage: 'COLLSCAN'` and `totalDocsExamined: ~40000`.
7. **Index demo AFTER** — the `explain()` output showing `stage: 'IXSCAN'`, `totalDocsExamined: <small>`, and a lower `executionTimeMillis`.

> Paste every real output into the matching `[paste real output here]` placeholder in `aggregations.js` (or in the final PDF). Nothing here is invented.

---

## Git commit

```bash
git add portfolio-4-nosql/
git commit -m "P4: MongoDB document model with schema validation, 40k docs, aggregations, COLLSCAN->IXSCAN"
git push
```

---

## Plain-English explanation

The PassPoint upload step is the perfect NoSQL workload: there are five different document types, each with its own shape (a birth certificate has a `registration_number`, an old passport has a `passport_number` and `issue_date`, an affidavit has a `court_name` and ` affidavit_number`, a photo has a `pixel_width` and `pixel_height`, an NIN slip has a `nin_slip_id`). Trying to force all five shapes into one SQL table would mean either a wide table with mostly-NULL columns (poor normalisation, poor indexing) or five separate tables joined at read time (five joins for every applicant). MongoDB's document model lets each document be its own shape while still living in one collection, and the JSON Schema validator in `schema_validation.js` makes sure the per-type required fields are actually present — this is "schema-on-write with a flexible schema", which is the best of both worlds. The 40 000-document seed proves the model holds at scale; the two aggregations answer the operations team's real questions (which document types get rejected most, and which offices are slow to verify); and the index demo shows the difference between a COLLSCAN reading every document and an IXSCAN touching only the relevant ones. The SQL-vs-NoSQL comparison at the end explains where each model fits in PassPoint overall.
