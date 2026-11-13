import {parseTimestampMs} from "./core";








const CODEX_USAGE_FIELDS=['input_tokens','cached_input_tokens','cache_write_input_tokens','output_tokens','reasoning_output_tokens','total_tokens'];
const isCodexTokenUsage = u => CODEX_USAGE_FIELDS.every(k=>Number.isInteger(u[k])&&u[k]>=0) && u.cached_input_tokens+u.cache_write_input_tokens<=u.input_tokens && u.reasoning_output_tokens<=u.output_tokens && u.total_tokens>=u.input_tokens+u.output_tokens;
function readCodexTokenUsage(value: unknown): CodexTokenUsage | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const input = raw["input_tokens"];
  const output = raw["output_tokens"];
  if (typeof input !== "number" || typeof output !== "number") return null;
  const usage = {
    input_tokens: input,
    cached_input_tokens: raw["cached_input_tokens"] === undefined ? 0 : raw["cached_input_tokens"],
    cache_write_input_tokens:
      raw["cache_write_input_tokens"] === undefined ? 0 : raw["cache_write_input_tokens"],
    output_tokens: output,
    reasoning_output_tokens:
      raw["reasoning_output_tokens"] === undefined ? 0 : raw["reasoning_output_tokens"],
    total_tokens: raw["total_tokens"] === undefined ? input + output : raw["total_tokens"],
  };
  return isCodexTokenUsage(usage) ? usage : null;
}

// A zeroed baseline rebases the counters, so the sequence start measured against it is forgotten.
function rebaseCodexUsage(state: CodexScanState, cumulative: CodexTokenUsage, timestampMs: number) {
  state.lastCumulativeUsage = cumulative;
  state.latestCumulativeAtMs = Math.max(state.latestCumulativeAtMs ?? timestampMs, timestampMs);
  delete state.unreportedRequests;
  if (cumulative.input_tokens + cumulative.output_tokens === 0) delete state.sequenceStartSignature;
}

function advanceCodexUsage(previous: CodexTokenUsage | null, last: CodexTokenUsage) {
  return readCodexTokenUsage(
    Object.fromEntries(CODEX_USAGE_FIELDS.map((key) => [key, (previous?.[key] ?? 0) + last[key]])),
  );
}

function unreportedRequests(
  previous: CodexTokenUsage | null,
  cumulative: CodexTokenUsage,
  last: CodexTokenUsage,
  pending: readonly CodexUnreportedRequest[] | undefined,
) {
  if (
    previous === null ||
    pending === undefined ||
    CODEX_USAGE_FIELDS.some(
      (key) =>
        cumulative[key] - previous[key] !==
        pending.reduce((sum, request) => sum + request.usage[key], 0),
    )
  ) {
    return null;
  }
  const final = pending.at(-1)!;
  const remainder = readCodexTokenUsage(
    Object.fromEntries(CODEX_USAGE_FIELDS.map((key) => [key, final.usage[key] - last[key]])),
  );
  if (remainder === null) return null;
  return [...pending.slice(0, -1), { ...final, usage: remainder }].filter(
    (request) => request.usage.input_tokens + request.usage.output_tokens > 0,
  );
}

/**
 * Codex `token_count` events carry no model or service tier, so both are carried forward: the model
 * from the most recent `turn_context`, the tier from the most recent `thread_settings_applied`.
 */
export function initialCodexScanState(): CodexScanState {
  return {
    model: "",
    speed: "standard",
    sessionId: "",
    lastUsageSignature: null,
    lastCumulativeUsage: null,
    malformedRecords: 0,
    sawSessionMeta: false,
    modelProvider: "",
    turnId: "",
    sawThreadSettings: false,
    suppressingForkCopies: false,
    forkCopyAnchorMs: 0,
  };
}

/** Forks copy and restamp parent history in a burst (0-40ms gaps); genuine child usage follows a model turn (5s+ observed). */
const FORK_COPY_MAX_GAP_MS = 1000;

function isForkedSessionMeta(payload: Record<string, unknown>): boolean {
  if (typeof payload["forked_from_id"] === "string") return true;
  const source = payload["source"];
  if (typeof source !== "object" || source === null) return false;
  const subagent = (source as Record<string, unknown>)["subagent"];
  if (typeof subagent !== "object" || subagent === null) return false;
  const spawn = (subagent as Record<string, unknown>)["thread_spawn"];
  if (typeof spawn !== "object" || spawn === null) return false;
  return typeof (spawn as Record<string, unknown>)["parent_thread_id"] === "string";
}

// The first usage line past the copied burst ends suppression for the rest of the rollout.
function isForkCopy(state: CodexScanState, timestampMs: number): boolean {
  if (!state.suppressingForkCopies) return false;
  if (timestampMs - state.forkCopyAnchorMs < FORK_COPY_MAX_GAP_MS) {
    state.forkCopyAnchorMs = timestampMs;
    return true;
  }
  state.suppressingForkCopies = false;
  state.lastUsageSignature = null;
  return false;
}

/**
 * Identified request-ledger entries report spending independently of context snapshots.
 * Legacy snapshots validate request deltas against cumulative counters.
 */
export function parseCodexLine(line: string, state: CodexScanState): readonly UsageRecord[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line);
  } catch {
    return [];
  }
  return parseCodexRecord(parsed, state);
}

function parseCodexRecord(parsed: unknown, state: CodexScanState): readonly UsageRecord[] {
  if (typeof parsed !== "object" || parsed === null) return [];

  const record = parsed as Record<string, unknown>;
  const payload = record["payload"];
  if (typeof payload !== "object" || payload === null) return [];
  const payloadRecord = payload as Record<string, unknown>;
  const payloadType = payloadRecord["type"];

  if (record["type"] === "session_meta") {
    // Only the first meta identifies this session; copied ancestor metas would misattribute later records.
    if (state.sawSessionMeta) return [];
    state.sawSessionMeta = true;
    const id = payloadRecord["id"] ?? payloadRecord["session_id"];
    if (typeof id === "string") state.sessionId = id;
    if (typeof payloadRecord["model_provider"] === "string") {
      state.modelProvider = payloadRecord["model_provider"];
    }
    const metaTimestampMs = parseTimestampMs(record["timestamp"]);
    if (metaTimestampMs !== null && isForkedSessionMeta(payloadRecord)) {
      state.suppressingForkCopies = true;
      state.forkCopyAnchorMs = metaTimestampMs;
    }
    return [];
  }

  if (record["type"] === "turn_context") {
    state.requestLedgerActive = false;
    if (typeof payloadRecord["model"] === "string") state.model = payloadRecord["model"];
    // Model carry is useful for usage, but history recovery needs this context's own identity.
    state.turnId =
      typeof payloadRecord["turn_id"] === "string" &&
      typeof payloadRecord["model"] === "string" &&
      payloadRecord["model"].length > 0
        ? payloadRecord["turn_id"]
        : "";
    return [];
  }

  // Request ledgers include spending that context snapshots can omit.
  if (record["type"] === "token_usage_record") {
    const timestampMs = parseTimestampMs(record["timestamp"]);
    const usage = readCodexTokenUsage(payloadRecord["usage"]);
    if (timestampMs === null || usage === null || state.model.length === 0) return [];
    // Copied history is already billed in the parent.
    if (isForkCopy(state, timestampMs)) return [];
    const responseId = payloadRecord["response_id"];
    if (typeof responseId === "string" && responseId.length > 0) {
      const pending = state.unreportedRequests ?? [];
      state.requestLedgerActive = true;
      for (const request of pending) {
        state.lastCumulativeUsage = advanceCodexUsage(state.lastCumulativeUsage, request.usage);
      }
      state.lastCumulativeUsage = advanceCodexUsage(state.lastCumulativeUsage, usage);
      delete state.unreportedRequests;
      return [
        ...pending.map((request) => codexRequestRecord(state, request.usage, request)),
        {
          ...codexRequestRecord(state, usage, codexAttribution(state, timestampMs)),
          dedupeKey: JSON.stringify(["codex", state.sessionId, responseId]),
        },
      ];
    }
    state.requestLedgerActive = false;
    (state.unreportedRequests ??= []).push({ ...codexAttribution(state, timestampMs), usage });
    return [];
  }

  if (payloadType === "thread_settings_applied") {
    state.sawThreadSettings = true;
    const settings = payloadRecord["thread_settings"];
    if (typeof settings === "object" && settings !== null) {
      state.speed = codexSpeed((settings as Record<string, unknown>)["service_tier"]);
    }
    return [];
  }

  if (payloadType !== "token_count") return [];

  const info = payloadRecord["info"];
  if (typeof info !== "object" || info === null) return [];
  const infoRecord = info as Record<string, unknown>;

  // Codex may re-emit these counters after the model or timestamp becomes available.
  const timestampMs = parseTimestampMs(record["timestamp"]);
  if (timestampMs === null || state.model.length === 0) return [];

  const last = readCodexTokenUsage(infoRecord["last_token_usage"]);
  const rawCumulative = infoRecord["total_token_usage"];
  const hasCumulative = rawCumulative !== undefined && rawCumulative !== null;
  const cumulative = hasCumulative ? readCodexTokenUsage(rawCumulative) : null;

  if (isForkCopy(state, timestampMs)) {
    // Copied history is already billed in the parent, but establishes the child's baseline.
    const signature = last === null ? null : JSON.stringify(last);
    if (cumulative !== null) rebaseCodexUsage(state, cumulative, timestampMs);
    else if (!hasCumulative && last !== null && signature !== state.lastUsageSignature) {
      state.lastCumulativeUsage = advanceCodexUsage(state.lastCumulativeUsage, last);
    }
    state.lastUsageSignature = signature;
    return [];
  }

  // Context snapshots can rewind on resume and omit compaction spending; identified requests are authoritative.
  if (state.requestLedgerActive) {
    if (cumulative !== null) rebaseCodexUsage(state, cumulative, timestampMs);
    return [];
  }

  const previous = state.lastCumulativeUsage;
  const latestCumulativeAtMs = state.latestCumulativeAtMs;
  const pending = state.unreportedRequests;
  // A valid snapshot remains the next baseline even when its paired request is malformed.
  if (cumulative !== null) rebaseCodexUsage(state, cumulative, timestampMs);
  if (last === null || (hasCumulative && cumulative === null)) {
    state.malformedRecords += 1;
    return [];
  }

  // Zero-component counters report context size, not a request: fill_to_context_window, or the
  // post-compaction marker whose total is the new context size (its cumulative may reset to zero).
  if (last.input_tokens + last.output_tokens === 0) {
    state.lastUsageSignature = null;
    return [];
  }

  if (
    cumulative !== null &&
    previous !== null &&
    CODEX_USAGE_FIELDS.every((key) => cumulative[key] === previous[key])
  ) {
    return [];
  }

  if (last.total_tokens !== last.input_tokens + last.output_tokens) {
    state.malformedRecords += 1;
    return [];
  }

  const signature = JSON.stringify(last);
  let unreported: readonly CodexUnreportedRequest[] = [];
  if (cumulative !== null) {
    // A session resumed in a new Codex process restarts its cumulative counters at this request.
    const restarted = CODEX_USAGE_FIELDS.every((key) => cumulative[key] === last[key]);
    const sequenceStart = JSON.stringify([timestampMs, last]);
    // Only the same event is a replay; a later request can restart with identical counters.
    if (restarted && sequenceStart === state.sequenceStartSignature) {
      state.lastCumulativeUsage = previous;
      return [];
    }
    // Forks and paginated continuations can inherit totals without copying a counter snapshot, and
    // a later request can continue from an earlier snapshot; a re-emitted old snapshot is not later.
    // Only bill the latest request, and require the unseen prefix to be valid usage too.
    const rewound =
      previous !== null &&
      (latestCumulativeAtMs === undefined || timestampMs > latestCumulativeAtMs) &&
      CODEX_USAGE_FIELDS.some((key) => cumulative[key] < previous[key]);
    const reconciled =
      previous === null || rewound
        ? readCodexTokenUsage(
            Object.fromEntries(CODEX_USAGE_FIELDS.map((key) => [key, cumulative[key] - last[key]])),
          ) !== null
        : CODEX_USAGE_FIELDS.every((key) => cumulative[key] - previous[key] === last[key]);
    if (!restarted && !reconciled) {
      const bridged = unreportedRequests(previous, cumulative, last, pending);
      if (bridged === null) {
        state.malformedRecords += 1;
        return [];
      }
      unreported = bridged;
    }
    if (restarted) state.sequenceStartSignature = sequenceStart;
  } else {
    if (signature === state.lastUsageSignature) return [];
    // Advance expected totals for billed legacy requests so a cumulative re-emission is stale.
    const advanced = advanceCodexUsage(previous, last);
    if (advanced === null) {
      state.malformedRecords += 1;
      return [];
    }
    state.lastCumulativeUsage = advanced;
  }
  state.lastUsageSignature = signature;

  return [
    ...unreported.map((request) => codexRequestRecord(state, request.usage, request)),
    codexRequestRecord(state, last, codexAttribution(state, timestampMs)),
  ];
}

function codexAttribution(state: CodexScanState, timestampMs: number): CodexRequestAttribution {
  return {
    timestampMs,
    model: state.model,
    turnId: state.turnId,
    speed: state.speed,
    sawThreadSettings: state.sawThreadSettings,
  };
}

function codexRequestRecord(
  state: CodexScanState,
  usage: CodexTokenUsage,
  { timestampMs, model, turnId, speed, sawThreadSettings }: CodexRequestAttribution,
): UsageRecord {
  const inputTokens = usage.input_tokens;
  const cachedInputTokens = usage.cached_input_tokens;
  const cacheCreationTokens = usage.cache_write_input_tokens;
  const outputTokens = usage.output_tokens;

  const totals: UsageTokenTotals = {
    // Codex reports `input_tokens` inclusive of the cached portion.
    uncachedInputTokens: inputTokens - cachedInputTokens - cacheCreationTokens,
    cachedInputTokens,
    cacheCreationTokens,
    outputTokens,
    // Reported inside output_tokens, surfaced separately for the token mix.
    reasoningTokens: usage.reasoning_output_tokens,
  };

  return {
    provider: "codex",
    timestampMs,
    model,
    sessionId: state.sessionId,
    totals,
    reportedCostUsd: null,
    speed,
    ...(!sawThreadSettings &&
    state.modelProvider === "openai" &&
    state.sessionId.length > 0 &&
    turnId.length > 0
      ? { unresolvedServiceTierTurnId: turnId }
      : {}),
    dedupeKey: null,
  };
}

/** Missing, default and standard tiers bill as standard; fast aliases priority. */
function codexSpeed(serviceTier: unknown): UsageSpeed {
  if (serviceTier === "priority" || serviceTier === "fast") return "fast";
  if (serviceTier === "ultrafast") return "ultrafast";
  return "standard";
}

