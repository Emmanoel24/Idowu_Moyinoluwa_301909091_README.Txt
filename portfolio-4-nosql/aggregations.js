// =====================================================================
// aggregations.js — PassPoint MongoDB aggregations + index demo
// Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
//
// Two real aggregation pipelines + one COLLSCAN -> IXSCAN demo.
// Run:
//   mongosh --quiet passpoint portfolio-4-nosql/aggregations.js
//
// Every result block below has [paste real output here] — paste the
// actual output from your terminal.
// =====================================================================

db = db.getSiblingDB("passpoint");   // ("use" is a shell helper and cannot be used inside a script file)

print("====================================================================");
print(" PassPoint MongoDB aggregations + index demo");
print(" collection: passpoint.documents  · count = " + db.documents.countDocuments());
print("====================================================================");

// ---------------------------------------------------------------------
// Aggregation 1 — rejection reasons per document type
//   For each document_type, count each verification.reject_reason.
//   Useful for "which document type causes the most rejections, and why?"
// ---------------------------------------------------------------------
print("\n##### Aggregation 1 — rejection reasons per document_type #####");

const agg1 = [
  { $match: { "verification.status": "REJECTED" } },
  { $group: {
      _id: { document_type: "$document_type",
             reject_reason: "$verification.reject_reason" },
      count: { $sum: 1 }
  }},
  { $sort: { "_id.document_type": 1, count: -1 } },
  { $project: {
      _id: 0,
      document_type: "$_id.document_type",
      reject_reason: "$_id.reject_reason",
      count: 1
  }}
];

const result1 = db.documents.aggregate(agg1).toArray();
printjson(result1);

// paste the real output here:
// [paste real output here]

// ---------------------------------------------------------------------
// Aggregation 2 — average verification time per office (in minutes)
//   Filter to documents that HAVE a verified_at, then compute average
//   minutes between uploaded_at and verification.verified_at, grouped
//   by office_code.
// ---------------------------------------------------------------------
print("\n##### Aggregation 2 — avg verification time per office (minutes) #####");

const agg2 = [
  { $match: { "verification.verified_at": { $exists: true, $ne: null } } },
  { $addFields: {
      verification_minutes: {
        $divide: [
          { $subtract: ["$verification.verified_at", "$uploaded_at"] },
          60 * 1000     // ms -> minutes
        ]
      }
  }},
  { $group: {
      _id: "$office_code",
      avg_minutes:     { $avg: "$verification_minutes" },
      min_minutes:     { $min: "$verification_minutes" },
      max_minutes:     { $max: "$verification_minutes" },
      verified_count:  { $sum: 1 }
  }},
  { $sort: { avg_minutes: -1 } },
  { $project: {
      _id: 0, office_code: "$_id",
      avg_minutes: { $round: ["$avg_minutes", 2] },
      min_minutes: { $round: ["$min_minutes", 2] },
      max_minutes: { $round: ["$max_minutes", 2] },
      verified_count: 1
  }}
];

const result2 = db.documents.aggregate(agg2).toArray();
printjson(result2);

// paste the real output here:
// [paste real output here]

// ---------------------------------------------------------------------
// Index demo — COLLSCAN -> IXSCAN
//
// Query: "find all documents uploaded at LGW-IKO in the last 30 days".
// Without an index on (office_code, uploaded_at) this is a COLLSCAN.
// With the index it becomes an IXSCAN.
// ---------------------------------------------------------------------
print("\n##### Index demo — COLLSCAN (no index) #####");

// drop any existing index on (office_code, uploaded_at) so the BEFORE
// plan is a true COLLSCAN
try { db.documents.dropIndex("office_uploaded_idx"); } catch (e) { print("  (no index to drop)"); }

const query = {
  office_code: "LGW-IKO",
  uploaded_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) }
};

// BEFORE — no index
const explainBefore = db.documents.find(query).explain("executionStats");
print("BEFORE plan (top level):");
printjson(explainBefore.executionStats);
print("  winningPlan.stage = " +
  (explainBefore.queryPlanner.winningPlan.stage || "unknown"));

// paste the real BEFORE explain here:
// [paste real EXPLAIN here]

// create the index
db.documents.createIndex({ office_code: 1, uploaded_at: -1 }, { name: "office_uploaded_idx" });
print("\n  created index office_uploaded_idx on (office_code:1, uploaded_at:-1)");

// AFTER — with index
const explainAfter = db.documents.find(query).explain("executionStats");
print("\n##### Index demo — IXSCAN (with index) #####");
print("AFTER plan (top level):");
printjson(explainAfter.executionStats);

// walk the plan to find the IXSCAN stage
function findStage(plan, name) {
  if (!plan) return null;
  if (plan.stage === name) return plan;
  if (plan.inputStage)     return findStage(plan.inputStage, name);
  if (plan.inputStages)    for (var s of plan.inputStages) { var r = findStage(s, name); if (r) return r; }
  return null;
}
const ixscan = findStage(explainAfter.queryPlanner.winningPlan, "IXSCAN");
const collscan = findStage(explainBefore.queryPlanner.winningPlan, "COLLSCAN");
print("  BEFORE winningPlan stage = " + (collscan ? "COLLSCAN" :
        explainBefore.queryPlanner.winningPlan.stage));
print("  AFTER  winningPlan stage = " + (ixscan  ? "IXSCAN"  :
        explainAfter.queryPlanner.winningPlan.stage));
print("  BEFORE totalDocsExamined = " + explainBefore.executionStats.totalDocsExamined);
print("  AFTER  totalDocsExamined = " + explainAfter.executionStats.totalDocsExamined);
print("  BEFORE executionTimeMillis = " + explainBefore.executionStats.executionTimeMillis);
print("  AFTER  executionTimeMillis = " + explainAfter.executionStats.executionTimeMillis);

// paste the real AFTER explain here:
// [paste real EXPLAIN here]

print("\n====================================================================");
print(" Done. Paste every result block above into the matching");
print(" [paste real output here] / [paste real EXPLAIN here] placeholder");
print(" in the final PDF (or in this file, after the relevant printjson).");
print("====================================================================");
