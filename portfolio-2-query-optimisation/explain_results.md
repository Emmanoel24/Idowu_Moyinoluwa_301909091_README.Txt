# EXPLAIN ANALYZE — Before / After Indexing Results

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Portfolio:** 2 — Query Processing and Optimisation
**Database:** `passpoint` (PostgreSQL 16)
**Date run:** `[paste the date you ran run_p2.sh]`

> **Honesty convention.** Every `[paste …]` placeholder below must be filled in with the real output from `explain_results_output.txt` (produced by `run_p2.sh`). No EXPLAIN plan, no row count, no execution time is invented or simulated. The "Scan type", "Rows touched" and "Execution time" columns are summaries of the real output — paste them as they appear in your terminal.

---

## How to read this table

For each query, the **BEFORE** row shows the EXPLAIN ANALYZE result *without* the supporting index (typically a `Seq Scan` on the largest table touched), and the **AFTER** row shows the same query *with* the index created (typically an `Index Scan`, `Index Only Scan`, or `Bitmap Heap Scan + Bitmap Index Scan`). The two numbers that matter for the comparison are:

- **Execution Time** (the millisecond figure on the `Execution Time:` line at the bottom of each EXPLAIN ANALYZE) — lower is better.
- **Rows touched by the scan node** (the `rows=` figure on the seq-scan / index-scan node) — lower means the index let PostgreSQL skip irrelevant rows.

---

## Q1 — Free slots at an office for a given date

| Stage | Scan type on `slot` | Rows touched by scan | Execution Time |
|---|---|---|---|
| BEFORE (no index) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |
| AFTER (with `slot_lookup_idx`) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |

**Full BEFORE EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Full AFTER EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Observation (write after running):** `[paste your observation here — e.g. "Seq Scan on slot read ~32 000 rows; after the partial index the planner switched to an Index Scan reading only the 16 slots for that office+date, cutting execution time from N ms to M ms."]`

---

## Q2 — Appointments per office per month

| Stage | Scan type on `appointment` | Rows touched by scan | Execution Time |
|---|---|---|---|
| BEFORE (no index) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |
| AFTER (with `appointment_booked_at_idx`) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |

**Full BEFORE EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Full AFTER EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Observation:** `[paste your observation here]`

---

## Q3 — No-show rate per office per month

| Stage | Scan type on `appointment` | Rows touched by scan | Execution Time |
|---|---|---|---|
| BEFORE (no index) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |
| AFTER (with `appointment_no_show_idx`) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |

**Full BEFORE EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Full AFTER EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Observation:** `[paste your observation here — note the partial index helps the FILTER (status = 'NO_SHOW') even though the GROUP BY still scans the year's appointments; comment on whether the planner used an Index Only Scan or a Bitmap Scan.]`

---

## Q4 — Average days from booking to collection

| Stage | Scan type on `collection` | Rows touched by scan | Execution Time |
|---|---|---|---|
| BEFORE (no index) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |
| AFTER (with `collection_appointment_idx`) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |

**Full BEFORE EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Full AFTER EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Observation:** `[paste your observation here]`

---

## Q5 — Busiest days and times

| Stage | Scan type on `slot` | Rows touched by scan | Execution Time |
|---|---|---|---|
| BEFORE (no index) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |
| AFTER (with `slot_date_time_idx`) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |

**Full BEFORE EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Full AFTER EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Observation:** `[paste your observation here]`

---

## Q6 — Revenue per service type

| Stage | Scan type on `payment` | Rows touched by scan | Execution Time |
|---|---|---|---|
| BEFORE (no index) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |
| AFTER (with `payment_confirmed_idx`) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |

**Full BEFORE EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Full AFTER EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Observation:** `[paste your observation here]`

---

## Q7 — Revenue per office per month (bonus trend line)

| Stage | Scan type on `payment` | Rows touched by scan | Execution Time |
|---|---|---|---|
| BEFORE (no index) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |
| AFTER (with `payment_amount_idx` + `payment_confirmed_idx`) | `[paste real result here]` | `[paste real result here]` | `[paste real result here]` |

**Full BEFORE EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Full AFTER EXPLAIN ANALYZE:**

```
[paste real EXPLAIN ANALYZE here]
```

**Observation:** `[paste your observation here]`

---

## Summary

| Query | Supporting index | Before exec time | After exec time | Speed-up |
|---|---|---|---|---|
| Q1 free slots | `slot_lookup_idx` (partial) | `[paste]` | `[paste]` | `[paste]` |
| Q2 appts/office/month | `appointment_booked_at_idx` | `[paste]` | `[paste]` | `[paste]` |
| Q3 no-show rate | `appointment_no_show_idx` (partial) | `[paste]` | `[paste]` | `[paste]` |
| Q4 days to collection | `collection_appointment_idx` | `[paste]` | `[paste]` | `[paste]` |
| Q5 busiest days/times | `slot_date_time_idx` | `[paste]` | `[paste]` | `[paste]` |
| Q6 revenue per service | `payment_confirmed_idx` (partial) | `[paste]` | `[paste]` | `[paste]` |
| Q7 revenue/office/month | `payment_amount_idx` | `[paste]` | `[paste]` | `[paste]` |

**Overall analysis (write after running):** `[paste your overall analysis here — e.g. "Partial indexes gave the biggest speed-ups on Q1, Q3 and Q6 because the predicate (is_open / NO_SHOW / CONFIRMED) is highly selective. The composite index on booked_at helped Q2 the most because the WHERE clause is a range scan on booked_at and the GROUP BY is on the same column. Q4 and Q5 were already fast because their tables are smaller; the index helped less in absolute terms but still changed a Seq Scan into an Index Scan."]`
