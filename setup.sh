#!/usr/bin/env bash
# =====================================================================
# setup.sh — Codespaces bootstrap for MIT 8103 Advanced Database Systems
# Portfolio (PassPoint case study)
#
# Student : Moyinoluwa Emmanuel Idowu
# Matric  : 2026/A/MIT/0077
#
# Installs PostgreSQL 16 and MongoDB 8 inside a Codespaces Ubuntu
# container, creates the two databases used by the portfolio, and
# prints the connection strings.
#
# Codespaces-specific rules this script follows (from the brief):
#   * Codespaces lets the default user use sudo only as root, so we
#     ALWAYS call `sudo runuser -u postgres -- ...` (never `sudo -u postgres`).
#   * Ubuntu keeps PostgreSQL 16 config in /etc/postgresql/16/main/.
#   * pg_ctl lives at /usr/lib/postgresql/16/bin/pg_ctl.
#   * TCP logins need a password — we connect through the Unix socket
#     (host=/var/run/postgresql), so no password is required.
#   * /etc/apt/sources.list.d/yarn.list breaks apt-get update on some
#     Codespaces images, so we remove it first.
#   * postgres_fdw is NOT used anywhere in this portfolio.
# =====================================================================

set -euo pipefail

echo "==> [1/8] Removing problematic yarn.list (if present) and refreshing apt"
if [ -f /etc/apt/sources.list.d/yarn.list ]; then
  sudo rm -f /etc/apt/sources.list.d/yarn.list
fi
sudo apt-get update -y

echo "==> [2/8] Installing PostgreSQL 16 and MongoDB 8 packages"
sudo apt-get install -y curl gnupg ca-certificates lsb-release \
    postgresql-16 postgresql-client-16 postgresql-contrib-16 \
    python3 python3-pip libpq-dev

# --- MongoDB 8 (official repo) -------------------------------------
if ! command -v mongod >/dev/null 2>&1; then
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
    | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/8.0 multiverse" \
    | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y mongodb-org
fi

echo "==> [3/8] Starting PostgreSQL 16 cluster"
sudo pg_ctlcluster 16 main start || sudo pg_ctlcluster 16 main restart

echo "==> [4/8] Starting MongoDB 8 daemon"
sudo mkdir -p /data/db /var/log/mongodb
sudo chown -R mongodb:mongodb /data/db /var/log/mongodb
if ! pgrep -x mongod >/dev/null 2>&1; then
  sudo runuser -u mongodb -- /usr/bin/mongod \
    --dbpath /data/db \
    --logpath /var/log/mongodb/mongod.log \
    --fork \
    --bind_ip 127.0.0.1 \
    --port 27017
fi

echo "==> [5/8] Creating PostgreSQL role + databases for the portfolio"
# Codespaces default user is `codespace` (or whoever owns /home). We create
# a matching SQL role with CREATE DB privilege so each run_pN.sh can connect
# through the Unix socket without a password.
OS_USER="$(id -un)"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${OS_USER}') THEN
    CREATE ROLE "${OS_USER}" WITH LOGIN SUPERUSER CREATEDB;
  END IF;
END \$\$;
SQL

sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 \
  -c "CREATE DATABASE passpoint;" || true
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 \
  -c "CREATE DATABASE passpoint_p3_race;" || true
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 \
  -c "CREATE DATABASE passpoint_p5_primary;" || true

# Grant the OS-user database ownership (Codespaces: only root can sudo).
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 \
  -c "ALTER DATABASE passpoint OWNER TO ${OS_USER};" || true
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 \
  -c "ALTER DATABASE passpoint_p3_race OWNER TO ${OS_USER};" || true
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 \
  -c "ALTER DATABASE passpoint_p5_primary OWNER TO ${OS_USER};" || true

echo "==> [6/8] Creating MongoDB database + collection scaffolding"
# (connect straight to the passpoint database: a "use passpoint;" line inside
#  --eval is not run as the shell helper, so nothing below it ran)
mongosh --quiet passpoint --eval '
db.createCollection("documents");
db.documents.createIndex({ appointment_id: 1 });
db.documents.createIndex({ office_code: 1, uploaded_at: -1 });
print("MongoDB passpoint.documents ready");
'

echo "==> [7/8] Python deps for the bulk generators"
pip3 install --quiet --user psycopg2-binary pymongo faker || \
  pip3 install --quiet psycopg2-binary pymongo faker || \
  pip3 install --quiet --break-system-packages psycopg2-binary pymongo faker

echo "==> [8/8] Status check"
echo
echo "---- PostgreSQL ----"
sudo runuser -u postgres -- psql -c "SELECT version();"
psql -d passpoint -c "SELECT current_user, current_database();"
echo
echo "---- MongoDB --------"
mongosh --quiet --eval 'db.adminCommand({ ping: 1 })'
echo
echo "=============================================================="
echo " Setup complete. Databases ready:"
echo "   PostgreSQL : postgresql:///passpoint  (Unix socket, no pwd)"
echo "   MongoDB    : mongodb://127.0.0.1:27017/passpoint"
echo " Config dirs  : /etc/postgresql/16/main/ (postgresql.conf, pg_hba.conf)"
echo "=============================================================="
