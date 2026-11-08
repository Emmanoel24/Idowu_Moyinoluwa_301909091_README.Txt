-- =====================================================================
-- seed.sql — small seed dataset for PassPoint (Portfolio 1)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Seeds: 4 offices, 8 counters, 3 service types, a handful of applicants,
-- a handful of slots (computed relative to today so they never expire),
-- and a couple of appointments + payments to demonstrate the lifecycle.
--
-- All NINs are stored as SHA-256 hashes (via the passpoint_hash_nin()
-- helper installed by triggers.sql). Plaintext NINs never appear in
-- this file or anywhere else in the portfolio.
-- =====================================================================

\set ON_ERROR_STOP on

-- make sure triggers are installed before we insert, so the audit/status
-- triggers fire and the NIN-hash trigger validates everything.
\i triggers.sql

-- ---------------------------------------------------------------------
-- Offices (Lagos x2, Abuja x1, Port Harcourt x1)
-- ---------------------------------------------------------------------
INSERT INTO office (office_code, name, city, address) VALUES
 ('LGW-IKO', 'Ikoyi Passport Office',    'Lagos',          '5 Bamako Street, Ikoyi, Lagos'),
 ('LGW-ALA', 'Alausa Passport Office',   'Lagos',          'Secretariat Road, Alausa, Ikeja, Lagos'),
 ('ABJ-ABD', 'Abuja Passport Office',    'Abuja',          '4 Ibrahim Abacha Road, Garki, Abuja'),
 ('PHC-MRD', 'Port Harcourt Passport Office', 'Port Harcourt', '10 Aba Road, Port Harcourt');

-- ---------------------------------------------------------------------
-- Counters (2 per office => 8 total)
-- ---------------------------------------------------------------------
INSERT INTO counter (office_id, counter_no, label)
SELECT o.office_id, n.counter_no, 'Counter ' || n.counter_no::text
FROM office o
CROSS JOIN (VALUES (1),(2)) AS n(counter_no)
ORDER BY o.office_code, n.counter_no
ON CONFLICT (office_id, counter_no) DO NOTHING;

-- ---------------------------------------------------------------------
-- Service types (FRESH, RENEWAL, REPLACEMENT) with realistic ₦ fees
-- ---------------------------------------------------------------------
INSERT INTO service_type (code, name, base_fee_ngn, processing_days,
                          requires_old_passport, requires_affidavit) VALUES
 ('FRESH',      'Fresh passport application',      35000.00, 14, false, false),
 ('RENEWAL',    'Passport renewal',                25000.00,  7, true,  false),
 ('REPLACEMENT','Replacement of lost/damaged passport', 45000.00, 10, true, true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------
-- Applicants: 4 demo applicants. NIN is hashed via passpoint_hash_nin().
-- The plaintext NINs here are demo values; they are NEVER stored in the
-- table — only their SHA-256 hash is. Use exactly the function installed
-- by triggers.sql so the trigger is exercised.
-- ---------------------------------------------------------------------
INSERT INTO applicant (nin_hash, first_name, last_name, email, phone, date_of_birth, gender)
SELECT passpoint_hash_nin(nin), fn, ln, em, ph, dob::date, gd
FROM (VALUES
  ('20234567890','Adaeze','Okoro',     'adaeze.okoro@example.com',    '08030000001','1990-04-12','F'),
  ('20234567891','Babatunde','Okafor', 'babatunde.okafor@example.com','08030000002','1985-09-23','M'),
  ('20234567892','Chinwe','Eze',       'chinwe.eze@example.com',      '08030000003','1992-12-02','F'),
  ('20234567893','Danjuma','Bello',    'danjuma.bello@example.com',   '08030000004','1988-07-15','M')
) AS t(nin, fn, ln, em, ph, dob, gd)
ON CONFLICT (nin_hash) DO NOTHING;

-- ---------------------------------------------------------------------
-- Slots: generate the next 5 weekdays from today, 08:00..16:00, 30-min
-- intervals, two counters per office, all three service types per slot.
-- This is computed dynamically from CURRENT_DATE so the seed never
-- expires. (A larger bulk generator is provided separately in
-- bulk_generator.py for the 50k+ appointments requirement.)
-- ---------------------------------------------------------------------
WITH days AS (
  SELECT d::date AS slot_date
  FROM generate_series(
    (SELECT date_trunc('day', now())::date
       + CASE WHEN EXTRACT(ISODOW FROM now()) IN (6,7)
              THEN 1 ELSE 0 END),
    (SELECT date_trunc('day', now())::date + 7),
    interval '1 day'
  ) t(d)
  WHERE EXTRACT(ISODOW FROM d::date) BETWEEN 1 AND 5
  LIMIT 5
),
times AS (
  -- generate_series has no time-of-day version, so step through timestamps
  SELECT t::time AS start_time, (t + interval '30 minutes')::time AS end_time
  FROM generate_series(timestamp '2000-01-01 08:00', timestamp '2000-01-01 15:30', interval '30 minutes') t
)
INSERT INTO slot (office_id, counter_id, service_id, slot_date, start_time, end_time, is_open)
SELECT o.office_id, c.counter_id, s.service_id, d.slot_date, tm.start_time, tm.end_time, true
FROM office o
JOIN counter  c ON c.office_id = o.office_id
CROSS JOIN days d
CROSS JOIN times tm
-- one service per slot, rotating FRESH / RENEWAL / REPLACEMENT by hour
JOIN service_type s
  ON s.code::text = (ARRAY['FRESH','RENEWAL','REPLACEMENT'])[1 + (EXTRACT(HOUR FROM tm.start_time)::int % 3)]
ON CONFLICT (office_id, counter_id, slot_date, start_time) DO NOTHING;

-- ---------------------------------------------------------------------
-- Two demo appointments (with payment) to exercise the lifecycle triggers
-- ---------------------------------------------------------------------
-- Appointment 1: BOOKED -> CONFIRMED (with CONFIRMED payment)
INSERT INTO appointment (applicant_id, slot_id, service_id, status)
SELECT a.applicant_id, sl.slot_id, s.service_id, 'BOOKED'
FROM applicant a, slot sl, service_type s
WHERE a.email = 'adaeze.okoro@example.com'
  AND sl.slot_date = (SELECT min(slot_date) FROM slot)
  AND s.code = 'FRESH'
LIMIT 1;

INSERT INTO payment (appointment_id, amount_ngn, channel, reference, payment_status, paid_at, confirmed_at)
SELECT a.appointment_id, st.base_fee_ngn, 'CARD',
       'PSPT-' || a.appointment_id::text,
       'CONFIRMED', now(), now()
FROM appointment a
JOIN service_type st ON st.service_id = a.service_id
WHERE a.applicant_id = (SELECT applicant_id FROM applicant WHERE email='adaeze.okoro@example.com')
  AND a.status = 'BOOKED';

-- Now flip the appointment to CONFIRMED (the payment_before_confirm trigger
-- must allow this because the payment is CONFIRMED).
UPDATE appointment SET status = 'CONFIRMED'
WHERE applicant_id = (SELECT applicant_id FROM applicant WHERE email='adaeze.okoro@example.com')
  AND status = 'BOOKED';

-- Appointment 2: just BOOKED, payment still PENDING (so it cannot be CONFIRMED yet)
INSERT INTO appointment (applicant_id, slot_id, service_id, status)
SELECT a.applicant_id, sl.slot_id, s.service_id, 'BOOKED'
FROM applicant a, slot sl, service_type s
WHERE a.email = 'babatunde.okafor@example.com'
  AND sl.slot_date = (SELECT min(slot_date) + 1 FROM slot)
  AND s.code = 'RENEWAL'
LIMIT 1;

INSERT INTO payment (appointment_id, amount_ngn, channel, reference, payment_status)
SELECT a.appointment_id, st.base_fee_ngn, 'USSD',
       'PSPT-' || a.appointment_id::text,
       'PENDING'
FROM appointment a
JOIN service_type st ON st.service_id = a.service_id
WHERE a.applicant_id = (SELECT applicant_id FROM applicant WHERE email='babatunde.okafor@example.com');

-- ---------------------------------------------------------------------
-- Mark the demo slots as taken (UNIQUE constraint will stop a second
-- appointment from using them — see constraint_tests.sql, TEST 3).
-- ---------------------------------------------------------------------
UPDATE slot SET is_open = false
WHERE slot_id IN (SELECT slot_id FROM appointment);

-- =====================================================================
-- End of seed.sql
-- =====================================================================
