#!/usr/bin/env bash
# =====================================================================
# run_p2.sh — runs every artifact in Portfolio 2 in order
# Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")"

if ! psql -d passpoint -tAc "SELECT 1 FROM appointment LIMIT 1" | grep -q 1; then
    echo "ERROR: passpoint.appointment is empty. Run run_p1.sh first."
    exit 1
fi

echo "==> [1/2] Running queries.sql (BEFORE/AFTER EXPLAIN ANALYZE for Q1..Q7)"
psql -d passpoint -v ON_ERROR_STOP=0 -f queries.sql 2>&1 | tee explain_results_output.txt

echo "==> [2/2] (reference) loading indexes.sql so the database keeps the indexes"
psql -d passpoint -v ON_ERROR_STOP=0 -f indexes.sql

echo
echo "==> Portfolio 2 complete."
echo "    Paste the BEFORE / AFTER blocks from explain_results_output.txt"
echo "    into the [paste real EXPLAIN ANALYZE here] placeholders in"
echo "    explain_results.md."
