#!/usr/bin/env bash
# =====================================================================
# run_p3.sh — runs the single-terminal parts of Portfolio 3
# Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
#
# NOTE: The race-condition, isolation and deadlock demos need TWO
# interactive psql sessions side by side — a script cannot run both
# sides of an interactive demo. This script therefore:
#   1. loads book_slot.sql + runs the failed-payment rollback test
#   2. sets up the passpoint_p3_race database for the two-terminal demos
#   3. prints the exact commands to run in Terminal A and Terminal B
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")"

echo "==> [1/3] Loading book_slot.sql + running the failed-payment rollback test"
psql -d passpoint -v ON_ERROR_STOP=1 -f book_slot.sql 2>&1 | tee book_slot_output.txt

echo
echo "==> [2/3] Setting up passpoint_p3_race database for the two-terminal demos"
psql -d passpoint_p3_race -v ON_ERROR_STOP=1 -f race_setup.sql 2>&1 | tee race_setup_output.txt

echo
echo "==> [3/3] Two-terminal demos — run these manually in TWO psql sessions"
echo
echo "   Open two terminals in Codespaces (or split the pane)."
echo "   In each terminal run:"
echo "       cd portfolio-3-transactions-concurrency && psql -d passpoint_p3_race"
echo
echo "   Then follow race_condition_demo.md step by step. It covers all six"
echo "   two-terminal demos: the race bug, 3 fixes, isolation levels, deadlock."
echo
echo "==> Portfolio 3 single-terminal parts complete."
echo "    Paste the contents of book_slot_output.txt and the two-terminal"
echo "    outputs into the [paste real output here] placeholders in"
echo "    race_condition_demo.md."
