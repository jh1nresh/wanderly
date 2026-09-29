import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomBytes, createHash } from "node:crypto";
import { importSPKI, jwtVerify, type JWTPayload, type KeyLike } from "jose";
import pg, { type PoolClient } from "pg";
import { createGuestSession, userIdFromGuestSessionToken } from "./guestSessions.js";
import {
  buildMaatPlaceAnalysis,
  buildPublicPlaceCard,
  buildTrustSummary,
  formatPlaceClaim,
  normalizePlaceClaimCreate,
  normalizeRecommendationRequest,
  normalizeUsageReceiptCreate,
  parseProofLevel,
  proofLevelsAtLeast,
  recommendPlacesByClaims,
} from "./placeClaims.js";
import { enrichMaatPlaceAnalysisWithPublicWeb } from "./maatPublicWebAnalysis.js";
import { runSourceSearchRecovery, type SourceSearchCandidate } from "./sourceSearchWorker.js";
import { buildClearingBlockDraft } from "./clearingBlocks.js";
import {
  formatSharedPlaceLink,
  normalizeSharedPlaceLinkCreate,
} from "./shareLinks.js";
import {
  normalizeFollowRequest,
  normalizeVisibilityRequest,
  parseLens,
} from "./socialContracts.js";
import {
  normalizePlaceRecoveryWorkOrderCreate,
  normalizePlaceRecoveryRunCreate,
  normalizePlaceRecoveryWorkerResult,
  normalizeUserDecision,
  placeRecoveryWorkflowId,
  receiptForResult,
} from "./workflowContracts.js";
import {
  buildRecommendationAnalysisReceiptDraft,
  envelopeForRecommendationAnalysisReceipt,
  normalizeRecommendationAnalysisReceiptPayload,
  RecommendationAnalysisReceiptPayloadError,
  recommendationAnalysisReceiptPayloadMaxBytes,
} from "./receiptEnvelope.js";
import { readSourceRecoveryConfigStatus } from "./sourceRecoveryConfig.js";

type JsonBody = Record<string, unknown>;
type QueryValue = string | number | boolean | Date | string[] | JsonBody | JsonBody[] | null;

const { Pool } = pg;

const databaseUrl = requireEnv("DATABASE_URL");
const privyAppId = requireEnv("PRIVY_APP_ID");
const privyVerificationKey = requireEnv("PRIVY_VERIFICATION_KEY");
const guestSessionSecret = process.env.SAVE_GUEST_SESSION_SECRET?.trim() || randomBytes(32).toString("hex");
const defaultJsonBodyMaxBytes = 256 * 1024;
const geminiProxyRequestMaxBytes = 64 * 1024;
const geminiProxyResponseMaxBytes = 512 * 1024;

const pool = new Pool({
  connectionString: databaseUrl,
  ssl: databaseSSLConfig(databaseUrl),
});

let verificationKeyPromise: Promise<KeyLike> | undefined;

const placeFields = [
  "id",
  "name",
  "address",
  "latitude",
  "longitude",
  "google_place_id",
  "category",
  "status",
  "rating",
  "note",
  "source_url",
  "source_platform",
  "source_image_url",
  "business_photo_urls",
  "extracted_dishes",
  "price_range",
  "recommender",
  "google_rating",
  "google_price_level",
  "opening_hours",
  "created_at",
] as const;

const tripFields = [
  "id",
  "name",
  "city",
  "start_date",
  "end_date",
  "is_optimized",
  "created_at",
] as const;

const tripStopFields = [
  "id",
  "place_id",
  "place_name",
  "day",
  "order_index",
  "start_time",
  "duration",
  "note",
] as const;

const profileFields = ["display_name", "avatar_url", "handle", "referral_code"] as const;

const captureFields = [
  "id",
  "source_type",
  "source_url",
  "raw_text",
  "title",
  "status",
  "created_at",
] as const;

const placeCandidateFields = [
  "id",
  "capture_id",
  "workflow_run_id",
  "place_id",
  "name",
  "address",
  "city",
  "latitude",
  "longitude",
  "evidence",
  "confidence",
  "missing_info",
  "status",
  "created_at",
] as const;

const placeClaimFields = [
  "id",
  "place_id",
  "claim_type",
  "claim",
  "agent_usable_summary",
  "author_type",
  "author_public_handle",
  "author_relationship",
  "proof_level",
  "evidence_refs",
  "visibility",
  "confidence",
  "context",
  "ratings",
  "observed_at",
  "expires_or_stale_after",
  "created_at",
] as const;

const claimUsageReceiptFields = [
  "id",
  "claim_id",
  "place_id",
  "consumer_agent_id",
  "consumer_user_id",
  "action",
  "outcome",
  "created_at",
] as const;

const recommendationAnalysisReceiptFields = [
  "id",
  "user_id",
  "product",
  "receipt_type",
  "agent_id",
  "capability",
  "input_hash",
  "output_hash",
  "private_payload_ref",
  "private_payload",
  "public_summary",
  "preference_signals",
  "evaluator_verdict",
  "settlement_state",
  "created_at",
] as const;

const agentDecisionFields = [
  "id",
  "candidate_id",
  "action",
  "reason",
  "created_at",
] as const;

const agentCapabilityFields = [
  "id",
  "agent_family",
  "vertical",
  "action",
  "description",
  "risk_level",
  "input_schema",
  "output_schema",
  "enabled",
  "created_at",
] as const;

const agentToolCallFields = [
  "id",
  "capability_id",
  "capture_id",
  "recommendation_set_id",
  "input",
  "output",
  "status",
  "error",
  "created_at",
] as const;

const recommendationSetFields = [
  "id",
  "capture_id",
  "prompt",
  "summary",
  "context",
  "status",
  "created_at",
] as const;

const recommendationItemFields = [
  "id",
  "recommendation_set_id",
  "place_candidate_id",
  "place_id",
  "rank",
  "title",
  "rationale",
  "r8_score",
  "slr_status",
  "evidence",
  "created_at",
] as const;

const sharedPlaceLinkFields = [
  "code",
  "user_id",
  "source_place_id",
  "payload",
  "expires_at",
] as const;

const workflowRunFields = [
  "work_order_id",
  "workflow_id",
  "listing_id",
  "user_id",
  "source_url",
  "source_type",
  "status",
  "result_type",
  "confidence",
  "evidence_tier",
  "result_evidence_refs",
  "result_candidate_refs",
  "credit_reserved",
  "credit_settlement",
  "receipt_id",
  "completed_at",
] as const;

const workOrderFields = [
  "workflow_id",
  "listing_id",
  "user_id",
  "intent",
  "input_type",
  "input_ref",
  "source_url",
  "evaluator_policy_id",
  "settlement_mode",
  "budget_policy",
  "status",
] as const;

const userDecisionFields = [
  "run_id",
  "user_id",
  "action",
  "edited_payload",
  "reason",
] as const;

const workflowReceiptFields = [
  "run_id",
  "workflow_id",
  "verdict",
  "settlement",
  "evaluator_summary",
  "evidence_refs",
  "candidate_refs",
  "receipt_hash",
  "anchor_status",
  "private_url",
] as const;

const clearingBlockFields = [
  "chain_namespace",
  "user_id",
  "block_number",
  "previous_block_hash",
  "merkle_root",
  "receipt_count",
  "block_hash",
  "signer_agent_id",
  "anchor_status",
  "anchor_chain",
  "anchor_tx_hash",
] as const;

const clearingBlockItemFields = [
  "block_id",
  "receipt_id",
  "receipt_hash",
  "merkle_proof",
  "position",
] as const;

const creditLedgerFields = [
  "run_id",
  "user_id",
  "delta",
  "reason",
  "settlement",
] as const;

const jsonbFields = new Set([
  "context",
  "evidence",
  "edited_payload",
  "input",
  "input_schema",
  "budget_policy",
  "output",
  "output_schema",
  "payload",
  "private_payload",
  "public_summary",
  "ratings",
]);

createServer(async (request, response) => {
  if (request.method === "OPTIONS") {
    return sendJson(response, null, 204);
  }

  try {
    const url = new URL(request.url ?? "/", "http://localhost");
    if (request.method === "GET" && url.pathname === "/") {
      return sendJson(response, { ok: true, service: "save-backend" });
    }
    if (request.method === "GET" && url.pathname === "/health/source-recovery") {
      const status = await readSourceRecoveryConfigStatus();
      return sendJson(response, status, status.ready ? 200 : 503);
    }

    const rawSegments = url.pathname.split("/").filter(Boolean);
    const isPublicV0 = rawSegments[0] === "public" && rawSegments[1] === "v0";
    if (isPublicV0) {
      return await handlePublicV0(request, response, rawSegments.slice(2));
    }

    const isV0 = rawSegments[0] === "v0";
    const segments = isV0 ? rawSegments.slice(1) : rawSegments;
    const [resource, id] = segments;

    if (request.method === "GET" && resource === "referrals") {
      return await handleReferrals(request, response, id, url);
    }
    if (isV0 && request.method === "GET" && resource === "shared-place-links" && id) {
      return await handleSharedPlaceLinkPublic(response, id);
    }
    if (isV0 && request.method === "POST" && resource === "guest-sessions" && !id) {
      return sendJson(response, createGuestSession(guestSessionSecret), 201);
    }

    const userId = await resolveUserId(request);
    await ensureProfile(userId);

    if (isV0 && resource === "places" && id === "recommend-by-claims") {
      return await handleRecommendByClaims(request, response, userId);
    }
    if (isV0 && resource === "recommendation-analysis-receipts") {
      return await handleRecommendationAnalysisReceipts(request, response, userId);
    }
    if (isV0 && resource === "claims" && id === "usage-receipts") {
      return await handleAuthenticatedClaimUsageReceipts(request, response, userId);
    }
    if (isV0 && resource === "llm") {
      return await handleLLMProxy(request, response, segments.slice(1));
    }
    if (isV0 && resource === "places" && id && segments[2] === "verified-claims") {
      return await handlePlaceVerifiedClaims(request, response, id, url, userId);
    }
    if (isV0 && resource === "places" && id && segments[2] === "maat-analysis") {
      return await handlePlaceMaatAnalysis(request, response, id, url, userId);
    }
    if (isV0 && resource === "places" && id && segments[2] === "trust-summary") {
      return await handlePlaceTrustSummary(request, response, id, userId);
    }
    if (resource === "places" && id && segments[2] === "visibility") {
      return await handlePlaceVisibility(request, response, id, userId);
    }
    if (resource === "places") return await handlePlaces(request, response, id, userId);
    if (resource === "trips") return await handleTrips(request, response, id, userId);
    if (resource === "profile") return await handleProfile(request, response, userId);
    if (resource === "follows") return await handleFollows(request, response, userId);
    if (isV0 && resource === "shared-place-links") return await handleSharedPlaceLinks(request, response, id, userId);
    if (isV0 && resource === "workflows") return await handleWorkflows(request, response, segments.slice(1), userId);
    if (resource === "social" && id === "signals") return await handleSocialSignals(request, response, url, userId);
    if (resource === "memory") {
      return await handleMemory(request, response, segments.slice(1), url, userId);
    }
    if (resource === "agents") {
      return await handleAgents(request, response, segments.slice(1), url, userId);
    }

    return sendJson(response, { error: "Not found" }, 404);
  } catch (error) {
    const status = error instanceof ApiError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown error";
    return sendJson(response, { error: message }, status);
  }
}).listen(Number(process.env.PORT ?? 3000), () => {
  console.log(`SAV-E backend listening on ${process.env.PORT ?? 3000}`);
});

async function handlePlaces(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !placeId) {
    const rows = await fetchPlacesWithOptionalVisibility(userId);
    return sendJson(response, rows.map(formatPlace));
  }

  if (request.method === "POST" && !placeId) {
    const body = withOwner(await readJson(request), userId);
    const insert = buildInsert("places", body, [...placeFields, "user_id"]);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatPlace(rows[0]), 201);
  }

  if (request.method === "PATCH" && placeId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "created_at", "updated_at"]);
    const update = buildUpdate("places", body, placeFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, placeId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning *`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Place not found" }, 404);
    return sendJson(response, formatPlace(rows[0]));
  }

  if (request.method === "DELETE" && placeId) {
    const { rows } = await pool.query(
      "delete from places where id = $1 and user_id = $2 returning id",
      [placeId, userId],
    );
    if (!rows[0]) return sendJson(response, { error: "Place not found" }, 404);
    return sendJson(response, null, 204);
  }

  return sendJson(response, { error: "Unsupported places route" }, 405);
}

async function fetchPlacesWithOptionalVisibility(userId: string): Promise<JsonBody[]> {
  try {
    const { rows } = await pool.query(
      `select p.*, pv.visibility
       from places p
       left join place_visibility pv on pv.place_id = p.id
       where p.user_id = $1
       order by p.created_at desc`,
      [userId],
    );
    return rows;
  } catch (error) {
    if (!isMissingRelationError(error)) throw error;

    console.warn("place_visibility table is missing; returning places with private visibility fallback.");
    const { rows } = await pool.query(
      `select p.*, 'private' as visibility
       from places p
       where p.user_id = $1
       order by p.created_at desc`,
      [userId],
    );
    return rows;
  }
}

async function handlePublicV0(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
): Promise<void> {
  const [resource, id] = segments;

  if (resource === "cards" && id) {
    return await handlePublicPlaceCard(request, response, id);
  }
  if (resource === "claim-usage-receipts") {
    return await handlePublicClaimUsageReceipts(request, response);
  }

  return sendJson(response, { error: "Unsupported public v0 route" }, 404);
}

async function handlePublicPlaceCard(
  request: IncomingMessage,
  response: ServerResponse,
  cardId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported public card route" }, 405);

  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as public_visibility,
       owner.handle as owner_handle
     from places p
     join place_visibility pv on pv.place_id = p.id
     join profiles owner on owner.id = p.user_id
     where p.id = $1
       and pv.visibility in ('public_link', 'public_guide')
     limit 1`,
    [cardId],
  );
  if (!rows[0]) return sendJson(response, { error: "Public card not found" }, 404);

  const { rows: claims } = await pool.query(
    `select
       pc.*,
       coalesce(receipts.usage_count, 0)::int as usage_count,
       coalesce(receipts.accepted_count, 0)::int as accepted_count
     from place_claims pc
     left join (
       select
         claim_id,
         count(*)::int as usage_count,
         count(*) filter (where outcome = 'accepted')::int as accepted_count
       from claim_usage_receipts
       group by claim_id
     ) receipts on receipts.claim_id = pc.id
     where pc.place_id = $1
       and pc.visibility in ('public', 'link_shared')
       and (pc.expires_or_stale_after is null or pc.expires_or_stale_after >= now())
     order by pc.created_at desc`,
    [cardId],
  );

  return sendJson(response, buildPublicPlaceCard(formatDates(rows[0]), claims.map((claim) => formatDates(claim))));
}

async function handlePublicClaimUsageReceipts(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported usage receipt route" }, 405);

  let body: JsonBody;
  try {
    body = normalizeUsageReceiptCreate(await readJson(request));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid usage receipt";
    return sendJson(response, { error: message }, 400);
  }

  const claim = await publicClaimForReceipt(String(body.claim_id));
  body.place_id = claim.place_id;
  const insert = buildInsert("claim_usage_receipts", body, claimUsageReceiptFields);
  const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
  return sendJson(response, formatDates(rows[0]), 201);
}

async function handleAuthenticatedClaimUsageReceipts(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported usage receipt route" }, 405);

  let body: JsonBody;
  try {
    body = normalizeUsageReceiptCreate(await readJson(request));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid usage receipt";
    return sendJson(response, { error: message }, 400);
  }

  const claim = await ownedClaimForReceipt(String(body.claim_id), userId);
  body.place_id = claim.place_id;
  body.consumer_user_id = userId;
  const insert = buildInsert("claim_usage_receipts", body, claimUsageReceiptFields);
  const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
  return sendJson(response, formatDates(rows[0]), 201);
}

async function handlePlaceVerifiedClaims(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  url: URL,
  userId: string,
): Promise<void> {
  await ensureOwnedPlaceReference(placeId, userId);

  if (request.method === "GET") {
    const includePrivateEvidence = url.searchParams.get("includePrivateEvidence") === "true" ||
      url.searchParams.get("include_private_evidence") === "true";
    const claims = await placeClaimsForPlace(placeId, userId, {
      proofLevelMin: url.searchParams.get("proofLevelMin") ?? url.searchParams.get("proof_level_min"),
      claimType: url.searchParams.get("claimType") ?? url.searchParams.get("claim_type"),
      visibility: url.searchParams.get("visibility"),
      relationship: url.searchParams.get("relationship"),
      freshness: url.searchParams.get("freshness"),
    });

    return sendJson(response, {
      place_id: placeId,
      claims: claims.map((claim) => formatPlaceClaim(formatDates(claim), includePrivateEvidence)),
    });
  }

  if (request.method === "POST") {
    let body: JsonBody;
    try {
      body = normalizePlaceClaimCreate(await readJson(request), placeId, userId);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid claim";
      return sendJson(response, { error: message }, 400);
    }

    const insert = buildInsert("place_claims", body, [...placeClaimFields, "user_id"]);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatPlaceClaim(formatDates(rows[0]), true), 201);
  }

  return sendJson(response, { error: "Unsupported verified claims route" }, 405);
}

async function handlePlaceMaatAnalysis(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported maat analysis route" }, 405);

  const place = await ownedPlaceForAnalysis(placeId, userId);
  const claims = await placeClaimsForPlace(placeId, userId);
  const includePrivateEvidence = url.searchParams.get("includePrivateEvidence") === "true" ||
    url.searchParams.get("include_private_evidence") === "true";
  const includePublicWeb = url.searchParams.get("includePublicWeb") === "true" ||
    url.searchParams.get("include_public_web") === "true";
  const maxCitedClaims = Number(url.searchParams.get("maxCitedClaims") ?? url.searchParams.get("max_cited_claims") ?? 3);
  const formattedClaims = claims.map((claim) => formatDates(claim));
  const analysis = buildMaatPlaceAnalysis(place, formattedClaims, {
    includePrivateEvidence,
    maxCitedClaims,
  });
  const enrichedAnalysis = includePublicWeb
    ? await enrichMaatPlaceAnalysisWithPublicWeb({
      place,
      claims: formattedClaims,
      analysis,
      includePrivateEvidence,
    })
    : analysis;
  return sendJson(response, enrichedAnalysis);
}

async function handlePlaceTrustSummary(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  userId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported trust summary route" }, 405);

  await ensureOwnedPlaceReference(placeId, userId);
  const claims = await placeClaimsForPlace(placeId, userId);
  return sendJson(response, buildTrustSummary(placeId, claims.map((claim) => formatDates(claim))));
}

async function handleRecommendByClaims(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported recommend-by-claims route" }, 405);

  const recommendationRequest = normalizeRecommendationRequest(await readJson(request));
  const proofLevels = proofLevelsAtLeast(recommendationRequest.proofLevelMin ?? "user_confirmed_place");
  const { rows } = await pool.query(
    `select
       pc.*,
       p.name as place_name,
       p.address as place_address,
       p.category as place_category,
       p.status as place_status,
       p.rating as place_rating,
       p.google_rating as place_google_rating,
       p.price_range as place_price_range,
       coalesce(receipts.usage_count, 0)::int as usage_count,
       coalesce(receipts.accepted_count, 0)::int as accepted_count
     from place_claims pc
     join places p on p.id = pc.place_id
     left join (
       select
         claim_id,
         count(*)::int as usage_count,
         count(*) filter (where outcome = 'accepted')::int as accepted_count
       from claim_usage_receipts
       group by claim_id
     ) receipts on receipts.claim_id = pc.id
     where pc.user_id = $1
       and p.user_id = $1
       and pc.proof_level = any($2::text[])
     order by pc.created_at desc
     limit 200`,
    [userId, proofLevels],
  );

  const recommendationOutput = recommendPlacesByClaims(rows.map((row) => formatDates(row)), recommendationRequest);
  const receiptDraft = buildRecommendationAnalysisReceiptDraft({
    userId,
    request: recommendationRequest as JsonBody,
    output: recommendationOutput,
  });
  const receiptInsert = buildInsert(
    "recommendation_analysis_receipts",
    receiptDraft,
    recommendationAnalysisReceiptFields,
  );
  const { rows: receiptRows } = await pool.query(`${receiptInsert.sql} returning *`, receiptInsert.values);

  return sendJson(response, {
    ...recommendationOutput,
    agent_shack_receipt_envelope: envelopeForRecommendationAnalysisReceipt(formatDates(receiptRows[0])),
  });
}

async function handleRecommendationAnalysisReceipts(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported recommendation analysis receipt route" }, 405);
  }

  const body = await readJson(request, recommendationAnalysisReceiptPayloadMaxBytes);
  let payload;
  try {
    payload = normalizeRecommendationAnalysisReceiptPayload(body);
  } catch (error) {
    if (error instanceof RecommendationAnalysisReceiptPayloadError) {
      const status = error.message.includes("too large") ? 413 : 400;
      return sendJson(response, { error: error.message }, status);
    }
    throw error;
  }
  const receiptDraft = buildRecommendationAnalysisReceiptDraft({
    userId,
    agentId: payload.agentId,
    request: payload.request,
    output: payload.output,
  });
  const receiptInsert = buildInsert(
    "recommendation_analysis_receipts",
    receiptDraft,
    recommendationAnalysisReceiptFields,
  );
  const { rows } = await pool.query(`${receiptInsert.sql} returning *`, receiptInsert.values);
  const row = formatDates(rows[0]);

  return sendJson(response, {
    id: row.id,
    envelope: envelopeForRecommendationAnalysisReceipt(row),
    full_payload_json: JSON.stringify(row.private_payload),
  }, 201);
}

async function handleLLMProxy(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
): Promise<void> {
  const [providerAction] = segments;
  if (providerAction !== "gemini-generate-content") {
    return sendJson(response, { error: "Unsupported LLM route" }, 404);
  }
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported LLM route" }, 405);
  }

  const apiKey = process.env.GEMINI_API_KEY ?? process.env.GOOGLE_GEMINI_API_KEY;
  if (!apiKey) throw new ApiError(503, "Gemini proxy is not configured");

  const body = await readJson(request, geminiProxyRequestMaxBytes);
  const model = geminiProxyModel(body.model);
  const geminiBody = geminiProxyBody(body);
  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": "SAV-E backend Gemini proxy/1.0",
      },
      body: JSON.stringify(geminiBody),
      redirect: "manual",
      signal: AbortSignal.timeout(20_000),
    },
  );

  if (upstream.status >= 300 && upstream.status < 400) {
    throw new ApiError(502, "Gemini proxy blocked redirect response");
  }
  const raw = await boundedResponseBuffer(upstream, geminiProxyResponseMaxBytes);
  if (!upstream.ok) {
    return sendJson(response, { error: "Gemini upstream request failed", status: upstream.status }, 502);
  }
  const parsed = JSON.parse(new TextDecoder().decode(raw));
  return sendJson(response, parsed);
}

function geminiProxyModel(value: unknown): string {
  const model = typeof value === "string" && value.trim() ? value.trim() : "gemini-3.5-flash";
  const allowed = new Set((process.env.SAVE_GEMINI_PROXY_MODELS ?? "gemini-3.5-flash")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean));
  if (!allowed.has(model)) throw new ApiError(400, "Unsupported Gemini model");
  return model;
}

function geminiProxyBody(body: JsonBody): JsonBody {
  const contents = body.contents;
  if (!Array.isArray(contents) || contents.length === 0) throw new ApiError(400, "contents is required");
  const result: JsonBody = { contents };
  if (body.generationConfig && typeof body.generationConfig === "object" && !Array.isArray(body.generationConfig)) {
    result.generationConfig = body.generationConfig as JsonBody;
  }
  if (body.systemInstruction && typeof body.systemInstruction === "object" && !Array.isArray(body.systemInstruction)) {
    result.systemInstruction = body.systemInstruction as JsonBody;
  }
  return result;
}

async function placeClaimsForPlace(
  placeId: string,
  userId: string,
  filters: {
    proofLevelMin?: string | null;
    claimType?: string | null;
    visibility?: string | null;
    relationship?: string | null;
    freshness?: string | null;
  } = {},
): Promise<JsonBody[]> {
  const values: QueryValue[] = [placeId, userId];
  const where = ["pc.place_id = $1", "pc.user_id = $2"];

  if (filters.proofLevelMin) {
    values.push(proofLevelsAtLeast(parseProofLevel(filters.proofLevelMin, "source_backed")));
    where.push(`pc.proof_level = any($${values.length}::text[])`);
  }
  if (filters.claimType) {
    values.push(filters.claimType);
    where.push(`pc.claim_type = $${values.length}`);
  }
  if (filters.visibility) {
    values.push(filters.visibility);
    where.push(`pc.visibility = $${values.length}`);
  }
  if (filters.relationship) {
    values.push(filters.relationship);
    where.push(`pc.author_relationship = $${values.length}`);
  }
  if (filters.freshness === "active") {
    where.push("(pc.expires_or_stale_after is null or pc.expires_or_stale_after >= now())");
  } else if (filters.freshness === "stale") {
    where.push("pc.expires_or_stale_after < now()");
  }

  const { rows } = await pool.query(
    `select
       pc.*,
       coalesce(receipts.usage_count, 0)::int as usage_count,
       coalesce(receipts.accepted_count, 0)::int as accepted_count
     from place_claims pc
     left join (
       select
         claim_id,
         count(*)::int as usage_count,
         count(*) filter (where outcome = 'accepted')::int as accepted_count
       from claim_usage_receipts
       group by claim_id
     ) receipts on receipts.claim_id = pc.id
     where ${where.join(" and ")}
     order by pc.created_at desc`,
    values,
  );
  return rows;
}

async function publicClaimForReceipt(claimId: string): Promise<JsonBody> {
  const { rows } = await pool.query(
    `select pc.id, pc.place_id
     from place_claims pc
     join place_visibility pv on pv.place_id = pc.place_id
     where pc.id = $1
       and pc.visibility in ('public', 'link_shared')
       and pv.visibility in ('public_link', 'public_guide')
     limit 1`,
    [claimId],
  );
  if (!rows[0]) throw new ApiError(404, "Public claim not found");
  return asObject(rows[0]);
}

async function ownedClaimForReceipt(claimId: string, userId: string): Promise<JsonBody> {
  const { rows } = await pool.query(
    "select id, place_id from place_claims where id = $1 and user_id = $2 limit 1",
    [claimId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Claim not found");
  return asObject(rows[0]);
}

async function handleTrips(
  request: IncomingMessage,
  response: ServerResponse,
  tripId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !tripId) {
    const { rows } = await pool.query(tripsSelect("where t.user_id = $1", "order by t.created_at desc"), [userId]);
    return sendJson(response, rows.map(formatTrip));
  }

  if (request.method === "POST" && !tripId) {
    const body = await readJson(request);
    const stops = Array.isArray(body.trip_stops) ? body.trip_stops.map(asObject) : [];
    const tripBody = withOwner(writableFields(body, ["trip_stops"]), userId);
    const client = await pool.connect();

    try {
      await client.query("begin");
      const insert = buildInsert("trips", tripBody, [...tripFields, "user_id"]);
      const { rows: tripRows } = await client.query(`${insert.sql} returning *`, insert.values);
      const trip = tripRows[0] as { id: string };

      for (const stop of stops) {
        const stopBody = { ...writableFields(stop, ["trip_id", "created_at"]), trip_id: trip.id };
        const stopInsert = buildInsert("trip_stops", stopBody, [...tripStopFields, "trip_id"]);
        await client.query(stopInsert.sql, stopInsert.values);
      }

      const { rows } = await client.query(tripsSelect("where t.id = $1 and t.user_id = $2"), [trip.id, userId]);
      await client.query("commit");
      return sendJson(response, formatTrip(rows[0]), 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  if (request.method === "PATCH" && tripId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "trip_stops", "created_at", "updated_at"]);
    const update = buildUpdate("trips", body, tripFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, tripId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning id`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Trip not found" }, 404);

    const { rows: trips } = await pool.query(tripsSelect("where t.id = $1 and t.user_id = $2"), [tripId, userId]);
    return sendJson(response, formatTrip(trips[0]));
  }

  if (request.method === "DELETE" && tripId) {
    const { rows } = await pool.query(
      "delete from trips where id = $1 and user_id = $2 returning id",
      [tripId, userId],
    );
    if (!rows[0]) return sendJson(response, { error: "Trip not found" }, 404);
    return sendJson(response, null, 204);
  }

  return sendJson(response, { error: "Unsupported trips route" }, 405);
}

async function handleProfile(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method === "GET") {
    const { rows } = await pool.query(
      `select
        p.*,
        (select count(*)::int from places where user_id = p.id) as saved_count,
        (select count(*)::int from places where user_id = p.id and status = 'visited') as visited_count,
        (select count(distinct city)::int from trips where user_id = p.id and city <> '') as cities_count
      from profiles p
      where p.id = $1`,
      [userId],
    );
    return sendJson(response, formatProfile(rows[0]));
  }

  if (request.method === "PATCH") {
    const body = pickFields(await readJson(request), profileFields);
    const update = buildUpdate("profiles", body, profileFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, userId];
    const { rows } = await pool.query(`${update.sql} where id = $${values.length} returning *`, values);
    return sendJson(response, formatProfile(rows[0]));
  }

  return sendJson(response, { error: "Unsupported profile route" }, 405);
}

async function handleFollows(
  request: IncomingMessage,
  response: ServerResponse,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") return sendJson(response, { error: "Unsupported follows route" }, 405);

  const followRequest = normalizeFollowRequest(await readJson(request));
  const target = await resolveFollowTarget(followRequest);
  const targetId = stringValue(target.id);
  if (!targetId) throw new ApiError(404, "Profile not found");
  if (targetId === userId) return sendJson(response, { error: "Cannot follow yourself" }, 400);

  const { rows } = await pool.query(
    `insert into follows (follower_id, following_id, lens, source, referral_code)
     values ($1, $2, $3, $4, $5)
     on conflict (follower_id, following_id) do update set
       lens = excluded.lens,
       source = excluded.source,
       referral_code = coalesce(excluded.referral_code, follows.referral_code)
     returning *`,
    [userId, targetId, followRequest.lens, followRequest.source, followRequest.referralCode ?? null],
  );

  return sendJson(response, {
    follow: formatFollow(rows[0]),
    profile: formatPublicProfile(target),
  }, 201);
}

async function handlePlaceVisibility(
  request: IncomingMessage,
  response: ServerResponse,
  placeId: string,
  userId: string,
): Promise<void> {
  if (request.method !== "PATCH") return sendJson(response, { error: "Unsupported place visibility route" }, 405);

  await ensureOwnedPlaceReference(placeId, userId);
  const visibility = normalizeVisibilityRequest(await readJson(request));
  const { rows } = await pool.query(
    `insert into place_visibility (
       place_id,
       user_id,
       visibility,
       allow_friend_signal,
       allow_trending_signal,
       published_at
     )
     values ($1, $2, $3, $4, $5, case when $3 = 'private' then null else now() end)
     on conflict (place_id) do update set
       visibility = excluded.visibility,
       allow_friend_signal = excluded.allow_friend_signal,
       allow_trending_signal = excluded.allow_trending_signal,
       published_at = case
         when excluded.visibility = 'private' then null
         when place_visibility.published_at is null then now()
         else place_visibility.published_at
       end
     returning *`,
    [
      placeId,
      userId,
      visibility.visibility,
      visibility.allowFriendSignal,
      visibility.allowTrendingSignal,
    ],
  );

  return sendJson(response, formatDates(rows[0]));
}

async function handleSharedPlaceLinkPublic(
  response: ServerResponse,
  code: string,
): Promise<void> {
  const { rows } = await pool.query(
    `select *
     from shared_place_links
     where code = $1
       and (expires_at is null or expires_at > now())
     limit 1`,
    [code],
  );
  if (!rows[0]) return sendJson(response, { error: "Shared place link not found" }, 404);
  return sendJson(response, formatSharedPlaceLink(formatDates(rows[0])));
}

async function handleSharedPlaceLinks(
  request: IncomingMessage,
  response: ServerResponse,
  code: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !code) {
    const { rows } = await pool.query(
      `select *
       from shared_place_links
       where user_id = $1
       order by created_at desc
       limit 100`,
      [userId],
    );
    return sendJson(response, rows.map((row) => formatSharedPlaceLink(formatDates(row))));
  }

  if (request.method === "POST" && !code) {
    let create;
    try {
      create = normalizeSharedPlaceLinkCreate(await readJson(request));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid shared place payload";
      return sendJson(response, { error: message }, 400);
    }

    await ensureOwnedPlaceReference(create.sourcePlaceId, userId);
    const body: JsonBody = {
      code: await uniqueShareCode(),
      user_id: userId,
      source_place_id: create.sourcePlaceId ?? null,
      payload: create.payload,
      expires_at: create.expiresAt ?? null,
    };
    const insert = buildInsert("shared_place_links", body, sharedPlaceLinkFields);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatSharedPlaceLink(formatDates(rows[0])), 201);
  }

  return sendJson(response, { error: "Unsupported shared place links route" }, 405);
}

async function handleWorkflows(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
  userId: string,
): Promise<void> {
  if (segments[0] !== "place-recovery") {
    return sendJson(response, { error: "Unsupported workflows route" }, 405);
  }

  const kind = segments[1];
  const id = segments[2];
  const action = segments[3];

  if (kind === "work-orders") {
    if (request.method === "GET" && !id) {
      const { rows } = await pool.query(
        `select *
         from work_orders
         where user_id = $1 and workflow_id = $2
         order by created_at desc
         limit 100`,
        [userId, placeRecoveryWorkflowId],
      );
      return sendJson(response, rows.map((row) => formatDates(row)));
    }

    if (request.method === "POST" && !id) {
      const workOrder = normalizePlaceRecoveryWorkOrderCreate(await readJson(request));
      const client = await pool.connect();
      try {
        const row = await createPlaceRecoveryWorkOrder(client, userId, workOrder);
        return sendJson(response, formatDates(row), 201);
      } finally {
        client.release();
      }
    }

    return sendJson(response, { error: "Unsupported work order route" }, 405);
  }

  if (kind === "clearing-blocks") {
    if (request.method === "GET" && id) {
      const block = await clearingBlockForUser(id, userId);
      const { rows: items } = await pool.query(
        `select receipt_id, receipt_hash, merkle_proof, position, created_at
         from clearing_block_items
         where block_id = $1
         order by position asc`,
        [id],
      );
      return sendJson(response, {
        block: formatDates(block),
        items: items.map((row) => formatDates(row)),
      });
    }

    if (request.method === "GET" && !id) {
      const { rows } = await pool.query(
        `select *
         from clearing_blocks
         where user_id = $1 and chain_namespace = $2
         order by block_number desc
         limit 100`,
        [userId, placeRecoveryWorkflowId],
      );
      return sendJson(response, rows.map((row) => formatDates(row)));
    }

    if (request.method === "POST" && !id) {
      const created = await createClearingBlockForPendingReceipts(userId, await readJson(request));
      return sendJson(response, created, created.created ? 201 : 200);
    }

    return sendJson(response, { error: "Unsupported clearing block route" }, 405);
  }

  if (kind !== "runs") {
    return sendJson(response, { error: "Unsupported workflows route" }, 405);
  }

  const runId = id;

  if (request.method === "GET" && !runId) {
    const { rows } = await pool.query(
      `select *
       from workflow_runs
       where user_id = $1 and workflow_id = $2
       order by created_at desc
       limit 100`,
      [userId, placeRecoveryWorkflowId],
    );
    return sendJson(response, rows.map((row) => formatDates(row)));
  }

  if (request.method === "POST" && !runId) {
    const body = await readJson(request);
    const run = normalizePlaceRecoveryRunCreate(body);
    const workOrder = normalizePlaceRecoveryWorkOrderCreate({
      ...body,
      source_url: run.sourceUrl,
      source_type: run.sourceType,
      credit_reserved: run.creditReserved,
    });
    const client = await pool.connect();
    try {
      await client.query("begin");
      const workOrderId = run.workOrderId
        ? await ensureWorkOrderOwner(run.workOrderId, userId, client)
        : String((await createPlaceRecoveryWorkOrder(client, userId, workOrder)).id);
      const insert = buildInsert("workflow_runs", {
        work_order_id: workOrderId,
        workflow_id: run.workflowId,
        listing_id: run.listingId,
        user_id: userId,
        source_url: run.sourceUrl ?? null,
        source_type: run.sourceType,
        status: "queued",
        credit_reserved: run.creditReserved,
        credit_settlement: "pending",
      }, workflowRunFields);
      const { rows } = await client.query(`${insert.sql} returning *`, insert.values);
      const created = asObject(rows[0]);
      await client.query("update work_orders set status = 'running' where id = $1 and user_id = $2", [workOrderId, userId]);
      await insertCreditLedger(client, {
        run_id: String(created.id),
        user_id: userId,
        delta: -run.creditReserved,
        reason: "reserve",
        settlement: "pending",
      });
      await client.query("commit");
      return sendJson(response, formatDates(created), 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  if (!runId) return sendJson(response, { error: "Workflow run is required" }, 400);
  await ensureWorkflowRunOwner(runId, userId);

  if (request.method === "POST" && action === "result") {
    const result = normalizePlaceRecoveryWorkerResult(await readJson(request));
    const status = result.resultType === "technical_failure"
      ? "failed"
      : result.resultType === "confirmed_map_stamp"
        ? "completed"
        : "needs_review";
    const { rows } = await pool.query(
      `update workflow_runs
       set status = $1,
           result_type = $2,
           confidence = $3,
           evidence_tier = $4,
           result_evidence_refs = $5,
           result_candidate_refs = $6,
           completed_at = case when $1 in ('completed', 'failed') then now() else completed_at end
       where id = $7 and user_id = $8
       returning *`,
      [
        status,
        result.resultType,
        result.confidence,
        result.evidenceTier,
        result.evidenceRefs,
        result.candidateRefs,
        runId,
        userId,
      ],
    );
    await syncWorkOrderStatusForRun(asObject(rows[0]), status);
    return sendJson(response, formatDates(rows[0]));
  }

  if (request.method === "POST" && action === "decision") {
    const decision = normalizeUserDecision(await readJson(request), runId);
    const run = await workflowRunForUser(runId, userId);
    const result = normalizePlaceRecoveryWorkerResult({
      result_type: run.result_type ?? "source_only_clue",
      evidence_tier: run.evidence_tier ?? "none",
      confidence: run.confidence ?? 0,
      evidence_refs: run.result_evidence_refs ?? [],
      candidate_refs: run.result_candidate_refs ?? [],
    });
    const receipt = receiptForResult(result, decision);
    const client = await pool.connect();
    try {
      await client.query("begin");
      const decisionInsert = buildInsert("user_decisions", {
        run_id: runId,
        user_id: userId,
        action: decision.action,
        edited_payload: decision.editedPayload,
        reason: decision.reason ?? null,
      }, userDecisionFields);
      await client.query(decisionInsert.sql, decisionInsert.values);

      const receiptBody = {
        run_id: runId,
        workflow_id: placeRecoveryWorkflowId,
        verdict: receipt.verdict,
        settlement: receipt.settlement,
        evaluator_summary: receipt.evaluatorSummary,
        evidence_refs: receipt.evidenceRefs,
        candidate_refs: receipt.candidateRefs,
        receipt_hash: receiptHash(runId, receipt),
        anchor_status: "offchain",
        private_url: null,
      };
      const receiptInsert = buildInsert("workflow_receipts", receiptBody, workflowReceiptFields);
      const { rows: receiptRows } = await client.query(`${receiptInsert.sql} returning *`, receiptInsert.values);
      const receiptRow = asObject(receiptRows[0]);

      await insertCreditLedger(client, {
        run_id: runId,
        user_id: userId,
        delta: settlementDelta(receipt.creditSettlement, Number(run.credit_reserved ?? 1)),
        reason: receipt.creditSettlement,
        settlement: receipt.creditSettlement,
      });
      const { rows } = await client.query(
        `update workflow_runs
         set status = 'completed',
             credit_settlement = $1,
             receipt_id = $2,
             completed_at = coalesce(completed_at, now())
         where id = $3 and user_id = $4
         returning *`,
        [receipt.creditSettlement, receiptRow.id, runId, userId],
      );
      const completedRun = asObject(rows[0]);
      if (completedRun.work_order_id) {
        await client.query(
          "update work_orders set status = 'completed' where id = $1 and user_id = $2",
          [completedRun.work_order_id, userId],
        );
      }
      await client.query("commit");
      return sendJson(response, {
        run: formatDates(rows[0]),
        receipt: formatDates(receiptRow),
      }, 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  return sendJson(response, { error: "Unsupported workflow run route" }, 405);
}

async function handleSocialSignals(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported social signals route" }, 405);

  const lens = parseLens(url.searchParams.get("lens"), "forYou");
  const limit = clampLimit(url.searchParams.get("limit"));
  const signals: JsonBody[] = [];

  try {
    if (lens === "forYou" || lens === "friends") {
      signals.push(...await friendSignalPlaces(userId, limit));
    }
    if (lens === "forYou" || lens === "trending") {
      signals.push(...await trendingSignalPlaces(userId, limit));
    }
  } catch (error) {
    if (isMissingRelationError(error)) {
      console.warn("Social signal schema is missing; returning empty signals until migrations run.");
      return sendJson(response, []);
    }
    throw error;
  }

  return sendJson(response, signals.slice(0, limit));
}

async function handleReferrals(
  request: IncomingMessage,
  response: ServerResponse,
  referralCode: string | undefined,
  url: URL,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported referrals route" }, 405);

  const code = referralCode ?? url.searchParams.get("code") ?? undefined;
  const handle = url.searchParams.get("handle") ?? undefined;
  const profile = await referralProfile(code, handle);
  const profileId = stringValue(profile.id);
  if (!profileId) throw new ApiError(404, "Referral profile not found");
  const featuredPlaces = await referralFeaturedPlaces(profileId, stringValue(profile.referral_code) ?? code ?? "");

  return sendJson(response, {
    referrerId: profileId,
    handle: stringValue(profile.handle) ?? "",
    displayName: displayName(profile),
    referralCode: stringValue(profile.referral_code) ?? "",
    lens: "friends",
    avatarUrl: profile.avatar_url ?? null,
    trustedGuideCount: profile.trusted_guide_count ?? 0,
    featuredPlaces,
  });
}

async function handleMemory(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
  url: URL,
  userId: string,
): Promise<void> {
  const [kind, id] = segments;

  if (kind === "captures" && id && segments[2] === "search-recovery") {
    return await handleCaptureSearchRecovery(request, response, id, userId);
  }
  if (kind === "captures") return await handleMemoryCaptures(request, response, id, userId);
  if (kind === "candidates") return await handleMemoryCandidates(request, response, id, url, userId);
  if (kind === "decisions") return await handleMemoryDecisions(request, response, url, userId);
  if (kind === "recommendations") return await handleMemoryRecommendations(request, response, id, userId);

  return sendJson(response, { error: "Unsupported memory route" }, 405);
}

async function handleCaptureSearchRecovery(
  request: IncomingMessage,
  response: ServerResponse,
  captureId: string,
  userId: string,
): Promise<void> {
  if (request.method !== "POST") {
    return sendJson(response, { error: "Unsupported capture search recovery route" }, 405);
  }

  await ensureCaptureOwner(captureId, userId);
  const body = await readJson(request);
  const requestedQueries = stringArray(body.queries);
  const maxQueries = typeof body.max_queries === "number" ? Math.max(1, Math.min(6, body.max_queries)) : undefined;
  if (body.workflow_run_id !== undefined && typeof body.workflow_run_id !== "string") {
    return sendJson(response, { error: "workflow_run_id must be a string" }, 400);
  }
  const workflowRunId = stringValue(body.workflow_run_id);
  if (workflowRunId) await ensureWorkflowRunOwner(workflowRunId, userId);

  const { rows } = await pool.query("select * from captures where id = $1 and user_id = $2", [captureId, userId]);
  const capture = asObject(rows[0]);

  await pool.query("update captures set status = 'investigating' where id = $1 and user_id = $2", [captureId, userId]);

  const recovery = await runSourceSearchRecovery({
    sourceUrl: stringValue(capture.source_url),
    rawText: stringValue(capture.raw_text),
    title: stringValue(capture.title),
    suggestedSearchQueries: requestedQueries,
    maxQueries,
  });

  const existingKeys = await existingCandidateKeys(captureId);
  const createdCandidates: JsonBody[] = [];

  for (const candidate of recovery.candidates) {
    const key = candidateKey(candidate.name, candidate.address);
    if (existingKeys.has(key)) continue;
    existingKeys.add(key);

    const body = sourceSearchCandidateBody(candidate, captureId, workflowRunId);
    const insert = buildInsert("place_candidates", body, placeCandidateFields);
    const { rows: insertedRows } = await pool.query(`${insert.sql} returning *`, insert.values);
    createdCandidates.push(formatPlaceCandidate(insertedRows[0]));
  }

  await pool.query("update captures set status = 'review' where id = $1 and user_id = $2", [captureId, userId]);

  return sendJson(response, {
    capture_id: captureId,
    queries: recovery.queries,
    search_results: recovery.searchResults,
    created_candidates: createdCandidates,
    media_evidence: recovery.mediaEvidence,
    errors: recovery.errors,
    receipt: recovery.receipt,
  });
}

async function handleMemoryCaptures(
  request: IncomingMessage,
  response: ServerResponse,
  captureId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !captureId) {
    const { rows } = await pool.query(
      "select * from captures where user_id = $1 order by created_at desc",
      [userId],
    );
    return sendJson(response, rows.map(formatCapture));
  }

  if (request.method === "GET" && captureId) {
    const { rows } = await pool.query(
      "select * from captures where id = $1 and user_id = $2",
      [captureId, userId],
    );
    if (!rows[0]) return sendJson(response, { error: "Capture not found" }, 404);
    return sendJson(response, formatCapture(rows[0]));
  }

  if (request.method === "POST" && !captureId) {
    const body = withOwner(await readJson(request), userId);
    const insert = buildInsert("captures", body, [...captureFields, "user_id"]);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatCapture(rows[0]), 201);
  }

  if (request.method === "PATCH" && captureId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "created_at", "updated_at"]);
    const update = buildUpdate("captures", body, captureFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, captureId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning *`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Capture not found" }, 404);
    return sendJson(response, formatCapture(rows[0]));
  }

  return sendJson(response, { error: "Unsupported memory captures route" }, 405);
}

async function handleMemoryCandidates(
  request: IncomingMessage,
  response: ServerResponse,
  candidateId: string | undefined,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !candidateId) {
    const captureId = url.searchParams.get("capture_id");
    const where = captureId
      ? "where c.user_id = $1 and pc.capture_id = $2"
      : "where c.user_id = $1";
    const values = captureId ? [userId, captureId] : [userId];
    const { rows } = await pool.query(
      `select pc.*
       from place_candidates pc
       join captures c on c.id = pc.capture_id
       ${where}
       order by pc.created_at desc`,
      values,
    );
    return sendJson(response, rows.map(formatPlaceCandidate));
  }

  if (request.method === "POST" && !candidateId) {
    const body = await readJson(request);
    const captureId = typeof body.capture_id === "string" ? body.capture_id : undefined;
    if (!captureId) return sendJson(response, { error: "capture_id is required" }, 400);
    await ensureCaptureOwner(captureId, userId);
    if (body.workflow_run_id !== undefined && typeof body.workflow_run_id !== "string") {
      return sendJson(response, { error: "workflow_run_id must be a string" }, 400);
    }
    if (body.workflow_run_id) await ensureWorkflowRunOwner(body.workflow_run_id, userId);
    await ensureOwnedPlaceReference(body.place_id, userId);

    const insert = buildInsert("place_candidates", body, placeCandidateFields);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatPlaceCandidate(rows[0]), 201);
  }

  if (request.method === "PATCH" && candidateId) {
    const body = writableFields(await readJson(request), ["id", "capture_id", "created_at", "updated_at"]);
    await ensureOwnedPlaceReference(body.place_id, userId);
    const update = buildUpdate("place_candidates", body, placeCandidateFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, candidateId, userId];
    const { rows } = await pool.query(
      `${update.sql}
       from captures c
       where place_candidates.capture_id = c.id
         and place_candidates.id = $${values.length - 1}
         and c.user_id = $${values.length}
       returning place_candidates.*`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Candidate not found" }, 404);
    return sendJson(response, formatPlaceCandidate(rows[0]));
  }

  return sendJson(response, { error: "Unsupported memory candidates route" }, 405);
}

async function handleMemoryDecisions(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method === "GET") {
    const candidateId = url.searchParams.get("candidate_id");
    const where = candidateId
      ? "where c.user_id = $1 and ad.candidate_id = $2"
      : "where c.user_id = $1";
    const values = candidateId ? [userId, candidateId] : [userId];
    const { rows } = await pool.query(
      `select ad.*
       from agent_decisions ad
       join place_candidates pc on pc.id = ad.candidate_id
       join captures c on c.id = pc.capture_id
       ${where}
       order by ad.created_at desc`,
      values,
    );
    return sendJson(response, rows.map(formatAgentDecision));
  }

  if (request.method === "POST") {
    const body = await readJson(request);
    const candidateId = typeof body.candidate_id === "string" ? body.candidate_id : undefined;
    if (!candidateId) return sendJson(response, { error: "candidate_id is required" }, 400);
    await ensureCandidateOwner(candidateId, userId);

    const insert = buildInsert("agent_decisions", body, agentDecisionFields);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatAgentDecision(rows[0]), 201);
  }

  return sendJson(response, { error: "Unsupported memory decisions route" }, 405);
}

async function handleMemoryRecommendations(
  request: IncomingMessage,
  response: ServerResponse,
  recommendationSetId: string | undefined,
  userId: string,
): Promise<void> {
  if (request.method === "GET" && !recommendationSetId) {
    const sets = await recommendationSetsForUser(userId);
    return sendJson(response, sets);
  }

  if (request.method === "GET" && recommendationSetId) {
    const sets = await recommendationSetsForUser(userId, recommendationSetId);
    if (!sets[0]) return sendJson(response, { error: "Recommendation not found" }, 404);
    return sendJson(response, sets[0]);
  }

  if (request.method === "POST" && !recommendationSetId) {
    const body = await readJson(request);
    const items = Array.isArray(body.items) ? body.items.map(asObject) : [];
    await ensureOwnedCaptureReference(body.capture_id, userId);
    for (const item of items) await ensureRecommendationItemReferences(item, userId);

    const client = await pool.connect();
    try {
      await client.query("begin");
      const setBody = withOwner(writableFields(body, ["items"]), userId);
      const setInsert = buildInsert("recommendation_sets", setBody, [...recommendationSetFields, "user_id"]);
      const { rows: setRows } = await client.query(`${setInsert.sql} returning *`, setInsert.values);
      const recommendationSet = setRows[0] as { id: string };

      const itemRows: JsonBody[] = [];
      for (const item of items) {
        const itemBody = { ...writableFields(item, ["recommendation_set_id", "created_at"]), recommendation_set_id: recommendationSet.id };
        const itemInsert = buildInsert("recommendation_items", itemBody, recommendationItemFields);
        const { rows } = await client.query(`${itemInsert.sql} returning *`, itemInsert.values);
        itemRows.push(asObject(rows[0]));
      }

      await client.query("commit");
      return sendJson(response, assembleRecommendationSets(setRows, itemRows)[0], 201);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  if (request.method === "PATCH" && recommendationSetId) {
    const body = writableFields(await readJson(request), ["id", "user_id", "items", "created_at", "updated_at"]);
    await ensureOwnedCaptureReference(body.capture_id, userId);
    const update = buildUpdate("recommendation_sets", body, recommendationSetFields);
    if (!update) return sendJson(response, { error: "No writable fields" }, 400);

    const values = [...update.values, recommendationSetId, userId];
    const { rows } = await pool.query(
      `${update.sql} where id = $${values.length - 1} and user_id = $${values.length} returning *`,
      values,
    );
    if (!rows[0]) return sendJson(response, { error: "Recommendation not found" }, 404);

    const sets = await recommendationSetsForUser(userId, recommendationSetId);
    return sendJson(response, sets[0]);
  }

  return sendJson(response, { error: "Unsupported memory recommendations route" }, 405);
}

async function handleAgents(
  request: IncomingMessage,
  response: ServerResponse,
  segments: string[],
  url: URL,
  userId: string,
): Promise<void> {
  const [kind] = segments;

  if (kind === "capabilities") return await handleAgentCapabilities(request, response);
  if (kind === "tool-calls") return await handleAgentToolCalls(request, response, url, userId);

  return sendJson(response, { error: "Unsupported agents route" }, 405);
}

async function handleAgentCapabilities(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  if (request.method !== "GET") return sendJson(response, { error: "Unsupported agent capabilities route" }, 405);

  const { rows } = await pool.query(
    "select * from agent_capabilities where enabled = true order by agent_family, vertical, action",
  );
  return sendJson(response, rows.map(formatAgentCapability));
}

async function handleAgentToolCalls(
  request: IncomingMessage,
  response: ServerResponse,
  url: URL,
  userId: string,
): Promise<void> {
  if (request.method === "GET") {
    const capabilityId = url.searchParams.get("capability_id");
    const recommendationSetId = url.searchParams.get("recommendation_set_id");
    const filters = ["user_id = $1"];
    const values: QueryValue[] = [userId];

    if (capabilityId) {
      values.push(capabilityId);
      filters.push(`capability_id = $${values.length}`);
    }

    if (recommendationSetId) {
      values.push(recommendationSetId);
      filters.push(`recommendation_set_id = $${values.length}`);
    }

    const { rows } = await pool.query(
      `select * from agent_tool_calls where ${filters.join(" and ")} order by created_at desc`,
      values,
    );
    return sendJson(response, rows.map(formatAgentToolCall));
  }

  if (request.method === "POST") {
    const body = await readJson(request);
    const capabilityId = typeof body.capability_id === "string" ? body.capability_id : undefined;
    if (!capabilityId) return sendJson(response, { error: "capability_id is required" }, 400);
    await ensureCapabilityEnabled(capabilityId);
    await ensureOwnedCaptureReference(body.capture_id, userId);
    await ensureOwnedRecommendationSetReference(body.recommendation_set_id, userId);

    const callBody = withOwner(body, userId);
    const insert = buildInsert("agent_tool_calls", callBody, [...agentToolCallFields, "user_id"]);
    const { rows } = await pool.query(`${insert.sql} returning *`, insert.values);
    return sendJson(response, formatAgentToolCall(rows[0]), 201);
  }

  return sendJson(response, { error: "Unsupported agent tool calls route" }, 405);
}

async function resolveFollowTarget(followRequest: ReturnType<typeof normalizeFollowRequest>): Promise<JsonBody> {
  if (followRequest.followingId) {
    const { rows } = await pool.query("select * from profiles where id = $1", [followRequest.followingId]);
    if (!rows[0]) throw new ApiError(404, "Profile not found");
    return asObject(rows[0]);
  }

  if (followRequest.handle) {
    const { rows } = await pool.query("select * from profiles where lower(handle) = lower($1)", [followRequest.handle]);
    if (!rows[0]) throw new ApiError(404, "Profile not found");
    return asObject(rows[0]);
  }

  if (followRequest.referralCode) {
    const { rows } = await pool.query("select * from profiles where referral_code = $1", [followRequest.referralCode]);
    if (!rows[0]) throw new ApiError(404, "Profile not found");
    return asObject(rows[0]);
  }

  throw new ApiError(400, "following_id, handle, or referral_code is required");
}

async function referralProfile(code: string | undefined, handle: string | undefined): Promise<JsonBody> {
  if (!code && !handle) throw new ApiError(400, "code or handle is required");

  const filters: string[] = [];
  const values: QueryValue[] = [];
  if (code) {
    values.push(code);
    filters.push(`referral_code = $${values.length}`);
  }
  if (handle) {
    values.push(handle.replace(/^@+/, ""));
    filters.push(`lower(handle) = lower($${values.length})`);
  }

  const { rows } = await pool.query(`select * from profiles where ${filters.join(" or ")} limit 1`, values);
  if (!rows[0]) throw new ApiError(404, "Referral profile not found");
  return asObject(rows[0]);
}

async function friendSignalPlaces(userId: string, limit: number): Promise<JsonBody[]> {
  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as social_visibility,
       f.lens as follow_lens,
       actor.id as actor_id,
       actor.display_name as actor_display_name,
       actor.handle as actor_handle,
       actor.referral_code as actor_referral_code
     from follows f
     join profiles actor on actor.id = f.following_id
     join places p on p.user_id = f.following_id
     join place_visibility pv on pv.place_id = p.id
     where f.follower_id = $1
       and p.user_id <> $1
       and pv.allow_friend_signal = true
       and pv.visibility in ('friends', 'public_link', 'public_guide')
     order by p.created_at desc
     limit $2`,
    [userId, limit],
  );

  return rows.map((row) => {
    const value = asObject(row);
    const actorName = displayName({
      display_name: value.actor_display_name,
      handle: value.actor_handle,
    });
    return formatSocialPlace(value, {
      kind: "friend_saved",
      lens: parseLens(value.follow_lens, "friends"),
      friendNames: actorName ? [actorName] : [],
      friendCount: 1,
      saveCount: 1,
      trendingRank: null,
      categoryRank: null,
      sourceLabel: actorName,
      referrerId: stringValue(value.actor_id) ?? null,
      referralCode: stringValue(value.actor_referral_code) ?? null,
    });
  });
}

async function trendingSignalPlaces(userId: string, limit: number): Promise<JsonBody[]> {
  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as social_visibility,
       pss.lens as signal_lens,
       pss.friend_count,
       pss.save_count,
       pss.category_rank,
       pss.source_label,
       pss.referrer_id,
       pss.referral_code
     from place_social_signals pss
     join places p on p.id = pss.place_id
     join place_visibility pv on pv.place_id = p.id
     where (pss.viewer_user_id = $1 or pss.viewer_user_id is null)
       and pss.signal_type = 'trending'
       and p.user_id <> $1
       and pv.allow_trending_signal = true
       and pv.visibility in ('public_link', 'public_guide')
     order by pss.trending_score desc, pss.created_at desc
     limit $2`,
    [userId, limit],
  );

  return rows.map((row, index) => {
    const value = asObject(row);
    const categoryRank = numberValue(value.category_rank) ?? index + 1;
    return formatSocialPlace(value, {
      kind: "trending",
      lens: parseLens(value.signal_lens, "trending"),
      friendNames: [],
      friendCount: numberValue(value.friend_count) ?? 0,
      saveCount: numberValue(value.save_count) ?? 0,
      trendingRank: categoryRank,
      categoryRank,
      sourceLabel: stringValue(value.source_label) ?? "Trending in SAV-E",
      referrerId: stringValue(value.referrer_id) ?? null,
      referralCode: stringValue(value.referral_code) ?? null,
    });
  });
}

async function referralFeaturedPlaces(referrerId: string, referralCode: string): Promise<JsonBody[]> {
  const { rows } = await pool.query(
    `select
       p.*,
       pv.visibility as social_visibility,
       owner.display_name as owner_display_name,
       owner.handle as owner_handle
     from places p
     join place_visibility pv on pv.place_id = p.id
     join profiles owner on owner.id = p.user_id
     where p.user_id = $1
       and pv.allow_friend_signal = true
       and pv.visibility in ('public_link', 'public_guide')
     order by p.created_at desc
     limit 6`,
    [referrerId],
  );

  return rows.map((row) => {
    const value = asObject(row);
    const ownerName = displayName({
      display_name: value.owner_display_name,
      handle: value.owner_handle,
    });
    return formatSocialPlace(value, {
      kind: "referral_guide",
      lens: "friends",
      friendNames: [],
      friendCount: 0,
      saveCount: 0,
      trendingRank: null,
      categoryRank: null,
      sourceLabel: ownerName,
      referrerId,
      referralCode,
    });
  });
}

function formatSocialPlace(row: JsonBody, socialSignal: JsonBody): JsonBody {
  return {
    ...formatDates(pickFields(row, [...placeFields, "user_id"])),
    visibility: stringValue(row.social_visibility) ?? "private",
    social_signal: socialSignal,
  };
}

function formatFollow(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatPublicProfile(row: JsonBody): JsonBody {
  return {
    id: row.id,
    handle: row.handle ?? null,
    display_name: displayName(row),
    avatar_url: row.avatar_url ?? null,
    referral_code: row.referral_code ?? null,
  };
}

function displayName(row: JsonBody): string {
  return stringValue(row.display_name) ?? stringValue(row.handle) ?? "SAV-E User";
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return undefined;
}

function clampLimit(value: string | null): number {
  const parsed = value ? Number(value) : 40;
  if (!Number.isFinite(parsed)) return 40;
  return Math.max(1, Math.min(100, Math.trunc(parsed)));
}

function isMissingRelationError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as { code?: unknown; message?: unknown };
  return value.code === "42P01" ||
    (typeof value.message === "string" && value.message.includes("does not exist"));
}

async function existingCandidateKeys(captureId: string): Promise<Set<string>> {
  const { rows } = await pool.query("select name, address from place_candidates where capture_id = $1", [captureId]);
  return new Set(rows.map((row) => {
    const value = asObject(row);
    return candidateKey(stringValue(value.name) ?? "", stringValue(value.address) ?? "");
  }));
}

function sourceSearchCandidateBody(candidate: SourceSearchCandidate, captureId: string, workflowRunId?: string): JsonBody {
  return {
    capture_id: captureId,
    workflow_run_id: workflowRunId,
    name: candidate.name,
    address: candidate.address,
    city: "",
    latitude: candidate.latitude ?? null,
    longitude: candidate.longitude ?? null,
    evidence: candidate.evidence.map((text) => ({ text })),
    confidence: candidate.confidence,
    missing_info: candidate.missingInfo,
    status: "review",
  };
}

function candidateKey(name: string, address: string): string {
  return `${canonicalCandidateValue(name)}|${canonicalCandidateValue(address)}`;
}

function canonicalCandidateValue(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, " ").trim();
}

function stringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

async function ensureCaptureOwner(captureId: string, userId: string): Promise<void> {
  const { rows } = await pool.query("select id from captures where id = $1 and user_id = $2", [captureId, userId]);
  if (!rows[0]) throw new ApiError(404, "Capture not found");
}

async function ensureCandidateOwner(candidateId: string, userId: string): Promise<void> {
  const { rows } = await pool.query(
    `select pc.id
     from place_candidates pc
     join captures c on c.id = pc.capture_id
     where pc.id = $1 and c.user_id = $2`,
    [candidateId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Candidate not found");
}

async function ownedPlaceForAnalysis(placeId: unknown, userId: string): Promise<JsonBody> {
  if (typeof placeId !== "string") throw new ApiError(400, "place_id must be a string");

  const { rows } = await pool.query(
    "select * from places where id = $1 and user_id = $2 limit 1",
    [placeId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Place not found");
  return asObject(rows[0]);
}

async function ensureOwnedPlaceReference(placeId: unknown, userId: string): Promise<void> {
  if (placeId === undefined || placeId === null) return;
  if (typeof placeId !== "string") throw new ApiError(400, "place_id must be a string");

  const { rows } = await pool.query("select id from places where id = $1 and user_id = $2", [placeId, userId]);
  if (!rows[0]) throw new ApiError(404, "Place not found");
}

async function ensureOwnedCaptureReference(captureId: unknown, userId: string): Promise<void> {
  if (captureId === undefined || captureId === null) return;
  if (typeof captureId !== "string") throw new ApiError(400, "capture_id must be a string");
  await ensureCaptureOwner(captureId, userId);
}

async function ensureOwnedCandidateReference(candidateId: unknown, userId: string): Promise<void> {
  if (candidateId === undefined || candidateId === null) return;
  if (typeof candidateId !== "string") throw new ApiError(400, "place_candidate_id must be a string");
  await ensureCandidateOwner(candidateId, userId);
}

async function ensureOwnedRecommendationSetReference(recommendationSetId: unknown, userId: string): Promise<void> {
  if (recommendationSetId === undefined || recommendationSetId === null) return;
  if (typeof recommendationSetId !== "string") throw new ApiError(400, "recommendation_set_id must be a string");

  const { rows } = await pool.query("select id from recommendation_sets where id = $1 and user_id = $2", [
    recommendationSetId,
    userId,
  ]);
  if (!rows[0]) throw new ApiError(404, "Recommendation not found");
}

async function createPlaceRecoveryWorkOrder(
  client: PoolClient,
  userId: string,
  workOrder: ReturnType<typeof normalizePlaceRecoveryWorkOrderCreate>,
): Promise<JsonBody> {
  const insert = buildInsert("work_orders", {
    workflow_id: workOrder.workflowId,
    listing_id: workOrder.listingId,
    user_id: userId,
    intent: workOrder.intent,
    input_type: workOrder.inputType,
    input_ref: workOrder.inputRef ?? null,
    source_url: workOrder.sourceUrl ?? null,
    evaluator_policy_id: workOrder.evaluatorPolicyId,
    settlement_mode: workOrder.settlementMode,
    budget_policy: workOrder.budgetPolicy,
    status: "queued",
  }, workOrderFields);
  const { rows } = await client.query(`${insert.sql} returning *`, insert.values);
  return asObject(rows[0]);
}

async function ensureWorkOrderOwner(workOrderId: string, userId: string, client?: PoolClient): Promise<string> {
  const db = client ?? pool;
  const { rows } = await db.query("select id from work_orders where id = $1 and user_id = $2", [workOrderId, userId]);
  if (!rows[0]) throw new ApiError(404, "Work order not found");
  return workOrderId;
}

async function ensureWorkflowRunOwner(runId: string, userId: string): Promise<void> {
  const { rows } = await pool.query("select id from workflow_runs where id = $1 and user_id = $2", [runId, userId]);
  if (!rows[0]) throw new ApiError(404, "Workflow run not found");
}

async function workflowRunForUser(runId: string, userId: string): Promise<JsonBody> {
  const { rows } = await pool.query("select * from workflow_runs where id = $1 and user_id = $2", [runId, userId]);
  if (!rows[0]) throw new ApiError(404, "Workflow run not found");
  return asObject(rows[0]);
}

async function clearingBlockForUser(blockId: string, userId: string): Promise<JsonBody> {
  const { rows } = await pool.query(
    "select * from clearing_blocks where id = $1 and user_id = $2",
    [blockId, userId],
  );
  if (!rows[0]) throw new ApiError(404, "Clearing block not found");
  return asObject(rows[0]);
}

async function createClearingBlockForPendingReceipts(userId: string, body: JsonBody): Promise<JsonBody> {
  const limit = boundedClearingBlockLimit(body.limit);
  const client = await pool.connect();
  try {
    await client.query("begin");
    const { rows: receiptRows } = await client.query(
      `select wr.id, wr.receipt_hash
       from workflow_receipts wr
       join workflow_runs r on r.id = wr.run_id
       where r.user_id = $1
         and wr.workflow_id = $2
         and not exists (
           select 1 from clearing_block_items cbi where cbi.receipt_id = wr.id
         )
       order by wr.created_at asc, wr.id asc
       limit $3
       for update of wr skip locked`,
      [userId, placeRecoveryWorkflowId, limit],
    );

    if (!receiptRows.length) {
      await client.query("commit");
      return { created: false, pending_receipt_count: 0 };
    }

    const { rows: previousRows } = await client.query(
      `select block_number, block_hash
       from clearing_blocks
       where user_id = $1 and chain_namespace = $2
       order by block_number desc
       limit 1
       for update`,
      [userId, placeRecoveryWorkflowId],
    );
    const previous = previousRows[0] ? asObject(previousRows[0]) : {};
    const blockNumber = Number(previous.block_number ?? 0) + 1;
    const previousBlockHash = stringValue(previous.block_hash);
    const receipts = receiptRows.map((row) => {
      const receipt = asObject(row);
      return {
        id: String(receipt.id),
        receiptHash: String(receipt.receipt_hash),
      };
    });
    const draft = buildClearingBlockDraft({
      chainNamespace: placeRecoveryWorkflowId,
      blockNumber,
      previousBlockHash,
      receipts,
    });

    const blockInsert = buildInsert("clearing_blocks", {
      chain_namespace: draft.chainNamespace,
      user_id: userId,
      block_number: draft.blockNumber,
      previous_block_hash: draft.previousBlockHash ?? null,
      merkle_root: draft.merkleRoot,
      receipt_count: draft.receiptCount,
      block_hash: draft.blockHash,
      signer_agent_id: "save-backend",
      anchor_status: "offchain",
      anchor_chain: null,
      anchor_tx_hash: null,
    }, clearingBlockFields);
    const { rows: blockRows } = await client.query(`${blockInsert.sql} returning *`, blockInsert.values);
    const block = asObject(blockRows[0]);

    const items: JsonBody[] = [];
    for (const [position, receipt] of receipts.entries()) {
      const itemInsert = buildInsert("clearing_block_items", {
        block_id: block.id,
        receipt_id: receipt.id,
        receipt_hash: receipt.receiptHash,
        merkle_proof: [],
        position,
      }, clearingBlockItemFields);
      const { rows } = await client.query(`${itemInsert.sql} returning *`, itemInsert.values);
      items.push(asObject(rows[0]));
    }

    await client.query(
      "update workflow_receipts set anchor_status = 'batch_anchored' where id = any($1::uuid[])",
      [receipts.map((receipt) => receipt.id)],
    );
    await client.query("commit");
    return {
      created: true,
      block: formatDates(block),
      items: items.map((item) => formatDates(item)),
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function syncWorkOrderStatusForRun(run: JsonBody, status: string): Promise<void> {
  const workOrderId = stringValue(run.work_order_id);
  const userId = stringValue(run.user_id);
  if (!workOrderId || !userId) return;
  await pool.query("update work_orders set status = $1 where id = $2 and user_id = $3", [status, workOrderId, userId]);
}

function boundedClearingBlockLimit(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value)) return 50;
  return Math.max(1, Math.min(100, value));
}

async function uniqueShareCode(): Promise<string> {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const code = randomBytes(6).toString("base64url");
    const { rows } = await pool.query("select code from shared_place_links where code = $1", [code]);
    if (!rows[0]) return code;
  }
  throw new ApiError(500, "Could not allocate share code");
}

async function insertCreditLedger(client: PoolClient, body: JsonBody): Promise<void> {
  const insert = buildInsert("credit_ledger", body, creditLedgerFields);
  await client.query(insert.sql, insert.values);
}

function receiptHash(runId: string, receipt: unknown): string {
  return createHash("sha256")
    .update(JSON.stringify({ runId, receipt }))
    .digest("hex");
}

function settlementDelta(settlement: string, creditReserved: number): number {
  if (settlement === "refunded") return creditReserved;
  if (settlement === "partial") return Math.ceil(creditReserved / 2);
  return 0;
}

async function ensureRecommendationItemReferences(item: JsonBody, userId: string): Promise<void> {
  await ensureOwnedCandidateReference(item.place_candidate_id, userId);
  await ensureOwnedPlaceReference(item.place_id, userId);
}

async function ensureCapabilityEnabled(capabilityId: string): Promise<void> {
  const { rows } = await pool.query("select id from agent_capabilities where id = $1 and enabled = true", [
    capabilityId,
  ]);
  if (!rows[0]) throw new ApiError(404, "Capability not found");
}

async function ensureProfile(userId: string): Promise<void> {
  await pool.query(
    `insert into profiles (id, display_name)
     values ($1, 'SAV-E User')
     on conflict (id) do nothing`,
    [userId],
  );
}

async function resolveUserId(request: IncomingMessage): Promise<string> {
  const header = request.headers.authorization ?? "";
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];
  if (token) return verifiedPrivySubject(token);

  const guestToken = request.headers["x-save-guest-token"] ?? request.headers["x-wanderly-guest-token"];
  const normalizedGuestToken = Array.isArray(guestToken) ? guestToken[0] : guestToken;
  if (typeof normalizedGuestToken === "string") {
    const guestUserId = userIdFromGuestSessionToken(normalizedGuestToken, guestSessionSecret);
    if (guestUserId) return guestUserId;
  }

  throw new ApiError(401, "Missing bearer token or guest session");
}

async function verifiedPrivySubject(token: string): Promise<string> {
  const key = await verificationKey();
  const { payload } = await jwtVerify(token, key, {
    issuer: "privy.io",
    audience: privyAppId,
  });

  return subjectFromPayload(payload);
}

function subjectFromPayload(payload: JWTPayload): string {
  if (typeof payload.sub !== "string" || payload.sub.length === 0) {
    throw new ApiError(401, "Invalid Privy subject");
  }
  return payload.sub;
}

async function verificationKey(): Promise<KeyLike> {
  verificationKeyPromise ??= importVerificationKey();
  return verificationKeyPromise;
}

async function importVerificationKey(): Promise<KeyLike> {
  const pem = normalizePem(privyVerificationKey);
  try {
    return await importSPKI(pem, "ES256");
  } catch {
    return await importSPKI(pem, "EdDSA");
  }
}

function normalizePem(key: string): string {
  const value = key.replace(/\\n/g, "\n").trim();
  if (value.includes("BEGIN PUBLIC KEY")) return value;
  return `-----BEGIN PUBLIC KEY-----\n${value}\n-----END PUBLIC KEY-----`;
}

async function readJson(request: IncomingMessage, maxBytes = defaultJsonBodyMaxBytes): Promise<JsonBody> {
  const chunks: Buffer[] = [];
  let byteLength = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteLength += buffer.byteLength;
    if (byteLength > maxBytes) throw new ApiError(413, "JSON payload is too large");
    chunks.push(buffer);
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};
  return asObject(JSON.parse(raw));
}

async function boundedResponseBuffer(response: Response, maxBytes: number): Promise<Uint8Array> {
  const length = Number(response.headers.get("content-length") ?? "0");
  if (length > maxBytes) throw new ApiError(502, "Upstream response is too large");
  if (!response.body) return new Uint8Array();

  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  const reader = response.body.getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteLength += value.byteLength;
    if (byteLength > maxBytes) {
      await reader.cancel();
      throw new ApiError(502, "Upstream response is too large");
    }
    chunks.push(value);
  }

  const data = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return data;
}

function asObject(value: unknown): JsonBody {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as JsonBody;
  }
  throw new ApiError(400, "Expected JSON object");
}

function withOwner(body: JsonBody, userId: string): JsonBody {
  return { ...writableFields(body), user_id: userId };
}

function writableFields(body: JsonBody, omit: string[] = []): JsonBody {
  const blocked = new Set(["user_id", ...omit]);
  return Object.fromEntries(Object.entries(body).filter(([key]) => !blocked.has(key)));
}

function pickFields<T extends readonly string[]>(body: JsonBody, allowed: T): JsonBody {
  const allowedSet = new Set<string>(allowed);
  return Object.fromEntries(Object.entries(body).filter(([key]) => allowedSet.has(key)));
}

function buildInsert(table: string, body: JsonBody, allowed: readonly string[]): { sql: string; values: QueryValue[] } {
  const columns = Object.keys(pickFields(body, allowed)).filter((column) => body[column] !== undefined);
  if (columns.length === 0) throw new ApiError(400, "No writable fields");

  const values = columns.map((column) => queryValue(column, body[column]));
  const params = columns.map((_, index) => `$${index + 1}`);
  return {
    sql: `insert into ${table} (${columns.join(", ")}) values (${params.join(", ")})`,
    values,
  };
}

function buildUpdate(
  table: string,
  body: JsonBody,
  allowed: readonly string[],
): { sql: string; values: QueryValue[] } | undefined {
  const columns = Object.keys(pickFields(body, allowed)).filter((column) => body[column] !== undefined);
  if (columns.length === 0) return undefined;

  const values = columns.map((column) => queryValue(column, body[column]));
  const assignments = columns.map((column, index) => `${column} = $${index + 1}`);
  return {
    sql: `update ${table} set ${assignments.join(", ")}`,
    values,
  };
}

function queryValue(column: string, value: unknown): QueryValue {
  if (jsonbFields.has(column) && value !== null && value !== undefined) {
    return JSON.stringify(value);
  }
  return value as QueryValue;
}

function tripsSelect(whereClause: string, orderClause = ""): string {
  return `
    select
      t.*,
      coalesce(
        json_agg(ts order by ts.day, ts.order_index) filter (where ts.id is not null),
        '[]'::json
      ) as trip_stops
    from trips t
    left join trip_stops ts on ts.trip_id = t.id
    ${whereClause}
    group by t.id
    ${orderClause}
  `;
}

async function recommendationSetsForUser(userId: string, recommendationSetId?: string): Promise<JsonBody[]> {
  const values = recommendationSetId ? [userId, recommendationSetId] : [userId];
  const where = recommendationSetId ? "where user_id = $1 and id = $2" : "where user_id = $1";
  const { rows: setRows } = await pool.query(
    `select * from recommendation_sets ${where} order by created_at desc`,
    values,
  );
  if (setRows.length === 0) return [];

  const setIds = setRows.map((row) => (row as { id: string }).id);
  const { rows: itemRows } = await pool.query(
    "select * from recommendation_items where recommendation_set_id = any($1::uuid[]) order by rank, created_at",
    [setIds],
  );

  return assembleRecommendationSets(setRows, itemRows);
}

function assembleRecommendationSets(setRows: JsonBody[], itemRows: JsonBody[]): JsonBody[] {
  const itemsBySetId = new Map<string, JsonBody[]>();
  for (const row of itemRows) {
    const item = formatRecommendationItem(row);
    const setId = String(item.recommendation_set_id);
    const items = itemsBySetId.get(setId) ?? [];
    items.push(item);
    itemsBySetId.set(setId, items);
  }

  return setRows.map((row) => {
    const set = formatRecommendationSet(row);
    return {
      ...set,
      items: itemsBySetId.get(String(set.id)) ?? [],
    };
  });
}

function sendJson(response: ServerResponse, body: unknown, status = 200): void {
  response.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type, x-save-guest-token, x-wanderly-guest-token",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Content-Type": "application/json",
  });
  response.end(status === 204 ? undefined : JSON.stringify(body));
}

function formatPlace(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatTrip(row: JsonBody): JsonBody {
  return formatDates({
    ...row,
    trip_stops: Array.isArray(row.trip_stops)
      ? row.trip_stops.map((stop) => formatDates(asObject(stop)))
      : [],
  });
}

function formatProfile(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatCapture(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatPlaceCandidate(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatAgentDecision(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatAgentCapability(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatAgentToolCall(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatRecommendationSet(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatRecommendationItem(row: JsonBody): JsonBody {
  return formatDates(row);
}

function formatDates(row: JsonBody): JsonBody {
  return Object.fromEntries(
    Object.entries(row).map(([key, value]) => {
      if (value instanceof Date) return [key, toIsoSeconds(value)];
      return [key, value];
    }),
  );
}

function toIsoSeconds(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function databaseSSLConfig(url: string): undefined | { rejectUnauthorized: boolean; ca?: string } {
  const sslMode = process.env.PGSSLMODE?.trim().toLowerCase();
  if (sslMode === "disable") return undefined;
  let hostname = "";
  try {
    hostname = new URL(url).hostname.toLowerCase();
  } catch {
    hostname = "";
  }
  if (hostname === "localhost" || hostname === "127.0.0.1" || hostname.endsWith(".railway.internal")) {
    return undefined;
  }
  if (sslMode === "no-verify") return { rejectUnauthorized: false };
  const ca = process.env.DATABASE_CA_CERT?.replace(/\\n/g, "\n");
  return ca ? { rejectUnauthorized: true, ca } : { rejectUnauthorized: true };
}

class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}
