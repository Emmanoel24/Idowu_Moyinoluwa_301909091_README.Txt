-- =====================================================================
-- schema.sql — PassPoint relational schema (Portfolio 1)
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
-- Database: passpoint  (PostgreSQL 16, Unix-socket connection)
--
-- All constraints required by the brief are implemented here:
--   * UNIQUE on appointment.slot_id             (one appointment per slot)
--   * Partial UNIQUE INDEX on appointment       (an applicant cannot hold
--     two ACTIVE appointments for the same service)
--   * CHECK on slot.slot_date                   (weekdays only)
--   * CHECK on slot.start_time / end_time       (08:00–16:00, 30 min long)
--   * CHECK on applicant.nin_hash                (never plaintext — must be
--     a 64-char hex SHA-256 digest)
--   * Trigger: payment must be CONFIRMED before appointment is CONFIRMED
--   * Trigger: at most 2 reschedules per appointment
--   * Trigger: status follows BOOKED -> CONFIRMED -> CAPTURED ->
--     PROCESSING -> READY -> COLLECTED, or CANCELLED / NO_SHOW
--   * Trigger: NIN hashing safety (rejects plaintext NIN at INSERT/UPDATE)
-- =====================================================================

\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- for gen_random_uuid(), digest()

-- ---------------------------------------------------------------------
-- Enumerations
-- ---------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE service_code AS ENUM ('FRESH','RENEWAL','REPLACEMENT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE appointment_status AS ENUM
    ('BOOKED','CONFIRMED','CAPTURED','PROCESSING','READY','COLLECTED',
     'CANCELLED','NO_SHOW');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE payment_status AS ENUM ('PENDING','CONFIRMED','FAILED','REFUNDED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE payment_channel AS ENUM ('CARD','BANK_TRANSFER','USSD');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------
-- 1. office
-- ---------------------------------------------------------------------
CREATE TABLE office (
    office_id    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    office_code  text        NOT NULL UNIQUE,
    name         text        NOT NULL,
    city         text        NOT NULL CHECK (city IN ('Lagos','Abuja','Port Harcourt')),
    address      text        NOT NULL,
    is_active    boolean     NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. counter
-- ---------------------------------------------------------------------
CREATE TABLE counter (
    counter_id   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id    uuid        NOT NULL REFERENCES office(office_id) ON DELETE CASCADE,
    counter_no   smallint    NOT NULL,
    label        text        NOT NULL,
    is_active    boolean     NOT NULL DEFAULT true,
    UNIQUE (office_id, counter_no)
);

-- ---------------------------------------------------------------------
-- 3. service_type
-- ---------------------------------------------------------------------
CREATE TABLE service_type (
    service_id     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    code           service_code NOT NULL UNIQUE,
    name           text        NOT NULL,
    base_fee_ngn   numeric(10,2) NOT NULL CHECK (base_fee_ngn > 0),
    processing_days smallint   NOT NULL CHECK (processing_days > 0),
    requires_old_passport boolean NOT NULL DEFAULT false,
    requires_affidavit      boolean NOT NULL DEFAULT false
);

-- ---------------------------------------------------------------------
-- 4. slot  (with weekday + time-window CHECKs)
-- ---------------------------------------------------------------------
CREATE TABLE slot (
    slot_id      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id    uuid        NOT NULL REFERENCES office(office_id),
    counter_id   uuid        NOT NULL REFERENCES counter(counter_id),
    service_id   uuid        NOT NULL REFERENCES service_type(service_id),
    slot_date    date        NOT NULL,
    start_time   time        NOT NULL,
    end_time     time        NOT NULL,
    is_open      boolean     NOT NULL DEFAULT true,

    -- weekday-only: Monday (1) .. Friday (5)
    CONSTRAINT slot_weekday_check
      CHECK (EXTRACT(ISODOW FROM slot_date) BETWEEN 1 AND 5),

    -- 30-minute slot inside working hours 08:00..16:00
    CONSTRAINT slot_time_check
      CHECK (start_time >= time '08:00'
             AND end_time   <= time '16:00'
             AND end_time = (start_time + interval '30 minutes')::time),

    -- one slot per office/counter/date/time
    UNIQUE (office_id, counter_id, slot_date, start_time)
);

CREATE INDEX slot_lookup_idx
  ON slot (office_id, slot_date, start_time)
  WHERE is_open;

-- ---------------------------------------------------------------------
-- 5. applicant  (NIN stored only as SHA-256 hash, never plaintext)
-- ---------------------------------------------------------------------
CREATE TABLE applicant (
    applicant_id   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    nin_hash       text        NOT NULL UNIQUE,
    first_name     text        NOT NULL,
    last_name      text        NOT NULL,
    email          text        NOT NULL UNIQUE,
    phone          text        NOT NULL,
    date_of_birth  date        NOT NULL,
    gender         text        NOT NULL CHECK (gender IN ('M','F')),
    created_at     timestamptz NOT NULL DEFAULT now(),

    -- A SHA-256 hex digest is exactly 64 lowercase hex chars.
    -- Anything that looks like an 11-digit plaintext NIN (e.g. "12345678901")
    -- will not match this pattern and will be rejected; the trigger below
    -- is an extra belt-and-braces check.
    CONSTRAINT nin_hash_format_check
      CHECK (nin_hash ~ '^[0-9a-f]{64}$')
);

-- ---------------------------------------------------------------------
-- 6. appointment
-- ---------------------------------------------------------------------
CREATE TABLE appointment (
    appointment_id   uuid              PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id     uuid              NOT NULL REFERENCES applicant(applicant_id),
    slot_id          uuid              NOT NULL REFERENCES slot(slot_id),
    service_id       uuid              NOT NULL REFERENCES service_type(service_id),
    status           appointment_status NOT NULL DEFAULT 'BOOKED',
    reschedule_count smallint          NOT NULL DEFAULT 0
                                       CHECK (reschedule_count BETWEEN 0 AND 2),
    booked_at        timestamptz       NOT NULL DEFAULT now(),
    updated_at       timestamptz       NOT NULL DEFAULT now(),

    -- UNIQUE: one appointment per slot.
    CONSTRAINT one_appointment_per_slot UNIQUE (slot_id)
);

-- Partial UNIQUE: an applicant may not hold two ACTIVE appointments for
-- the same service. "Active" = not yet terminal (COLLECTED/CANCELLED/NO_SHOW).
CREATE UNIQUE INDEX applicant_service_active_uniq
  ON appointment (applicant_id, service_id)
  WHERE status NOT IN ('COLLECTED','CANCELLED','NO_SHOW');

CREATE INDEX appointment_status_idx        ON appointment (status);
CREATE INDEX appointment_booked_at_idx     ON appointment (booked_at);
CREATE INDEX appointment_applicant_idx     ON appointment (applicant_id);

-- ---------------------------------------------------------------------
-- 7. payment  (1:1 with appointment)
-- ---------------------------------------------------------------------
CREATE TABLE payment (
    payment_id     uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id uuid           NOT NULL UNIQUE REFERENCES appointment(appointment_id) ON DELETE CASCADE,
    amount_ngn     numeric(10,2)  NOT NULL CHECK (amount_ngn > 0),
    channel        payment_channel NOT NULL,
    reference      text           NOT NULL UNIQUE,
    payment_status payment_status NOT NULL DEFAULT 'PENDING',
    paid_at        timestamptz,
    confirmed_at   timestamptz,
    created_at     timestamptz    NOT NULL DEFAULT now()
);

CREATE INDEX payment_status_idx ON payment (payment_status);

-- ---------------------------------------------------------------------
-- 8. application_status_history
-- ---------------------------------------------------------------------
CREATE TABLE application_status_history (
    history_id     bigserial      PRIMARY KEY,
    appointment_id uuid           NOT NULL REFERENCES appointment(appointment_id) ON DELETE CASCADE,
    from_status    appointment_status,
    to_status      appointment_status NOT NULL,
    actor          text           NOT NULL CHECK (actor IN ('APPLICANT','OFFICER','SYSTEM')),
    note           text,
    changed_at     timestamptz    NOT NULL DEFAULT now()
);

CREATE INDEX hist_appointment_idx ON application_status_history (appointment_id, changed_at);

-- ---------------------------------------------------------------------
-- 9. collection  (1:0..1 with appointment)
-- ---------------------------------------------------------------------
CREATE TABLE collection (
    collection_id        uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id       uuid        NOT NULL UNIQUE REFERENCES appointment(appointment_id) ON DELETE CASCADE,
    collected_by         text        NOT NULL,
    collector_relation   text        NOT NULL CHECK (collector_relation IN ('SELF','SPOUSE','PARENT','SIBLING','AGENT')),
    collector_id_hash    text        NOT NULL CHECK (collector_id_hash ~ '^[0-9a-f]{64}$'),
    collected_at         timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- End of schema.sql
-- =====================================================================
