-- =====================================================================
-- replication_demo.sql: primary write + replica write-reject + lag (P5)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Run ONCE, after the replica is streaming (replication_setup.md):
--   psql -d passpoint -f replication_demo.sql
--
-- The script switches between the PRIMARY (port 5432) and the REPLICA
-- (port 55432) itself with \connect, using the Unix socket so no
-- password is needed. Paste each block's output into the matching
-- [paste real output here] placeholder in the final PDF.
-- =====================================================================

\echo '----- BLOCK 0: who is who -----'
\connect -reuse-previous=off passpoint - /var/run/postgresql 5432
SELECT 'PRIMARY' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
SELECT count(*) AS primary_rows_before FROM appointment_p5;
\connect -reuse-previous=off passpoint - /var/run/postgresql 55432
SELECT 'REPLICA' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
SELECT count(*) AS replica_rows_before FROM appointment_p5;

\echo ''
\echo '----- BLOCK 1: try to WRITE on the REPLICA (must fail) -----'
\echo '      expected: ERROR: cannot execute INSERT in a read-only transaction'
INSERT INTO appointment_p5 (applicant_id, slot_id, service_id, status, booked_at)
SELECT applicant_id, slot_id, service_id, 'BOOKED', now() FROM appointment_p5 LIMIT 1;
-- [paste real output here]

\echo ''
\echo '----- BLOCK 2: WRITE on the PRIMARY -----'
\connect -reuse-previous=off passpoint - /var/run/postgresql 5432
INSERT INTO appointment_p5 (applicant_id, slot_id, service_id, status, booked_at)
SELECT applicant_id, slot_id, service_id, 'BOOKED', now() FROM appointment_p5 LIMIT 1
RETURNING appointment_id AS new_id, booked_at \gset
\echo 'new row written on the primary:' :new_id
SELECT count(*) AS primary_rows_after FROM appointment_p5;
-- [paste real output here]

\echo ''
\echo '----- BLOCK 3: the new row ARRIVES on the REPLICA -----'
SELECT pg_sleep(1);   -- give streaming replication a moment
\connect -reuse-previous=off passpoint - /var/run/postgresql 55432
SELECT appointment_id, status, booked_at FROM appointment_p5 WHERE appointment_id = :'new_id';
SELECT count(*) AS replica_rows_after FROM appointment_p5;
-- [paste real output here]

\echo ''
\echo '----- BLOCK 4: replica lag, seen from the REPLICA -----'
SELECT now() - pg_last_xact_replay_timestamp() AS time_since_last_replay,
       pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_backlog_bytes;
-- [paste real output here]

\echo ''
\echo '----- BLOCK 5: replication status, seen from the PRIMARY -----'
\connect -reuse-previous=off passpoint - /var/run/postgresql 5432
SELECT application_name, client_addr, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
-- [paste real output here]

\echo ''
\echo '===================================================================='
\echo ' End of replication demo. Paste every block above into the final PDF.'
\echo '===================================================================='
