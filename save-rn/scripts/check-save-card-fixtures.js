#!/usr/bin/env node

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const rnRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(rnRoot, "..");
const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "save-card-fixtures-"));

execFileSync(
  path.join(rnRoot, "node_modules", ".bin", "tsc"),
  [
    "--target",
    "ES2022",
    "--module",
    "commonjs",
    "--moduleResolution",
    "node",
    "--skipLibCheck",
    "--outDir",
    outDir,
    path.join(rnRoot, "src", "saveCard.ts"),
  ],
  { stdio: "inherit" }
);

const { validateSaveCard } = require(path.join(outDir, "saveCard.js"));
const fixtureDir = path.join(repoRoot, "fixtures", "save-cards");
const fixtures = fs
  .readdirSync(fixtureDir)
  .filter((file) => file.endsWith(".card.json"))
  .sort();

assert.ok(fixtures.length >= 3, "expected at least three save card fixtures");

const cards = fixtures.map((file) => {
  const card = validateSaveCard(JSON.parse(fs.readFileSync(path.join(fixtureDir, file), "utf8")));
  assert.equal(card.visibility, "private", `${file}: fixtures must start private`);
  return { file, card };
});

assert.ok(
  cards.some(({ card }) => card.source.kind === "instagram" && card.places.some((place) => place.status === "review_candidate")),
  "expected an Instagram review_candidate fixture"
);
assert.ok(
  cards.some(({ card }) => card.source.kind === "luma" && card.redactions.length > 0),
  "expected a Luma fixture with redactions"
);
assert.ok(
  cards.some(({ card }) =>
    card.source.kind === "google_maps" &&
    card.places.some((place) => place.status === "confirmed_place" && place.geo)
  ),
  "expected a Google Maps confirmed_place fixture with coordinates"
);

console.log(`Validated ${fixtures.length} save.card.v0 fixtures.`);
