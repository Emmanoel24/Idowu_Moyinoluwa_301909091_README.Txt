#!/usr/bin/env bash
# =====================================================================
# run_p5.sh — runs the single-terminal parts of Portfolio 5
# Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
#
# NOTE: The streaming-replica demo needs a second PostgreSQL cluster on
# port 55432. This script loads partition.sql on the primary and prints
# the exact commands to run for the replica (see replication_setup.md).
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")"

if ! psql -d passpoint -tAc "SELECT 1 FROM appointment LIMIT 1" | grep -q 1; then
    echo "ERROR: passpoint.appointment is empty. Run run_p1.sh first."
    exit 1
fi

echo "==> [1/2] Loading partition.sql on passpoint (copies appointments into appointment_p5)"
psql -d passpoint -v ON_ERROR_STOP=1 -f partition.sql \
    2>&1 | tee partition_output.txt

echo
echo "==> [2/2] The replication demo needs a second PostgreSQL cluster."
echo "    Follow the step-by-step guide in:"
echo "        portfolio-5-distributed-cloud/replication_setup.md"
echo
echo "    Quick summary of what you will do:"
echo "      1. CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '...';"
echo "      2. Append wal_level=replica / max_wal_senders=10 to the primary's"
echo "         /etc/postgresql/16/main/postgresql.conf  (use sudo runuser -u postgres -- ...)"
echo "      3. Prepend a host replication ... line to the TOP of pg_hba.conf"
echo "      4. pg_basebackup -h 127.0.0.1 -U replicator -D /var/lib/postgresql/16/replica -R"
echo "      5. Edit the replica's own postgresql.conf (port=55432, hot_standby=on)"
echo "      6. pg_ctl -D /var/lib/postgresql/16/replica start"
echo "      7. Open two psql sessions (primary on 5432, replica on 55432)"
echo "         and run the blocks in replication_demo.sql"
echo
echo "==> Portfolio 5 single-terminal parts complete."
echo "    Paste the contents of partition_output.txt and the two-terminal"
echo "    replication outputs into the [paste real output here] placeholders"
echo "    in partition.sql / replication_demo.sql / the final PDF."
