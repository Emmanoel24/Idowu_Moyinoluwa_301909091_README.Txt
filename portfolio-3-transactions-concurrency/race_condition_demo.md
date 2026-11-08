# Two-terminal concurrency demos (Portfolio 3)

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Database:** `passpoint_p3_race`. It is separate from the real `passpoint` schema, so the buggy version can be shown without weakening the real one.

## Before you start

1. Open **two terminals** in Codespaces: click **+** in the terminal panel, then the split icon, so you can see both side by side. Left = **T1**, right = **T2**.
2. In **both** terminals:
   ```bash
   cd portfolio-3-transactions-concurrency
   psql -d passpoint_p3_race
   ```
3. In **T1 only**, reset the demo tables:
   ```sql
   \i race_setup.sql
   ```
4. In **both** terminals, load the two slot ids and two applicant ids into psql variables. Every step below uses them, so there is nothing to copy and paste by hand:
   ```sql
   SELECT slot_id AS slot  FROM slot_race ORDER BY start_time LIMIT 1 \gset
   SELECT slot_id AS slot2 FROM slot_race ORDER BY start_time OFFSET 1 LIMIT 1 \gset
   SELECT applicant_id AS aisha  FROM applicant_race WHERE email = 'alice@example.com' \gset
   SELECT applicant_id AS bolaji FROM applicant_race WHERE email = 'bob@example.com' \gset
   ```

Type each step into the terminal named in the table, **one step at a time, in order**. Take a screenshot of **both** terminals at the end of every part.

---

## Part 1: THE BUG (check-then-insert, no constraint, no lock)

`appointment_race` deliberately has **no** UNIQUE constraint on `slot_id`, like an application that relies only on its own "is it free?" check.

| Step | Terminal | Type this | You should see |
|---|---|---|---|
| 1 | T1 | `BEGIN;`<br>`SELECT count(*) AS taken FROM appointment_race WHERE slot_id = :'slot';` | `0`: the slot looks free |
| 2 | T2 | `BEGIN;`<br>`SELECT count(*) AS taken FROM appointment_race WHERE slot_id = :'slot';` | `0`: also looks free |
| 3 | T1 | `INSERT INTO appointment_race (applicant_id, slot_id) VALUES (:'aisha', :'slot');`<br>`COMMIT;` | `INSERT 0 1`, `COMMIT` |
| 4 | T2 | `INSERT INTO appointment_race (applicant_id, slot_id) VALUES (:'bolaji', :'slot');`<br>`COMMIT;` | `INSERT 0 1`, `COMMIT` |
| 5 | either | `SELECT applicant_id, slot_id FROM appointment_race WHERE slot_id = :'slot';` | **2 rows: the same slot given to two applicants** ❌ |

**Why:** both transactions checked *before* either one inserted, so both saw "free". Under concurrency, a check in application code is not enough.

---

## Part 2: FIX 1, the UNIQUE constraint catches it

`appointment_race_uniq` has `CONSTRAINT one_appointment_per_slot_race UNIQUE (slot_id)`, the same rule as the real `appointment` table.

| Step | Terminal | Type this | You should see |
|---|---|---|---|
| 1 | T1 | `BEGIN;`<br>`INSERT INTO appointment_race_uniq (applicant_id, slot_id) VALUES (:'aisha', :'slot');` | `INSERT 0 1` (not committed yet) |
| 2 | T2 | `BEGIN;`<br>`INSERT INTO appointment_race_uniq (applicant_id, slot_id) VALUES (:'bolaji', :'slot');` | **T2 waits**: the unique index is checking T1's uncommitted row |
| 3 | T1 | `COMMIT;` | `COMMIT` |
| 4 | T2 | *(nothing to type, T2 wakes up by itself)* | **`ERROR: duplicate key value violates unique constraint "one_appointment_per_slot_race"`** ✅ |
| 5 | T2 | `ROLLBACK;` | `ROLLBACK` |

**Why:** the constraint is the last line of defence. There's no double booking, but the user gets a raw database error.

---

## Part 3: FIX 2, `SELECT … FOR UPDATE` queues the second request

First clear Part 2's booking. In **T1**: `DELETE FROM appointment_race_uniq;`

| Step | Terminal | Type this | You should see |
|---|---|---|---|
| 1 | T1 | `BEGIN;`<br>`SELECT is_open FROM slot_race WHERE slot_id = :'slot' FOR UPDATE;` | `t`, and **T1 now holds the lock on the slot row** |
| 2 | T2 | `BEGIN;`<br>`SELECT is_open FROM slot_race WHERE slot_id = :'slot' FOR UPDATE;` | **T2 waits** at the lock |
| 3 | T1 | `INSERT INTO appointment_race_uniq (applicant_id, slot_id) VALUES (:'aisha', :'slot');`<br>`UPDATE slot_race SET is_open = false WHERE slot_id = :'slot';`<br>`COMMIT;` | `INSERT 0 1`, `UPDATE 1`, `COMMIT` |
| 4 | T2 | *(T2 wakes up by itself)* | **`f`**: T2 re-reads the row **after** T1's commit and sees the slot is now closed ✅ |
| 5 | T2 | `ROLLBACK;` | the application shows a friendly "slot already booked" message (this is exactly what `book_slot()` does) |

**Why:** `FOR UPDATE` makes the second request queue behind the first, then re-read the latest data. The UNIQUE constraint stays as a safety net.

---

## Part 4: FIX 3, SERIALIZABLE isolation catches it with no constraint at all

Back on the **constraint-less** `appointment_race` table from Part 1, for the second slot.

| Step | Terminal | Type this | You should see |
|---|---|---|---|
| 1 | T1 | `BEGIN ISOLATION LEVEL SERIALIZABLE;`<br>`SELECT count(*) AS taken FROM appointment_race WHERE slot_id = :'slot2';` | `0` |
| 2 | T2 | `BEGIN ISOLATION LEVEL SERIALIZABLE;`<br>`SELECT count(*) AS taken FROM appointment_race WHERE slot_id = :'slot2';` | `0` |
| 3 | T1 | `INSERT INTO appointment_race (applicant_id, slot_id) VALUES (:'aisha', :'slot2');` | `INSERT 0 1` |
| 4 | T2 | `INSERT INTO appointment_race (applicant_id, slot_id) VALUES (:'bolaji', :'slot2');` | `INSERT 0 1` |
| 5 | T1 | `COMMIT;` | `COMMIT` |
| 6 | T2 | `COMMIT;` | **`ERROR: could not serialize access due to read/write dependencies among transactions`** ✅ The application retries, sees `taken = 1`, and refuses. |

**Why:** SERIALIZABLE notices that the two transactions could not have run one after the other with these results, so it aborts one of them.

---

## Part 5: Isolation levels, READ COMMITTED vs REPEATABLE READ

First reopen the first slot. In **T1**: `UPDATE slot_race SET is_open = true WHERE slot_id = :'slot';`

**READ COMMITTED** (PostgreSQL's default): each statement sees the latest committed data.

| Step | Terminal | Type this | You should see |
|---|---|---|---|
| 1 | T1 | `BEGIN ISOLATION LEVEL READ COMMITTED;`<br>`SELECT is_open FROM slot_race WHERE slot_id = :'slot';` | `t` |
| 2 | T2 | `UPDATE slot_race SET is_open = false WHERE slot_id = :'slot';` | `UPDATE 1` (auto-committed) |
| 3 | T1 | `SELECT is_open FROM slot_race WHERE slot_id = :'slot';`<br>`COMMIT;` | **`f`**: the value changed inside one transaction (a **non-repeatable read**) |

**REPEATABLE READ:** the whole transaction sees one snapshot.

| Step | Terminal | Type this | You should see |
|---|---|---|---|
| 1 | T1 | `BEGIN ISOLATION LEVEL REPEATABLE READ;`<br>`SELECT is_open FROM slot_race WHERE slot_id = :'slot';` | `f` |
| 2 | T2 | `UPDATE slot_race SET is_open = true WHERE slot_id = :'slot';` | `UPDATE 1` |
| 3 | T1 | `SELECT is_open FROM slot_race WHERE slot_id = :'slot';`<br>`COMMIT;` | **still `f`**: same snapshot, even though T2 committed a change |

---

## Part 6: Deadlock

| Step | Terminal | Type this | You should see |
|---|---|---|---|
| 1 | T1 | `BEGIN;`<br>`UPDATE slot_race SET is_open = true WHERE slot_id = :'slot';` | `UPDATE 1`, and T1 locks slot 1 |
| 2 | T2 | `BEGIN;`<br>`UPDATE slot_race SET is_open = true WHERE slot_id = :'slot2';` | `UPDATE 1`, and T2 locks slot 2 |
| 3 | T1 | `UPDATE slot_race SET is_open = false WHERE slot_id = :'slot2';` | **T1 waits** for T2 |
| 4 | T2 | `UPDATE slot_race SET is_open = false WHERE slot_id = :'slot';` | about 1 second later, one of them gets **`ERROR: deadlock detected`** ✅ (the other one continues) |
| 5 | both | `ROLLBACK;` | `ROLLBACK` |

**Why:** T1 waits for T2 and T2 waits for T1, a cycle. PostgreSQL's deadlock detector (after `deadlock_timeout`, 1 s by default) aborts one transaction so the other can finish. **Prevention:** always lock rows in the same order (e.g. by `slot_id`), which `book_slot()` does by locking the slot first.

---

## Summary table: fill in after running

| Demo | Behaviour | Real output |
|---|---|---|
| Part 1 Bug (no constraint) | double booking (two rows for one slot) | `[paste real output here]` |
| Part 2 Fix 1 (UNIQUE) | second INSERT errors with `duplicate key value` | `[paste real output here]` |
| Part 3 Fix 2 (`FOR UPDATE`) | second caller waits, then sees the slot closed | `[paste real output here]` |
| Part 4 Fix 3 (SERIALIZABLE) | second COMMIT fails with a serialization error | `[paste real output here]` |
| Part 5 READ COMMITTED | non-repeatable read observed | `[paste real output here]` |
| Part 5 REPEATABLE READ | same snapshot both times | `[paste real output here]` |
| Part 6 Deadlock | one transaction aborted with `deadlock detected` | `[paste real output here]` |
