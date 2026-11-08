#!/usr/bin/env python3
"""
seed_docs.py — bulk generator for passpoint.documents (Portfolio 4)

Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
Database: MongoDB passpoint.documents  (MongoDB 8)

Generates 40 000+ document records spread across the five document types
required by the brief:

    * birth_certificate          (required for FRESH applicants)
    * nin_slip                    (required for all applicants)
    * old_passport_data_page     (required for RENEWAL + REPLACEMENT)
    * photo                       (required for all applicants)
    * affidavit                   (required for REPLACEMENT only)

Each document has:
  * the common fields (appointment_id, applicant_id, office_code,
    document_type, file_name, file_size_bytes, mime_type, uploaded_at,
    verification{status, verified_by, verified_at, reject_reason}, officer_notes[])
  * the per-document-type conditional fields (birth_certificate, nin_slip,
    old_passport, photo, affidavit) populated when applicable.

The generator is idempotent: re-running it drops the collection first.
Run with:
    python3 seed_docs.py [--target 40000] [--uri mongodb://127.0.0.1:27017]
"""

from __future__ import annotations
import argparse, random, sys
from datetime import datetime, timedelta, timezone

import pymongo
from bson import ObjectId

# ---------------------------------------------------------------------
# Document-type weights (matches the PassPoint service-type mix from P1)
#   FRESH       ~ 50% of appointments  -> birth_certificate + nin_slip + photo
#   RENEWAL     ~ 35%                  -> nin_slip + old_passport + photo
#   REPLACEMENT ~ 15%                  -> nin_slip + old_passport + photo + affidavit
# So across N documents the type mix is roughly:
#   photo                       : 100%
#   nin_slip                    : 100%
#   birth_certificate           : ~50%
#   old_passport_data_page      : ~50%
#   affidavit                   : ~15%
# ---------------------------------------------------------------------
TYPE_WEIGHTS = {
    "photo":                    1.00,
    "nin_slip":                 1.00,
    "birth_certificate":        0.50,
    "old_passport_data_page":   0.50,
    "affidavit":                0.15,
}

OFFICES = ["LGW-IKO","LGW-ALA","ABJ-ABD","PHC-MRD"]
MIME_BY_EXT = {
    "pdf": "application/pdf",
    "jpg": "image/jpeg",
    "png": "image/png",
}
EXTS = ["pdf","jpg","png"]
REJECT_REASONS = [
    "document blurry",
    "wrong document uploaded",
    "expired document",
    "photo background not white",
    "affidavit notarization missing",
    "name mismatch with applicant",
    "NIN slip not legible",
]
OFFICERS = ["officer-1","officer-2","officer-3","officer-4","officer-5","officer-6",
            "officer-7","officer-8","officer-9","officer-10"]
STATES = ["Lagos","Abuja","Port Harcourt","Oyo","Kano","Rivers","Enugu","Kaduna","Edo","Ogun"]
COURTS = ["Magistrate Court, Ikoyi","Magistrate Court, Garki",
          "Magistrate Court, Port Harcourt","High Court, Ikeja",
          "High Court, Abuja","Magistrate Court, Alausa"]


def rand_file_size(dt: str) -> int:
    if dt == "photo":
        return random.randint(40_000, 120_000)
    return random.randint(80_000, 1_500_000)


def make_birth_certificate(uploaded_at: datetime) -> dict:
    return {
        "registration_number": f"{random.choice(['AB','CD','EF'])}/{random.randint(1000,9999)}/{random.randint(100,999)}",
        "issuing_state": random.choice(STATES),
        "date_of_registration": uploaded_at - timedelta(days=random.randint(365*18, 365*40)),
    }


def make_nin_slip(uploaded_at: datetime) -> dict:
    return {
        "nin_slip_id": f"NIN-SLIP-{random.randint(10000,99999)}",
        "issue_date": uploaded_at - timedelta(days=random.randint(30, 800)),
    }


def make_old_passport(uploaded_at: datetime) -> dict:
    issued = uploaded_at - timedelta(days=random.randint(365, 365*10))
    return {
        "passport_number": f"{random.choice(['A','B','C'])}{random.randint(1000000,9999999)}",
        "issue_date": issued,
        "issuing_office": random.choice(OFFICES),
        "expiry_date": issued + timedelta(days=365*5),
    }


def make_photo() -> dict:
    return {
        "pixel_width": random.choice([480, 600, 800, 1024]),
        "pixel_height": random.choice([480, 600, 800, 1024]),
        "background_color": random.choices(["white","off-white","white"],
                                            weights=[8,1,1], k=1)[0],
    }


def make_affidavit(uploaded_at: datetime) -> dict:
    return {
        "court_name": random.choice(COURTS),
        "affidavit_number": f"AFF-{uploaded_at.year}-{random.randint(1,9999):04d}",
        "sworn_on": uploaded_at - timedelta(days=random.randint(1, 30)),
        "deponent_name": f"Deponent {random.randint(1,9999)}",
    }


PER_TYPE_FACTORIES = {
    "birth_certificate":         make_birth_certificate,
    "nin_slip":                  make_nin_slip,
    "old_passport_data_page":    make_old_passport,
    "photo":                     make_photo,
    "affidavit":                 make_affidavit,
}


def make_verification(uploaded_at: datetime, dt: str) -> dict:
    # ~80% APPROVED, ~10% REJECTED, ~6% NEEDS_RESUBMISSION, ~4% PENDING
    r = random.random()
    if r < 0.04:
        return {"status": "PENDING"}
    if r < 0.14:
        reason = random.choice(REJECT_REASONS)
        return {
            "status": "REJECTED",
            "reject_reason": reason,
            "verified_by": random.choice(OFFICERS),
            "verified_at": uploaded_at + timedelta(minutes=random.randint(5, 240)),
            "notes": f"rejected: {reason}",
        }
    if r < 0.20:
        reason = random.choice(REJECT_REASONS)
        return {
            "status": "NEEDS_RESUBMISSION",
            "reject_reason": reason,
            "verified_by": random.choice(OFFICERS),
            "verified_at": uploaded_at + timedelta(minutes=random.randint(5, 120)),
            "notes": f"applicant to re-upload: {reason}",
        }
    return {
        "status": "APPROVED",
        "verified_by": random.choice(OFFICERS),
        "verified_at": uploaded_at + timedelta(minutes=random.randint(1, 480)),
        "notes": "looks genuine",
    }


def make_officer_notes(uploaded_at: datetime, v_status: str) -> list:
    notes = [{
        "officer": "front-desk",
        "note": "uploaded at counter",
        "at": uploaded_at,
    }]
    if v_status in ("APPROVED","REJECTED","NEEDS_RESUBMISSION"):
        notes.append({
            "officer": random.choice(OFFICERS),
            "note": "verified" if v_status == "APPROVED" else "flagged for review",
            "at": uploaded_at + timedelta(minutes=random.randint(1, 480)),
        })
    return notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", type=int, default=42000,
                    help="approx number of documents to generate (default 42000)")
    ap.add_argument("--uri", default="mongodb://127.0.0.1:27017")
    ap.add_argument("--db", default="passpoint")
    args = ap.parse_args()

    random.seed(2026_0077)
    client = pymongo.MongoClient(args.uri, serverSelectionTimeoutMS=5000)
    db = client[args.db]
    coll = db["documents"]

    print(f"[seed_docs] connecting to {args.uri}/{args.db}.documents")
    print(f"[seed_docs] target documents = {args.target:,}")

    # Drop + recreate (the validator is re-applied by schema_validation.js
    # OR we can attach it inline here. We attach inline so the run_p4.sh
    # script can call this script alone if needed.)
    coll.drop()
    db.create_collection("documents")
    # apply the same $jsonSchema validator used in schema_validation.js
    db.command("collMod", "documents", validator={
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["appointment_id","office_code","applicant_id",
                         "document_type","file_name","file_size_bytes",
                         "mime_type","uploaded_at","verification","officer_notes"],
            "properties": {
                "appointment_id": {"bsonType": "string"},
                "applicant_id":   {"bsonType": "string"},
                "office_code":    {"enum": OFFICES},
                "document_type":  {"enum": list(TYPE_WEIGHTS.keys())},
                "file_name":        {"bsonType": "string"},
                "file_size_bytes":  {"bsonType": "int"},
                "mime_type":        {"bsonType": "string"},
                "uploaded_at":      {"bsonType": "date"},
                "verification": {
                    "bsonType": "object",
                    "required": ["status"],
                    "properties": {
                        "status":         {"enum": ["PENDING","APPROVED","REJECTED","NEEDS_RESUBMISSION"]},
                        "verified_by":    {"bsonType": "string"},
                        "verified_at":    {"bsonType": "date"},
                        "reject_reason":  {"bsonType": "string"},
                        "notes":          {"bsonType": "string"},
                    },
                },
                "officer_notes": {
                    "bsonType": "array",
                    "items": {
                        "bsonType": "object",
                        "required": ["officer","note","at"],
                        "properties": {
                            "officer": {"bsonType": "string"},
                            "note":    {"bsonType": "string"},
                            "at":      {"bsonType": "date"},
                        },
                    },
                },
                # per-type sub-docs (optional unless document_type matches)
                "birth_certificate": {"bsonType": "object"},
                "nin_slip":           {"bsonType": "object"},
                "old_passport":       {"bsonType": "object"},
                "photo":              {"bsonType": "object"},
                "affidavit":          {"bsonType": "object"},
            },
        }
    }, validationLevel="strict", validationAction="error")
    print("[seed_docs] validator attached")

    # generate
    now = datetime.now(timezone.utc)
    start_window = now - timedelta(days=730)   # last 2 years
    docs = []
    for i in range(args.target):
        # pick a document type from the weighted distribution
        dt = random.choices(list(TYPE_WEIGHTS.keys()),
                            weights=list(TYPE_WEIGHTS.values()), k=1)[0]
        uploaded = start_window + timedelta(
            seconds=random.randint(0, int((now - start_window).total_seconds())))
        ext = random.choice(EXTS)
        v = make_verification(uploaded, dt)
        doc = {
            "appointment_id": f"appt-{i:07d}",
            "applicant_id":   f"app-{random.randint(1, 30000):06d}",
            "office_code":    random.choice(OFFICES),
            "document_type":  dt,
            "file_name":      f"{dt}_{i}.{ext}",
            "file_size_bytes": rand_file_size(dt),
            "mime_type":      MIME_BY_EXT[ext],
            "uploaded_at":    uploaded,
            "verification":   v,
            "officer_notes":  make_officer_notes(uploaded, v["status"]),
            "_factory_seed":  PER_TYPE_FACTORIES[dt](uploaded) if dt != "photo" else make_photo(),
        }
        # flatten the per-type sub-doc to the right key
        factory_key = {
            "birth_certificate":         "birth_certificate",
            "nin_slip":                  "nin_slip",
            "old_passport_data_page":    "old_passport",
            "photo":                     "photo",
            "affidavit":                 "affidavit",
        }[dt]
        doc[factory_key] = doc.pop("_factory_seed")
        docs.append(doc)

        if (i + 1) % 5000 == 0:
            coll.insert_many(docs, ordered=False)
            print(f"[seed_docs]   inserted {i+1:,} / {args.target:,}")
            docs = []
    if docs:
        coll.insert_many(docs, ordered=False)

    print(f"[seed_docs] inserted {args.target:,} documents total")
    print(f"[seed_docs] countDocuments() = {coll.count_documents({}):,}")

    # group-by summary
    pipeline = [
        {"$group": {"_id": "$document_type", "count": {"$sum": 1}}},
        {"$sort": {"_id": 1}},
    ]
    print("[seed_docs] per document_type:")
    for r in coll.aggregate(pipeline):
        print(f"[seed_docs]   {r['_id']:30s} {r['count']:>8,}")
    client.close()


if __name__ == "__main__":
    main()
