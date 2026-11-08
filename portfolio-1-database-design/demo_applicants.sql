-- =====================================================================
-- demo_applicants.sql: re-adds the 4 named demo applicants AFTER the bulk
-- generator (which empties the applicant table before rebuilding it).
-- Portfolio 3's book_slot demos book appointments for these applicants.
-- =====================================================================
INSERT INTO applicant (nin_hash, first_name, last_name, email, phone, date_of_birth, gender)
SELECT passpoint_hash_nin(nin), fn, ln, em, ph, dob::date, gd
FROM (VALUES
  ('20234567890','Adaeze','Okoro',     'adaeze.okoro@example.com',    '08030000001','1990-04-12','F'),
  ('20234567891','Babatunde','Okafor', 'babatunde.okafor@example.com','08030000002','1985-09-23','M'),
  ('20234567892','Chinwe','Eze',       'chinwe.eze@example.com',      '08030000003','1992-12-02','F'),
  ('20234567893','Danjuma','Bello',    'danjuma.bello@example.com',   '08030000004','1988-07-15','M')
) AS t(nin, fn, ln, em, ph, dob, gd)
ON CONFLICT (nin_hash) DO NOTHING;
