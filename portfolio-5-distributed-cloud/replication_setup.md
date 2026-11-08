# Streaming physical replica — step-by-step setup (Portfolio 5)

**Student:** Moyinoluwa Emmanuel Idowu · **Matric:** 2026/A/MIT/0077
**Codespace rules followed** (from the brief):
- The codespace user can use `sudo` only as root, so we **always** call `sudo runuser -u postgres -- …` and **never** `sudo -u postgres`.
- Ubuntu keeps PostgreSQL 16 config in `/etc/postgresql/16/main/`.
- `pg_ctl` lives at `/usr/lib/postgresql/16/bin/pg_ctl`.
- A replica made with `pg_basebackup` needs its **own** `postgresql.conf` (it must not share the primary's).
- `pg_hba.conf` trust lines must go at the **top** of the file (PostgreSQL reads `pg_hba.conf` top-down and stops at the first match).
- TCP logins need a password — connect through the **Unix socket** (`host=/var/run/postgresql`).
- Do **not** use `postgres_fdw` (the brief forbids it; we use streaming replication, which is the right tool anyway).

This guide creates a streaming physical replica of the whole PostgreSQL cluster (including the `passpoint` database) on the same Codespace, on a non-default port (55432) so it does not clash with the primary on 5432.

---

## Step 0 — make sure the primary exists and has data

After `run_p5.sh` has run `partition.sql`, the `passpoint` database has the partitioned `appointment_p5` table with data. Confirm:

```bash
psql -d passpoint -c "SELECT count(*) FROM appointment_p5;"
```

---

## Step 1 — create a replication role on the primary

```bash
sudo runuser -u postgres -- psql -c \
  "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replica_pw_2026';"
```

(The password is needed for the replication connection over TCP — the replica connects to `127.0.0.1:5432`, not to the Unix socket, because the replica is a different process.)

---

## Step 2 — enable replication on the primary's `postgresql.conf`

```bash
sudo runuser -u postgres -- bash -c "cat >> /etc/postgresql/16/main/postgresql.conf <<EOF

# --- P5 replication settings (added by Portfolio 5) ---
listen_addresses = '127.0.0.1'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1024
hot_standby = on
EOF"
```

> Note: on Ubuntu, `pg_ctlcluster 16 main restart` is equivalent and is the
> recommended shortcut:

```bash
sudo pg_ctlcluster 16 main restart
```

---

## Step 3 — allow the replication role to connect (top of `pg_hba.conf`)

The brief is explicit: **trust lines must go at the top of the file**, because PostgreSQL matches `pg_hba.conf` top-down. We prepend the replication line with `sed -i '1i …'` so it lands at line 1.

```bash
sudo sed -i '1ihost  replication  replicator  127.0.0.1/32  md5' \
  /etc/postgresql/16/main/pg_hba.conf
sudo sed -i '1ihost  all          replicator  127.0.0.1/32  md5' \
  /etc/postgresql/16/main/pg_hba.conf

sudo pg_ctlcluster 16 main reload
```

---

## Step 4 — `pg_basebackup` the primary into a replica data directory

A replica made with `pg_basebackup` needs its **own** data directory and its **own** `postgresql.conf` — it must not share the primary's. We use `/var/lib/postgresql/16/replica` as the replica data directory.

```bash
sudo mkdir -p /var/lib/postgresql/16/replica
sudo chown postgres:postgres /var/lib/postgresql/16/replica
sudo chmod 700 /var/lib/postgresql/16/replica   # PostgreSQL refuses a data directory others can read

# PGPASSWORD supplies the replicator password, so there is no prompt
sudo runuser -u postgres -- env PGPASSWORD=replica_pw_2026 \
  /usr/lib/postgresql/16/bin/pg_basebackup \
  -h 127.0.0.1 -p 5432 -U replicator -D /var/lib/postgresql/16/replica \
  -Fp -Xs -P -R
```

`-R` writes a minimal `standby.signal` file and a `primary.conninfo` line into the replica's `postgresql.conf`, which is enough to start the replica in standby mode. We still need to make sure the replica listens on a **different port** (55432) and uses its **own** socket directory so it doesn't clash with the primary.

---

## Step 5 — give the replica its own `postgresql.conf`

The replica's `postgresql.conf` was copied from the primary by `pg_basebackup`. Edit it:

```bash
sudo runuser -u postgres -- bash -c "cat >> /var/lib/postgresql/16/replica/postgresql.conf <<EOF

# --- replica-specific settings (added by Portfolio 5) ---
port = 55432
listen_addresses = '127.0.0.1'
hot_standby = on
unix_socket_directories = '/var/run/postgresql'
EOF"

# On Ubuntu the access-control files live in /etc, not in the data
# directory, so the copied replica has none. Give it copies of its own.
sudo cp /etc/postgresql/16/main/pg_hba.conf /etc/postgresql/16/main/pg_ident.conf \
  /var/lib/postgresql/16/replica/
sudo chown postgres:postgres /var/lib/postgresql/16/replica/pg_hba.conf \
  /var/lib/postgresql/16/replica/pg_ident.conf
```

The `primary_conninfo` line written by `pg_basebackup -R` should already be in `postgresql.conf` (or in `postgresql.auto.conf`). Verify:

```bash
sudo runuser -u postgres -- grep primary_conninfo \
  /var/lib/postgresql/16/replica/postgresql.auto.conf \
  /var/lib/postgresql/16/replica/postgresql.conf
```

You should see something like:

```
primary_conninfo = 'user=replicator password=replica_pw_2026 channel_binding=prefer host=127.0.0.1 port=5432 sslmode=prefer sslcompression=0 sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres target_session_attrs=any'
```

---

## Step 6 — start the replica with `pg_ctl`

```bash
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
  -D /var/lib/postgresql/16/replica \
  -l /tmp/pg_replica.log \
  -o "-c config_file=/var/lib/postgresql/16/replica/postgresql.conf" \
  start
```

Wait a couple of seconds, then check the log:

```bash
sudo tail -20 /tmp/pg_replica.log
```

You should see `database system is ready to accept read only connections` (note "read only").

---

## Step 7 — verify replication is streaming

On the **primary**:

```bash
psql -d passpoint -c "SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

You should see one row with `state = streaming` and `sync_state = async`.

On the **replica** (note the port and that we still connect through the Unix socket, no password):

```bash
psql -p 55432 -d passpoint -c \
  "SELECT pg_is_in_recovery(), now() - pg_last_xact_replay_timestamp() AS lag;"
```

You should see `pg_is_in_recovery = t` and a small `lag` (a few hundred milliseconds).

> **Connecting to the replica through the Unix socket:** the replica listens on `127.0.0.1:55432` *and* on the Unix socket at `/var/run/postgresql` (because `unix_socket_directories` is set there). `psql -p 55432` connects through the socket — **no password required**. This is the Codespaces-friendly pattern: TCP logins need a password; socket logins do not.

---

## Step 8 — run the replication demo

Open **two** terminals:

Run the demo script once. It switches between the primary (5432) and the replica (55432) by itself:

```bash
psql -d passpoint -f replication_demo.sql
```

The demo shows:

1. A write to the primary succeeds.
2. The same write to the replica is rejected (`cannot execute INSERT in a read-only transaction`).
3. After a short wait, the new row from the primary appears on the replica.

---

## Troubleshooting (Codespaces-specific)

| Symptom | Likely cause | Fix |
|---|---|---|
| `pg_basebackup` says "no pg_hba.conf line matches" | the trust line was not at the top of `pg_hba.conf` | re-run the `sed -i '1i…'` step in Step 3 |
| replica starts but `pg_stat_replication` is empty | primary's `wal_level` is still `minimal` or `replica` was not reloaded | `sudo pg_ctlcluster 16 main restart` |
| replica's `psql -p 55432` asks for a password | the replica is listening on TCP only, not on the socket | re-check `unix_socket_directories = '/var/run/postgresql'` in the replica's `postgresql.conf` |
| `replication_demo.sql` says "relation appointment_p5 does not exist" on the replica | `partition.sql` ran *after* `pg_basebackup` | run `run_p5.sh` first, then redo Step 4 (`pg_basebackup`) |
| Two PostgreSQL clusters compete for the same data directory | you reused `/var/lib/postgresql/16/main` for the replica | the replica must use its own directory (`/var/lib/postgresql/16/replica`), as in Step 4 |
