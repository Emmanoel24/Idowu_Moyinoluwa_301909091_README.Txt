-- =====================================================================
-- race_setup.sql — schema for the P3 two-terminal race-condition demo
-- Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
--
-- Run against the `passpoint_p3_race` database (created by setup.sh).
-- This database is INTENTIONALLY separate from `passpoint` so the demo
-- can use a constraint-less table to show the bug, without weakening
-- the real production schema.
--
--   psql -d passpoint_p3_race -v ON_ERROR_STOP=1 -f race_setup.sql
-- =====================================================================

\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

CREATE TABLE applicant_race (
    applicant_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email          text NOT NULL,
    first_name     text NOT NULL,
    last_name      text NOT NULL
);

CREATE TABLE slot_race (
    slot_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    office_code  text NOT NULL,
    slot_date    date NOT NULL,
    start_time   time NOT NULL,
    is_open      boolean NOT NULL DEFAULT true
);

-- ---------------------------------------------------------------------
-- BUG version: NO UNIQUE constraint on slot_id. Two transactions can
-- both insert an appointment for the same slot -> double booking.
-- ---------------------------------------------------------------------
CREATE TABLE appointment_race (
    appointment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id   uuid NOT NULL,
    slot_id        uuid NOT NULL,        -- deliberately NOT UNIQUE (the bug)
    status         text NOT NULL DEFAULT 'BOOKED',
    booked_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- FIX 1 version: UNIQUE constraint on slot_id. The second INSERT is
-- rejected with "duplicate key value violates unique constraint".
-- ---------------------------------------------------------------------
CREATE TABLE appointment_race_uniq (
    appointment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id   uuid NOT NULL,
    slot_id        uuid NOT NULL,
    status         text NOT NULL DEFAULT 'BOOKED',
    booked_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT one_appointment_per_slot_race UNIQUE (slot_id)
);

-- ---------------------------------------------------------------------
-- Seed: 4 applicants + 1 demo slot
-- ---------------------------------------------------------------------
INSERT INTO applicant_race (email, first_name, last_name) VALUES
 ('alice@example.com','Aisha','Okafor'),
 ('bob@example.com',  'Bolaji','Eze'),
 ('chinwe@example.com','Chinwe','Adamu'),
 ('danjuma@example.com','Danjuma','Bello');

INSERT INTO slot_race (office_code, slot_date, start_time, is_open)
VALUES ('LGW-IKO',
        (SELECT min(d)::date FROM generate_series(
           date_trunc('day', now())::date,
           date_trunc('day', now())::date + interval '7 days',
           interval '1 day') t(d)
         WHERE EXTRACT(ISODOW FROM d::date) BETWEEN 1 AND 5),
        time '10:00',
        true);

-- a second slot (10:30 on the same day), used by the deadlock demo
INSERT INTO slot_race (office_code, slot_date, start_time, is_open)
SELECT office_code, slot_date, time '10:30', true FROM slot_race;

\echo 'Setup complete. Demo slot:'
SELECT slot_id, office_code, slot_date, start_time, is_open FROM slot_race;
