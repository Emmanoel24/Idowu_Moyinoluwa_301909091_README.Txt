// =====================================================================
// index_demo.js — focused COLLSCAN -> IXSCAN demo for Portfolio 4
// Student : Moyinoluwa Emmanuel Idowu  · Matric: 2026/A/MIT/0077
//
// Same query as in aggregations.js, isolated for clarity and for the
// screenshot. Drops the index, runs explain("executionStats") — that's
// the BEFORE (COLLSCAN). Recreates the index, runs explain again —
// that's the AFTER (IXSCAN). Prints a tiny summary table at the end.
// =====================================================================

db = db.getSiblingDB("passpoint");   // ("use" is a shell helper and cannot be used inside a script file)

print("====================================================================");
print(" PassPoint index demo — COLLSCAN -> IXSCAN");
print(" collection: passpoint.documents");
print("====================================================================");

const query = {
  office_code: "LGW-IKO",
  uploaded_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) }
};

// --- BEFORE ----------------------------------------------------------
try { db.documents.dropIndex("office_uploaded_idx"); } catch (e) { print("  (no index to drop yet)"); }

print("\n--- BEFORE: no index on (office_code, uploaded_at) ---");
const before = db.documents.find(query).explain("executionStats");
printjson(before.queryPlanner.winningPlan);
print("  totalDocsExamined = " + before.executionStats.totalDocsExamined);
print("  executionTimeMillis = " + before.executionStats.executionTimeMillis);
print("  nReturned = " + before.executionStats.nReturned);

// [paste real EXPLAIN here]

// --- create the index ------------------------------------------------
db.documents.createIndex({ office_code: 1, uploaded_at: -1 }, { name: "office_uploaded_idx" });
print("\n  created index office_uploaded_idx on (office_code:1, uploaded_at:-1)");

// --- AFTER -----------------------------------------------------------
print("\n--- AFTER: with index office_uploaded_idx ---");
const after = db.documents.find(query).explain("executionStats");
printjson(after.queryPlanner.winningPlan);
print("  totalDocsExamined = " + after.executionStats.totalDocsExamined);
print("  executionTimeMillis = " + after.executionStats.executionTimeMillis);
print("  nReturned = " + after.executionStats.nReturned);

// [paste real EXPLAIN here]

// --- summary ---------------------------------------------------------
print("\n========================= SUMMARY ==================================");
print("                  stage          totalDocsExamined   executionTimeMillis");
function pickStage(plan) {
  const names = ["IXSCAN","COLLSCAN","FETCH"];
  function walk(p) {
    if (!p) return "?";
    if (names.includes(p.stage)) return p.stage;
    if (p.inputStage)  return walk(p.inputStage);
    if (p.inputStages) return walk(p.inputStages[0]);
    return p.stage || "?";
  }
  return walk(plan);
}
print("  BEFORE   " + pickStage(before.queryPlanner.winningPlan).padEnd(15) +
      String(before.executionStats.totalDocsExamined).padStart(15) +
      String(before.executionStats.executionTimeMillis).padStart(18));
print("  AFTER    " + pickStage(after.queryPlanner.winningPlan).padEnd(15) +
      String(after.executionStats.totalDocsExamined).padStart(15) +
      String(after.executionStats.executionTimeMillis).padStart(18));
print("====================================================================");
