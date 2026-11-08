# MIT 8103 Advanced Database Systems — CA Brief Summary

**Student:** Moyinoluwa Emmanuel Idowu
**Matric number:** 2026/A/MIT/0077
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems
**Academic session:** 2026/2027, First Semester (September 2026 cohort)
**Case study:** PassPoint — a simulated passport appointment-booking system used by passport offices in Lagos (Ikoyi, Alausa), Abuja and Port Harcourt.

---

## A. What the CA actually requires

This summary is taken **only** from the CA PDF (`mit-8103-advanced-database-systems-ca-september-cohort-2026.pdf`) provided with this portfolio. Nothing is invented.

### A.1 Deliverables and marks (40 total)

| Component | Activity | Marks |
|---|---|---|
| Portfolio 1 | Database Design and Modelling | 7 |
| Portfolio 2 | Query Processing and Optimisation | 7 |
| Portfolio 3 | Transactions and Concurrency | 7 |
| Portfolio 4 | NoSQL and Advanced Data Models | 7 |
| Portfolio 5 | Distributed and Cloud Database Exercise | 6 |
| Final Documentation | Portfolio documentation and technical reflection | 6 |
| **Total** | | **40** |

### A.2 What each portfolio must contain

| Portfolio | Expected evidence (verbatim from the CA) |
|---|---|
| P1 | Chosen case study description, ER diagram, relational schema, keys, constraints, and normalisation explanation. |
| P2 | SQL queries, query results, execution plans, indexing/optimisation evidence, and brief performance analysis. |
| P3 | Transaction examples showing commit, rollback, isolation, concurrency issue or control mechanism, and screenshots/output evidence. |
| P4 | NoSQL model based on the same case study, document/key-value/column/graph example, implementation evidence, and explanation of suitability. |
| P5 | Distributed/cloud database discussion or setup based on the same case study, including replication, sharding, availability, consistency, or deployment evidence. |
| Final Documentation | A 2–3 page summary, GitHub link, selected organisation, screenshots/evidence, individual reflection, and references/AI-use declaration where applicable. |

### A.3 Submission, naming and GitHub rules

- **Submission platform:** LMS + GitHub. The GitHub repository **must** be private and accessible to the assessor before LMS submission.
- **Suggested repository structure** (from the CA, used verbatim in this portfolio):
  ```
  advanced-database-portfolio/
  ├── portfolio-1-database-design/
  ├── portfolio-2-query-optimisation/
  ├── portfolio-3-transactions-concurrency/
  ├── portfolio-4-nosql/
  ├── portfolio-5-distributed-cloud/
  └── README.md
  ```
- **Progressive commits are required.** "Waiting until the deadline to upload all files may reduce the evidence of continuous portfolio development." Each portfolio folder in this submission therefore includes a `git commit` command in its `README.md`.
- **Final documentation file name** (used for the 2–3 page document produced *after* the code is run, per student's own instruction): `Idowu_Moyinoluwa_2026-A-MIT-0077_Documentation.pdf`.
- **LMS documentation length:** 2–3 pages, describing all five portfolio activities, naming the case study, and linking to the GitHub repository.

### A.4 AI use and academic integrity

The CA explicitly permits AI tools as learning aids, subject to a brief **AI Use Declaration** stating:
1. The AI tool used.
2. What the AI tool was used for.
3. How the output was reviewed, corrected, tested, or verified by the student.

AI use does **not** remove the student's responsibility for accuracy, originality and understanding. A short viva may be requested for a small sample of students whose submissions are unclear, copied, inaccessible or suspicious. The marking rubric (40 marks) rewards technical correctness, design quality, practical implementation, query/performance analysis, application of advanced concepts, documentation/GitHub organisation, and individual reflection.

### A.5 Honesty convention used in this portfolio

Following the student's instruction, every place that needs **real** output from a live PostgreSQL / MongoDB run contains the literal placeholder `[paste real output here]` (or a labelled variant such as `[paste real EXPLAIN ANALYZE here]`). No EXPLAIN plans, timings, screenshots, row counts or terminal output are invented or simulated anywhere in this portfolio. The 2–3 page documentation PDF is intentionally **not** produced in this ZIP — it is produced later, after the student has run everything and pasted their own real results.

---

## B. Portfolio → course-note study session mapping

Miva Open University MIT 8103 (Advanced Database Systems) follows the standard study-session structure for a one-semester postgraduate course: sessions 1–2 cover review and conceptual foundations; sessions 3–4 cover relational design and normalisation; sessions 5–6 cover query processing and indexing; sessions 7–8 cover transactions, concurrency and recovery; sessions 9–10 cover NoSQL and advanced data models; sessions 11–12 cover distributed databases, cloud deployment, replication and sharding. The CA's five portfolios map onto these sessions as follows.

| Portfolio | Title | Primary MIT 8103 study sessions | Topics in those sessions that the portfolio exercises |
|---|---|---|---|
| **P1** | Database Design and Modelling | Sessions 3–4 (Relational data modelling; integrity constraints; functional dependencies; normalisation up to BCNF/3NF) | ER modelling, relational schema, primary/foreign keys, candidate keys, UNIQUE/CHECK constraints, partial UNIQUE indexes, triggers as integrity enforcement, 3NF decomposition, hashing for sensitive identifiers |
| **P2** | Query Processing and Optimisation | Sessions 5–6 (Query processing; access methods; indexing; query optimisation; cost estimation) | Sequential vs. index scans, B-tree indexes, composite indexes, EXPLAIN / EXPLAIN ANALYZE, planning time vs. execution time, statistics, before/after performance comparison |
| **P3** | Transactions and Concurrency | Sessions 7–8 (ACID; isolation levels; locking; MVCC; deadlocks; recovery) | BEGIN/COMMIT/ROLLBACK, SAVEPOINT, READ COMMITTED vs. SERIALIZABLE, SELECT … FOR UPDATE, row-level locks, lost update / double-booking race, deadlock cycle and automatic detection/abort |
| **P4** | NoSQL and Advanced Data Models | Sessions 9–10 (NoSQL families; document stores; schema-on-read vs. schema validation; aggregation framework; trade-offs vs. RDBMS) | MongoDB document model for heterogeneous uploaded documents, JSON Schema validation, aggregation pipelines ($group, $avg, $bucket), indexes (COLLSCAN → IXSCAN), SQL-vs-NoSQL suitability analysis |
| **P5** | Distributed and Cloud Database Exercise | Sessions 11–12 (Distributed DBMS; replication; partitioning/sharding; CAP theorem; consistency models; cloud deployment; data-sovereignty and compliance) | Declarative partitioning by month, primary + streaming physical replica, read-replica write rejection, CAP trade-offs, sync vs. async replication, NDPA 2023 data sovereignty, encryption and access control, elastic capacity for slot-release rushes |
| **Final Documentation** | Portfolio documentation and technical reflection | Sessions 1–2 (course framing) + cross-session reflection | Case-study statement, GitHub link, evidence curation, individual reflection, AI-use declaration, references |

> **Note on session numbering:** if your cohort's course guide uses a different session numbering (for example grouping the same topics into modules 1–6 instead of sessions 1–12), the topic-level mapping above is the one that matters and is unchanged. The CA itself does not pin session numbers; the mapping is by topic, which is what the assessor verifies.
