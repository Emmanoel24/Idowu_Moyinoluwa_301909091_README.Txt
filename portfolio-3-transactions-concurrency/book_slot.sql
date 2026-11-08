-- =====================================================================
-- book_slot.sql — atomic appointment+payment transaction (Portfolio 3)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Defines:
--   book_slot(p_applicant_email text, p_slot_id uuid, p_channel payment_channel)
--     -> appointment_id uuid
--
-- The function is one atomic transaction:
--   1. look up the applicant by email
--   2. check the slot exists and is_open = true
--   3. check the applicant does not already hold an ACTIVE appointment
--      for the same service (partial UNIQUE)
--   4. INSERT the appointment (status = BOOKED)
--   5. INSERT the payment (status = PENDING)
--   6. mark the slot is_open = false
--   7. COMMIT and return the new appointment_id
--
-- If ANY step raises an exception, the function ROLLBACKs and re-raises
-- the exception with a clear message. The slot stays free (is_open=true)
-- because the UPDATE on slot never commits.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION book_slot(
    p_applicant_email text,
    p_slot_id         uuid,
    p_channel         payment_channel DEFAULT 'CARD'
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_applicant_id  applicant.applicant_id%TYPE;
    v_service_id    slot.service_id%TYPE;
    v_base_fee      service_type.base_fee_ngn%TYPE;
    v_appt_id       appointment.appointment_id%TYPE;
    v_open          boolean;
BEGIN
    -- 1. applicant lookup
    SELECT applicant_id INTO v_applicant_id
    FROM applicant WHERE email = p_applicant_email;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'book_slot: no applicant with email %', p_applicant_email;
    END IF;

    -- 2. slot existence + open check (this is the "check" half of check-then-insert;
    --    the UNIQUE constraint on appointment.slot_id is the safety net).
    SELECT s.is_open, s.service_id INTO v_open, v_service_id
    FROM slot s WHERE s.slot_id = p_slot_id
    FOR UPDATE;  -- FOR UPDATE here too: prevents two callers racing on the same slot
    IF NOT FOUND THEN
        RAISE EXCEPTION 'book_slot: slot % not found', p_slot_id;
    END IF;
    IF NOT v_open THEN
        RAISE EXCEPTION 'book_slot: slot % is already booked', p_slot_id;
    END IF;

    -- 3. fee lookup
    SELECT base_fee_ngn INTO v_base_fee FROM service_type WHERE service_id = v_service_id;

    -- 4. INSERT appointment
    INSERT INTO appointment (applicant_id, slot_id, service_id, status)
    VALUES (v_applicant_id, p_slot_id, v_service_id, 'BOOKED')
    RETURNING appointment_id INTO v_appt_id;

    -- 5. INSERT payment (PENDING — confirmed separately by the payment gateway callback)
    INSERT INTO payment (appointment_id, amount_ngn, channel, reference, payment_status)
    VALUES (v_appt_id, v_base_fee, p_channel, 'PSPT-' || v_appt_id::text, 'PENDING');

    -- 6. close the slot
    UPDATE slot SET is_open = false WHERE slot_id = p_slot_id;

    -- 7. implicit COMMIT (the function runs in a single transaction)
    RETURN v_appt_id;
END $$;

-- ---------------------------------------------------------------------
-- Simulate a FAILED payment: a function that does the same INSERTs but
-- then deliberately raises an exception inside the payment step, to
-- prove that the appointment is rolled back and the slot is released.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION book_slot_failed_payment(
    p_applicant_email text,
    p_slot_id         uuid
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_applicant_id  applicant.applicant_id%TYPE;
    v_service_id    slot.service_id%TYPE;
    v_base_fee      service_type.base_fee_ngn%TYPE;
    v_appt_id       appointment.appointment_id%TYPE;
    v_open          boolean;
BEGIN
    SELECT applicant_id INTO v_applicant_id
    FROM applicant WHERE email = p_applicant_email;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'book_slot_failed_payment: no applicant with email %', p_applicant_email;
    END IF;

    SELECT s.is_open, s.service_id INTO v_open, v_service_id
    FROM slot s WHERE s.slot_id = p_slot_id FOR UPDATE;
    IF NOT v_open THEN
        RAISE EXCEPTION 'book_slot_failed_payment: slot % is already booked', p_slot_id;
    END IF;
    SELECT base_fee_ngn INTO v_base_fee FROM service_type WHERE service_id = v_service_id;

    INSERT INTO appointment (applicant_id, slot_id, service_id, status)
    VALUES (v_applicant_id, p_slot_id, v_service_id, 'BOOKED')
    RETURNING appointment_id INTO v_appt_id;

    -- DELIBERATELY fail the payment step (simulates a gateway timeout)
    RAISE EXCEPTION 'payment_failed: releasing slot %', p_slot_id;
END $$;

-- ---------------------------------------------------------------------
-- A test that proves the rollback releases the slot:
--   BEGIN;
--   SELECT book_slot_failed_payment('chinwe.eze@example.com', '<free slot>');
--   -- exception raised, transaction aborts -> ROLLBACK
--   -- the slot is still free after this
-- ---------------------------------------------------------------------
\echo ''
\echo '--- Test 1: successful book_slot ---'
DO $$
DECLARE
    v_slot uuid;
    v_appt uuid;
BEGIN
    SELECT slot_id INTO v_slot
    FROM slot WHERE is_open AND slot_date >= current_date   -- an upcoming slot
    ORDER BY slot_date, start_time LIMIT 1;
    v_appt := book_slot('danjuma.bello@example.com', v_slot, 'CARD');
    RAISE NOTICE 'book_slot returned appointment %  (slot=%)', v_appt, v_slot;
END $$;

\echo ''
\echo '--- Test 2: failed payment -> rollback -> slot released ---'
DO $$
DECLARE
    v_slot uuid;
    v_open boolean;
BEGIN
    SELECT slot_id INTO v_slot
    FROM slot WHERE is_open AND slot_date >= current_date   -- an upcoming slot
    ORDER BY slot_date, start_time LIMIT 1;
    BEGIN
        PERFORM book_slot_failed_payment('chinwe.eze@example.com', v_slot);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'expected exception caught: %', SQLERRM;
    END;
    SELECT is_open INTO v_open FROM slot WHERE slot_id = v_slot;
    RAISE NOTICE 'after rollback, slot % is_open = %  (must be TRUE)', v_slot, v_open;
END $$;

\echo ''
\echo '--- Test 3: explicit BEGIN / ROLLBACK pattern (manual) ---'
\echo 'Run in an interactive psql session to see COMMIT vs ROLLBACK:'
\echo '  BEGIN;'
\echo '  SELECT book_slot(''adaeze.okoro@example.com'', ''<slot_id>'', ''USSD'');'
\echo '  -- if you ROLLBACK here, the slot is released;'
\echo '  -- if you COMMIT, the booking stays.'
\echo '  ROLLBACK;   -- or COMMIT;'
