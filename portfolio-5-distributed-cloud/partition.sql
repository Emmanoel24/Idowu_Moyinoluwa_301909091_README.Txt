-- =====================================================================
-- partition.sql — monthly RANGE partitioning of appointment (Portfolio 5)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Demonstrates PostgreSQL 16 declarative partitioning by month, plus
-- partition pruning in EXPLAIN. Run against the passpoint
-- database, because it copies rows from passpoint.appointment.
--
--   psql -d passpoint -v ON_ERROR_STOP=1 -f partition.sql
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- 1. Drop and recreate a separate partitioned appointment table for P5
--    (we use a _p5 suffix so the real passpoint.appointment is untouched).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS appointment_p5 CASCADE;

CREATE TABLE appointment_p5 (
    appointment_id   uuid              NOT NULL DEFAULT gen_random_uuid(),
    applicant_id     uuid              NOT NULL,
    slot_id          uuid              NOT NULL,
    service_id       uuid              NOT NULL,
    status           text              NOT NULL DEFAULT 'BOOKED',
    reschedule_count smallint          NOT NULL DEFAULT 0,
    booked_at        timestamptz       NOT NULL DEFAULT now(),
    updated_at       timestamptz       NOT NULL DEFAULT now(),
    PRIMARY KEY (appointment_id, booked_at)   -- partition key must be in PK
) PARTITION BY RANGE (booked_at);

-- ---------------------------------------------------------------------
-- 2. Create monthly partitions for the last 24 months PLUS next month
--    (the data includes bookings for the coming two weeks), and a
--    default partition for anything outside the range.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    start_month date := date_trunc('month', now())::date - interval '23 months';
    d date;
    next_d date;
    label text;
BEGIN
    FOR i IN 0..24 LOOP
        d       := (start_month + (i || ' months')::interval)::date;
        next_d  := (start_month + ((i+1) || ' months')::interval)::date;
        label   := to_char(d, 'YYYY_MM');
        EXECUTE format(
          'CREATE TABLE appointment_p5_%s PARTITION OF appointment_p5
             FOR VALUES FROM (%L) TO (%L)', label, d, next_d);
    END LOOP;

    -- default partition for safety (catches anything outside the range)
    EXECUTE 'CREATE TABLE appointment_p5_default PARTITION OF appointment_p5 DEFAULT';
END $$;

-- ---------------------------------------------------------------------
-- 3. Copy ALL rows of the real passpoint.appointment table into the
--    partitioned table, so every monthly partition holds real volumes.
-- ---------------------------------------------------------------------
INSERT INTO appointment_p5 (appointment_id, applicant_id, slot_id, service_id,
                            status, reschedule_count, booked_at, updated_at)
SELECT appointment_id, applicant_id, slot_id, service_id,
       status::text, reschedule_count, booked_at, updated_at
FROM   appointment
ON CONFLICT DO NOTHING;
ANALYZE appointment_p5;

-- ---------------------------------------------------------------------
-- 4. Show the partition tree
-- ---------------------------------------------------------------------
\echo ''
\echo '----- partition tree of appointment_p5 -----'
SELECT relid::regclass AS table_name, parentrelid::regclass AS parent, isleaf, level
FROM pg_partition_tree('appointment_p5')
ORDER BY level, table_name;

-- [paste real output here]

-- ---------------------------------------------------------------------
-- 5. Show partition pruning: a one-month query scans only ONE partition
-- ---------------------------------------------------------------------
\echo ''
\echo '----- EXPLAIN: a one-month query (only one partition should be scanned) -----'

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM appointment_p5
WHERE booked_at >= date_trunc('month', now()) - interval '1 month'
  AND booked_at <  date_trunc('month', now());

-- [paste real EXPLAIN here]

-- ---------------------------------------------------------------------
-- 6. Compare with a query that touches the whole 2-year window
-- ---------------------------------------------------------------------
\echo ''
\echo '----- EXPLAIN: a 2-year query (all 24 partitions scanned) -----'

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM appointment_p5
WHERE booked_at >= date_trunc('month', now()) - interval '24 months';

-- [paste real EXPLAIN here]

-- ---------------------------------------------------------------------
-- 7. Insert a new row and verify it lands in the right monthly partition
-- ---------------------------------------------------------------------
\echo ''
\echo '----- INSERT a row dated today and see which partition it lands in -----'

INSERT INTO appointment_p5 (appointment_id, applicant_id, slot_id, service_id, status, booked_at)
SELECT gen_random_uuid(), a.applicant_id, s.slot_id, s.service_id, 'BOOKED', now()
FROM applicant a
CROSS JOIN LATERAL (
  SELECT slot_id, service_id FROM slot WHERE is_open LIMIT 1
) s
WHERE a.email='adaeze.okoro@example.com'
LIMIT 1;

\echo ''
\echo '----- which partition holds rows for the current month? -----'
DO $$
DECLARE
    cur_month text := to_char(date_trunc('month', now()), 'YYYY_MM');
    n bigint;
BEGIN
    EXECUTE format('SELECT count(*) FROM appointment_p5_%s', cur_month) INTO n;
    RAISE NOTICE 'current-month partition = appointment_p5_%  has % rows', cur_month, n;
END $$;

-- tableoid tells you which partition a row physically lives in
SELECT tableoid::regclass AS partition, count(*)
FROM   appointment_p5
GROUP BY tableoid
ORDER BY partition;

-- [paste real output here]
