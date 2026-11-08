#!/usr/bin/env bash
# =====================================================================
# run_p1.sh — runs every artifact in Portfolio 1 in order
# Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
# =====================================================================
set -euo pipefail   # stop at the first real failure (constraint tests below use ON_ERROR_STOP=0)
cd "$(dirname "$0")"

echo "==> [1/5] Loading schema.sql (tables, CHECKs, UNIQUE, partial UNIQUE)"
psql -d passpoint -v ON_ERROR_STOP=1 -f schema.sql

echo "==> [2/5] Loading triggers.sql (4 PL/pgSQL integrity triggers + helpers)"
psql -d passpoint -v ON_ERROR_STOP=1 -f triggers.sql

echo "==> [3/5] Loading seed.sql (offices, counters, services, demo applicants)"
psql -d passpoint -v ON_ERROR_STOP=1 -f seed.sql

echo "==> [4/5] Running bulk_generator.py (>=50 000 appointments over 2 years)"
python3 bulk_generator.py --target 60000 --dsn "postgresql:///passpoint"
echo "==> [4b] Re-adding the 4 named demo applicants used by Portfolio 3"
psql -d passpoint -v ON_ERROR_STOP=1 -f demo_applicants.sql

echo "==> [5/5] Running constraint_tests.sql (every test MUST error out)"
psql -d passpoint -v ON_ERROR_STOP=0 -f constraint_tests.sql \
    2>&1 | tee constraint_tests_output.txt

echo
echo "==> Portfolio 1 complete."
echo "    Paste the contents of constraint_tests_output.txt into the"
echo "    [paste real output here] placeholders of the final PDF."
