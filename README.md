# MIT 8103 Advanced Database Systems — Portfolio

**Student:** Moyinoluwa Emmanuel Idowu
**Matric number:** 2026/A/MIT/0077
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems (2026/2027, First Semester — September 2026 cohort)
**GitHub repository:** [GitHub link]

## Case study — PassPoint (passport appointment slots)

PassPoint is a **simulated** appointment-booking platform used by passport offices in Lagos (Ikoyi, Alausa), Abuja and Port Harcourt. It is **not** a real government service and is not affiliated with the Nigeria Immigration Service or any government body. It exists purely as a realistic case study for this portfolio.

**What PassPoint does**

* Applicants choose an office, a service (fresh passport, renewal, replacement of a lost/damaged passport) and a 30-minute slot on a weekday between 08:00 and 16:00.
* They upload supporting documents (birth certificate, NIN slip, old passport data page, photo, and an affidavit for replacements).
* They pay the prescribed fee.
* They attend the office for biometric capture on the booked date.
* They track the application through a status lifecycle:
  `BOOKED → CONFIRMED → CAPTURED → PROCESSING → READY → COLLECTED`
  (or `CANCELLED` / `NO_SHOW` at any point).
* They collect the finished passport.

**Major data stored:** offices, counters, service types, slots, applicants (with hashed NIN — never plain text), appointments, payments, application status history, document uploads, and passport collection records.

**Key operations supported:** search free slots, book a slot, pay, confirm appointment, capture biometrics, advance status, list no-shows, compute revenue, list busiest days/times, partition historical appointments by month, replicate to a read replica, and store heterogeneous uploaded documents in MongoDB.

---

## Repository structure

```
advanced-database-portfolio/
├── docs/
│   └── 00_brief_summary.md              # CA summary + portfolio→session map
├── portfolio-1-database-design/         # ER diagram, 3NF schema, constraints, triggers, seed, 50k bulk generator
├── portfolio-2-query-optimisation/      # 6–8 queries + EXPLAIN ANALYZE before/after indexes
├── portfolio-3-transactions-concurrency/# book_slot() txn, two-terminal race demo, isolation, deadlock
├── portfolio-4-nosql/                   # MongoDB document model, schema validation, aggregations, 40k docs, index demo
├── portfolio-5-distributed-cloud/       # Monthly partitioning, primary+replica, NDPA-2023 cloud architecture
├── setup.sh                             # Codespaces bootstrap (PostgreSQL 16 + MongoDB 8)
└── README.md                            # This file
```

Each portfolio folder has its own `README.md` with the **exact Codespaces commands**, **what to screenshot**, the **git commit command**, and a **plain-English explanation** of what the portfolio demonstrates and which MIT 8103 study session it covers.

---

## One-time setup (Codespaces)

Run from the repository root inside a Codespace:

```bash
chmod +x setup.sh
./setup.sh
```

This installs and starts PostgreSQL 16 and MongoDB 8, creates the `passpoint` (and helper) databases, and prints the connection strings. All connections go through the **Unix socket** (`host=/var/run/postgresql`), so no password is required. See `setup.sh` for the Codespaces-specific conventions used (e.g. `sudo runuser -u postgres -- ...` instead of `sudo -u postgres`).

## Running each portfolio

Each portfolio folder contains a `run_pN.sh` script that runs every artifact in that portfolio in the right order. From the repository root:

```bash
./portfolio-1-database-design/run_p1.sh
./portfolio-2-query-optimisation/run_p2.sh
./portfolio-3-transactions-concurrency/run_p3.sh
./portfolio-4-nosql/run_p4.sh
./portfolio-5-distributed-cloud/run_p5.sh
```

> **Honesty convention.** Every place that requires real output from a live PostgreSQL / MongoDB run contains the literal placeholder `[paste real output here]` (or a labelled variant such as `[paste real EXPLAIN ANALYZE here]`). No EXPLAIN plans, timings, screenshots or row counts are invented anywhere. The 2–3 page documentation PDF is produced **after** you have run everything and pasted your own real results, and is named `Idowu_Moyinoluwa_2026-A-MIT-0077_Documentation.pdf`.

## Progressive git commits

Each portfolio `README.md` ends with the suggested commit command for that portfolio, so commits land progressively rather than all on the deadline. After running every portfolio, run:

```bash
git add .
git commit -m "MIT 8103 portfolio — P1..P5 complete with real outputs"
git push
```

## AI-use declaration (to be completed by the student)

This portfolio was developed with the assistance of AI tools used as learning aids: Z.ai (GLM) to draft the scripts and documentation, and Claude (Anthropic) to test and fix errors (every fix is listed in `CHANGES.md`), in line with section 11 of the CA brief. The student remains responsible for the accuracy, originality and understanding of all submitted work, and has reviewed, corrected, tested and verified every script in Codespaces before submission. The full AI-use declaration will appear in the final documentation PDF.
