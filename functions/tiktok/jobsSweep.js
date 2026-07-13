const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const { JOBS_COLLECTION } = require("./dispatch");
const { fetchAndResolveStatus } = require("./resolve");

const JOBS_PER_RUN_LIMIT = 25;
const MAX_CONCURRENT_CONNECTIONS = 5; // caps how many connections' Fetch Status calls run in parallel per sweep tick

function db() {
  return admin.firestore();
}

function groupByConnection(docs) {
  const groups = new Map();
  for (const doc of docs) {
    const connectionId = doc.data().connectionId || "unknown";
    if (!groups.has(connectionId)) groups.set(connectionId, []);
    groups.get(connectionId).push(doc.id);
  }
  return [...groups.values()];
}

function chunk(array, size) {
  const out = [];
  for (let i = 0; i < array.length; i += size) out.push(array.slice(i, i + size));
  return out;
}

// Jobs belonging to the SAME TikTok connection are processed sequentially
// (respecting that connection's own rate limit — TikTok documents 30
// requests/minute per user access_token for the status-fetch endpoint).
// Different connections are independent rate-limit buckets on TikTok's side,
// so their groups run concurrently, bounded by MAX_CONCURRENT_CONNECTIONS.
async function processConnectionGroup(jobIds) {
  for (const jobId of jobIds) {
    try {
      await fetchAndResolveStatus(jobId);
    } catch (error) {
      logger.error("TikTok publish job sweep failed for one job", {
        jobId,
        message: error.message || String(error),
      });
    }
  }
}

// One unified sweep does both jobs the approved design called for two
// functions to do: staged fast-lane polling (because nextPollAt is set to
// 30s/1m/2m/5m out by resolve.js's scheduleNextPoll, this sweep catches a
// freshly-accepted job on its very next 1-minute tick) AND the 15-minute+
// reconciliation safety net (because nextPollAt keeps advancing for
// long-processing jobs, and this sweep never stops checking). A webhook
// firing just short-circuits the wait; it does not replace this sweep.
//
// Overlap safety: fetchAndResolveStatus() claims each job transactionally
// (see resolve.js's claimJobForProcessing) before touching it, so if one
// sweep invocation is still running when the next scheduled tick fires,
// they cannot both process the same job.
const tiktokPublishJobsSweep = onSchedule(
  { schedule: "every 1 minutes", region: "asia-south1" },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db()
      .collection(JOBS_COLLECTION)
      .where("status", "==", "accepted_processing")
      .where("nextPollAt", "<=", now)
      .limit(JOBS_PER_RUN_LIMIT)
      .get();

    if (snap.empty) return;

    const connectionGroups = groupByConnection(snap.docs);

    for (const batch of chunk(connectionGroups, MAX_CONCURRENT_CONNECTIONS)) {
      await Promise.all(batch.map((jobIds) => processConnectionGroup(jobIds)));
    }
  }
);

module.exports = { tiktokPublishJobsSweep };
