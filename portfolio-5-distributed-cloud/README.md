# Portfolio 5 — Distributed and Cloud Database Exercise

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Case study:** PassPoint (passport appointment slots) · **Databases:** `passpoint_p5_primary` (primary) + `passpoint_p5_replica` (streaming replica), PostgreSQL 16
**MIT 8103 study sessions covered:** Sessions 11–12 (distributed DBMS, replication, partitioning/sharding, CAP theorem, consistency models, cloud deployment, data-sovereignty and compliance).

---

## What this portfolio demonstrates

This portfolio covers four distributed/cloud topics on the PassPoint case study:

1. **Declarative partitioning of `appointment` by month.** With 60 000+ appointments over two years, the `appointment` table is large enough that a single table costs more in maintenance (VACUUM, index rebuilds) and in scanned rows for date-range queries than it earns in simplicity. `partition.sql` creates a partitioned `appointment` table by month and routes every INSERT to the right monthly partition automatically.

2. **Primary + streaming read replica.** A separate PostgreSQL cluster on the same Codespace acts as a **physical streaming replica** of the primary. The replica:
   - rejects all writes (`cannot execute INSERT in a read-only transaction`),
   - shows new rows from the primary within milliseconds (asynchronous streaming replication, the default and the right choice for a passport office where a few hundred milliseconds of replica lag is acceptable).

3. **Cloud architecture with data sovereignty under NDPA 2023.** `cloud_architecture.md` describes the production deployment: a primary in a Lagos region, a streaming replica in an Abuja region, encrypted at rest and in transit, access controlled by IAM roles, with personal data kept **inside Nigeria** as the NDPA 2023 (Nigeria Data Protection Act) requires. It also covers the **CAP theorem** trade-off, the **sync vs. async replication** trade-off, encryption and access control for personal data, and how to handle the rush when new slots open (elastic capacity, queue-based writes, partition pruning).

4. **A run script + step-by-step instructions** for the replication demo (the replica rejects a write; a new row from the primary arrives on the replica after replication catches up).

---

## Files in this folder

| File | Purpose |
|---|---|
| `partition.sql` | Creates a partitioned `appointment` table by month (RANGE on `booked_at`) and demonstrates partition pruning with `EXPLAIN`. |
| `replication_setup.md` | Step-by-step guide for creating a streaming physical replica with `pg_basebackup`, configuring `postgresql.conf` and `pg_hba.conf`, and starting the replica. Includes the Codespaces-specific rules (`sudo runuser -u postgres -- ...`, `/etc/postgresql/16/main/`, `pg_ctl` at `/usr/lib/postgresql/16/bin/pg_ctl`, `pg_hba.conf` trust lines at the top of the file, no `postgres_fdw`, Unix-socket login). |
| `replication_demo.sql` | One script (`psql -d passpoint -f replication_demo.sql`) that switches between primary and replica by itself: (a) a write on the replica is rejected; (b) a write on the primary succeeds; (c) the new row appears on the replica; (d) lag and `pg_stat_replication`. |
| `cloud_architecture.md` | The cloud architecture discussion: NDPA 2023 data sovereignty, CAP theorem, sync vs. async replication, encryption, access control, handling the rush when new slots open. |
| `run_p5.sh` | Loads `partition.sql` into `passpoint`, then prints the steps for building the replica (`replication_setup.md`). |
| `README.md` | This file. |

---

## Exact Codespaces commands (after `setup.sh`)

```bash
chmod +x portfolio-5-distributed-cloud/run_p5.sh
./portfolio-5-distributed-cloud/run_p5.sh

# Then follow replication_setup.md to create the streaming replica
# (it walks you through pg_basebackup + the right postgresql.conf + pg_hba.conf
#  changes, all using sudo runuser -u postgres -- ...).
```

After building the replica with `replication_setup.md`, run the demo in **one** terminal: `psql -d passpoint -f replication_demo.sql`. It connects to the primary (5432) and the replica (55432) itself.

---

## What to screenshot (evidence)

1. **Partition pruning** — the `EXPLAIN` output of a date-range SELECT on the partitioned `appointment` table, showing only the relevant monthly partitions scanned (e.g. `Append` with only one child `SeqScan on appointment_2025_09`).
2. **The `appointment` partition tree** — output of `SELECT * FROM pg_partition_tree('appointment');`.
3. **Replica rejects writes**: the `INSERT` on the replica errors with `ERROR: cannot execute INSERT in a read-only transaction`.
4. **New rows arrive on the replica**: the script inserts a row on the primary, waits 1 second, and finds the same `appointment_id` on the replica.
5. **Replication status** — `SELECT * FROM pg_stat_replication;` on the primary shows one row (the replica), and `SELECT now() - pg_last_xact_replay_timestamp();` on the replica shows the lag in seconds.

> Paste every real output into the matching `[paste real output here]` placeholder. Nothing here is invented.

---

## Git commit

```bash
git add portfolio-5-distributed-cloud/
git commit -m "P5: monthly partitioning + streaming replica (write-reject, lag), NDPA-2023 cloud architecture"
git push
```

---

## Plain-English explanation

PassPoint's `appointment` table grows fast — every working day at four offices adds roughly a thousand rows, so over a year the table reaches ~250 000 rows and over five years ~1.25 million. A single table at that size is still manageable, but every VACUUM, every index rebuild, every date-range query touches the whole table; partitioning by month makes each operation touch only the relevant month's data, and lets old partitions be archived or dropped wholesale. The first artifact in this portfolio (`partition.sql`) creates a partitioned `appointment` table by month and shows the planner pruning partitions for a one-month query. The second artifact is a **streaming physical replica**: a second PostgreSQL cluster on the same Codespace that consumes the primary's WAL stream and stays a few hundred milliseconds behind. The replica rejects all writes (`cannot execute INSERT in a read-only transaction`) — it exists for read-scaling and for disaster recovery, not for writes. The third artifact is the **cloud architecture** for a real production deployment: a primary in a Lagos AWS region, a streaming replica in an Abuja region, encrypted at rest with KMS-managed keys and in transit with TLS, access controlled by IAM roles, with **all personal data kept inside Nigeria** as the NDPA 2023 requires. The architecture document also covers the CAP trade-off (the system chooses AP — availability and partition tolerance over strong consistency, because the replica is allowed to lag a few hundred milliseconds), the sync vs. async replication trade-off (async is the right choice for a passport office because the cost of a synchronous write across regions is much higher than the cost of a 200-ms replica lag), and how to handle the rush when new slots open (elastic capacity, queue-based writes, partition pruning so the rush hits only the current month's partition).
