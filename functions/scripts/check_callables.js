/**
 * Post-deploy smoke check: every callable must be reachable by the Firebase SDK.
 *
 * Callables need `allUsers` → Cloud Run Invoker on their service. firebase-tools
 * grants it only when a function is first created and never re-applies it on
 * later deploys, so if it goes missing the client just sees UNAUTHENTICATED
 * (Google's front end answers 403 before our code runs).
 *
 * This sends each callable an unauthenticated, empty request. A healthy one
 * reaches our code and answers with its own JSON `{"error": ...}` (we throw
 * "Must be signed in."); a broken one returns Google's HTML 403 page.
 * Nothing is executed beyond the request.auth check.
 *
 * Usage (from functions/): npm run check:callables
 * Fix a failure: Cloud Console → Cloud Run → <service> → Security →
 *   "Allow unauthenticated invocations".
 */

"use strict";

const PROJECT_ID = "jukebox-996de";

async function main() {
  const fns = require("../index.js");
  const callables = Object.entries(fns)
    .filter(([, f]) => f && f.__endpoint && f.__endpoint.callableTrigger)
    .map(([name, f]) => ({ name, region: (f.__endpoint.region || ["us-central1"])[0] }));

  let broken = 0;
  for (const { name, region } of callables) {
    const url = `https://${region}-${PROJECT_ID}.cloudfunctions.net/${name}`;
    let verdict;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ data: {} }),
        signal: AbortSignal.timeout(30000),
      });
      const body = await res.text();
      const reachedOurCode = body.trimStart().startsWith("{") && body.includes('"error"');
      verdict = reachedOurCode ? "ok" : `NOT REACHABLE (HTTP ${res.status})`;
    } catch (e) {
      verdict = `REQUEST FAILED (${e.message})`;
    }
    if (verdict !== "ok") broken++;
    console.log(`${verdict === "ok" ? "✓" : "✗"} ${name.padEnd(24)} ${verdict}`);
  }

  if (broken) {
    console.error(
      `\n${broken} callable(s) unreachable. Grant allUsers the Cloud Run Invoker role:\n` +
      "Cloud Console → Cloud Run → <service> → Security → Allow unauthenticated invocations."
    );
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
