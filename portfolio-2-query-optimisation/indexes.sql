-- =====================================================================
-- indexes.sql — supporting indexes for Portfolio 2 queries
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- These are the indexes that the AFTER-stage of each EXPLAIN comparison
-- uses. They are also created/dropped inline by queries.sql so the
-- before/after comparison is self-contained; this file exists only as a
-- reference list and can be sourced after run_p1.sh has loaded data.
-- =====================================================================

\set ON_ERROR_STOP 0

-- Q1: free-slot lookup by office + date (already created in schema.sql;
-- re-declared here so the AFTER stage is reproducible even if the schema
-- was edited).
CREATE INDEX IF NOT EXISTS slot_lookup_idx
  ON slot (office_id, slot_date, start_time)
  WHERE is_open;

-- Q2: appointments per office per month — drive from booked_at
CREATE INDEX IF NOT EXISTS appointment_booked_at_idx
  ON appointment (booked_at);

CREATE INDEX IF NOT EXISTS appointment_slot_idx
  ON appointment (slot_id);

-- Q3: no-show rate — partial index on the NO_SHOW status
CREATE INDEX IF NOT EXISTS appointment_no_show_idx
  ON appointment (status)
  WHERE status = 'NO_SHOW';

-- Q4: collection lookup by appointment_id
CREATE INDEX IF NOT EXISTS collection_appointment_idx
  ON collection (appointment_id, collected_at);

-- Q5: busiest days and times — slot date + start_time
CREATE INDEX IF NOT EXISTS slot_date_time_idx
  ON slot (slot_date, start_time);

-- Q6: revenue per service type — partial index on confirmed payments
CREATE INDEX IF NOT EXISTS payment_confirmed_idx
  ON payment (payment_status)
  WHERE payment_status = 'CONFIRMED';

-- Q7: revenue per office per month — join payment -> appointment -> slot -> office
-- already covered by appointment_slot_idx and slot_lookup_idx; add a payment amount
-- index for sorted aggregation.
CREATE INDEX IF NOT EXISTS payment_amount_idx
  ON payment (amount_ngn);
