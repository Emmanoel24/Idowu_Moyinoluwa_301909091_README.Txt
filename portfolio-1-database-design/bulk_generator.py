#!/usr/bin/env python3
"""
bulk_generator.py — PassPoint bulk data generator (Portfolio 1)

Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
Database: passpoint  (PostgreSQL 16, Unix-socket connection)

Generates 50 000+ appointments spread across the last two years
(relative to today, so the dataset never expires), with:

  * realistic Nigerian first/last names (Yoruba, Igbo, Hausa, mixed);
  * slots that are weekdays only, 08:00–16:00, 30 minutes long;
  * each slot used at most once (UNIQUE on appointment.slot_id);
  * service types FRESH / RENEWAL / REPLACEMENT with realistic ₦ fees;
  * payment rows matching the appointments (mostly CONFIRMED, some PENDING);
  * a realistic status distribution along the lifecycle
        BOOKED -> CONFIRMED -> CAPTURED -> PROCESSING -> READY -> COLLECTED
    plus CANCELLED / NO_SHOW;
  * collection rows for COLLECTED appointments;
  * SHA-256 hashed NINs — plaintext NINs are NEVER stored.

Usage:
    python3 bulk_generator.py [--target 60000] [--dsn postgresql:///passpoint]

By default it targets 60 000 appointments (≥ the 50k requirement).
The script is idempotent: re-running it cleans out the appointment/payment/
history/collection tables and slot/applicant rows it created, then rebuilds.
"""

from __future__ import annotations
import argparse, hashlib, os, random, sys, time
from datetime import date, datetime, timedelta, time as dtime
from uuid import uuid4

import psycopg2
import psycopg2.extras

psycopg2.extras.register_uuid()

# ---------------------------------------------------------------------
# Realistic Nigerian name pools (deliberately multi-ethnic)
# ---------------------------------------------------------------------
YORUBA_FIRST = [
    "Adaeze","Adebayo","Ademola","Aderonke","Adetutu","Ayomide","Babatunde",
    "Bisi","Chukwuemeka","Damola","Dayo","Dolapo","Folasade","Funmilayo",
    "Gbolahan","Ifeoma","Ireti","Kehinde","Kunle","Mobolaji","Modupe",
    "Moyinoluwa","Ngozi","Nkem","Obafemi","Olamide","Olanrewaju","Oluwaseun",
    "Oluwafemi","Oluwatobi","Opeyemi","Remilekun","Sade","Seyi","Taiwo",
    "Temitope","Tunde","Wale","Yemisi","Yetunde",
]
HAUSA_FIRST = [
    "Abubakar","Aisha","Bello","Bilkisu","Danjuma","Fatima","Garba",
    "Hadiza","Halima","Ibrahim","Jamila","Kabiru","Lami","Musa",
    "Nafisa","Sadiq","Sanusi","Umar","Yakubu","Zainab",
]
IGBO_FIRST = [
    "Adaobi","Chidinma","Chika","Chinonso","Chinwe","Chinyere","Emeka",
    "Ezinne","Ifeoma","Ihuoma","Kelechi","Ngozi","Nneka","Obinna",
    "Okonkwo","Onyeka","Tochukwu","Uche","Uchenna","Ugochi",
]
LAST = [
    "Adeyemi","Adeyinka","Adebiyi","Adeleke","Adekunle","Aderemi","Ajayi",
    "Akande","Akinwale","Alabi","Anozie","Aro","Afolabi","Bello","Chukwu",
    "Danjuma","Eze","Ezeji","Ezegwu","Fashola","Ganiyu","Ibrahim","Idowu",
    "Ikegwuonu","Johnson","Lawal","Mba","Mohammed","Nwosu","Obi","Obiefuna",
    "Okafor","Okonkwo","Okoro","Olawale","Olejeme","Oyetola","Sani","Sowunmi",
    "Uche","Udo","Williams","Yakubu","Yusuf",
]

GENDERS = ["M","F"]
PHONE_PREFIXES = ["0703","0706","0803","0806","0810","0813","0814","0816","0903","0906","0705","0805","0811","0815","0905"]
EMAIL_DOMAINS = ["gmail.com","yahoo.com","outlook.com","hotmail.com","zoho.com","protonmail.com"]

CITIES = {
    "Lagos":          ["LGW-IKO","LGW-ALA"],
    "Abuja":          ["ABJ-ABD"],
    "Port Harcourt":  ["PHC-MRD"],
}

SERVICES = ["FRESH","RENEWAL","REPLACEMENT"]
# Realistic ₦ fees (kept in sync with seed.sql — the script reads the live
# table for the actual fee, so editing seed.sql is enough).
SERVICE_WEIGHTS = {"FRESH":0.5,"RENEWAL":0.35,"REPLACEMENT":0.15}

CHANNELS = ["CARD","BANK_TRANSFER","USSD"]
CHANNEL_WEIGHTS = [0.55,0.30,0.15]

# Status distribution for CLOSED appointments (the rest are still open)
CLOSED_STATUS_DIST = [
    ("COLLECTED", 0.70),
    ("NO_SHOW",   0.12),
    ("CANCELLED", 0.10),
    ("READY",     0.05),
    ("PROCESSING",0.02),
    ("CAPTURED",  0.01),
]


def hash_nin(plaintext: str) -> str:
    """SHA-256 hex digest of an NIN. Plaintext NIN is never stored."""
    return hashlib.sha256(plaintext.encode("utf-8")).hexdigest()


def pick_nin() -> str:
    """Random 11-digit NIN — returned as a plaintext string that we
    immediately hash. The plaintext is never sent to the database."""
    return "".join(str(random.randint(0,9)) for _ in range(11))


def pick_first_name() -> str:
    return random.choice(YORUBA_FIRST + HAUSA_FIRST + IGBO_FIRST)


def pick_phone() -> str:
    return random.choice(PHONE_PREFIXES) + "".join(str(random.randint(0,9)) for _ in range(8))


def pick_email(first: str, last: str, n: int) -> str:
    return f"{first.lower()}.{last.lower()}{n}@{random.choice(EMAIL_DOMAINS)}"


def weekdays_in_range(start: date, end: date):
    d = start
    while d <= end:
        if d.weekday() < 5:  # Mon..Fri
            yield d
        d += timedelta(days=1)


SLOT_STARTS = [dtime(h, m) for h in range(8, 16) for m in (0, 30)]  # 08:00..15:30, 16 slots/day


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", type=int, default=60000,
                    help="approx number of appointments to generate (default 60000)")
    ap.add_argument("--dsn", default="postgresql:///passpoint",
                    help="psycopg2 dsn (default postgresql:///passpoint, uses Unix socket)")
    args = ap.parse_args()

    random.seed(2026_0077)  # reproducible per matric number

    conn = psycopg2.connect(args.dsn)
    conn.autocommit = False
    cur = conn.cursor()

    print(f"[bulk] connecting to {args.dsn}")
    print(f"[bulk] target appointments = {args.target:,}")

    # ----- 1. clean previous bulk run ------------------------------------
    print("[bulk] truncating previous bulk tables (history, collection, payment, "
          "appointment, slot, applicant) ...")
    cur.execute("TRUNCATE application_status_history, collection, payment, "
                "appointment, slot, applicant RESTART IDENTITY CASCADE;")
    conn.commit()

    # ----- 2. make sure offices/counters/service_types exist (re-seed if empty)
    cur.execute("SELECT count(*) FROM office");       n_office = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM counter");      n_counter = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM service_type"); n_service = cur.fetchone()[0]
    if n_office == 0 or n_counter == 0 or n_service == 0:
        print("[bulk] office/counter/service_type empty — running seed.sql first")
        cur.close(); conn.close()
        import subprocess
        subprocess.check_call(["psql","-d","passpoint","-v","ON_ERROR_STOP=1",
                               "-f","seed.sql"])
        conn = psycopg2.connect(args.dsn); conn.autocommit = False
        cur = conn.cursor()
        cur.execute("TRUNCATE application_status_history, collection, payment, "
                    "appointment, slot, applicant RESTART IDENTITY CASCADE;")
        conn.commit()

    # ----- 3. load offices, counters, services ---------------------------
    cur.execute("SELECT office_id, office_code, city FROM office")
    offices = cur.fetchall()
    cur.execute("SELECT counter_id, office_id FROM counter ORDER BY office_id, counter_no")
    counters = cur.fetchall()
    cur.execute("SELECT service_id, code, base_fee_ngn, processing_days FROM service_type")
    services = cur.fetchall()
    svc_by_code = {row[1]: row for row in services}

    # ----- 4. generate applicants ----------------------------------------
    n_applicants = max(args.target // 2, 30000)
    print(f"[bulk] generating {n_applicants:,} applicants (hashed NINs) ...")
    applicants = []
    seen_email = set()
    for i in range(n_applicants):
        fn = pick_first_name()
        ln = random.choice(LAST)
        email = pick_email(fn, ln, i)
        while email in seen_email:
            email = pick_email(fn, ln, i + random.randint(1,9999))
        seen_email.add(email)
        applicants.append((
            hash_nin(pick_nin()),            # nin_hash
            fn, ln, email, pick_phone(),
            date(random.randint(1960, 2005), random.randint(1,12), random.randint(1,28)),
            random.choice(GENDERS),
        ))

    # bulk insert applicants in batches
    batch_size = 5000
    for i in range(0, len(applicants), batch_size):
        cur.executemany(
            "INSERT INTO applicant "
            "(nin_hash, first_name, last_name, email, phone, date_of_birth, gender) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s)",
            applicants[i:i+batch_size],
        )
    conn.commit()
    print(f"[bulk]   inserted {len(applicants):,} applicants")

    # ----- 5. generate slots over the last 2 years (relative to today) ---
    # two years of history PLUS the next 14 days, so there are upcoming
    # BOOKED / CONFIRMED appointments (and free future slots) for the
    # constraint tests, the P3 transactions and the P2 "free slots" query
    end_date = date.today() + timedelta(days=14)
    start_date = date.today() - timedelta(days=730)
    print(f"[bulk] generating slots from {start_date} to {end_date} (weekdays only) ...")

    slots = []   # (office_id, counter_id, service_id, slot_date, start_time, end_time, is_open)
    for d in weekdays_in_range(start_date, end_date):
        for off in offices:
            office_id, office_code, city = off
            # 2 counters per office x 16 slots/day x 1 service per slot
            office_counters = [c for c in counters if c[1] == office_id]
            for cidx, (counter_id, _) in enumerate(office_counters):
                for sidx, start_time in enumerate(SLOT_STARTS):
                    # pick a service deterministically so each (office,counter,date,time)
                    # has a stable service — round-robin by index
                    svc = SERVICES[(sidx + cidx) % len(SERVICES)]
                    service_id = svc_by_code[svc][0]
                    slots.append((
                        office_id, counter_id, service_id,
                        d, start_time, (datetime.combine(d, start_time) + timedelta(minutes=30)).time(),
                        True,
                    ))

    print(f"[bulk]   generated {len(slots):,} candidate slots — bulk-inserting ...")
    for i in range(0, len(slots), 5000):
        cur.executemany(
            "INSERT INTO slot (office_id, counter_id, service_id, slot_date, start_time, end_time, is_open) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
            slots[i:i+5000],
        )
    conn.commit()
    cur.execute("SELECT count(*) FROM slot")
    print(f"[bulk]   slot table now has {cur.fetchone()[0]:,} rows")

    # ----- 6. book appointments: pick a random slot per appointment -------
    print(f"[bulk] booking {args.target:,} appointments (each slot used once) ...")
    cur.execute("SELECT slot_id FROM slot ORDER BY random() LIMIT %s", (args.target,))
    slot_ids = [r[0] for r in cur.fetchall()]
    if len(slot_ids) < args.target:
        print(f"[bulk] WARNING: only {len(slot_ids)} slots available — booking all of them")
    random.shuffle(slot_ids)

    cur.execute("SELECT applicant_id FROM applicant")
    applicant_ids = [r[0] for r in cur.fetchall()]

    appointments = []
    payments = []
    collections = []
    histories = []
    closed_statuses = [s for s,_ in CLOSED_STATUS_DIST]
    ACTIVE_STATUSES = {"BOOKED","CONFIRMED","CAPTURED","PROCESSING","READY"}
    active_pairs = set()   # (applicant_id, service_id) pairs holding an active appointment
    closed_weights = [w for _,w in CLOSED_STATUS_DIST]

    now = datetime.utcnow()
    book_day_window = (start_date, end_date - timedelta(days=1))

    for i, slot_id in enumerate(slot_ids):
        # service = the slot's service (must match the slot)
        cur.execute("SELECT service_id, slot_date FROM slot WHERE slot_id = %s", (slot_id,))
        service_id, slot_date = cur.fetchone()
        # booked_at some days before the slot_date
        booked_at = datetime.combine(slot_date - timedelta(days=random.randint(1,30)), dtime(random.randint(8,16), random.randint(0,59)))
        if booked_at > now:
            booked_at = now - timedelta(days=random.randint(1,60))
        # status: appointments whose slot_date is in the past are mostly closed,
        # future ones are mostly open
        if slot_date < date.today():
            status = random.choices(closed_statuses, weights=closed_weights, k=1)[0]
        else:
            status = random.choices(["BOOKED","CONFIRMED","CAPTURED"], weights=[0.7,0.2,0.1], k=1)[0]

        # Pick an applicant. The partial UNIQUE index applicant_service_active_uniq
        # allows only ONE active (not COLLECTED/CANCELLED/NO_SHOW) appointment per
        # applicant per service, so re-draw if this applicant already has one.
        applicant_id = random.choice(applicant_ids)
        if status in ACTIVE_STATUSES:
            while (applicant_id, service_id) in active_pairs:
                applicant_id = random.choice(applicant_ids)
            active_pairs.add((applicant_id, service_id))

        appt_id = uuid4()
        appointments.append((appt_id, applicant_id, slot_id, service_id, status, 0, booked_at, booked_at))

        # payment: only if status >= BOOKED (which is all of them)
        svc_fee = next(s[2] for s in services if s[0] == service_id)
        # small fee variance for realism (some paid slightly different amounts)
        amount = round(float(svc_fee) * random.uniform(0.99, 1.01), 2)
        channel = random.choices(CHANNELS, weights=CHANNEL_WEIGHTS, k=1)[0]
        if status == "BOOKED":
            pay_status = random.choices(["PENDING","CONFIRMED"], weights=[0.7,0.3], k=1)[0]
        elif status == "CANCELLED":
            pay_status = random.choices(["FAILED","REFUNDED","PENDING"], weights=[0.6,0.3,0.1], k=1)[0]
        else:
            pay_status = "CONFIRMED"
        paid_at = booked_at + timedelta(minutes=random.randint(1,120)) if pay_status in ("CONFIRMED","REFUNDED") else None
        confirmed_at = paid_at + timedelta(minutes=random.randint(1,30)) if pay_status == "CONFIRMED" else None
        payments.append((uuid4(), appt_id, amount, channel, f"PSPT-{appt_id.hex[:12]}", pay_status, paid_at, confirmed_at, booked_at))

        # history rows: reconstruct a plausible lifecycle for closed appointments
        if status in ("COLLECTED","READY","PROCESSING","CAPTURED"):
            chain = ["BOOKED","CONFIRMED","CAPTURED","PROCESSING","READY","COLLECTED"]
            upto = chain.index(status)
            for k in range(1, upto+1):
                histories.append((appt_id, chain[k-1], chain[k], "SYSTEM",
                                  "auto-generated history", booked_at + timedelta(days=k)))
        elif status == "CANCELLED":
            histories.append((appt_id, "BOOKED", "CANCELLED", "APPLICANT",
                              "applicant cancelled", booked_at + timedelta(hours=random.randint(1,72))))
        elif status == "NO_SHOW":
            histories.append((appt_id, "BOOKED", "NO_SHOW", "SYSTEM",
                              "applicant did not show up", datetime.combine(slot_date, dtime(16,30))))

        # collection row for COLLECTED
        if status == "COLLECTED":
            rel = random.choices(["SELF","SPOUSE","PARENT","SIBLING","AGENT"],
                                 weights=[0.6,0.15,0.1,0.1,0.05], k=1)[0]
            collected_by = random.choice(LAST) + " " + pick_first_name() if rel != "SELF" else None
            if collected_by is None:
                # need the applicant's name
                cur.execute("SELECT first_name || ' ' || last_name FROM applicant WHERE applicant_id = %s",
                            (applicant_id,))
                collected_by = cur.fetchone()[0]
            collections.append((uuid4(), appt_id, collected_by, rel,
                                hash_nin(pick_nin()),
                                datetime.combine(slot_date + timedelta(days=random.randint(7,21)),
                                                 dtime(random.randint(9,15), random.randint(0,59)))))

    # bulk-insert appointments
    print(f"[bulk]   inserting {len(appointments):,} appointments ...")
    for i in range(0, len(appointments), 5000):
        cur.executemany(
            "INSERT INTO appointment "
            "(appointment_id, applicant_id, slot_id, service_id, status, reschedule_count, booked_at, updated_at) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
            appointments[i:i+5000],
        )
    conn.commit()

    # bulk-insert payments
    print(f"[bulk]   inserting {len(payments):,} payments ...")
    for i in range(0, len(payments), 5000):
        cur.executemany(
            "INSERT INTO payment "
            "(payment_id, appointment_id, amount_ngn, channel, reference, payment_status, paid_at, confirmed_at, created_at) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)",
            payments[i:i+5000],
        )
    conn.commit()

    # bulk-insert history (insert directly — the audit trigger only fires on UPDATE,
    # not on our bulk INSERT, so we add the rows manually)
    print(f"[bulk]   inserting {len(histories):,} status-history rows ...")
    for i in range(0, len(histories), 5000):
        cur.executemany(
            "INSERT INTO application_status_history "
            "(appointment_id, from_status, to_status, actor, note, changed_at) "
            "VALUES (%s,%s,%s,%s,%s,%s)",
            histories[i:i+5000],
        )
    conn.commit()

    # bulk-insert collections
    print(f"[bulk]   inserting {len(collections):,} collection rows ...")
    for i in range(0, len(collections), 5000):
        cur.executemany(
            "INSERT INTO collection "
            "(collection_id, appointment_id, collected_by, collector_relation, collector_id_hash, collected_at) "
            "VALUES (%s,%s,%s,%s,%s,%s)",
            collections[i:i+5000],
        )
    conn.commit()

    # mark used slots as closed
    print(f"[bulk]   marking used slots as is_open=false ...")
    cur.execute("UPDATE slot SET is_open = false WHERE slot_id IN (SELECT slot_id FROM appointment)")
    conn.commit()

    # ----- 7. summary ----------------------------------------------------
    cur.execute("""SELECT 'office' AS t, count(*) FROM office
                   UNION ALL SELECT 'counter', count(*) FROM counter
                   UNION ALL SELECT 'service_type', count(*) FROM service_type
                   UNION ALL SELECT 'slot', count(*) FROM slot
                   UNION ALL SELECT 'applicant', count(*) FROM applicant
                   UNION ALL SELECT 'appointment', count(*) FROM appointment
                   UNION ALL SELECT 'payment', count(*) FROM payment
                   UNION ALL SELECT 'application_status_history', count(*) FROM application_status_history
                   UNION ALL SELECT 'collection', count(*) FROM collection""")
    rows = cur.fetchall()
    print("\n[bulk] ===== FINAL ROW COUNTS =====")
    for t, c in rows:
        print(f"[bulk]   {t:30s} {c:>10,}")
    print("[bulk] done.")
    cur.close(); conn.close()


if __name__ == "__main__":
    main()
