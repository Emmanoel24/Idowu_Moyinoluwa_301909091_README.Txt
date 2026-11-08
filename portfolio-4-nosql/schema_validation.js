// =====================================================================
// schema_validation.js — MongoDB JSON Schema for passpoint.documents
// Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
//
// Runs against the `passpoint` database (MongoDB 8). Drops the existing
// collection, recreates it with a $jsonSchema validator, then inserts
// one valid document of each type as a smoke test.
//
// Run:
//   mongosh --quiet passpoint portfolio-4-nosql/schema_validation.js
// =====================================================================

db = db.getSiblingDB("passpoint");   // ("use" is a shell helper and cannot be used inside a script file)

// --- drop + recreate with the validator --------------------------------
db.documents.drop();

db.createCollection("documents", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "appointment_id",        // FK to PostgreSQL appointment.appointment_id
        "office_code",           // e.g. LGW-IKO
        "applicant_id",          // FK to PostgreSQL applicant.applicant_id
        "document_type",         // enum below
        "file_name",
        "file_size_bytes",
        "mime_type",
        "uploaded_at",
        "verification",          // embedded sub-document
        "officer_notes"          // array of {officer, note, at}
      ],
      properties: {
        appointment_id: { bsonType: "string" },
        applicant_id:   { bsonType: "string" },
        office_code:    { enum: ["LGW-IKO","LGW-ALA","ABJ-ABD","PHC-MRD"] },
        document_type:  {
          enum: ["birth_certificate","nin_slip","old_passport_data_page",
                 "photo","affidavit"]
        },
        file_name:        { bsonType: "string" },
        file_size_bytes:  { bsonType: "int", minimum: 0, maximum: 10485760 },
        mime_type:        { bsonType: "string" },
        uploaded_at:      { bsonType: "date" },

        // ---- per-document-type conditional fields ---------------------
        birth_certificate: {
          bsonType: "object",
          required: ["registration_number","issuing_state","date_of_registration"],
          properties: {
            registration_number:   { bsonType: "string" },
            issuing_state:         { bsonType: "string" },
            date_of_registration:  { bsonType: "date" }
          }
        },
        nin_slip: {
          bsonType: "object",
          required: ["nin_slip_id","issue_date"],
          properties: {
            nin_slip_id:  { bsonType: "string" },     // does NOT store the NIN itself
            issue_date:   { bsonType: "date" }
          }
        },
        old_passport: {
          bsonType: "object",
          required: ["passport_number","issue_date","issuing_office"],
          properties: {
            passport_number:  { bsonType: "string" },
            issue_date:       { bsonType: "date" },
            issuing_office:   { bsonType: "string" },
            expiry_date:      { bsonType: "date" }
          }
        },
        photo: {
          bsonType: "object",
          required: ["pixel_width","pixel_height","background_color"],
          properties: {
            pixel_width:      { bsonType: "int", minimum: 200, maximum: 4000 },
            pixel_height:     { bsonType: "int", minimum: 200, maximum: 4000 },
            background_color: { bsonType: "string" }    // "white"
          }
        },
        affidavit: {
          bsonType: "object",
          required: ["court_name","affidavit_number","sworn_on","deponent_name"],
          properties: {
            court_name:        { bsonType: "string" },
            affidavit_number:  { bsonType: "string" },
            sworn_on:          { bsonType: "date" },
            deponent_name:     { bsonType: "string" }
          }
        },

        // ---- verification sub-document --------------------------------
        verification: {
          bsonType: "object",
          required: ["status"],
          properties: {
            status: {
              enum: ["PENDING","APPROVED","REJECTED","NEEDS_RESUBMISSION"]
            },
            verified_by:    { bsonType: "string" },     // officer name
            verified_at:    { bsonType: "date" },
            reject_reason:  { bsonType: "string" },     // populated when status=REJECTED
            notes:          { bsonType: "string" }
          }
        },

        // ---- officer_notes array (audit trail) ------------------------
        officer_notes: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["officer","note","at"],
            properties: {
              officer: { bsonType: "string" },
              note:    { bsonType: "string" },
              at:      { bsonType: "date" }
            }
          }
        }
      },

      // ---- "if document_type = X then sub-document Y is required" ----
      // MongoDB's $jsonSchema does not support if/then/else, so the same
      // rule is written as oneOf: a document must match exactly one branch.
      oneOf: [
        { properties: { document_type: { enum: ["birth_certificate"] } },      required: ["birth_certificate"] },
        { properties: { document_type: { enum: ["nin_slip"] } },               required: ["nin_slip"] },
        { properties: { document_type: { enum: ["old_passport_data_page"] } }, required: ["old_passport"] },
        { properties: { document_type: { enum: ["photo"] } },                  required: ["photo"] },
        { properties: { document_type: { enum: ["affidavit"] } },              required: ["affidavit"] }
      ]
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

print("====================================================================");
print(" passpoint.documents collection created with $jsonSchema validator.");
print("====================================================================");

// --- smoke test: insert one valid document of each type ---------------
var now = new Date();
var appt = "smoke-test-appointment";

db.documents.insertOne({
  appointment_id: appt, applicant_id: "applicant-A", office_code: "LGW-IKO",
  document_type: "birth_certificate",
  file_name: "bc.pdf", file_size_bytes: NumberInt(120000), mime_type: "application/pdf",
  uploaded_at: now,
  birth_certificate: {
    registration_number: "AB/CD/12345",
    issuing_state: "Lagos",
    date_of_registration: ISODate("1990-04-12")
  },
  verification: { status: "PENDING" },
  officer_notes: [{ officer: "front-desk-1", note: "uploaded at counter 1", at: now }]
});

db.documents.insertOne({
  appointment_id: appt, applicant_id: "applicant-A", office_code: "LGW-IKO",
  document_type: "nin_slip",
  file_name: "nin.jpg", file_size_bytes: NumberInt(80000), mime_type: "image/jpeg",
  uploaded_at: now,
  nin_slip: { nin_slip_id: "NIN-SLIP-9999", issue_date: ISODate("2024-01-15") },
  verification: { status: "PENDING" },
  officer_notes: [{ officer: "front-desk-1", note: "uploaded at counter 1", at: now }]
});

db.documents.insertOne({
  appointment_id: appt, applicant_id: "applicant-B", office_code: "LGW-ALA",
  document_type: "old_passport_data_page",
  file_name: "old_pp.png", file_size_bytes: NumberInt(220000), mime_type: "image/png",
  uploaded_at: now,
  old_passport: {
    passport_number: "A01234567",
    issue_date: ISODate("2019-05-10"),
    issuing_office: "Ikoyi", expiry_date: ISODate("2024-05-09")
  },
  verification: { status: "PENDING" },
  officer_notes: [{ officer: "front-desk-2", note: "uploaded at counter 2", at: now }]
});

db.documents.insertOne({
  appointment_id: appt, applicant_id: "applicant-B", office_code: "LGW-ALA",
  document_type: "photo",
  file_name: "photo.jpg", file_size_bytes: NumberInt(60000), mime_type: "image/jpeg",
  uploaded_at: now,
  photo: { pixel_width: NumberInt(600), pixel_height: NumberInt(600), background_color: "white" },
  verification: { status: "APPROVED", verified_by: "officer-X", verified_at: now },
  officer_notes: [{ officer: "officer-X", note: "photo meets spec", at: now }]
});

db.documents.insertOne({
  appointment_id: appt, applicant_id: "applicant-C", office_code: "ABJ-ABD",
  document_type: "affidavit",
  file_name: "affidavit.pdf", file_size_bytes: NumberInt(150000), mime_type: "application/pdf",
  uploaded_at: now,
  affidavit: {
    court_name: "Magistrate Court, Garki",
    affidavit_number: "AFF-2024-0099",
    sworn_on: ISODate("2024-09-01"),
    deponent_name: "Adamu Bello"
  },
  verification: { status: "APPROVED", verified_by: "officer-Y", verified_at: now },
  officer_notes: [{ officer: "officer-Y", note: "affidavit looks genuine", at: now }]
});

print("====================================================================");
print(" inserted 5 smoke-test documents (one per document_type).");
print(" count = " + db.documents.countDocuments());
print("====================================================================");

// --- negative test: insert an INVALID document (missing required field)
// This MUST be rejected by the validator.
print("");
print("-- negative test: insert a birth_certificate WITHOUT birth_certificate sub-doc --");
try {
  db.documents.insertOne({
    appointment_id: "smoke-test-bad", applicant_id: "applicant-Z", office_code: "LGW-IKO",
    document_type: "birth_certificate",
    file_name: "bad.pdf", file_size_bytes: NumberInt(100), mime_type: "application/pdf",
    uploaded_at: now,
    verification: { status: "PENDING" },
    officer_notes: []
  });
  print("UNEXPECTED: insert succeeded (validator not enforced)");
} catch (e) {
  print("EXPECTED rejection: " + e.message.split("\n")[0]);
}
