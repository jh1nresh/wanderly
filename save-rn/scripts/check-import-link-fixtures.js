#!/usr/bin/env node

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "save-import-link-"));

execFileSync(
  path.join(repoRoot, "node_modules", ".bin", "tsc"),
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
    path.join(repoRoot, "src", "models.ts"),
    path.join(repoRoot, "src", "importLink.ts"),
  ],
  { stdio: "inherit" }
);

const { parseSharedLink } = require(path.join(outDir, "importLink.js"));

const fixtures = [
  {
    name: "instagram reel stays review draft",
    url: "https://www.instagram.com/reel/DWfT8pUpMlv/?igsh=NTc4MTIwNjQ2YQ==",
    expected: {
      sourcePlatform: "instagram",
      importKind: "draft",
      latitude: 0,
      longitude: 0,
    },
  },
  {
    name: "instagram reel with base64-style igsh stays review draft",
    url: "https://www.instagram.com/reel/DU3WPMpE1zE/?igsh=NTc4MTIwNjQ2YQ==",
    expected: {
      sourcePlatform: "instagram",
      importKind: "draft",
      latitude: 0,
      longitude: 0,
    },
  },
  {
    name: "google maps with explicit coordinates can save as place",
    url: "https://www.google.com/maps/place/Ulaman+Bali/@-8.5929653,115.1305649,17z",
    expected: {
      sourcePlatform: "googleMaps",
      importKind: "place",
      latitude: -8.5929653,
      longitude: 115.1305649,
    },
  },
  {
    name: "apple maps with q address and ll can save as place",
    url: "https://maps.apple.com/?address=317%20S%20Broadway,%20Los%20Angeles,%20CA%2090013,%20United%20States&auid=123&ll=34.050536,-118.248981&lsp=9902&q=Grand%20Central%20Market",
    expected: {
      sourcePlatform: "appleMaps",
      importKind: "place",
      latitude: 34.050536,
      longitude: -118.248981,
    },
  },
  {
    name: "apple maps place route with name and coordinate can save as place",
    url: "Check out Grand Central Market https://maps.apple.com/place?address=317%20S%20Broadway,%20Los%20Angeles,%20CA%2090013&coordinate=34.050536,-118.248981&name=Grand%20Central%20Market",
    expected: {
      sourcePlatform: "appleMaps",
      importKind: "place",
      latitude: 34.050536,
      longitude: -118.248981,
      name: "Grand Central Market",
    },
  },
  {
    name: "luma event stays unresolved candidate",
    url: "https://lu.ma/save-agent-dinner-at-riverside-hall",
    expected: {
      sourcePlatform: "luma",
      importKind: "event",
      latitude: 0,
      longitude: 0,
    },
  },
  {
    name: "generic article stays unresolved draft",
    url: "https://example.com/best-hidden-restaurants-in-bali",
    expected: {
      sourcePlatform: "other",
      importKind: "draft",
      latitude: 0,
      longitude: 0,
    },
  },
];

for (const fixture of fixtures) {
  const parsed = parseSharedLink(fixture.url);
  assert.ok(parsed, `${fixture.name}: expected parser result`);

  for (const [key, expectedValue] of Object.entries(fixture.expected)) {
    assert.equal(parsed[key], expectedValue, `${fixture.name}: ${key}`);
  }
}

console.log(`Validated ${fixtures.length} import link fixtures.`);
