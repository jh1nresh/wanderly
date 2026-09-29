import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";

const maxBodyBytes = 64_000;
const defaultModel = "gemini-3.5-flash";
const allowedTiers = new Set(["source_only", "weak", "likely", "corroborated"]);

export function createEvidenceRubricServer(env = process.env, fetchImpl = fetch) {
  const token = env.SAVE_EVIDENCE_RUBRIC_TOKEN?.trim();
  const geminiKey = env.GEMINI_API_KEY?.trim();
  const model = env.GEMINI_MODEL?.trim() || defaultModel;

  return createServer(async (request, response) => {
    try {
      if (request.method === "GET" && request.url === "/health") {
        return sendJson(response, {
          ready: Boolean(token && geminiKey),
          tokenConfigured: Boolean(token),
          geminiConfigured: Boolean(geminiKey),
          model,
        }, token && geminiKey ? 200 : 503);
      }

      const requestURL = new URL(request.url ?? "/", "http://localhost");
      if (request.method !== "POST" || requestURL.pathname !== "/rubric") {
        return sendJson(response, { error: "Not found" }, 404);
      }
      if (!token || !geminiKey) {
        return sendJson(response, { error: "Rubric service is not configured" }, 503);
      }
      if (!validBearer(request.headers.authorization, token)) {
        return sendJson(response, { error: "Unauthorized" }, 401);
      }

      const input = await readJson(request, maxBodyBytes);
      const verdict = await evaluateRubric(input, { geminiKey, model, fetchImpl });
      return sendJson(response, verdict);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      const status = message.includes("too large") ? 413 : 502;
      return sendJson(response, { error: message }, status);
    }
  });
}

export async function evaluateRubric(input, { geminiKey, model = defaultModel, fetchImpl = fetch }) {
  const url = new URL(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`);
  url.searchParams.set("key", geminiKey);
  const response = await fetchImpl(url.toString(), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{
            text: [
              "You are SAV-E's evidence rubric evaluator for place source recovery.",
              "Return only a conservative JSON verdict.",
              "Do not invent addresses, coordinates, place IDs, or facts not present in the supplied evidence.",
              "Use corroborated only when cited evidence already includes verified address and coordinates.",
              "Use likely when source/search/media evidence supports a venue and address but coordinates still need verification.",
              "Use weak when there are place-bearing clues but insufficient proof for map-ready saving.",
              "Use source_only when no reliable place evidence is present.",
              "",
              "Input projection:",
              JSON.stringify(input).slice(0, maxBodyBytes),
            ].join(" "),
          }],
        },
      ],
      generationConfig: {
        temperature: 0,
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          additionalProperties: false,
          required: ["evidence_tier", "confidence_reason", "missing_info"],
          properties: {
            evidence_tier: {
              type: "string",
              enum: ["source_only", "weak", "likely", "corroborated"],
            },
            confidence_reason: {
              type: "string",
              maxLength: 500,
            },
            missing_info: {
              type: "array",
              maxItems: 12,
              items: {
                type: "string",
                maxLength: 120,
              },
            },
          },
        },
      },
      systemInstruction: {
        parts: [{
          text: [
            "You are SAV-E's evidence rubric evaluator for place source recovery.",
            "Return strict JSON matching the requested schema.",
            "Never invent facts beyond supplied evidence.",
          ].join(" "),
        }],
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`Gemini rubric request failed: ${response.status}`);
  }
  const body = await response.json();
  const rawContent = body?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof rawContent !== "string") {
    throw new Error("Gemini rubric response was missing content");
  }
  const parsed = JSON.parse(rawContent);
  return normalizeVerdict(parsed);
}

function normalizeVerdict(value) {
  if (!value || typeof value !== "object") throw new Error("Invalid rubric verdict");
  const tier = value.evidence_tier;
  if (!allowedTiers.has(tier)) throw new Error("Invalid rubric evidence_tier");
  const reason = String(value.confidence_reason ?? "").replace(/\s+/g, " ").trim();
  if (!reason) throw new Error("Invalid rubric confidence_reason");
  const missing = Array.isArray(value.missing_info) ? value.missing_info : [];
  return {
    evidence_tier: tier,
    confidence_reason: reason.slice(0, 500),
    missing_info: [...new Set(missing.map((item) => String(item).replace(/\s+/g, " ").trim()).filter(Boolean))].slice(0, 12),
  };
}

function validBearer(header, expected) {
  if (!header?.startsWith("Bearer ")) return false;
  const actual = header.slice("Bearer ".length);
  const actualBytes = Buffer.from(actual);
  const expectedBytes = Buffer.from(expected);
  return actualBytes.length === expectedBytes.length && timingSafeEqual(actualBytes, expectedBytes);
}

async function readJson(request, maxBytes) {
  const chunks = [];
  let byteLength = 0;
  for await (const chunk of request) {
    byteLength += chunk.byteLength;
    if (byteLength > maxBytes) throw new Error("Request body too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function sendJson(response, body, status = 200) {
  response.writeHead(status, {
    "content-type": "application/json",
  });
  response.end(JSON.stringify(body));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT ?? 3000);
  createEvidenceRubricServer().listen(port, () => {
    console.log(`SAV-E evidence rubric service listening on ${port}`);
  });
}
