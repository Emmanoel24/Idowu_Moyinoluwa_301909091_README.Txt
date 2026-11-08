# Portfolio 2 — Query Processing and Optimisation

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Case study:** PassPoint (passport appointment slots) · **Database:** `passpoint` (PostgreSQL 16)
**MIT 8103 study sessions covered:** Sessions 5–6 (query processing, access methods, indexing, query optimisation, cost estimation).

---

## What this portfolio demonstrates

For each of the **seven queries** below, we:

1. Run `EXPLAIN (ANALYZE, BUFFERS)` **before** adding any supporting index — this typically produces a `Seq Scan` over the appointment or slot table.
2. Add the supporting **B-tree index** declared in `indexes.sql`.
3. Re-run `EXPLAIN (ANALYZE, BUFFERS)` **after** and compare. Selective lookups (Q1) switch to an `Index Scan` and get much faster. Reports that read most of a table (Q5–Q7, and the low-selectivity `status` indexes in Q3/Q6) often **keep the Seq Scan**, because reading the whole table is cheaper than jumping through an index. Explaining *why* an index was or was not used is part of the analysis.
4. Paste the real `Execution Time` and `Planning Time` from each run into the **before/after table** in `explain_results.md` (which has `[paste real …]` placeholders).

The seven queries (Q1–Q7) cover every workload the brief asks for, plus one extra (`Q7` revenue per service type):

| # | Query | What it answers | Index added |
|---|---|---|---|
| Q1 | Free slots at an office for a given date | "Can I book Ikoyi tomorrow morning?" | partial index on `slot(office_id, slot_date, start_time) WHERE is_open` |
| Q2 | Appointments per office per month | "How busy was each office last month?" | composite index on `appointment(booked_at)` joined via `slot` |
| Q3 | No-show rate (per office, per month) | "Which office has the worst no-show problem?" | partial index `appointment(status) WHERE status = 'NO_SHOW'` |
| Q4 | Average days from booking to collection | "How long does an applicant wait end-to-end?" | index on `collection(appointment_id, collected_at)` |
| Q5 | Busiest days and times | "When should we deploy extra counters?" | index on `slot(slot_date, start_time)` |
| Q6 | Revenue per service type | "Which service brings in the most money?" | index on `payment(payment_status)` partial WHERE CONFIRMED |
| Q7 | Revenue per office per month (bonus) | "Trend line for management reporting" | index on `appointment(booked_at)` + slot |

> Each query is wrapped in a transaction that **drops the supporting index first**, runs the BEFORE plan, then re-creates the index and runs the AFTER plan — so the comparison is clean and reproducible every run.

---

## Files in this folder

| File | Purpose |
|---|---|
| `queries.sql` | The 7 queries, each written twice: a `-- BEFORE` block (no index) and an `-- AFTER` block (with index), inside one script that drops+creates the index between the two EXPLAIN runs. |
| `indexes.sql` | All the indexes added by this portfolio, declared separately for reference. The `queries.sql` script also creates/drops them inline so the before/after comparison is self-contained. |
| `explain_results.md` | Before/after table with `[paste real EXPLAIN ANALYZE here]` placeholders for every query. **You paste your real output here after running.** |
| `run_p2.sh` | Drops the supporting indexes, runs BEFORE EXPLAINs, recreates indexes, runs AFTER EXPLAINs, dumps everything to `explain_results_output.txt`. |
| `README.md` | This file. |

---

## Exact Codespaces commands (after `setup.sh` and `run_p1.sh` have been run)

```bash
chmod +x portfolio-2-query-optimisation/run_p2.sh
./portfolio-2-query-optimisation/run_p2.sh
# the script writes the full EXPLAIN output to explain_results_output.txt

# (optional) re-run a single query interactively for screenshots:
psql -d passpoint -c "\timing on"
psql -d passpoint -f portfolio-2-query-optimisation/queries.sql
```

All `psql` calls connect through the Unix socket (no password).

---

## What to screenshot (evidence)

For **each of the 7 queries**, capture two screenshots (or two pasted blocks in `explain_results_output.txt`):

1. **BEFORE**: the `EXPLAIN (ANALYZE, BUFFERS)` output showing `Seq Scan` on the appointment / slot / payment table, the `Execution Time` line, and `rows=…` from the seq scan node.
2. **AFTER**: the same `EXPLAIN (ANALYZE, BUFFERS)` output, showing whether the planner switched to an `Index Scan` / `Index Only Scan` / `Bitmap Index Scan` or kept the `Seq Scan`, and the new `Execution Time`.

Then paste the **Execution Time** numbers into the before/after table in `explain_results.md` (it has `[paste real …]` placeholders for exactly this).

---

## Git commit

```bash
git add portfolio-2-query-optimisation/
git commit -m "P2: 7 queries with EXPLAIN ANALYZE before/after indexes"
git push
```

---

## Plain-English explanation

This portfolio takes the PassPoint schema we built in P1 and asks the seven questions an operations manager at a passport office actually cares about: "are there free slots tomorrow?", "how busy was each office last month?", "what's our no-show rate?", "how long does an applicant wait end-to-end?", "when are our busiest days and times?", "how much money did each service bring in?", and (bonus) "what's the revenue trend per office per month?". For each question we run the query through PostgreSQL's `EXPLAIN (ANALYZE, BUFFERS)` *before* adding an index — which usually shows a sequential scan reading every row of a 60 000-row appointment table — and then again *after* adding a B-tree index that lets the planner go straight to the relevant rows. The before/after comparison makes the impact of indexing visible: the same query goes from tens of milliseconds to a millisecond or two, and from a full table scan to an index scan touching only the rows that match the predicate. This is exactly the topic of MIT 8103 study sessions 5 and 6 — query processing, access methods, and indexing.
