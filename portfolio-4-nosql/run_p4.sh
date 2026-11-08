#!/usr/bin/env bash
# =====================================================================
# run_p4.sh — runs every artifact in Portfolio 4 in order
# Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")"

echo "==> [1/4] Applying the \$jsonSchema validator + smoke test"
mongosh --quiet passpoint schema_validation.js 2>&1 | tee schema_validation_output.txt

echo "==> [2/4] Seeding 40 000+ documents via seed_docs.py"
python3 seed_docs.py --target 42000 --uri "mongodb://127.0.0.1:27017" \
    2>&1 | tee seed_docs_output.txt

echo "==> [3/4] Running aggregations.js + the COLLSCAN->IXSCAN demo"
mongosh --quiet passpoint aggregations.js 2>&1 | tee aggregations_output.txt

echo "==> [4/4] (optional) running the focused index_demo.js for cleaner screenshots"
mongosh --quiet passpoint index_demo.js 2>&1 | tee index_demo_output.txt

echo
echo "==> Portfolio 4 complete."
echo "    Paste the contents of:"
echo "      schema_validation_output.txt"
echo "      seed_docs_output.txt"
echo "      aggregations_output.txt"
echo "      index_demo_output.txt"
echo "    into the [paste real output here] placeholders in"
echo "    aggregations.js (and the final PDF)."
