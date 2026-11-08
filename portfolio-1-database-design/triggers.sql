-- =====================================================================
-- triggers.sql — PL/pgSQL integrity triggers for PassPoint (Portfolio 1)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Implements the four procedural rules from the brief:
--   T1  payment must be CONFIRMED before appointment.status can become CONFIRMED
--   T2  at most 2 reschedules per appointment (reschedule_count cap)
--   T3  status must follow the valid lifecycle order, or move to CANCELLED/NO_SHOW
--   T4  national ID numbers stored only as SHA-256 hashes (reject plaintext NIN)
--
-- Plus a small housekeeping trigger:
--   T5  bump appointment.updated_at on every UPDATE
--   T6  write a row into application_status_history whenever status changes
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- T1. Payment must be CONFIRMED before appointment can be CONFIRMED
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enforce_payment_before_confirm()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    p_status payment_status;
BEGIN
    IF NEW.status = 'CONFIRMED' AND
       (OLD IS NULL OR OLD.status <> 'CONFIRMED') THEN
        SELECT payment_status INTO p_status
        FROM payment
        WHERE appointment_id = NEW.appointment_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION
              'payment_before_confirm: appointment % has no payment row — cannot CONFIRM',
              NEW.appointment_id;
        END IF;

        IF p_status <> 'CONFIRMED' THEN
            RAISE EXCEPTION
              'payment_before_confirm: payment for appointment % is % — must be CONFIRMED before the appointment can be CONFIRMED',
              NEW.appointment_id, p_status;
        END IF;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_payment_before_confirm ON appointment;
CREATE TRIGGER trg_payment_before_confirm
BEFORE UPDATE OF status ON appointment
FOR EACH ROW
EXECUTE FUNCTION enforce_payment_before_confirm();

-- ---------------------------------------------------------------------
-- T2. At most 2 reschedules per appointment
-- ---------------------------------------------------------------------
-- A reschedule = the slot_id changes. We bump reschedule_count and refuse
-- if it would exceed 2.
CREATE OR REPLACE FUNCTION enforce_max_reschedules()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.slot_id IS DISTINCT FROM OLD.slot_id THEN
        IF OLD.reschedule_count >= 2 THEN
            RAISE EXCEPTION
              'max_reschedules: appointment % already rescheduled % times — limit is 2',
              NEW.appointment_id, OLD.reschedule_count;
        END IF;
        NEW.reschedule_count := OLD.reschedule_count + 1;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_max_reschedules ON appointment;
CREATE TRIGGER trg_max_reschedules
BEFORE UPDATE OF slot_id ON appointment
FOR EACH ROW
EXECUTE FUNCTION enforce_max_reschedules();

-- ---------------------------------------------------------------------
-- T3. Status must follow the valid lifecycle order
--     BOOKED -> CONFIRMED -> CAPTURED -> PROCESSING -> READY -> COLLECTED
--     or branch to CANCELLED / NO_SHOW (allowed from any non-terminal state)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enforce_status_order()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    allowed boolean;
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NEW;  -- no transition
    END IF;

    SELECT
      (OLD.status = 'BOOKED'      AND NEW.status IN ('CONFIRMED','CANCELLED','NO_SHOW')) OR
      (OLD.status = 'CONFIRMED'   AND NEW.status IN ('CAPTURED','CANCELLED','NO_SHOW')) OR
      (OLD.status = 'CAPTURED'    AND NEW.status IN ('PROCESSING','CANCELLED'))         OR
      (OLD.status = 'PROCESSING'  AND NEW.status IN ('READY','CANCELLED'))              OR
      (OLD.status = 'READY'       AND NEW.status IN ('COLLECTED','CANCELLED'))          OR
      (NEW.status = 'BOOKED' AND OLD IS NULL)   -- initial INSERT handled by trigger too
    INTO allowed;

    IF NOT allowed THEN
        RAISE EXCEPTION
          'valid_status_transition: appointment % cannot move from % to %',
          NEW.appointment_id, OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_status_order ON appointment;
CREATE TRIGGER trg_status_order
BEFORE UPDATE OF status ON appointment
FOR EACH ROW
WHEN (NEW.status IS DISTINCT FROM OLD.status)
EXECUTE FUNCTION enforce_status_order();

-- ---------------------------------------------------------------------
-- T4. NIN must be stored only as a SHA-256 hash, never plaintext.
--     Catches the case where someone tries to INSERT a raw 11-digit NIN
--     instead of its hash. The CHECK constraint on the column already
--     enforces the 64-hex-char shape; this trigger is the explicit
--     "no plaintext national ID" rule from the brief.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reject_plaintext_nin()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.nin_hash ~ '^[0-9]{11}$' THEN
        RAISE EXCEPTION
          'nin_plaintext_forbidden: national ID numbers must be stored only as SHA-256 hashes — got what looks like an 11-digit plaintext NIN';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_reject_plaintext_nin ON applicant;
CREATE TRIGGER trg_reject_plaintext_nin
BEFORE INSERT OR UPDATE OF nin_hash ON applicant
FOR EACH ROW
EXECUTE FUNCTION reject_plaintext_nin();

-- ---------------------------------------------------------------------
-- T5. Bump updated_at on every UPDATE of appointment
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bump_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_bump_updated_at ON appointment;
CREATE TRIGGER trg_bump_updated_at
BEFORE UPDATE ON appointment
FOR EACH ROW
EXECUTE FUNCTION bump_updated_at();

-- ---------------------------------------------------------------------
-- T6. Audit-trail: append to application_status_history on every status change
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO application_status_history
            (appointment_id, from_status, to_status, actor, note, changed_at)
        VALUES
            (NEW.appointment_id, OLD.status, NEW.status, 'SYSTEM',
             'status transition', now());
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_audit_status_change ON appointment;
CREATE TRIGGER trg_audit_status_change
AFTER UPDATE OF status ON appointment
FOR EACH ROW
WHEN (NEW.status IS DISTINCT FROM OLD.status)
EXECUTE FUNCTION audit_status_change();

-- ---------------------------------------------------------------------
-- Convenience helper: hash an NIN from SQL.
-- Usage: SELECT passpoint_hash_nin('12345678901');
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION passpoint_hash_nin(plaintext text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT encode(digest(plaintext, 'sha256'), 'hex')
$$;

-- =====================================================================
-- End of triggers.sql
-- =====================================================================
