-- =====================================================================
-- constraint_tests.sql — PassPoint constraint tests (Portfolio 1)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Every test below is designed to FAIL. Each one deliberately violates
-- one of the constraints required by the brief. When the test prints
-- "ERROR: ..." with the matching constraint name, the constraint is
-- proven to hold. If any test succeeds, the constraint is missing and
-- must be fixed before submission.
--
-- Run:
--     psql -d passpoint -v ON_ERROR_STOP=0 -f constraint_tests.sql \
--         2>&1 | tee constraint_tests_output.txt
--
-- (ON_ERROR_STOP=0 so psql keeps going after each expected error.)
-- =====================================================================

\set ON_ERROR_STOP 0
\pset pager off

\echo '===================================================================='
\echo ' PassPoint constraint tests — every block below MUST error out.'
\echo '===================================================================='

-- helper variables: pick two known applicants + a known office
\set applicant_a  '\'adaeze.okoro@example.com\''
\set applicant_b  '\'babatunde.okafor@example.com\''

-- ---------------------------------------------------------------------
-- TEST 1  —  slot_weekday_check : a Saturday slot must be rejected
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 1: slot on a Saturday (EXTRACT(ISODOW)=6) — must ERROR'
\echo '--         Expected: slot_weekday_check'

INSERT INTO slot (office_id, counter_id, service_id, slot_date, start_time, end_time, is_open)
SELECT o.office_id, c.counter_id, s.service_id,
       date_trunc('day', now())::date + (6 - EXTRACT(ISODOW FROM now())::int)::int,
       time '10:00', time '10:30', true
FROM office o, counter c, service_type s
WHERE o.office_code = 'LGW-IKO' LIMIT 1;

-- ---------------------------------------------------------------------
-- TEST 2  —  slot_time_check : a 17:00 slot (outside 08:00–16:00) must
--            be rejected
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 2: slot outside working hours (17:00–17:30) — must ERROR'
\echo '--         Expected: slot_time_check'

INSERT INTO slot (office_id, counter_id, service_id, slot_date, start_time, end_time, is_open)
SELECT o.office_id, c.counter_id, s.service_id,
       (date_trunc('week', now())::date + 7),   -- next Monday, a valid weekday
       time '17:00', time '17:30', true
FROM office o, counter c, service_type s
WHERE o.office_code = 'LGW-IKO' LIMIT 1;

-- ---------------------------------------------------------------------
-- TEST 3  —  one_appointment_per_slot (UNIQUE on appointment.slot_id)
--            a second appointment on an already-used slot must be rejected
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 3: second appointment on the same slot — must ERROR'
\echo '--         Expected: one_appointment_per_slot (UNIQUE violation)'

-- Take a slot that already has an appointment and try to give it to an
-- applicant who has no active appointment at all (so only the slot rule
-- can fail).
INSERT INTO appointment (applicant_id, slot_id, service_id, status)
SELECT (SELECT ap2.applicant_id FROM applicant ap2
         WHERE NOT EXISTS (SELECT 1 FROM appointment x
                           WHERE x.applicant_id = ap2.applicant_id
                             AND x.status NOT IN ('COLLECTED','CANCELLED','NO_SHOW'))
         LIMIT 1),
       ap.slot_id, ap.service_id, 'BOOKED'
FROM appointment ap
LIMIT 1;

-- ---------------------------------------------------------------------
-- TEST 4  —  applicant_service_active_uniq (partial UNIQUE)
--            the same applicant cannot hold two ACTIVE appointments for
--            the same service
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 4: same applicant holds two ACTIVE FRESH appointments — must ERROR'
\echo '--         Expected: applicant_service_active_uniq'

-- Take an applicant who already has an ACTIVE appointment for a service
-- and book them a second, free slot for the SAME service.
WITH holder AS (
  SELECT applicant_id, service_id
  FROM appointment
  WHERE status IN ('BOOKED','CONFIRMED','CAPTURED','PROCESSING','READY')
  LIMIT 1
)
INSERT INTO appointment (applicant_id, slot_id, service_id, status)
SELECT h.applicant_id,
       (SELECT sl.slot_id FROM slot sl
         WHERE sl.service_id = h.service_id
           AND NOT EXISTS (SELECT 1 FROM appointment x WHERE x.slot_id = sl.slot_id)
         LIMIT 1),
       h.service_id, 'BOOKED'
FROM holder h;

-- ---------------------------------------------------------------------
-- TEST 5  —  payment_before_confirm trigger
--            an appointment whose payment is still PENDING cannot be
--            moved to CONFIRMED
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 5: CONFIRM an appointment whose payment is PENDING — must ERROR'
\echo '--         Expected: payment_before_confirm'

UPDATE appointment SET status = 'CONFIRMED'
WHERE appointment_id = (
  SELECT a.appointment_id
  FROM appointment a
  JOIN payment p ON p.appointment_id = a.appointment_id
  WHERE p.payment_status = 'PENDING' AND a.status = 'BOOKED'
  LIMIT 1
);

-- ---------------------------------------------------------------------
-- TEST 6  —  max_reschedules trigger
--            an appointment cannot be rescheduled more than 2 times
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 6: third reschedule of an appointment — must ERROR'
\echo '--         Expected: max_reschedules'

-- First, find a BOOKED appointment that still has reschedule_count < 2
-- and force two reschedules, then try a third.
DO $$
DECLARE
    appt uuid;
    free_slot uuid;
    i int;
BEGIN
    SELECT a.appointment_id INTO appt
    FROM appointment a
    WHERE a.status = 'BOOKED' AND a.reschedule_count = 0
    LIMIT 1;

    IF appt IS NULL THEN
        RAISE NOTICE 'TEST 6 skipped: no BOOKED appointment with reschedule_count=0 found';
        RETURN;
    END IF;

    -- do two allowed reschedules
    FOR i IN 1..2 LOOP
        SELECT slot_id INTO free_slot
        FROM slot
        WHERE slot_id NOT IN (SELECT slot_id FROM appointment WHERE appointment_id <> appt)
        ORDER BY random() LIMIT 1;
        UPDATE appointment SET slot_id = free_slot WHERE appointment_id = appt;
    END LOOP;

    -- third reschedule — must raise max_reschedules
    SELECT slot_id INTO free_slot
    FROM slot
    WHERE slot_id NOT IN (SELECT slot_id FROM appointment WHERE appointment_id <> appt)
    ORDER BY random() LIMIT 1;
    UPDATE appointment SET slot_id = free_slot WHERE appointment_id = appt;
END $$;

-- ---------------------------------------------------------------------
-- TEST 7  —  valid_status_transition trigger
--            an appointment cannot jump from BOOKED straight to COLLECTED
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 7: jump BOOKED -> COLLECTED — must ERROR'
\echo '--         Expected: valid_status_transition'

UPDATE appointment SET status = 'COLLECTED'
WHERE appointment_id = (
  SELECT appointment_id FROM appointment
  WHERE status = 'BOOKED' LIMIT 1
);

-- ---------------------------------------------------------------------
-- TEST 8  —  nin_plaintext_forbidden trigger
--            inserting an applicant whose nin_hash looks like an
--            11-digit plaintext NIN must be rejected
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 8: store an 11-digit plaintext NIN as nin_hash — must ERROR'
\echo '--         Expected: nin_plaintext_forbidden (or nin_hash_format_check)'

INSERT INTO applicant (nin_hash, first_name, last_name, email, phone, date_of_birth, gender)
VALUES ('12345678901','Test','Plaintext','test.plaintext@example.com',
        '08031111111','1990-01-01','M');

-- ---------------------------------------------------------------------
-- TEST 9  —  reschedule_count CHECK (cannot be > 2 even via direct write)
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 9: set reschedule_count = 3 directly — must ERROR'
\echo '--         Expected: new constraint violation on reschedule_count'

UPDATE appointment SET reschedule_count = 3
WHERE appointment_id = (SELECT appointment_id FROM appointment LIMIT 1);

-- ---------------------------------------------------------------------
-- TEST 10 —  payment.reference UNIQUE
-- ---------------------------------------------------------------------
\echo ''
\echo '-- TEST 10: duplicate payment reference — must ERROR'
\echo '--          Expected: duplicate key value violates unique constraint'
-- A brand-new appointment (on a free slot, for an applicant with no active
-- appointment) gets a payment that REUSES an existing reference. The new
-- appointment has no payment yet, so only the reference rule can fail.
-- (Both inserts are one statement, so the failure rolls back both.)
WITH new_appt AS (
  INSERT INTO appointment (applicant_id, slot_id, service_id, status)
  SELECT (SELECT ap2.applicant_id FROM applicant ap2
           WHERE NOT EXISTS (SELECT 1 FROM appointment x
                             WHERE x.applicant_id = ap2.applicant_id
                               AND x.status NOT IN ('COLLECTED','CANCELLED','NO_SHOW'))
           LIMIT 1),
         sl.slot_id, sl.service_id, 'BOOKED'
  FROM slot sl
  WHERE NOT EXISTS (SELECT 1 FROM appointment x WHERE x.slot_id = sl.slot_id)
  LIMIT 1
  RETURNING appointment_id
)
INSERT INTO payment (appointment_id, amount_ngn, channel, reference, payment_status)
SELECT n.appointment_id, 100.00, 'CARD', (SELECT reference FROM payment LIMIT 1), 'PENDING'
FROM new_appt n;

\echo ''
\echo '===================================================================='
\echo ' End of constraint tests. Every block above must show an ERROR.'
\echo ' If any block shows INSERT/UPDATE 0 1 without an ERROR, the'
\echo ' corresponding constraint is missing — fix schema.sql/triggers.sql.'
\echo '===================================================================='
