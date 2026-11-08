# Portfolio 3 — Transactions and Concurrency

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Case study:** PassPoint (passport appointment slots) · **Database:** `passpoint` (PostgreSQL 16)
**MIT 8103 study sessions covered:** Sessions 7–8 (ACID, isolation levels, locking, MVCC, deadlocks, recovery).

---

## What this portfolio demonstrates

This portfolio proves that the PassPoint booking flow is safe under concurrency. It contains:

1. **`book_slot()` — an atomic transaction** that:
   * checks the slot is free,
   * inserts the appointment,
   * creates the matching `payment` row,
   * and either **COMMITs** the lot or **ROLLBACKs** the lot.
2. **A failed-payment rollback demo** — if the payment step raises an exception, the appointment row is released (the slot stays free).
3. **A two-terminal "same slot given to two applicants" race condition**, written as a **step-by-step guide for two interactive `psql` sessions** running side by side. The guide walks through:
   - **The bug**: a check-then-insert on a table *without* a UNIQUE constraint on the slot gives a double booking.
   - **Fix 1**: the UNIQUE constraint on `appointment.slot_id` rejects the second insert with a clear `duplicate key value violates unique constraint "one_appointment_per_slot"` message.
   - **Fix 2**: `SELECT … FOR UPDATE` on the slot row makes the second transaction **wait** until the first releases the lock, then sees the slot as taken and returns a clean "slot already booked" message.
4. **Isolation levels** — a script that runs the same workload under `READ COMMITTED` and `SERIALIZABLE` and shows the difference (with `[paste real output here]` placeholders for the actual outputs).
5. **A deadlock demo** — two sessions that take locks in opposite orders and trigger PostgreSQL's automatic deadlock detection and abort.

---

## Files in this folder

| File | Purpose |
|---|---|
| `book_slot.sql` | The `book_slot(applicant_email, slot_id, channel)` PL/pgSQL function — an atomic INSERT appointment + INSERT payment transaction with COMMIT/ROLLBACK. Plus a `failed_payment` test that proves rollback releases the slot. |
| `race_condition_demo.md` | The full step-by-step guide for two interactive `psql` sessions, covering the bug, fix 1 (UNIQUE), fix 2 (`SELECT … FOR UPDATE`), fix 3 (SERIALIZABLE), isolation levels and a deadlock, all tested one statement per step. Includes a separate `passpoint_p3_race` database used for the "no constraint" bug demo so the real `passpoint` schema is not weakened. |
| `race_setup.sql` | Schema for the `passpoint_p3_race` database: a deliberately **constraint-less** `appointment_race` table to demonstrate the bug, plus a `appointment_race_uniq` table to demonstrate fix 1. |
| `isolation_levels.sql` | Reference notes on isolation levels (run Part 5 of `race_condition_demo.md` for the screenshots). |
| `deadlock_demo.sql` | Reference notes on deadlocks (run Part 6 of `race_condition_demo.md` for the screenshots). |
| `run_p3.sh` | Loads `book_slot.sql`, runs the failed-payment rollback test, then prints the instructions for the two-terminal race + isolation + deadlock demos (these need two terminals — the script explains exactly what to run in each). |
| `README.md` | This file. |

---

## Exact Codespaces commands (after `setup.sh` and `run_p1.sh`)

```bash
chmod +x portfolio-3-transactions-concurrency/run_p3.sh
./portfolio-3-transactions-concurrency/run_p3.sh

# Open TWO terminals for the race / isolation / deadlock demos:
# Codespaces -> "New Terminal" (or split the pane with Ctrl-Shift-5).
# In Terminal A:
psql -d passpoint_p3_race
# In Terminal B:
psql -d passpoint_p3_race
# Then follow race_condition_demo.md, Parts 1–6. Each step says exactly what to
# type in T1 and what in T2.
```

All `psql` calls connect through the Unix socket (no password). `setup.sh` already created the `passpoint_p3_race` database for you.

---

## What to screenshot (evidence)

1. **`book_slot()` success** — output of `SELECT book_slot('adaeze.okoro@example.com', <slot_id>, 'CARD');` showing the new appointment UUID and a `payment_status = PENDING` row.
2. **`book_slot()` rollback** — output of the failed-payment block: the function raises `payment_failed: releasing slot`, the appointment table shows the slot is still free, and the payment table has no row for that appointment.
3. **Race condition (the bug)** — Terminal A and Terminal B both showing `INSERT 0 1` after running the check-then-insert on the constraint-less `appointment_race` table. Both rows are now in the table with the same `slot_id`.
4. **Fix 1 (UNIQUE)** — Terminal A succeeds, Terminal B errors with `duplicate key value violates unique constraint "one_appointment_per_slot"`.
5. **Fix 2 (`SELECT … FOR UPDATE`)** — Terminal A holds the lock; Terminal B blocks; once Terminal A commits, Terminal B returns a clean "slot already booked" message instead of erroring.
6. **Isolation levels** — the same workload under READ COMMITTED and SERIALIZABLE, showing the difference (phantom reads / serialization failures).
7. **Deadlock** — Terminal A's `UPDATE` completes; Terminal B's `UPDATE` aborts with `ERROR: deadlock detected`. PostgreSQL's deadlock detector fires automatically.

> Where actual terminal output is needed in the final PDF, paste it into the `[paste real output here]` placeholders. Do not invent any output.

---

## Git commit

```bash
git add portfolio-3-transactions-concurrency/
git commit -m "P3: book_slot() txn with rollback, two-terminal race + UNIQUE/FOR UPDATE fixes, isolation, deadlock"
git push
```

---

## Plain-English explanation

The PassPoint booking flow is a classic "check-then-act" pattern: read whether the slot is free, then insert the appointment. If two applicants click the same slot at the same moment, the database has to refuse one of them — otherwise the passport office ends up with two people arriving for the same counter at the same time. This portfolio shows three things. First, `book_slot()` is an atomic transaction: it inserts the appointment *and* the matching payment row in one unit, so the database never contains an appointment without a payment (or vice versa) — and if the payment step fails, the appointment is rolled back and the slot is released. Second, on a table with no constraint, two terminals can both see the slot as free and both insert — that's the bug; we then fix it two ways: a UNIQUE constraint on `appointment.slot_id` (the database rejects the second insert outright) and `SELECT … FOR UPDATE` (the second transaction waits for the first to commit, then sees the slot as taken and returns a clean error). Third, we demonstrate PostgreSQL's isolation levels and its automatic deadlock detector, which kills one of two transactions that take locks in opposite orders. This is the topic of MIT 8103 study sessions 7 and 8 — ACID, isolation, locking, MVCC and deadlock handling.
