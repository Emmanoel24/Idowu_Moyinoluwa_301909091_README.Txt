-- =====================================================================
-- NOTE: the tested, step-by-step version of this demo (one statement per
-- step, no pg_sleep timing) is in race_condition_demo.md, Part 6.
-- Use that guide for the screenshots; this file is kept as a reference.
-- =====================================================================
-- =====================================================================
-- deadlock_demo.sql — two-session deadlock demo (Portfolio 3)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- This file is a reference script for the deadlock demo described in
-- Part 5 of race_condition_demo.md. Run it in TWO interactive psql
-- sessions side by side. The comments mirror the step-by-step guide.
--
-- Database: passpoint (real schema with bulk data loaded).
-- =====================================================================

\echo '===================================================================='
\echo ' Deadlock demo — two sessions take locks in opposite orders.'
\echo ' PostgreSQL detects the cycle after deadlock_timeout (default 1s)'
\echo ' and aborts one transaction. The other transaction commits.'
\echo ''
\echo ' Open TWO psql sessions to passpoint, then follow the steps below.'
\echo '===================================================================='

-- ---------------------------------------------------------------------
-- Step 1 — Terminal A: lock appointment row first
-- ---------------------------------------------------------------------
\echo ''
\echo '-- Step 1: Terminal A'
\echo 'BEGIN;'
\echo 'UPDATE appointment SET updated_at = now()'
\echo 'WHERE appointment_id = (SELECT appointment_id FROM appointment WHERE status=''BOOKED'' ORDER BY appointment_id LIMIT 1);'
\echo '-- LEAVE THIS TRANSACTION OPEN. Switch to Terminal B and run Step 2.'

-- ---------------------------------------------------------------------
-- Step 2 — Terminal B: lock payment row first, then try to lock appointment
-- ---------------------------------------------------------------------
\echo ''
\echo '-- Step 2: Terminal B'
\echo 'BEGIN;'
\echo 'UPDATE payment SET created_at = now()'
\echo 'WHERE payment_id = (SELECT payment_id FROM payment ORDER BY payment_id LIMIT 1);'
\echo '-- Now try to lock the SAME appointment row Terminal A is holding:'
\echo 'UPDATE appointment SET updated_at = now()'
\echo 'WHERE appointment_id = (SELECT appointment_id FROM appointment WHERE status=''BOOKED'' ORDER BY appointment_id LIMIT 1);'
\echo '-- Terminal B now BLOCKS waiting for Terminal A''s appointment-row lock.'

-- ---------------------------------------------------------------------
-- Step 3 — back to Terminal A: try to lock payment (completes the cycle)
-- ---------------------------------------------------------------------
\echo ''
\echo '-- Step 3: Terminal A (run within ~1 second of Step 2)'
\echo 'UPDATE payment SET created_at = now()'
\echo 'WHERE payment_id = (SELECT payment_id FROM payment ORDER BY payment_id LIMIT 1);'
\echo '-- Terminal A also blocks. PostgreSQL''s deadlock detector fires'
\echo '-- after deadlock_timeout (default 1s), picks one victim and aborts it.'
\echo 'COMMIT;   -- only one of the two terminals reaches this'

-- ---------------------------------------------------------------------
-- Expected output
-- ---------------------------------------------------------------------
\echo ''
\echo '-- Expected: one of the two terminals prints:'
\echo '   ERROR:  deadlock detected'
\echo '   DETAIL: Process N waits for ShareLock on transaction M blocked by process K.'
\echo '   HINT:   See server log for query details.'
\echo '   CONTEXT: while updating tuple (X,Y) in relation "appointment" (or "payment")'
\echo ''
\echo '-- Paste that real output into race_condition_demo.md Part 5.'
\echo ''
\echo '-- To watch deadlock_timeout in action, you can also peek at the server log:'
\echo '-- sudo runuser -u postgres -- tail -f /var/log/postgresql/postgresql-16-main.log'

-- ---------------------------------------------------------------------
-- (Optional) shrink deadlock_timeout for faster demos
-- ---------------------------------------------------------------------
\echo ''
\echo '-- Optional: shorten deadlock_timeout for snappier demos:'
\echo '   sudo runuser -u postgres -- psql -c "ALTER SYSTEM SET deadlock_timeout = ''200ms'';"'
\echo '   sudo runuser -u postgres -- psql -c "SELECT pg_reload_conf();"'
