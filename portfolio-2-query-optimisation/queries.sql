-- =====================================================================
-- queries.sql — 7 PassPoint queries with EXPLAIN ANALYZE before/after
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Each query is run twice:
--   (a) BEFORE: with the supporting index dropped  -> usually Seq Scan
--   (b) AFTER : with the supporting index created  -> Index Scan / Bitmap
--
-- The script is idempotent: it drops the index first (BEFORE), runs
-- EXPLAIN, recreates the index (AFTER), and runs EXPLAIN again.
-- Output is captured to explain_results_output.txt by run_p2.sh.
--
-- NOTE: every "real" output goes into [paste real output here] in
-- explain_results.md. Nothing here is invented.
-- =====================================================================

\set ON_ERROR_STOP 0
\pset pager off
\timing on

\echo '===================================================================='
\echo ' PassPoint query optimisation — BEFORE / AFTER EXPLAIN ANALYZE'
\echo '===================================================================='

-- =====================================================================
-- Q1. Free slots at an office for a given date
--     (uses the next weekday relative to today so the script never expires)
-- =====================================================================
\echo ''
\echo '##### Q1 — Free slots at LGW-IKO for the next weekday #####'

-- pick the next weekday dynamically
\set q1_date  '(SELECT min(d)::date FROM generate_series(date_trunc(''day'', now())::date, date_trunc(''day'', now())::date + interval ''7 days'', interval ''1 day'') t(d) WHERE EXTRACT(ISODOW FROM d::date) BETWEEN 1 AND 5)'

-- BEFORE
DROP INDEX IF EXISTS slot_lookup_idx;
\echo '--- Q1 BEFORE (no index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.slot_id, s.start_time, s.end_time, st.code AS service
FROM slot s
JOIN service_type st ON st.service_id = s.service_id
WHERE s.office_id = (SELECT office_id FROM office WHERE office_code='LGW-IKO')
  AND s.slot_date = :q1_date
  AND s.is_open = true
ORDER BY s.start_time;

-- AFTER
CREATE INDEX slot_lookup_idx ON slot (office_id, slot_date, start_time) WHERE is_open;
\echo '--- Q1 AFTER (with slot_lookup_idx) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.slot_id, s.start_time, s.end_time, st.code AS service
FROM slot s
JOIN service_type st ON st.service_id = s.service_id
WHERE s.office_id = (SELECT office_id FROM office WHERE office_code='LGW-IKO')
  AND s.slot_date = :q1_date
  AND s.is_open = true
ORDER BY s.start_time;

-- =====================================================================
-- Q2. Appointments per office per month
-- =====================================================================
\echo ''
\echo '##### Q2 — Appointments per office per month (last 12 months) #####'

DROP INDEX IF EXISTS appointment_booked_at_idx;
DROP INDEX IF EXISTS appointment_slot_idx;
\echo '--- Q2 BEFORE (no index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       to_char(date_trunc('month', a.booked_at), 'YYYY-MM') AS month,
       count(*) AS appointments
FROM appointment a
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE a.booked_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY o.office_code, month
ORDER BY o.office_code, month;

CREATE INDEX appointment_booked_at_idx ON appointment (booked_at);
CREATE INDEX appointment_slot_idx      ON appointment (slot_id);
\echo '--- Q2 AFTER (with appointment_booked_at_idx + appointment_slot_idx) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       to_char(date_trunc('month', a.booked_at), 'YYYY-MM') AS month,
       count(*) AS appointments
FROM appointment a
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE a.booked_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY o.office_code, month
ORDER BY o.office_code, month;

-- =====================================================================
-- Q3. No-show rate per office per month
-- =====================================================================
\echo ''
\echo '##### Q3 — No-show rate per office per month #####'

DROP INDEX IF EXISTS appointment_no_show_idx;
\echo '--- Q3 BEFORE (no index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       to_char(date_trunc('month', a.booked_at), 'YYYY-MM') AS month,
       count(*) FILTER (WHERE a.status = 'NO_SHOW')    AS no_shows,
       count(*)                                         AS total,
       round(100.0 * count(*) FILTER (WHERE a.status = 'NO_SHOW')
              / nullif(count(*),0), 2)                  AS no_show_pct
FROM appointment a
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE a.booked_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY o.office_code, month
ORDER BY no_show_pct DESC, o.office_code, month;

CREATE INDEX appointment_no_show_idx ON appointment (status) WHERE status = 'NO_SHOW';
\echo '--- Q3 AFTER (with appointment_no_show_idx) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       to_char(date_trunc('month', a.booked_at), 'YYYY-MM') AS month,
       count(*) FILTER (WHERE a.status = 'NO_SHOW')    AS no_shows,
       count(*)                                         AS total,
       round(100.0 * count(*) FILTER (WHERE a.status = 'NO_SHOW')
              / nullif(count(*),0), 2)                  AS no_show_pct
FROM appointment a
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE a.booked_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY o.office_code, month
ORDER BY no_show_pct DESC, o.office_code, month;

-- =====================================================================
-- Q4. Average days from booking to collection
-- =====================================================================
\echo ''
\echo '##### Q4 — Average days from booking to collection (last 12 months) #####'

DROP INDEX IF EXISTS collection_appointment_idx;
\echo '--- Q4 BEFORE (no index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       -- round() does not take an interval: convert to days first
       round((avg(EXTRACT(EPOCH FROM (c.collected_at - a.booked_at))) / 86400)::numeric, 2) AS avg_days_to_collection
FROM collection c
JOIN appointment a ON a.appointment_id = c.appointment_id
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE c.collected_at >= now() - interval '12 months'
GROUP BY o.office_code
ORDER BY avg_days_to_collection DESC;

-- collected_at is the filtered column, so it leads; appointment_id is carried
-- in the index so the join key is read without visiting the table
CREATE INDEX collection_appointment_idx ON collection (collected_at) INCLUDE (appointment_id);
\echo '--- Q4 AFTER (with collection_appointment_idx) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       -- round() does not take an interval: convert to days first
       round((avg(EXTRACT(EPOCH FROM (c.collected_at - a.booked_at))) / 86400)::numeric, 2) AS avg_days_to_collection
FROM collection c
JOIN appointment a ON a.appointment_id = c.appointment_id
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE c.collected_at >= now() - interval '12 months'
GROUP BY o.office_code
ORDER BY avg_days_to_collection DESC;

-- =====================================================================
-- Q5. Busiest days and times (top 10 slot windows across all offices)
-- =====================================================================
\echo ''
\echo '##### Q5 — Busiest days and times #####'

DROP INDEX IF EXISTS slot_date_time_idx;
\echo '--- Q5 BEFORE (no index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT to_char(s.slot_date, 'YYYY-MM-DD (Dy)') AS slot_day,
       to_char(s.start_time, 'HH24:MI')       AS slot_time,
       count(*)                                AS appointments
FROM appointment a
JOIN slot s ON s.slot_id = a.slot_id
GROUP BY s.slot_date, s.start_time
ORDER BY appointments DESC
LIMIT 10;

CREATE INDEX slot_date_time_idx ON slot (slot_date, start_time);
\echo '--- Q5 AFTER (with slot_date_time_idx) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT to_char(s.slot_date, 'YYYY-MM-DD (Dy)') AS slot_day,
       to_char(s.start_time, 'HH24:MI')       AS slot_time,
       count(*)                                AS appointments
FROM appointment a
JOIN slot s ON s.slot_id = a.slot_id
GROUP BY s.slot_date, s.start_time
ORDER BY appointments DESC
LIMIT 10;

-- =====================================================================
-- Q6. Revenue per service type
-- =====================================================================
\echo ''
\echo '##### Q6 — Revenue per service type (last 12 months) #####'

DROP INDEX IF EXISTS payment_confirmed_idx;
\echo '--- Q6 BEFORE (no index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT st.code AS service,
       count(*) AS paid_appointments,
       sum(p.amount_ngn) AS revenue_ngn
FROM payment p
JOIN appointment a ON a.appointment_id = p.appointment_id
JOIN service_type st ON st.service_id = a.service_id
WHERE p.payment_status = 'CONFIRMED'
  AND p.confirmed_at >= now() - interval '12 months'
GROUP BY st.code
ORDER BY revenue_ngn DESC;

CREATE INDEX payment_confirmed_idx ON payment (payment_status) WHERE payment_status = 'CONFIRMED';
\echo '--- Q6 AFTER (with payment_confirmed_idx) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT st.code AS service,
       count(*) AS paid_appointments,
       sum(p.amount_ngn) AS revenue_ngn
FROM payment p
JOIN appointment a ON a.appointment_id = p.appointment_id
JOIN service_type st ON st.service_id = a.service_id
WHERE p.payment_status = 'CONFIRMED'
  AND p.confirmed_at >= now() - interval '12 months'
GROUP BY st.code
ORDER BY revenue_ngn DESC;

-- =====================================================================
-- Q7. Revenue per office per month (bonus trend line)
-- =====================================================================
\echo ''
\echo '##### Q7 — Revenue per office per month (last 12 months) #####'

DROP INDEX IF EXISTS payment_amount_idx;
\echo '--- Q7 BEFORE (no index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       to_char(date_trunc('month', p.confirmed_at), 'YYYY-MM') AS month,
       sum(p.amount_ngn) AS revenue_ngn
FROM payment p
JOIN appointment a ON a.appointment_id = p.appointment_id
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE p.payment_status = 'CONFIRMED'
  AND p.confirmed_at >= now() - interval '12 months'
GROUP BY o.office_code, month
ORDER BY o.office_code, month;

CREATE INDEX payment_amount_idx ON payment (amount_ngn);
\echo '--- Q7 AFTER (with payment_amount_idx + payment_confirmed_idx) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.office_code,
       to_char(date_trunc('month', p.confirmed_at), 'YYYY-MM') AS month,
       sum(p.amount_ngn) AS revenue_ngn
FROM payment p
JOIN appointment a ON a.appointment_id = p.appointment_id
JOIN slot   s ON s.slot_id   = a.slot_id
JOIN office o ON o.office_id = s.office_id
WHERE p.payment_status = 'CONFIRMED'
  AND p.confirmed_at >= now() - interval '12 months'
GROUP BY o.office_code, month
ORDER BY o.office_code, month;

\echo ''
\echo '===================================================================='
\echo ' End of queries.sql. Paste every BEFORE / AFTER block into the'
\echo ' matching [paste real EXPLAIN ANALYZE here] placeholder in'
\echo ' explain_results.md.'
\echo '===================================================================='
