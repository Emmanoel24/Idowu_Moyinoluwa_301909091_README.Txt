-- =====================================================================
-- NOTE: the tested, step-by-step version of this demo (one statement per
-- step, no pg_sleep timing) is in race_condition_demo.md, Part 5.
-- Use that guide for the screenshots; this file is kept as a reference.
-- =====================================================================
-- =====================================================================
-- isolation_levels.sql — READ COMMITTED / REPEATABLE READ / SERIALIZABLE
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- This file is a reference script for the isolation-level demos
-- described in Part 4 of race_condition_demo.md. It is meant to be
-- run in TWO interactive psql sessions side by side. The comments
-- below mirror the step-by-step guide in race_condition_demo.md.
--
-- Database: passpoint (the real schema with bulk data loaded).
-- =====================================================================

\echo '===================================================================='
\echo ' Isolation level demos — run in TWO terminals side by side.'
\echo ' See portfolio-3-transactions-concurrency/race_condition_demo.md'
\echo ' Part 4 for the step-by-step instructions.'
\echo '===================================================================='

-- ---------------------------------------------------------------------
-- READ COMMITTED (PostgreSQL default) — non-repeatable read DEMO
-- ---------------------------------------------------------------------
\echo ''
\echo '-- READ COMMITTED demo'
\echo '-- Terminal A:'
\echo '   SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED;'
\echo '   BEGIN;'
\echo '   SELECT count(*) FROM appointment WHERE status=''BOOKED'';   -- snapshot 1'
\echo '   -- switch to Terminal B and run its block'
\echo '   SELECT pg_sleep(2);'
\echo '   SELECT count(*) FROM appointment WHERE status=''BOOKED'';   -- snapshot 2 (sees B''s commit)'
\echo '   COMMIT;'
\echo '-- Terminal B:'
\echo '   BEGIN;'
\echo '   INSERT INTO appointment (applicant_id, slot_id, service_id, status)'
\echo '   SELECT a.applicant_id, sl.slot_id, sl.service_id, ''BOOKED'''
\echo '   FROM applicant a, slot sl WHERE a.email=''adaeze.okoro@example.com'' AND sl.is_open LIMIT 1;'
\echo '   COMMIT;'
\echo '-- Expected: Terminal A''s two counts differ by 1 (non-repeatable read).'

-- ---------------------------------------------------------------------
-- REPEATABLE READ — single snapshot for the whole txn
-- ---------------------------------------------------------------------
\echo ''
\echo '-- REPEATABLE READ demo'
\echo '-- Terminal A:'
\echo '   SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL REPEATABLE READ;'
\echo '   BEGIN;'
\echo '   SELECT count(*) FROM appointment WHERE status=''BOOKED'';'
\echo '   SELECT pg_sleep(2);'
\echo '   SELECT count(*) FROM appointment WHERE status=''BOOKED'';'
\echo '   COMMIT;'
\echo '-- Terminal B: same INSERT + COMMIT as above.'
\echo '-- Expected: Terminal A''s two counts are equal (single snapshot).'

-- ---------------------------------------------------------------------
-- SERIALIZABLE — SSI aborts one of two conflicting writes
-- ---------------------------------------------------------------------
\echo ''
\echo '-- SERIALIZABLE demo'
\echo '-- Terminal A:'
\echo '   SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;'
\echo '   BEGIN;'
\echo '   SELECT count(*) FROM appointment WHERE status=''BOOKED'';'
\echo '   SELECT pg_sleep(2);'
\echo '   INSERT INTO appointment (applicant_id, slot_id, service_id, status)'
\echo '   SELECT a.applicant_id, sl.slot_id, sl.service_id, ''BOOKED'''
\echo '   FROM applicant a, slot sl WHERE a.email=''danjuma.bello@example.com'' AND sl.is_open LIMIT 1;'
\echo '   COMMIT;'
\echo '-- Terminal B:'
\echo '   SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;'
\echo '   BEGIN;'
\echo '   SELECT count(*) FROM appointment WHERE status=''BOOKED'';'
\echo '   SELECT pg_sleep(2);'
\echo '   INSERT INTO appointment (applicant_id, slot_id, service_id, status)'
\echo '   SELECT a.applicant_id, sl.slot_id, sl.service_id, ''BOOKED'''
\echo '   FROM applicant a, slot sl WHERE a.email=''chinwe.eze@example.com'' AND sl.is_open LIMIT 1;'
\echo '   COMMIT;'
\echo '-- Expected: one of the two COMMITs aborts with'
\echo '   ERROR: could not serialize access due to read/write dependencies among transactions'
\echo '   (this is PostgreSQL''s SSI detector).'

-- ---------------------------------------------------------------------
-- Quick reference: which anomalies each level prevents
-- (from the PostgreSQL 16 manual)
-- ---------------------------------------------------------------------
\echo ''
\echo '-- Quick reference (PostgreSQL 16):'
\echo '--   READ UNCOMMITTED  -> treated as READ COMMITTED in PostgreSQL'
\echo '--   READ COMMITTED    -> prevents dirty reads; allows non-repeatable reads and phantoms'
\echo '--   REPEATABLE READ   -> prevents dirty + non-repeatable reads + phantoms (snapshot isolation)'
\echo '--   SERIALIZABLE      -> prevents all anomalies (SSI); may abort transactions that would conflict'
