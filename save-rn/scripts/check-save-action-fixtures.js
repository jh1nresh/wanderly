#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const fixtureDir = path.join(repoRoot, "fixtures", "save-actions");
const fixtures = fs
  .readdirSync(fixtureDir)
  .filter((file) => file.endsWith(".json"))
  .sort();

assert.deepEqual(fixtures, [
  "reservation-receipt.future.json",
  "restaurant-availability-quote.available.json",
  "restaurant-availability-quote.needs-handoff.json",
]);

const docs = new Map(
  fixtures.map((file) => [
    file,
    JSON.parse(fs.readFileSync(path.join(fixtureDir, file), "utf8")),
  ])
);

const quotes = [...docs.entries()].filter(([, doc]) => doc.schema === "reservation.quote.v0");
assert.equal(quotes.length, 2, "expected two reservation.quote.v0 fixtures");

for (const [file, quote] of quotes) {
  assert.match(quote.id, /^quote_/, `${file}: quote id prefix`);
  assert.match(quote.cardId, /^save_/, `${file}: card id prefix`);
  assert.equal(quote.capability, "SLR.restaurants.search_availability", `${file}: capability`);
  assert.equal(quote.riskLevel, "quote", `${file}: quote riskLevel`);
  assert.equal(quote.sideEffect, false, `${file}: quote must not have side effects`);
  assert.equal(quote.agentToolCallTrace?.table, "agent_tool_calls", `${file}: trace table`);
  assert.equal(quote.agentToolCallTrace?.autoBook, false, `${file}: autoBook must be false`);
  assert.ok(["available", "unavailable", "needs_handoff", "error", "unknown"].includes(quote.status), `${file}: status`);
  assert.ok(Array.isArray(quote.options), `${file}: options`);
}

const receipt = docs.get("reservation-receipt.future.json");
assert.equal(receipt.schema, "reservation.receipt.v0", "receipt schema");
assert.match(receipt.id, /^res_/, "receipt id prefix");
assert.match(receipt.cardId, /^save_/, "receipt card id prefix");
assert.match(receipt.quoteId, /^quote_/, "receipt quote id prefix");
assert.ok(["hold", "purchase"].includes(receipt.riskLevel), "receipt riskLevel");
assert.equal(receipt.sideEffect, true, "receipt sideEffect");
assert.equal(receipt.userConfirmed, true, "receipt userConfirmed");
assert.equal(receipt.executionBoundary?.fixtureOnly, true, "receipt must be fixture-only");
assert.equal(receipt.executionBoundary?.externalBookingApiCalled, false, "receipt must not call booking APIs");
assert.equal(receipt.executionBoundary?.paymentApiCalled, false, "receipt must not call payment APIs");

console.log(`Validated ${fixtures.length} save action fixtures.`);
