# CHANGES: AI-assisted debugging (Claude, November 2026)

Every script was run from scratch on PostgreSQL 16 and MongoDB 8, as a user who (like the `codespace` user) can only run `sudo` as root. These changes make everything run as described. The original design is kept.

## Setup
| # | File | Problem when run | Fix |
|---|---|---|---|
| 1 | `setup.sh` | `use passpoint;` inside `mongosh --eval` is not run as the shell helper, so the `documents` collection and its indexes were **never created**. | `mongosh --quiet passpoint --eval …` |
| 2 | `setup.sh` | If `pip3 install --user` is refused (Ubuntu's "externally managed" Python), the script stopped. | Added a `--break-system-packages` fallback. |

## Portfolio 1
| # | File | Problem when run | Fix |
|---|---|---|---|
| 3 | `seed.sql` | `date_of_birth` was given text, so **the seed stopped at the applicants**, and no slots or demo appointments were loaded. | `dob::date` |
| 4 | `seed.sql` | `generate_series(time, time, interval)` does not exist, so **no slots were created**. Every slot also got the same service. | Step through timestamps; rotate FRESH / RENEWAL / REPLACEMENT by hour. |
| 5 | `bulk_generator.py` | A random applicant could get a 2nd active appointment for the same service, so the partial UNIQUE index rejected it and **the bulk load crashed (0 appointments)**. | The generator re-draws the applicant if they already hold an active appointment for that service. **Result: 60,000 appointments, 60,000 payments, 239,821 status-history rows, 41,996 collections.** |
| 6 | `bulk_generator.py` | Data stopped at today, so there were no upcoming bookings, and the BOOKED/PENDING-based tests and P3 had nothing to work on. | It now generates 2 years of history **plus the next 14 days**. |
| 7 | `run_p1.sh` | No `set -e`: a failed step still printed "Portfolio 1 complete". | `set -euo pipefail` (the constraint tests still use `ON_ERROR_STOP=0`). |
| 8 | `demo_applicants.sql` (new) + `run_p1.sh` | The bulk generator empties `applicant`, which deleted the 4 named demo applicants P3 relies on. | They're re-added after the bulk load. |
| 9 | `constraint_tests.sql` | **Only 4 of the 10 tests failed for the right reason.** Tests 3–7 silently did nothing (they used the deleted demo rows or a missing future slot); Test 2 failed on a NULL date instead of the hours rule; Test 10 failed on the wrong constraint. | Each test now builds its own situation from the real data. **All 10 now fail with the intended constraint or trigger** (weekday, hours, one-per-slot, one-active-per-service, payment-before-confirm, max 2 reschedules, status order, plaintext NIN, reschedule CHECK, unique reference). |

## Portfolio 2
| # | File | Problem when run | Fix |
|---|---|---|---|
| 10 | `queries.sql` (Q4) | `round(interval, 2)` does not exist, so Q4's before/after plans **both errored**. | Average in days via `EXTRACT(EPOCH …)/86400`. |
| 11 | `queries.sql`, `indexes.sql` (Q4) | The index `(appointment_id, collected_at)` couldn't serve a filter on `collected_at`. | `(collected_at) INCLUDE (appointment_id)`: the plan now shows an **Index Only Scan**. |
| 12 | `README.md` | It promised every AFTER plan would show an index scan. In the real run, Q1 drops from 1.6 ms to 0.08 ms, but the reports (Q5–Q7) and the low-selectivity `status` indexes keep their Seq Scan. | The text now explains this. It's an honest finding and a good defence point. |

## Portfolio 3
| # | File | Problem when run | Fix |
|---|---|---|---|
| 13 | `book_slot.sql` | The demos used deleted demo applicants (fixed by #8) and booked the **oldest** open slot, from 2 years ago. | They now book an upcoming slot. **Tested: booking succeeds; a failed payment rolls back and the slot stays open.** |
| 14 | `race_condition_demo.md` | Parts 2 and 3 reused one slot without resetting, so Part 3 could only error. Users had to copy UUIDs by hand. The isolation and deadlock parts relied on `pg_sleep(2)` timing, which can't be hit by pasting by hand. | Rewritten as **6 step-by-step parts**, one statement per step, using psql `\gset` variables (no copying) and no sleeps: bug → UNIQUE → `FOR UPDATE` → **SERIALIZABLE (new)** → READ COMMITTED vs REPEATABLE READ → deadlock. **All 6 were verified with two real database sessions.** |
| 15 | `race_setup.sql` | The deadlock needs two rows. | Adds a second slot (10:30). |
| 16 | `run_p3.sh`, `isolation_levels.sql`, `deadlock_demo.sql`, `README.md` | They pointed to the sleep-based versions. | They now point to the tested guide (the old files are kept as reference notes). |

## Portfolio 4
| # | File | Problem when run | Fix |
|---|---|---|---|
| 17 | `run_p4.sh` | `"$jsonSchema"` in an `echo` with `set -u` crashed the script on line 9, so **nothing in P4 ran**. | Escaped the `$`. |
| 18 | all 3 `.js` files | `use passpoint;` is a syntax error inside a script file, so **all three scripts failed**. | `db = db.getSiblingDB("passpoint");` |
| 19 | `schema_validation.js` | MongoDB's `$jsonSchema` does not support `if/then`, so the collection was created **without any validator**. | The same rule rewritten with `oneOf`. **Tested: the validator is attached and an invalid document is rejected; 42,000 documents; COLLSCAN 19 ms (42,000 docs) → IXSCAN 2 ms (395 docs).** |

## Portfolio 5
| # | File | Problem when run | Fix |
|---|---|---|---|
| 20 | `run_p5.sh`, `partition.sql` | It ran in `passpoint_p5_primary`, which has no `appointment` table, so the copy failed. | It runs in `passpoint`. |
| 21 | `partition.sql` | A missing `service_id` in the test insert, and invalid PL/pgSQL (`(EXECUTE …)` inside an expression). Only 12 of the 24 months were copied, so half the partitions were empty. | Fixed. All appointments are copied, and next month's partition is added. **Tested: 25 monthly partitions of about 2,400–2,500 rows each; a one-month query shows "Subplans Removed: 25".** |
| 22 | `replication_setup.md` | `pg_ctl -D /etc/postgresql/…` is not a data directory (it fails); `pg_basebackup` would stop at a password prompt; the copied replica had **no `pg_hba.conf`** and its directory had the wrong permissions, so **the replica could not start**. | Removed the bad line; `PGPASSWORD`; copy hba/ident; `chmod 700`. **Tested: state = streaming.** |
| 23 | `replication_demo.sql` | Every replica step was commented out, it needed two terminals, and it copied UUIDs by hand. | Now **one script** (`psql -d passpoint -f replication_demo.sql`) that switches between 5432 and 55432 itself. **Tested: the replica rejects the INSERT; 60,002 → 60,003 rows on both; lag 0 bytes; streaming/async.** |

## Not changed (Moyinoluwa's own work)
His reflection, his AI-use declaration, the before/after results tables and all screenshots must come from **his own** Codespaces run. The real numbers above are from my test, for reference only.

**Design note for the defence:** the lifecycle triggers fire on **UPDATE** only, so a row inserted directly with status `COLLECTED` is not checked. The bulk generator relies on this to load history quickly. Be ready to explain it, or add an INSERT trigger that only allows `BOOKED`.
