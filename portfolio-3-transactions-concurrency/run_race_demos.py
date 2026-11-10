#!/usr/bin/env python3
"""
run_race_demos.py: runs all six two-terminal concurrency demos from
race_condition_demo.md automatically, using TWO real database sessions
(T1 and T2) so the timing is exact. Every line printed is real output from
this run. Save it with:   python3 run_race_demos.py | tee race_demos_output.log
"""
import psycopg2, threading, time, subprocess, os

DB = "passpoint_p3_race"
HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run(["psql", "-q", "-d", DB, "-f", os.path.join(HERE, "race_setup.sql")],
               check=True, stdout=subprocess.DEVNULL)

T1 = psycopg2.connect(dbname=DB); T2 = psycopg2.connect(dbname=DB)

def run(conn, sql, args=None):
    cur = conn.cursor(); cur.execute(sql, args)
    return cur.fetchall() if cur.description else f"{cur.statusmessage}"

def say(who, sql, res):
    print(f"  [{who}] {sql}\n         -> {res}")

def in_background(conn, sql, args):
    box = {}
    def go():
        try: box["result"] = run(conn, sql, args)
        except Exception as e: box["result"] = "ERROR: " + str(e).splitlines()[0]
    t = threading.Thread(target=go); t.start(); time.sleep(1.5)
    return t, box

slot  = run(T1, "SELECT slot_id FROM slot_race ORDER BY start_time LIMIT 1")[0][0]
slot2 = run(T1, "SELECT slot_id FROM slot_race ORDER BY start_time OFFSET 1 LIMIT 1")[0][0]
aisha  = run(T1, "SELECT applicant_id FROM applicant_race WHERE email='alice@example.com'")[0][0]
bolaji = run(T1, "SELECT applicant_id FROM applicant_race WHERE email='bob@example.com'")[0][0]
T1.commit()
COUNT = "SELECT count(*) FROM appointment_race WHERE slot_id = %s"

print("\n=== PART 1: THE BUG (check-then-insert, no constraint, no lock) ===")
say("T1", "BEGIN; " + COUNT % "slot", run(T1, COUNT, (slot,)))
say("T2", "BEGIN; " + COUNT % "slot", run(T2, COUNT, (slot,)))
say("T1", "INSERT appointment for Aisha; COMMIT", run(T1, "INSERT INTO appointment_race(applicant_id,slot_id) VALUES(%s,%s)", (aisha, slot))); T1.commit()
say("T2", "INSERT appointment for Bolaji; COMMIT", run(T2, "INSERT INTO appointment_race(applicant_id,slot_id) VALUES(%s,%s)", (bolaji, slot))); T2.commit()
say("T1", "rows for this slot", run(T1, COUNT, (slot,))); T1.commit()
print("  RESULT: the same slot was given to TWO applicants (double booking).")

print("\n=== PART 2: FIX 1, the UNIQUE constraint ===")
say("T1", "BEGIN; INSERT into appointment_race_uniq (Aisha)", run(T1, "INSERT INTO appointment_race_uniq(applicant_id,slot_id) VALUES(%s,%s)", (aisha, slot)))
t, box = in_background(T2, "INSERT INTO appointment_race_uniq(applicant_id,slot_id) VALUES(%s,%s)", (bolaji, slot))
print(f"  [T2] BEGIN; INSERT into appointment_race_uniq (Bolaji)\n         -> waiting for T1: {t.is_alive()}")
T1.commit(); print("  [T1] COMMIT"); t.join(); T2.rollback()
print(f"  [T2]   -> {box['result']}")

print("\n=== PART 3: FIX 2, SELECT ... FOR UPDATE ===")
run(T1, "DELETE FROM appointment_race_uniq"); T1.commit()
say("T1", "BEGIN; SELECT is_open ... FOR UPDATE", run(T1, "SELECT is_open FROM slot_race WHERE slot_id=%s FOR UPDATE", (slot,)))
t, box = in_background(T2, "SELECT is_open FROM slot_race WHERE slot_id=%s FOR UPDATE", (slot,))
print(f"  [T2] BEGIN; SELECT is_open ... FOR UPDATE\n         -> waiting for T1's lock: {t.is_alive()}")
run(T1, "INSERT INTO appointment_race_uniq(applicant_id,slot_id) VALUES(%s,%s)", (aisha, slot))
run(T1, "UPDATE slot_race SET is_open=false WHERE slot_id=%s", (slot,)); T1.commit()
print("  [T1] INSERT Aisha; UPDATE slot_race SET is_open=false; COMMIT")
t.join(); T2.rollback()
print(f"  [T2]   -> {box['result']}   (now sees the slot CLOSED, so it refuses)")

print("\n=== PART 4: FIX 3, SERIALIZABLE isolation (no constraint needed) ===")
T1.set_session(isolation_level="SERIALIZABLE"); T2.set_session(isolation_level="SERIALIZABLE")
say("T1", "BEGIN SERIALIZABLE; " + COUNT % "slot2", run(T1, COUNT, (slot2,)))
say("T2", "BEGIN SERIALIZABLE; " + COUNT % "slot2", run(T2, COUNT, (slot2,)))
say("T1", "INSERT Aisha", run(T1, "INSERT INTO appointment_race(applicant_id,slot_id) VALUES(%s,%s)", (aisha, slot2)))
say("T2", "INSERT Bolaji", run(T2, "INSERT INTO appointment_race(applicant_id,slot_id) VALUES(%s,%s)", (bolaji, slot2)))
T1.commit(); print("  [T1] COMMIT -> OK")
try: T2.commit(); print("  [T2] COMMIT -> OK (unexpected)")
except Exception as e: print("  [T2] COMMIT -> ERROR: " + str(e).splitlines()[0]); T2.rollback()
T1.set_session(isolation_level="READ COMMITTED"); T2.set_session(isolation_level="READ COMMITTED")

print("\n=== PART 5: READ COMMITTED vs REPEATABLE READ ===")
run(T1, "UPDATE slot_race SET is_open=true WHERE slot_id=%s", (slot,)); T1.commit()
T2.autocommit = True
Q = "SELECT is_open FROM slot_race WHERE slot_id=%s"
say("T1", "BEGIN READ COMMITTED; SELECT is_open", run(T1, Q, (slot,)))
say("T2", "UPDATE is_open=false (auto-commit)", run(T2, "UPDATE slot_race SET is_open=false WHERE slot_id=%s", (slot,)))
say("T1", "SELECT is_open again", run(T1, Q, (slot,))); T1.commit()
print("  RESULT: value changed inside one transaction (non-repeatable read).")
T1.set_session(isolation_level="REPEATABLE READ")
say("T1", "BEGIN REPEATABLE READ; SELECT is_open", run(T1, Q, (slot,)))
say("T2", "UPDATE is_open=true (auto-commit)", run(T2, "UPDATE slot_race SET is_open=true WHERE slot_id=%s", (slot,)))
say("T1", "SELECT is_open again", run(T1, Q, (slot,))); T1.commit()
print("  RESULT: same snapshot both times.")
T1.set_session(isolation_level="READ COMMITTED"); T2.autocommit = False

print("\n=== PART 6: DEADLOCK ===")
say("T1", "BEGIN; UPDATE slot 1", run(T1, "UPDATE slot_race SET is_open=true WHERE slot_id=%s", (slot,)))
say("T2", "BEGIN; UPDATE slot 2", run(T2, "UPDATE slot_race SET is_open=true WHERE slot_id=%s", (slot2,)))
t, box = in_background(T1, "UPDATE slot_race SET is_open=false WHERE slot_id=%s", (slot2,))
print(f"  [T1] UPDATE slot 2\n         -> waiting for T2: {t.is_alive()}")
try: res = run(T2, "UPDATE slot_race SET is_open=false WHERE slot_id=%s", (slot,))
except Exception as e: res = "ERROR: " + str(e).splitlines()[0]
print(f"  [T2] UPDATE slot 1\n         -> {res}")
T2.rollback(); t.join(); T1.rollback()
print(f"  [T1]   -> {box['result']}")
print("\nAll six demos finished.")
