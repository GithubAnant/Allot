// Extracted from T3 Code 60f70d98cdeb2c692db649b9ade3adf74dd62bf9; MIT license in T3-LICENSE.txt. Native I/O and SwiftUI replace the host and chart.
var T3Usage = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // t3-source/entry.ts
  var entry_exports = {};
  __export(entry_exports, {
    cursorRateModel: () => cursorRateModel,
    decodeCacheJSON: () => decodeCacheJSON,
    loadHistoryCacheJSON: () => loadHistoryCacheJSON,
    parseTranscriptJSON: () => parseTranscriptJSON,
    poolJSON: () => poolJSON,
    summaryJSON: () => summaryJSON,
    updateHistoryTranscriptJSON: () => updateHistoryTranscriptJSON
  });

  // t3-source/core.ts
  var EMPTY_TOTALS = {
    uncachedInputTokens: 0,
    cachedInputTokens: 0,
    cacheCreationTokens: 0,
    outputTokens: 0,
    reasoningTokens: 0
  };
  function tokenCount(value) {
    return typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.trunc(value) : 0;
  }
  function parseTimestampMs(value) {
    if (typeof value !== "string") return null;
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }

  // t3-source/pricing.ts
  function createOverrideRateTable(overrides) {
    return new Map(
      Object.entries(overrides).map(([model, prices]) => {
        const cacheCreationCostPerToken = (prices.cacheWriteCostPerMillionTokens ?? prices.inputCostPerMillionTokens) / 1e6;
        return [
          model.trim(),
          {
            inputCostPerToken: prices.inputCostPerMillionTokens / 1e6,
            outputCostPerToken: prices.outputCostPerMillionTokens / 1e6,
            cacheReadCostPerToken: (prices.cacheReadCostPerMillionTokens ?? prices.inputCostPerMillionTokens) / 1e6,
            cacheCreationCostPerToken,
            cacheCreation1hCostPerToken: cacheCreationCostPerToken,
            fast: null,
            ultrafast: null,
            contextTiers: []
          }
        ];
      })
    );
  }
  function finiteNumber(value) {
    return typeof value === "number" && Number.isFinite(value) ? value : null;
  }
  function readTokenRates(entry, suffix, standard, outputFallback) {
    const input = finiteNumber(entry[`input_cost_per_token${suffix}`]);
    const output = finiteNumber(entry[`output_cost_per_token${suffix}`]) ?? outputFallback ?? null;
    if (input === null || output === null) return null;
    const cacheRate = (name, field, fallback = input) => finiteNumber(entry[`${name}${suffix}`]) ?? (standard !== void 0 && standard.inputCostPerToken > 0 ? standard[field] / standard.inputCostPerToken * input : fallback);
    const cacheCreationCostPerToken = cacheRate(
      "cache_creation_input_token_cost",
      "cacheCreationCostPerToken"
    );
    return {
      inputCostPerToken: input,
      outputCostPerToken: output,
      cacheReadCostPerToken: cacheRate("cache_read_input_token_cost", "cacheReadCostPerToken"),
      cacheCreationCostPerToken,
      cacheCreation1hCostPerToken: cacheRate(
        "cache_creation_input_token_cost_above_1hr",
        "cacheCreation1hCostPerToken",
        cacheCreationCostPerToken
      )
    };
  }
  function scaleTokenRates(rates, multiple) {
    return {
      inputCostPerToken: rates.inputCostPerToken * multiple,
      outputCostPerToken: rates.outputCostPerToken * multiple,
      cacheReadCostPerToken: rates.cacheReadCostPerToken * multiple,
      cacheCreationCostPerToken: rates.cacheCreationCostPerToken * multiple,
      cacheCreation1hCostPerToken: rates.cacheCreation1hCostPerToken * multiple
    };
  }
  function fastMultiplier(entry) {
    const specific = entry["provider_specific_entry"];
    if (typeof specific !== "object" || specific === null) return null;
    const fast = finiteNumber(specific["fast"]);
    return fast !== null && fast > 0 ? fast : null;
  }
  function readSpeedRates(entry, standard, suffix = "") {
    const multiple = fastMultiplier(entry);
    return {
      ...standard,
      fast: multiple === null ? readTokenRates(entry, `${suffix}_priority`, standard) : scaleTokenRates(standard, multiple),
      ultrafast: readTokenRates(entry, `${suffix}_ultrafast`, standard)
    };
  }
  var CONTEXT_TIER_INPUT_KEY = /^input_cost_per_token_above_(\d{1,7})k_tokens(?:_priority|_ultrafast)?$/;
  function readContextTiers(entry, base) {
    const thresholds = /* @__PURE__ */ new Set();
    for (const key of Object.keys(entry)) {
      const match = CONTEXT_TIER_INPUT_KEY.exec(key);
      if (match !== null) thresholds.add(match[1]);
    }
    return [...thresholds].map((threshold) => {
      const suffix = `_above_${threshold}k_tokens`;
      const standard = readTokenRates(entry, suffix, base, base.outputCostPerToken) ?? base;
      return {
        thresholdTokens: Number(threshold) * 1e3,
        rate: readSpeedRates(entry, standard, suffix)
      };
    }).toSorted((a, b) => b.thresholdTokens - a.thresholdTokens);
  }
  var FIRST_PARTY_PROVIDERS = /* @__PURE__ */ new Set([
    "anthropic",
    "deepseek",
    "gemini",
    "meta",
    "mistral",
    "openai",
    "xai"
  ]);
  function parseRateTable(document) {
    const table = /* @__PURE__ */ new Map();
    if (typeof document !== "object" || document === null) return table;
    for (const [name, raw] of Object.entries(document)) {
      if (typeof raw !== "object" || raw === null) continue;
      const entry = raw;
      const standard = readTokenRates(entry, "");
      if (standard === null) continue;
      const key = normalizeRateKey(name);
      if (key.length === 0) continue;
      table.set(key, {
        ...readSpeedRates(entry, standard),
        contextTiers: readContextTiers(entry, standard)
      });
    }
    const aliasCandidates = /* @__PURE__ */ new Map();
    for (const [key, rate] of table) {
      const slash = key.indexOf("/");
      const alias = slash === -1 ? bedrockBaseModelName(key) : bareModelName(key);
      if (alias.length === 0 || alias === key || table.has(alias)) continue;
      const firstParty = slash !== -1 && FIRST_PARTY_PROVIDERS.has(key.slice(0, slash));
      const held = aliasCandidates.get(alias);
      if (held === void 0 || firstParty && !held.firstParty) {
        aliasCandidates.set(alias, { rate, firstParty });
      } else if (held.rate !== null && firstParty === held.firstParty) {
        aliasCandidates.set(alias, { rate: mergeAliasRate(held.rate, rate), firstParty });
      }
    }
    for (const [alias, { rate }] of aliasCandidates) {
      if (rate !== null) table.set(alias, rate);
    }
    return table;
  }
  function sameTokenRates(a, b) {
    if (a === null || b === null) return a === b;
    return a.inputCostPerToken === b.inputCostPerToken && a.outputCostPerToken === b.outputCostPerToken && a.cacheReadCostPerToken === b.cacheReadCostPerToken && a.cacheCreationCostPerToken === b.cacheCreationCostPerToken && a.cacheCreation1hCostPerToken === b.cacheCreation1hCostPerToken;
  }
  function mergeSpeedRates(a, b) {
    const fast = a.fast ?? b.fast;
    const ultrafast = a.ultrafast ?? b.ultrafast;
    if (!sameTokenRates(a, b) || !sameTokenRates(fast, b.fast ?? fast) || !sameTokenRates(ultrafast, b.ultrafast ?? ultrafast)) {
      return null;
    }
    return { ...a, fast, ultrafast };
  }
  function mergeContextTiers(a, b) {
    if (a.length === 0) return b;
    if (b.length === 0) return a;
    if (a.length !== b.length) return null;
    const merged = [];
    for (const [index, tier] of a.entries()) {
      const other = b[index];
      const rate = mergeSpeedRates(tier.rate, other.rate);
      if (tier.thresholdTokens !== other.thresholdTokens || rate === null) return null;
      merged.push({ thresholdTokens: tier.thresholdTokens, rate });
    }
    return merged;
  }
  function mergeAliasRate(a, b) {
    const speeds = mergeSpeedRates(a, b);
    const contextTiers = mergeContextTiers(a.contextTiers, b.contextTiers);
    return speeds === null || contextTiers === null ? null : { ...speeds, contextTiers };
  }
  function promptTokens(totals) {
    return totals.uncachedInputTokens + totals.cachedInputTokens + totals.cacheCreationTokens;
  }
  function ratesAt(rate, speed, totals) {
    const prompt = promptTokens(totals);
    const tier = rate.contextTiers.find((tier2) => prompt > tier2.thresholdTokens)?.rate;
    if (speed === "standard") return tier ?? rate;
    return tier?.[speed] ?? rate[speed] ?? tier ?? rate;
  }
  function normalizeRateKey(model) {
    return model.trim().toLowerCase();
  }
  function bareModelName(key) {
    const slash = key.lastIndexOf("/");
    return slash === -1 ? key : key.slice(slash + 1);
  }
  function bedrockBaseModelName(key) {
    return key.startsWith("anthropic.") ? key.slice("anthropic.".length) : key;
  }
  function stripVariantSuffix(key) {
    const bracket = key.indexOf("[");
    return bracket === -1 ? key : key.slice(0, bracket);
  }
  var UNPRICEABLE_MODELS = /* @__PURE__ */ new Set([
    "<synthetic>",
    "synthetic",
    "opus",
    "sonnet",
    "haiku",
    "fable"
  ]);
  var resolvedRates = /* @__PURE__ */ new WeakMap();
  function lookupRate(table, model) {
    let resolved = resolvedRates.get(table);
    if (resolved === void 0) {
      resolved = /* @__PURE__ */ new Map();
      resolvedRates.set(table, resolved);
    }
    let rate = resolved.get(model);
    if (rate === void 0) {
      rate = resolveRate(table, model);
      resolved.set(model, rate);
    }
    return rate;
  }
  function resolveRate(table, model) {
    const key = stripVariantSuffix(normalizeRateKey(model));
    const bareName = bareModelName(key);
    if (bareName.length === 0 || UNPRICEABLE_MODELS.has(bareName)) return null;
    return table.get(key) ?? null;
  }
  function recordRate(table, record) {
    const rate = record.rateModel === void 0 ? null : lookupRate(table, record.rateModel);
    return rate ?? lookupRate(table, record.model);
  }
  function costByCategory(record, rates) {
    const { totals } = record;
    const oneHour = Math.min(record.cacheCreation1hTokens ?? 0, totals.cacheCreationTokens);
    return {
      input: totals.uncachedInputTokens * rates.inputCostPerToken,
      cacheRead: totals.cachedInputTokens * rates.cacheReadCostPerToken,
      cacheWrite: (totals.cacheCreationTokens - oneHour) * rates.cacheCreationCostPerToken + oneHour * rates.cacheCreation1hCostPerToken,
      output: totals.outputTokens * rates.outputCostPerToken
    };
  }
  function sumCategories(cost) {
    return cost.input + cost.cacheRead + cost.cacheWrite + cost.output;
  }
  function priceUsage(table, record, overrides) {
    const { model, totals, reportedCostUsd } = record;
    const override = overrides?.get(model.trim());
    const reported = override === void 0 && reportedCostUsd !== null && Number.isFinite(reportedCostUsd) ? reportedCostUsd : null;
    const unsplit = (costUsd, costSource) => ({
      costUsd,
      costSource,
      categoryCostUsd: null,
      speedPremiumUsd: 0
    });
    const rate = override ?? recordRate(table, record);
    if (rate === null) {
      return reported === null ? unsplit(0, "unpriced") : unsplit(reported, "providerReported");
    }
    const listCost = costByCategory(record, ratesAt(rate, record.speed, totals));
    const listCostUsd = sumCategories(listCost);
    if (reported !== null && listCostUsd <= 0) return unsplit(reported, "providerReported");
    const premiumUsd = record.speed === "standard" ? 0 : listCostUsd - sumCategories(costByCategory(record, ratesAt(rate, "standard", totals)));
    const scale = reported === null ? 1 : reported / listCostUsd;
    return {
      costUsd: reported ?? listCostUsd,
      costSource: reported === null ? "modelPriced" : "providerReported",
      categoryCostUsd: {
        input: listCost.input * scale,
        cacheRead: listCost.cacheRead * scale,
        cacheWrite: listCost.cacheWrite * scale,
        output: listCost.output * scale
      },
      speedPremiumUsd: premiumUsd * scale
    };
  }
  function cacheSavingsUsd(table, record, overrides) {
    const rate = overrides?.get(record.model.trim()) ?? recordRate(table, record);
    if (rate === null) return 0;
    const rates = ratesAt(rate, record.speed, record.totals);
    return record.totals.cachedInputTokens * (rates.inputCostPerToken - rates.cacheReadCostPerToken);
  }

  // t3-source/aggregation.ts
  function makeDayFormatter(timeZone) {
    let format;
    try {
      format = new Intl.DateTimeFormat("en-CA", {
        timeZone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit"
      });
    } catch {
      format = new Intl.DateTimeFormat("en-CA", {
        timeZone: "UTC",
        year: "numeric",
        month: "2-digit",
        day: "2-digit"
      });
    }
    const days = /* @__PURE__ */ new Map();
    return (timestampMs) => {
      const slot = Math.floor(timestampMs / QUARTER_HOUR_MS);
      let day = days.get(slot);
      if (day === void 0) {
        const first = format.format(new Date(slot * QUARTER_HOUR_MS));
        const last = format.format(new Date((slot + 1) * QUARTER_HOUR_MS - 1));
        day = first === last ? first : null;
        days.set(slot, day);
      }
      return day ?? format.format(new Date(timestampMs));
    };
  }
  var QUARTER_HOUR_MS = 15 * 60 * 1e3;
  var HOUR_MS = 60 * 60 * 1e3;
  function resolveModelAliases(aliases) {
    const resolved = /* @__PURE__ */ new Map();
    for (const model of Object.keys(aliases)) {
      const seen = /* @__PURE__ */ new Set([model]);
      let target = aliases[model];
      while (Object.hasOwn(aliases, target) && !seen.has(target)) {
        seen.add(target);
        target = aliases[target];
      }
      if (!Object.hasOwn(aliases, target)) resolved.set(model, target);
    }
    return resolved;
  }
  function keepsUsageRecord(filter, record) {
    if (filter === void 0) return true;
    const model = record.model.trim();
    const matches = (selector) => selector.model === model && (selector.provider === void 0 || selector.provider === record.provider);
    return (filter.include?.some(matches) ?? true) && !(filter.exclude?.some(matches) ?? false);
  }
  function mergeUsageCopies(held, copy) {
    const a = held.totals;
    const b = copy.totals;
    const reportedCostUsd = held.reportedCostUsd === null || copy.reportedCostUsd === null ? held.reportedCostUsd ?? copy.reportedCostUsd : Math.max(held.reportedCostUsd, copy.reportedCostUsd);
    if (b.uncachedInputTokens <= a.uncachedInputTokens && b.cachedInputTokens <= a.cachedInputTokens && b.cacheCreationTokens <= a.cacheCreationTokens && b.outputTokens <= a.outputTokens && b.reasoningTokens <= a.reasoningTokens && (copy.cacheCreation1hTokens ?? 0) <= (held.cacheCreation1hTokens ?? 0) && reportedCostUsd === held.reportedCostUsd) {
      return held;
    }
    const cacheCreation1hTokens = Math.max(
      held.cacheCreation1hTokens ?? 0,
      copy.cacheCreation1hTokens ?? 0
    );
    return {
      ...held,
      ...cacheCreation1hTokens > 0 ? { cacheCreation1hTokens } : {},
      totals: {
        uncachedInputTokens: Math.max(a.uncachedInputTokens, b.uncachedInputTokens),
        cachedInputTokens: Math.max(a.cachedInputTokens, b.cachedInputTokens),
        cacheCreationTokens: Math.max(a.cacheCreationTokens, b.cacheCreationTokens),
        outputTokens: Math.max(a.outputTokens, b.outputTokens),
        reasoningTokens: Math.max(a.reasoningTokens, b.reasoningTokens)
      },
      reportedCostUsd
    };
  }
  var UsageAggregator = class {
    #buckets = /* @__PURE__ */ new Map();
    #seen = /* @__PURE__ */ new Map();
    #toDay;
    #hourlyWindow;
    #options;
    #lastBucket = null;
    #duplicatesDropped = 0;
    #outOfWindow = 0;
    constructor(options) {
      this.#options = options;
      this.#toDay = makeDayFormatter(options.timeZone);
      if (options.resolution === "hour") {
        if (options.sinceTimeMs === void 0 || options.untilTimeMs === void 0) {
          throw new Error("Hourly usage aggregation requires exact time bounds");
        }
        this.#hourlyWindow = {
          sinceTimeMs: options.sinceTimeMs,
          untilTimeMs: options.untilTimeMs
        };
      } else {
        this.#hourlyWindow = null;
      }
    }
    add(input, sourcePath) {
      if (!keepsUsageRecord(this.#options.modelFilter, input)) return false;
      const record = this.#mapModel(input);
      if (record.dedupeKey !== null) {
        const held = this.#seen.get(record.dedupeKey);
        if (held !== void 0) {
          this.#duplicatesDropped += 1;
          if (held.bucket !== null) held.record = mergeUsageCopies(held.record, record);
          return false;
        }
      }
      const bucket = this.#placeInWindow(record, sourcePath ?? "");
      if (record.dedupeKey !== null) this.#seen.set(record.dedupeKey, { record, bucket });
      if (bucket === null) {
        this.#outOfWindow += 1;
        return false;
      }
      if (record.dedupeKey === null) this.#accumulate(bucket, record);
      if (record.sessionId.length > 0) bucket.sessions.add(record.sessionId);
      return true;
    }
    #placeInWindow(record, source) {
      if (this.#hourlyWindow !== null && (record.timestampMs < this.#hourlyWindow.sinceTimeMs || record.timestampMs >= this.#hourlyWindow.untilTimeMs)) {
        return null;
      }
      const day = this.#toDay(record.timestampMs);
      if (this.#hourlyWindow === null && (day < this.#options.sinceDay || day > this.#options.untilDay)) {
        return null;
      }
      const hourIndex = this.#hourlyWindow === null ? -1 : Math.floor((record.timestampMs - this.#hourlyWindow.sinceTimeMs) / HOUR_MS);
      return this.#bucketFor(day, hourIndex, record.provider, record.model, source);
    }
    #accumulate(bucket, record) {
      const priced = priceUsage(this.#options.rates, record, this.#options.priceOverrides);
      const totals = bucket.totals;
      totals.uncachedInputTokens += record.totals.uncachedInputTokens;
      totals.cachedInputTokens += record.totals.cachedInputTokens;
      totals.cacheCreationTokens += record.totals.cacheCreationTokens;
      totals.outputTokens += record.totals.outputTokens;
      totals.reasoningTokens += record.totals.reasoningTokens;
      bucket.costUsd += priced.costUsd;
      if (priced.categoryCostUsd !== null) {
        const sum = bucket.categoryCostUsd;
        const add = priced.categoryCostUsd;
        bucket.categoryCostUsd = sum === null ? add : {
          input: sum.input + add.input,
          cacheRead: sum.cacheRead + add.cacheRead,
          cacheWrite: sum.cacheWrite + add.cacheWrite,
          output: sum.output + add.output
        };
      }
      if (record.speed === "fast") bucket.fastCostUsd += priced.costUsd;
      if (record.speed === "ultrafast") bucket.ultrafastCostUsd += priced.costUsd;
      bucket.speedPremiumUsd += priced.speedPremiumUsd;
      bucket.cacheSavingsUsd += cacheSavingsUsd(
        this.#options.rates,
        record,
        this.#options.priceOverrides
      );
      bucket.records += 1;
      if (priced.costSource === "unpriced") {
        bucket.unpricedRecords += 1;
        bucket.unpricedTokens += record.totals.uncachedInputTokens + record.totals.cachedInputTokens + record.totals.cacheCreationTokens + record.totals.outputTokens;
      }
      if (priced.costSource === "providerReported") bucket.providerReportedRecords += 1;
    }
    // Aliases use the target's rate, replacing provider-specific rateModel.
    #mapModel(record) {
      const model = this.#options.modelAliases?.get(record.model);
      if (model === void 0) return record;
      const { rateModel: _rateModel, ...rest } = record;
      return { ...rest, model };
    }
    // Time-ordered records usually reuse the previous bucket; avoid rebuilding its key.
    #bucketFor(day, hourIndex, provider, model, source) {
      const last = this.#lastBucket;
      if (last !== null && last.day === day && last.hourIndex === hourIndex && last.provider === provider && last.model === model && last.source === source) {
        return last.bucket;
      }
      const window = this.#hourlyWindow;
      const hourStart = window === null ? "" : new Date(window.sinceTimeMs + hourIndex * HOUR_MS).toISOString();
      const key = `${day}\0${hourStart}\0${provider}\0${model}\0${source}`;
      let bucket = this.#buckets.get(key);
      if (bucket === void 0) {
        bucket = {
          totals: { ...EMPTY_TOTALS },
          costUsd: 0,
          cacheSavingsUsd: 0,
          categoryCostUsd: null,
          fastCostUsd: 0,
          ultrafastCostUsd: 0,
          speedPremiumUsd: 0,
          records: 0,
          unpricedRecords: 0,
          unpricedTokens: 0,
          providerReportedRecords: 0,
          sessions: /* @__PURE__ */ new Set()
        };
        this.#buckets.set(key, bucket);
      }
      this.#lastBucket = { day, hourIndex, provider, model, source, bucket };
      return bucket;
    }
    finish() {
      for (const { record, bucket } of this.#seen.values()) {
        if (bucket !== null) this.#accumulate(bucket, record);
      }
      this.#seen.clear();
      const buckets = [];
      for (const [key, bucket] of this.#buckets) {
        const [day = "", hourStart = "", provider = "", model = "", sourcePath = ""] = key.split("\0");
        const category = bucket.categoryCostUsd;
        const fastCostUsd = roundUsd(bucket.fastCostUsd);
        const ultrafastCostUsd = roundUsd(bucket.ultrafastCostUsd);
        const speedPremiumUsd = roundUsd(bucket.speedPremiumUsd);
        buckets.push({
          day,
          ...hourStart === "" ? {} : { hourStart },
          provider,
          model,
          ...sourcePath === "" ? {} : { sourcePath },
          totals: { ...bucket.totals },
          costUsd: bucket.costUsd,
          cacheSavingsUsd: bucket.cacheSavingsUsd,
          ...category === null ? {} : {
            categoryCostUsd: {
              input: roundUsd(category.input),
              cacheRead: roundUsd(category.cacheRead),
              cacheWrite: roundUsd(category.cacheWrite),
              output: roundUsd(category.output)
            }
          },
          ...fastCostUsd === 0 ? {} : { fastCostUsd },
          ...ultrafastCostUsd === 0 ? {} : { ultrafastCostUsd },
          ...speedPremiumUsd === 0 ? {} : { speedPremiumUsd },
          costSource: resolveCostSource(bucket),
          records: bucket.records,
          unpricedRecords: bucket.unpricedRecords,
          unpricedTokens: bucket.unpricedTokens,
          sessions: bucket.sessions.size
        });
      }
      buckets.sort(
        (a, b) => a.day.localeCompare(b.day) || (a.hourStart ?? "").localeCompare(b.hourStart ?? "") || a.provider.localeCompare(b.provider) || a.model.localeCompare(b.model)
      );
      return {
        buckets,
        duplicatesDropped: this.#duplicatesDropped,
        outOfWindow: this.#outOfWindow
      };
    }
  };
  function roundUsd(value) {
    return Math.round(value * 1e6) / 1e6;
  }
  function resolveCostSource(bucket) {
    if (bucket.unpricedRecords === bucket.records) return "unpriced";
    if (bucket.providerReportedRecords === bucket.records) return "providerReported";
    return "modelPriced";
  }

  // t3-source/merge.ts
  var USAGE_MERGE_COMPATIBLE_SINCE = 4;
  function fingerprintKey(fingerprint) {
    return [
      fingerprint.hostId,
      fingerprint.provider,
      fingerprint.resolvedHomePath,
      fingerprint.volumeId
    ].join(" ");
  }
  function bucketsForSource(summary, source) {
    const providerSources = summary.sources.filter(
      (entry) => entry.fingerprint.provider === source.fingerprint.provider
    );
    return summary.buckets.filter(
      (bucket) => bucket.provider === source.fingerprint.provider && (bucket.sourcePath === source.fingerprint.resolvedHomePath || bucket.sourcePath === void 0 && providerSources.length === 1)
    );
  }
  function bucketKey(bucket) {
    return JSON.stringify([bucket.day, bucket.hourStart ?? null, bucket.provider, bucket.model]);
  }
  function claimSources(environments) {
    const ownerByFingerprint = /* @__PURE__ */ new Map();
    const ownerScanByFingerprint = /* @__PURE__ */ new Map();
    const seenBucketKeysByFingerprint = /* @__PURE__ */ new Map();
    const supplementalBucketsByEnvironment = /* @__PURE__ */ new Map();
    const sessionsByFingerprint = /* @__PURE__ */ new Map();
    const duplicates = [];
    const ordered = [...environments].sort(
      (a, b) => (Date.parse(b.summary.readAt) || 0) - (Date.parse(a.summary.readAt) || 0) || a.environmentId.localeCompare(b.environmentId)
    );
    for (const status of ["ok", "partial", "failed"]) {
      for (const environment of ordered) {
        for (const source of environment.summary.sources) {
          if (source.status !== status) continue;
          const key = fingerprintKey(source.fingerprint);
          if (ownerByFingerprint.has(key)) {
            duplicates.push(`${environment.label}: ${source.fingerprint.resolvedHomePath}`);
            continue;
          }
          ownerByFingerprint.set(key, environment.environmentId);
          ownerScanByFingerprint.set(key, { environment, source });
          sessionsByFingerprint.set(key, source.distinctSessions);
        }
      }
    }
    for (const environment of ordered) {
      for (const source of environment.summary.sources) {
        if (source.status !== "partial") continue;
        const key = fingerprintKey(source.fingerprint);
        const owner = ownerScanByFingerprint.get(key);
        if (owner?.source.status !== "ok" || Date.parse(environment.summary.readAt) <= Date.parse(owner.environment.summary.readAt) || JSON.stringify(environment.summary.modelFilter) !== JSON.stringify(owner.environment.summary.modelFilter)) {
          continue;
        }
        let seen = seenBucketKeysByFingerprint.get(key);
        if (seen === void 0) {
          seen = new Set(bucketsForSource(owner.environment.summary, owner.source).map(bucketKey));
          seenBucketKeysByFingerprint.set(key, seen);
        }
        const supplemental = supplementalBucketsByEnvironment.get(environment.environmentId) ?? /* @__PURE__ */ new Set();
        let added = false;
        for (const bucket of bucketsForSource(environment.summary, source)) {
          const cell = bucketKey(bucket);
          if (seen.has(cell)) continue;
          seen.add(cell);
          supplemental.add(bucket);
          added = true;
        }
        if (!added) continue;
        supplementalBucketsByEnvironment.set(environment.environmentId, supplemental);
        sessionsByFingerprint.set(
          key,
          Math.max(sessionsByFingerprint.get(key) ?? 0, source.distinctSessions)
        );
      }
    }
    return {
      ownerByFingerprint,
      supplementalBucketsByEnvironment,
      sessionsByFingerprint,
      duplicates
    };
  }
  function ownedContribution(environment, ownerByFingerprint, supplementalBuckets, sessionsByFingerprint) {
    const ownedProviders = /* @__PURE__ */ new Set();
    const ownedSources = /* @__PURE__ */ new Set();
    const sessionsByProvider = /* @__PURE__ */ new Map();
    for (const source of environment.summary.sources) {
      if (source.status === "missing") continue;
      const key = fingerprintKey(source.fingerprint);
      if (ownerByFingerprint.get(key) === environment.environmentId) {
        const provider = source.fingerprint.provider;
        ownedProviders.add(provider);
        ownedSources.add(`${provider}\0${source.fingerprint.resolvedHomePath}`);
        sessionsByProvider.set(
          provider,
          (sessionsByProvider.get(provider) ?? 0) + (sessionsByFingerprint.get(key) ?? source.distinctSessions)
        );
      }
    }
    return {
      buckets: environment.summary.buckets.filter(
        (bucket) => supplementalBuckets.has(bucket) || (bucket.sourcePath === void 0 ? ownedProviders.has(bucket.provider) : ownedSources.has(`${bucket.provider}\0${bucket.sourcePath}`))
      ),
      sessionsByProvider
    };
  }
  function bucketTokens(bucket) {
    return bucket.totals.uncachedInputTokens + bucket.totals.cachedInputTokens + bucket.totals.cacheCreationTokens + bucket.totals.outputTokens;
  }
  function isCompatibleUsageContractVersion(version, expected) {
    return version >= USAGE_MERGE_COMPATIBLE_SINCE && version <= expected;
  }
  var EMPTY_MERGED = {
    costUsd: 0,
    uncachedInputTokens: 0,
    cachedInputTokens: 0,
    cacheCreationTokens: 0,
    outputTokens: 0,
    reasoningTokens: 0,
    totalTokens: 0,
    records: 0,
    sessions: 0,
    providers: [],
    models: [],
    daily: [],
    hourly: [],
    costQuality: {
      providerReportedShare: 0,
      modelPricedShare: 0,
      unpricedShare: 0,
      cacheSavingsUsd: 0
    },
    categoryCost: { input: 0, cacheRead: 0, cacheWrite: 0, output: 0, unsplit: 0 },
    speedCost: { standard: 0, fast: 0, ultrafast: 0, premium: 0 },
    duplicateSources: [],
    contributingEnvironments: [],
    contractMismatches: []
  };
  function mergeUsage(environments, expectedContractVersion) {
    if (environments.length === 0) return EMPTY_MERGED;
    const current = [];
    const contractMismatches = [];
    for (const environment of environments) {
      if (isCompatibleUsageContractVersion(environment.summary.contractVersion, expectedContractVersion)) {
        current.push(environment);
      } else {
        contractMismatches.push({
          environmentId: environment.environmentId,
          direction: environment.summary.contractVersion < expectedContractVersion ? "serverBehind" : "clientBehind",
          contractVersion: environment.summary.contractVersion
        });
      }
    }
    const {
      ownerByFingerprint,
      supplementalBucketsByEnvironment,
      sessionsByFingerprint,
      duplicates
    } = claimSources(current);
    let costUsd = 0;
    let uncachedInputTokens = 0;
    let cachedInputTokens = 0;
    let cacheCreationTokens = 0;
    let outputTokens = 0;
    let reasoningTokens = 0;
    let records = 0;
    let sessions = 0;
    let cacheSavingsUsd2 = 0;
    let providerReportedRecords = 0;
    let unpricedRecords = 0;
    const categoryCost = { input: 0, cacheRead: 0, cacheWrite: 0, output: 0 };
    const speedCost = { fast: 0, ultrafast: 0, premium: 0 };
    const providerAccumulator = /* @__PURE__ */ new Map();
    const modelAccumulator = /* @__PURE__ */ new Map();
    const dailyAccumulator = /* @__PURE__ */ new Map();
    const hourlyAccumulator = /* @__PURE__ */ new Map();
    const contributingEnvironments = [];
    for (const environment of current) {
      const { buckets, sessionsByProvider } = ownedContribution(
        environment,
        ownerByFingerprint,
        supplementalBucketsByEnvironment.get(environment.environmentId) ?? /* @__PURE__ */ new Set(),
        sessionsByFingerprint
      );
      if (buckets.length > 0) contributingEnvironments.push(environment.environmentId);
      for (const [providerKind, providerSessions] of sessionsByProvider) {
        sessions += providerSessions;
        if (providerSessions === 0) continue;
        const provider = providerAccumulator.get(providerKind) ?? {
          costUsd: 0,
          totalTokens: 0,
          records: 0,
          sessions: 0
        };
        provider.sessions += providerSessions;
        providerAccumulator.set(providerKind, provider);
      }
      for (const bucket of buckets) {
        const tokens = bucketTokens(bucket);
        costUsd += bucket.costUsd;
        cacheSavingsUsd2 += bucket.cacheSavingsUsd;
        uncachedInputTokens += bucket.totals.uncachedInputTokens;
        cachedInputTokens += bucket.totals.cachedInputTokens;
        cacheCreationTokens += bucket.totals.cacheCreationTokens;
        outputTokens += bucket.totals.outputTokens;
        reasoningTokens += bucket.totals.reasoningTokens;
        records += bucket.records;
        unpricedRecords += bucket.unpricedRecords;
        if (bucket.costSource === "providerReported") providerReportedRecords += bucket.records;
        if (bucket.categoryCostUsd !== void 0) {
          categoryCost.input += bucket.categoryCostUsd.input;
          categoryCost.cacheRead += bucket.categoryCostUsd.cacheRead;
          categoryCost.cacheWrite += bucket.categoryCostUsd.cacheWrite;
          categoryCost.output += bucket.categoryCostUsd.output;
        }
        speedCost.fast += bucket.fastCostUsd ?? 0;
        speedCost.ultrafast += bucket.ultrafastCostUsd ?? 0;
        speedCost.premium += bucket.speedPremiumUsd ?? 0;
        const provider = providerAccumulator.get(bucket.provider) ?? {
          costUsd: 0,
          totalTokens: 0,
          records: 0,
          sessions: 0
        };
        provider.costUsd += bucket.costUsd;
        provider.totalTokens += tokens;
        provider.records += bucket.records;
        providerAccumulator.set(bucket.provider, provider);
        const modelKey = `${bucket.provider} ${bucket.model}`;
        const model = modelAccumulator.get(modelKey) ?? {
          provider: bucket.provider,
          costUsd: 0,
          totalTokens: 0,
          tokens: {
            uncachedInputTokens: 0,
            cachedInputTokens: 0,
            cacheCreationTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0
          },
          records: 0,
          unpricedRecords: 0,
          unpricedTokens: 0
        };
        model.costUsd += bucket.costUsd;
        model.totalTokens += tokens;
        model.tokens = {
          uncachedInputTokens: model.tokens.uncachedInputTokens + bucket.totals.uncachedInputTokens,
          cachedInputTokens: model.tokens.cachedInputTokens + bucket.totals.cachedInputTokens,
          cacheCreationTokens: model.tokens.cacheCreationTokens + bucket.totals.cacheCreationTokens,
          outputTokens: model.tokens.outputTokens + bucket.totals.outputTokens,
          reasoningTokens: model.tokens.reasoningTokens + bucket.totals.reasoningTokens
        };
        model.records += bucket.records;
        model.unpricedRecords += bucket.unpricedRecords;
        if (bucket.unpricedTokens !== void 0) {
          model.unpricedTokens += bucket.unpricedTokens;
        } else if (bucket.records > 0) {
          model.unpricedTokens += tokens * bucket.unpricedRecords / bucket.records;
        }
        modelAccumulator.set(modelKey, model);
        const day = dailyAccumulator.get(bucket.day) ?? {
          costUsd: 0,
          totalTokens: 0,
          byProvider: /* @__PURE__ */ new Map()
        };
        day.costUsd += bucket.costUsd;
        day.totalTokens += tokens;
        const dayProvider = day.byProvider.get(bucket.provider) ?? { costUsd: 0, totalTokens: 0 };
        dayProvider.costUsd += bucket.costUsd;
        dayProvider.totalTokens += tokens;
        day.byProvider.set(bucket.provider, dayProvider);
        dailyAccumulator.set(bucket.day, day);
        if (bucket.hourStart !== void 0) {
          const hour = hourlyAccumulator.get(bucket.hourStart) ?? {
            day: bucket.day,
            hourStart: bucket.hourStart,
            costUsd: 0,
            totalTokens: 0,
            byProvider: /* @__PURE__ */ new Map()
          };
          hour.costUsd += bucket.costUsd;
          hour.totalTokens += tokens;
          const hourProvider = hour.byProvider.get(bucket.provider) ?? {
            costUsd: 0,
            totalTokens: 0
          };
          hourProvider.costUsd += bucket.costUsd;
          hourProvider.totalTokens += tokens;
          hour.byProvider.set(bucket.provider, hourProvider);
          hourlyAccumulator.set(bucket.hourStart, hour);
        }
      }
    }
    const totalTokens = uncachedInputTokens + cachedInputTokens + cacheCreationTokens + outputTokens;
    const providers = [...providerAccumulator.entries()].map(([provider, totals]) => ({
      provider,
      costUsd: totals.costUsd,
      totalTokens: totals.totalTokens,
      records: totals.records,
      sessions: totals.sessions,
      costShare: costUsd === 0 ? 0 : totals.costUsd / costUsd,
      tokenShare: totalTokens === 0 ? 0 : totals.totalTokens / totalTokens
    })).sort((a, b) => b.costUsd - a.costUsd);
    const models = [...modelAccumulator.entries()].map(([key, totals]) => ({
      model: key.slice(key.indexOf(" ") + 1),
      provider: totals.provider,
      costUsd: totals.costUsd,
      totalTokens: totals.totalTokens,
      tokens: totals.tokens,
      records: totals.records,
      unpricedRecords: totals.unpricedRecords,
      unpricedTokens: totals.unpricedTokens,
      costShare: costUsd === 0 ? 0 : totals.costUsd / costUsd,
      tokenShare: totalTokens === 0 ? 0 : totals.totalTokens / totalTokens
    })).sort((a, b) => b.costUsd - a.costUsd || b.totalTokens - a.totalTokens);
    const daily = [...dailyAccumulator.entries()].map(([day, totals]) => ({
      day,
      costUsd: totals.costUsd,
      totalTokens: totals.totalTokens,
      byProvider: totals.byProvider
    })).sort((a, b) => a.day.localeCompare(b.day));
    const hourly = [...hourlyAccumulator.values()].sort(
      (a, b) => a.hourStart.localeCompare(b.hourStart)
    );
    return {
      costUsd,
      uncachedInputTokens,
      cachedInputTokens,
      cacheCreationTokens,
      outputTokens,
      reasoningTokens,
      totalTokens,
      records,
      sessions,
      providers,
      models,
      daily,
      hourly,
      costQuality: {
        providerReportedShare: records === 0 ? 0 : providerReportedRecords / records,
        unpricedShare: records === 0 ? 0 : unpricedRecords / records,
        modelPricedShare: records === 0 ? 0 : (records - providerReportedRecords - unpricedRecords) / records,
        cacheSavingsUsd: cacheSavingsUsd2
      },
      categoryCost: {
        ...categoryCost,
        unsplit: Math.max(
          0,
          costUsd - categoryCost.input - categoryCost.cacheRead - categoryCost.cacheWrite - categoryCost.output
        )
      },
      speedCost: {
        ...speedCost,
        standard: Math.max(0, costUsd - speedCost.fast - speedCost.ultrafast)
      },
      duplicateSources: duplicates,
      contributingEnvironments,
      contractMismatches
    };
  }

  // t3-source/limits.ts
  var MINUTE = 6e4;
  var HOUR = 60 * MINUTE;
  var DAY = 24 * HOUR;
  var CURSOR_USAGE_WINDOWS = [
    {
      id: "totalPercentUsed",
      label: "Overall",
      description: "All usage on your plan this billing cycle."
    },
    {
      id: "autoPercentUsed",
      label: "Cursor Models",
      description: "Grok, Composer, and Auto use this allowance."
    },
    {
      id: "apiPercentUsed",
      label: "Other Models",
      description: "Usage allowance for third-party models such as Claude, GPT, and Gemini."
    }
  ];
  function cursorUsageWindowDetails(id, pool) {
    const details = CURSOR_USAGE_WINDOWS.find((window) => window.id === id);
    return details && (pool.windows.length === 1 && id === "totalPercentUsed" || hasDuplicateCursorTotal(pool)) ? { ...details, label: null, description: void 0 } : details;
  }
  function cursorUsageWindowRank(id) {
    const rank = CURSOR_USAGE_WINDOWS.findIndex((window) => window.id === id);
    return rank < 0 ? CURSOR_USAGE_WINDOWS.length : rank;
  }
  function hasDuplicateCursorTotal(pool) {
    if (pool.windows.length !== 2) return false;
    const total = pool.windows.find((window) => window.id === "totalPercentUsed");
    const auto = pool.windows.find((window) => window.id === "autoPercentUsed");
    return total !== void 0 && auto !== void 0 && total.members.length === auto.members.length && total.members.every(
      ({ account, window }) => account.limits.windows.some(
        (candidate) => candidate.id === auto.id && candidate.kind === auto.kind && candidate.usedPercent === window.usedPercent && candidate.resetsAt === window.resetsAt
      )
    );
  }
  function displayLimitWindows(pool) {
    if (pool.driver === "antigravity") {
      return [...pool.windows].sort(
        (left, right) => Number(!left.id.startsWith("gemini-")) - Number(!right.id.startsWith("gemini-")) || left.id.replace(/-(5h|weekly|quota)$/, "").localeCompare(right.id.replace(/-(5h|weekly|quota)$/, "")) || WINDOW_KIND_ORDER[left.kind] - WINDOW_KIND_ORDER[right.kind]
      );
    }
    if (pool.driver !== "cursor") return pool.windows;
    const hasAuto = pool.windows.some((window) => window.id === "autoPercentUsed");
    const hasApi = pool.windows.some((window) => window.id === "apiPercentUsed");
    const hideTotal = hasAuto && hasApi || hasDuplicateCursorTotal(pool);
    return pool.windows.filter((window) => !hideTotal || window.id !== "totalPercentUsed").sort((left, right) => cursorUsageWindowRank(left.id) - cursorUsageWindowRank(right.id));
  }
  var WINDOW_KIND_ORDER = {
    session: 0,
    weekly: 1,
    monthly: 2,
    other: 3
  };
  function collectLimitPools(accounts, now) {
    const byDriver = /* @__PURE__ */ new Map();
    for (const account of accounts) {
      const list = byDriver.get(account.driver);
      if (list) list.push(account);
      else byDriver.set(account.driver, [account]);
    }
    return [...byDriver].map(([driver, members]) => {
      const orderWindow = members.flatMap((account) => account.limits.windows).sort((left, right) => WINDOW_KIND_ORDER[left.kind] - WINDOW_KIND_ORDER[right.kind])[0];
      const orderReset = (account) => {
        const window = account.limits.windows.find(
          (window2) => orderWindow && poolKey(driver, window2) === poolKey(driver, orderWindow)
        );
        return (window ? resetMillis(poolMember(account, window, now).window) : null) ?? Number.POSITIVE_INFINITY;
      };
      const sorted = [...members].sort(
        (left, right) => orderReset(left) - orderReset(right) || accountSortName(left).localeCompare(accountSortName(right)) || left.key.localeCompare(right.key)
      );
      return { driver, accounts: sorted, windows: poolWindows(sorted, now) };
    });
  }
  function accountSortName(account) {
    return (account.displayName ?? account.email ?? account.key).toLowerCase();
  }
  var CODEX_PLAN_CAPACITY = {
    "ChatGPT Plus Subscription": 1,
    "ChatGPT Pro 100 Subscription": 5,
    "ChatGPT Pro 200 Subscription": 20
  };
  var CLAUDE_SESSION_CAPACITY = { Pro: 1, Max: 5, Ultra: 20 };
  function planCapacity(account, kind) {
    if (!account.plan) return void 0;
    if (account.driver === "codex" && (kind === "session" || kind === "weekly")) {
      return CODEX_PLAN_CAPACITY[account.plan];
    }
    if (account.driver === "claudeAgent" && kind === "session") {
      return CLAUDE_SESSION_CAPACITY[account.plan];
    }
    return void 0;
  }
  function poolKey(driver, window) {
    return driver === "codex" ? window.kind : `${window.kind}:${window.id}`;
  }
  function poolMember(account, reported, now) {
    const spentWeekly = reported.kind === "session" ? account.limits.windows.find(
      (window) => window.usedPercent >= 100 && (account.driver === "claudeAgent" ? window.id === "seven_day" : account.driver === "codex" && window.kind === "weekly")
    ) : void 0;
    if (!spentWeekly) return { account, window: reported, refillPercent: reported.usedPercent };
    const weeklyReset = resetMillis(spentWeekly);
    const sessionReset = resetMillis(reported);
    const cutoff = Math.max(now, Date.parse(account.limits.checkedAt));
    let resetsAt;
    let refillPercent = 0;
    if (weeklyReset !== null && sessionReset !== null && weeklyReset > cutoff && sessionReset > cutoff) {
      if (sessionReset <= weeklyReset) {
        resetsAt = spentWeekly.resetsAt;
        refillPercent = 100;
      } else if (reported.usedPercent >= 100) {
        resetsAt = reported.resetsAt;
        refillPercent = 100;
      } else {
        resetsAt = spentWeekly.resetsAt;
        refillPercent = 100 - Math.max(0, Math.min(100, reported.usedPercent));
      }
    }
    return {
      account,
      // Suppression is not session spending, so it has no session pace clock.
      window: { ...reported, usedPercent: 100, resetsAt, windowDurationMins: void 0 },
      refillPercent
    };
  }
  function poolWindows(accounts, now) {
    const byKey = /* @__PURE__ */ new Map();
    for (const account of accounts) {
      for (const reported of account.limits.windows) {
        const member = poolMember(account, reported, now);
        const { window } = member;
        const pooled = poolKey(account.driver, window);
        const key = byKey.get(pooled)?.some((member2) => member2.account === account) ? `${window.kind}:${window.id}` : pooled;
        const list = byKey.get(key);
        if (list) list.push(member);
        else byKey.set(key, [member]);
      }
    }
    const pools = [...byKey].map(([key, members]) => {
      const memberByAccount = new Map(members.map((member) => [member.account.key, member]));
      const first = members[0].window;
      const id = members[0].account.driver === "codex" ? key : first.id;
      const capacities = members.map((m) => planCapacity(m.account, first.kind));
      const weights = capacities.every((capacity) => capacity !== void 0) ? capacities : members.map(() => 1);
      const weightOf = new Map(members.map((m, index) => [m, weights[index]]));
      const totalWeight = weights.reduce((sum, weight) => sum + weight, 0);
      const usedPercent = members.reduce((sum, m) => sum + m.window.usedPercent * weightOf.get(m), 0) / totalWeight;
      const timed = members.flatMap((m) => {
        const share = elapsedShare(m.window, now);
        return share === null ? [] : [{ used: m.window.usedPercent, elapsed: share, weight: weightOf.get(m) }];
      });
      const timedWeight = timed.reduce((sum, t) => sum + t.weight, 0);
      const timedUsed = timed.reduce((sum, t) => sum + t.used * t.weight, 0) / timedWeight;
      const meanElapsed = timed.length > 0 ? timed.reduce((sum, t) => sum + t.elapsed * t.weight, 0) / timedWeight : null;
      const resets = members.flatMap((member) => {
        const at = resetMillis(member.window);
        return at === null ? [] : [
          {
            member,
            at,
            restoresPercent: Math.round(
              member.refillPercent * weightOf.get(member) / totalWeight
            )
          }
        ];
      }).sort((left, right) => left.at - right.at);
      return {
        id,
        kind: first.kind,
        label: first.label,
        members,
        columns: accounts.map(
          (account) => memberByAccount.get(account.key) ?? { account, window: null }
        ),
        usedPercent: Math.round(usedPercent),
        remainingPercent: Math.round(100 - usedPercent),
        pace: meanElapsed === null ? null : paceOfShares(timedUsed, meanElapsed),
        resets
      };
    });
    return pools.sort((left, right) => WINDOW_KIND_ORDER[left.kind] - WINDOW_KIND_ORDER[right.kind]);
  }
  function remainingPercent(window) {
    return Math.round(100 - Math.max(0, Math.min(100, window.usedPercent)));
  }
  function resetMillis(window) {
    if (window.resetsAt === void 0) return null;
    const at = Date.parse(window.resetsAt);
    return Number.isFinite(at) ? at : null;
  }
  function elapsedShare(window, now) {
    const resetsAt = resetMillis(window);
    if (resetsAt === null || window.windowDurationMins === void 0) return null;
    const length = window.windowDurationMins * MINUTE;
    if (length <= 0) return null;
    return Math.max(0, Math.min(1, (length - (resetsAt - now)) / length));
  }
  function paceRemainingPercent(window, now) {
    const elapsed = elapsedShare(window, now);
    return elapsed === null ? null : Math.round((1 - elapsed) * 100);
  }
  function paceOfShares(usedPercent, elapsed) {
    const gap = usedPercent - elapsed * 100;
    if (gap > 5) return "ahead";
    if (gap < -5) return "under";
    return "on";
  }
  function formatDuration(ms) {
    const remaining = Math.max(0, ms);
    const days = Math.floor(remaining / DAY);
    const hours = Math.floor(remaining % DAY / HOUR);
    const minutes = Math.floor(remaining % HOUR / MINUTE);
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
  }
  function formatResetsIn(window, now) {
    const resetsAt = resetMillis(window);
    if (resetsAt === null) return null;
    if (resetsAt <= now) return "resets now";
    if (resetsAt - now < MINUTE) return "Resets momentarily";
    return `resets in ${formatDuration(resetsAt - now)}`;
  }

  // t3-source/claude.ts
  var CLAUDE_SYNTHETIC_MODEL = "<synthetic>";
  function parseClaudeLine(line) {
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch {
      return [];
    }
    return parseClaudeRecord(parsed);
  }
  function cacheCreation1h(usage) {
    const split = usage["cache_creation"];
    if (typeof split !== "object" || split === null) return {};
    const tokens = tokenCount(split["ephemeral_1h_input_tokens"]);
    return tokens > 0 ? { cacheCreation1hTokens: tokens } : {};
  }
  function parseClaudeRecord(parsed) {
    if (typeof parsed !== "object" || parsed === null) return [];
    const record = parsed;
    if (record["type"] !== "assistant") return [];
    const message = record["message"];
    if (typeof message !== "object" || message === null) return [];
    const messageRecord = message;
    const usage = messageRecord["usage"];
    if (typeof usage !== "object" || usage === null) return [];
    const usageRecord = usage;
    const timestampMs = parseTimestampMs(record["timestamp"]);
    if (timestampMs === null) return [];
    const model = typeof messageRecord["model"] === "string" ? messageRecord["model"] : "";
    if (model.length === 0 || model === CLAUDE_SYNTHETIC_MODEL) return [];
    const messageId = typeof messageRecord["id"] === "string" ? messageRecord["id"] : null;
    const requestId = typeof record["requestId"] === "string" ? record["requestId"] : null;
    const dedupeKey = messageId === null && requestId === null ? null : `${messageId ?? ""}:${requestId ?? ""}`;
    const cost = record["costUSD"];
    const executor = {
      provider: "claude",
      timestampMs,
      model,
      sessionId: typeof record["sessionId"] === "string" ? record["sessionId"] : "",
      totals: {
        uncachedInputTokens: tokenCount(usageRecord["input_tokens"]),
        cachedInputTokens: tokenCount(usageRecord["cache_read_input_tokens"]),
        cacheCreationTokens: tokenCount(usageRecord["cache_creation_input_tokens"]),
        outputTokens: tokenCount(usageRecord["output_tokens"]),
        // Anthropic folds thinking tokens into output and does not break them out.
        reasoningTokens: 0
      },
      ...cacheCreation1h(usageRecord),
      reportedCostUsd: typeof cost === "number" && Number.isFinite(cost) ? cost : null,
      speed: usageRecord["speed"] === "fast" ? "fast" : "standard",
      dedupeKey
    };
    const records = [executor];
    const iterations = Array.isArray(usageRecord["iterations"]) ? usageRecord["iterations"] : [];
    for (const [index, iteration] of iterations.entries()) {
      if (typeof iteration !== "object" || iteration === null) continue;
      const advisor = iteration;
      if (advisor["type"] !== "advisor_message") continue;
      const advisorModel = typeof advisor["model"] === "string" ? advisor["model"] : "";
      if (advisorModel.length === 0 || advisorModel === CLAUDE_SYNTHETIC_MODEL) continue;
      records.push({
        provider: "claude",
        timestampMs,
        model: advisorModel,
        sessionId: executor.sessionId,
        totals: {
          uncachedInputTokens: tokenCount(advisor["input_tokens"]),
          cachedInputTokens: tokenCount(advisor["cache_read_input_tokens"]),
          cacheCreationTokens: tokenCount(advisor["cache_creation_input_tokens"]),
          outputTokens: tokenCount(advisor["output_tokens"]),
          reasoningTokens: 0
        },
        ...cacheCreation1h(advisor),
        reportedCostUsd: null,
        speed: executor.speed,
        dedupeKey: dedupeKey === null ? null : `${dedupeKey}:advisor:${index}`
      });
    }
    return records;
  }

  // t3-source/codex.ts
  var CODEX_USAGE_FIELDS = ["input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"];
  var isCodexTokenUsage = (u) => CODEX_USAGE_FIELDS.every((k) => Number.isInteger(u[k]) && u[k] >= 0) && u.cached_input_tokens + u.cache_write_input_tokens <= u.input_tokens && u.reasoning_output_tokens <= u.output_tokens && u.total_tokens >= u.input_tokens + u.output_tokens;
  function readCodexTokenUsage(value) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
    const raw = value;
    const input = raw["input_tokens"];
    const output = raw["output_tokens"];
    if (typeof input !== "number" || typeof output !== "number") return null;
    const usage = {
      input_tokens: input,
      cached_input_tokens: raw["cached_input_tokens"] === void 0 ? 0 : raw["cached_input_tokens"],
      cache_write_input_tokens: raw["cache_write_input_tokens"] === void 0 ? 0 : raw["cache_write_input_tokens"],
      output_tokens: output,
      reasoning_output_tokens: raw["reasoning_output_tokens"] === void 0 ? 0 : raw["reasoning_output_tokens"],
      total_tokens: raw["total_tokens"] === void 0 ? input + output : raw["total_tokens"]
    };
    return isCodexTokenUsage(usage) ? usage : null;
  }
  function rebaseCodexUsage(state, cumulative, timestampMs) {
    state.lastCumulativeUsage = cumulative;
    state.latestCumulativeAtMs = Math.max(state.latestCumulativeAtMs ?? timestampMs, timestampMs);
    delete state.unreportedRequests;
    if (cumulative.input_tokens + cumulative.output_tokens === 0) delete state.sequenceStartSignature;
  }
  function advanceCodexUsage(previous, last) {
    return readCodexTokenUsage(
      Object.fromEntries(CODEX_USAGE_FIELDS.map((key) => [key, (previous?.[key] ?? 0) + last[key]]))
    );
  }
  function unreportedRequests(previous, cumulative, last, pending) {
    if (previous === null || pending === void 0 || CODEX_USAGE_FIELDS.some(
      (key) => cumulative[key] - previous[key] !== pending.reduce((sum, request) => sum + request.usage[key], 0)
    )) {
      return null;
    }
    const final = pending.at(-1);
    const remainder = readCodexTokenUsage(
      Object.fromEntries(CODEX_USAGE_FIELDS.map((key) => [key, final.usage[key] - last[key]]))
    );
    if (remainder === null) return null;
    return [...pending.slice(0, -1), { ...final, usage: remainder }].filter(
      (request) => request.usage.input_tokens + request.usage.output_tokens > 0
    );
  }
  function initialCodexScanState() {
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
      forkCopyAnchorMs: 0
    };
  }
  var FORK_COPY_MAX_GAP_MS = 1e3;
  function isForkedSessionMeta(payload) {
    if (typeof payload["forked_from_id"] === "string") return true;
    const source = payload["source"];
    if (typeof source !== "object" || source === null) return false;
    const subagent = source["subagent"];
    if (typeof subagent !== "object" || subagent === null) return false;
    const spawn = subagent["thread_spawn"];
    if (typeof spawn !== "object" || spawn === null) return false;
    return typeof spawn["parent_thread_id"] === "string";
  }
  function isForkCopy(state, timestampMs) {
    if (!state.suppressingForkCopies) return false;
    if (timestampMs - state.forkCopyAnchorMs < FORK_COPY_MAX_GAP_MS) {
      state.forkCopyAnchorMs = timestampMs;
      return true;
    }
    state.suppressingForkCopies = false;
    state.lastUsageSignature = null;
    return false;
  }
  function parseCodexLine(line, state) {
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch {
      return [];
    }
    return parseCodexRecord(parsed, state);
  }
  function parseCodexRecord(parsed, state) {
    if (typeof parsed !== "object" || parsed === null) return [];
    const record = parsed;
    const payload = record["payload"];
    if (typeof payload !== "object" || payload === null) return [];
    const payloadRecord = payload;
    const payloadType = payloadRecord["type"];
    if (record["type"] === "session_meta") {
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
      state.turnId = typeof payloadRecord["turn_id"] === "string" && typeof payloadRecord["model"] === "string" && payloadRecord["model"].length > 0 ? payloadRecord["turn_id"] : "";
      return [];
    }
    if (record["type"] === "token_usage_record") {
      const timestampMs2 = parseTimestampMs(record["timestamp"]);
      const usage = readCodexTokenUsage(payloadRecord["usage"]);
      if (timestampMs2 === null || usage === null || state.model.length === 0) return [];
      if (isForkCopy(state, timestampMs2)) return [];
      const responseId = payloadRecord["response_id"];
      if (typeof responseId === "string" && responseId.length > 0) {
        const pending2 = state.unreportedRequests ?? [];
        state.requestLedgerActive = true;
        for (const request of pending2) {
          state.lastCumulativeUsage = advanceCodexUsage(state.lastCumulativeUsage, request.usage);
        }
        state.lastCumulativeUsage = advanceCodexUsage(state.lastCumulativeUsage, usage);
        delete state.unreportedRequests;
        return [
          ...pending2.map((request) => codexRequestRecord(state, request.usage, request)),
          {
            ...codexRequestRecord(state, usage, codexAttribution(state, timestampMs2)),
            dedupeKey: JSON.stringify(["codex", state.sessionId, responseId])
          }
        ];
      }
      state.requestLedgerActive = false;
      (state.unreportedRequests ??= []).push({ ...codexAttribution(state, timestampMs2), usage });
      return [];
    }
    if (payloadType === "thread_settings_applied") {
      state.sawThreadSettings = true;
      const settings = payloadRecord["thread_settings"];
      if (typeof settings === "object" && settings !== null) {
        state.speed = codexSpeed(settings["service_tier"]);
      }
      return [];
    }
    if (payloadType !== "token_count") return [];
    const info = payloadRecord["info"];
    if (typeof info !== "object" || info === null) return [];
    const infoRecord = info;
    const timestampMs = parseTimestampMs(record["timestamp"]);
    if (timestampMs === null || state.model.length === 0) return [];
    const last = readCodexTokenUsage(infoRecord["last_token_usage"]);
    const rawCumulative = infoRecord["total_token_usage"];
    const hasCumulative = rawCumulative !== void 0 && rawCumulative !== null;
    const cumulative = hasCumulative ? readCodexTokenUsage(rawCumulative) : null;
    if (isForkCopy(state, timestampMs)) {
      const signature2 = last === null ? null : JSON.stringify(last);
      if (cumulative !== null) rebaseCodexUsage(state, cumulative, timestampMs);
      else if (!hasCumulative && last !== null && signature2 !== state.lastUsageSignature) {
        state.lastCumulativeUsage = advanceCodexUsage(state.lastCumulativeUsage, last);
      }
      state.lastUsageSignature = signature2;
      return [];
    }
    if (state.requestLedgerActive) {
      if (cumulative !== null) rebaseCodexUsage(state, cumulative, timestampMs);
      return [];
    }
    const previous = state.lastCumulativeUsage;
    const latestCumulativeAtMs = state.latestCumulativeAtMs;
    const pending = state.unreportedRequests;
    if (cumulative !== null) rebaseCodexUsage(state, cumulative, timestampMs);
    if (last === null || hasCumulative && cumulative === null) {
      state.malformedRecords += 1;
      return [];
    }
    if (last.input_tokens + last.output_tokens === 0) {
      state.lastUsageSignature = null;
      return [];
    }
    if (cumulative !== null && previous !== null && CODEX_USAGE_FIELDS.every((key) => cumulative[key] === previous[key])) {
      return [];
    }
    if (last.total_tokens !== last.input_tokens + last.output_tokens) {
      state.malformedRecords += 1;
      return [];
    }
    const signature = JSON.stringify(last);
    let unreported = [];
    if (cumulative !== null) {
      const restarted = CODEX_USAGE_FIELDS.every((key) => cumulative[key] === last[key]);
      const sequenceStart = JSON.stringify([timestampMs, last]);
      if (restarted && sequenceStart === state.sequenceStartSignature) {
        state.lastCumulativeUsage = previous;
        return [];
      }
      const rewound = previous !== null && (latestCumulativeAtMs === void 0 || timestampMs > latestCumulativeAtMs) && CODEX_USAGE_FIELDS.some((key) => cumulative[key] < previous[key]);
      const reconciled = previous === null || rewound ? readCodexTokenUsage(
        Object.fromEntries(CODEX_USAGE_FIELDS.map((key) => [key, cumulative[key] - last[key]]))
      ) !== null : CODEX_USAGE_FIELDS.every((key) => cumulative[key] - previous[key] === last[key]);
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
      codexRequestRecord(state, last, codexAttribution(state, timestampMs))
    ];
  }
  function codexAttribution(state, timestampMs) {
    return {
      timestampMs,
      model: state.model,
      turnId: state.turnId,
      speed: state.speed,
      sawThreadSettings: state.sawThreadSettings
    };
  }
  function codexRequestRecord(state, usage, { timestampMs, model, turnId, speed, sawThreadSettings }) {
    const inputTokens = usage.input_tokens;
    const cachedInputTokens = usage.cached_input_tokens;
    const cacheCreationTokens = usage.cache_write_input_tokens;
    const outputTokens = usage.output_tokens;
    const totals = {
      // Codex reports `input_tokens` inclusive of the cached portion.
      uncachedInputTokens: inputTokens - cachedInputTokens - cacheCreationTokens,
      cachedInputTokens,
      cacheCreationTokens,
      outputTokens,
      // Reported inside output_tokens, surfaced separately for the token mix.
      reasoningTokens: usage.reasoning_output_tokens
    };
    return {
      provider: "codex",
      timestampMs,
      model,
      sessionId: state.sessionId,
      totals,
      reportedCostUsd: null,
      speed,
      ...!sawThreadSettings && state.modelProvider === "openai" && state.sessionId.length > 0 && turnId.length > 0 ? { unresolvedServiceTierTurnId: turnId } : {},
      dedupeKey: null
    };
  }
  function codexSpeed(serviceTier) {
    if (serviceTier === "priority" || serviceTier === "fast") return "fast";
    if (serviceTier === "ultrafast") return "ultrafast";
    return "standard";
  }

  // t3-source/cursorCache.ts
  var CURSOR_ACCOUNT_TTL_MS = 60 * 1e3;
  var REFETCH_OVERLAP_MS = 60 * 60 * 1e3;
  var CURSOR_ACCOUNT_CACHE_VERSION = 1;
  var isFiniteNumber = (value) => typeof value === "number" && Number.isFinite(value);
  function decodeCursorAccountCaches(document) {
    const caches = /* @__PURE__ */ new Map();
    if (typeof document !== "object" || document === null) return caches;
    const root = document;
    const strings = root.strings;
    if (root.version !== CURSOR_ACCOUNT_CACHE_VERSION || !Array.isArray(strings) || !strings.every((value) => typeof value === "string") || typeof root.accounts !== "object" || root.accounts === null) {
      return caches;
    }
    const stringAt = (index) => typeof index === "number" ? strings[index] : void 0;
    const decodeRecord = (row) => {
      if (!Array.isArray(row)) return null;
      const [
        timestampMs,
        modelIndex,
        sessionIndex,
        uncached,
        cached,
        creation,
        output,
        cost,
        key
      ] = row;
      const model = stringAt(modelIndex);
      const sessionId = stringAt(sessionIndex);
      if (!isFiniteNumber(timestampMs) || model === void 0 || sessionId === void 0 || !isFiniteNumber(uncached) || !isFiniteNumber(cached) || !isFiniteNumber(creation) || !isFiniteNumber(output) || cost !== null && !isFiniteNumber(cost) || key !== null && typeof key !== "string") {
        return null;
      }
      return {
        provider: "cursor",
        timestampMs,
        model,
        rateModel: cursorRateModel(model),
        sessionId,
        totals: {
          uncachedInputTokens: uncached,
          cachedInputTokens: cached,
          cacheCreationTokens: creation,
          outputTokens: output,
          reasoningTokens: 0
        },
        reportedCostUsd: cost,
        speed: "standard",
        dedupeKey: key
      };
    };
    for (const [credentialKey, raw] of Object.entries(root.accounts)) {
      if (typeof raw !== "object" || raw === null) continue;
      const account = raw;
      if (typeof account.accountKey !== "string" || !isFiniteNumber(account.sinceMs) || !isFiniteNumber(account.untilMs) || !isFiniteNumber(account.fetchedAtMs) || !Array.isArray(account.records)) {
        continue;
      }
      const records = [];
      for (const row of account.records) {
        const record = decodeRecord(row);
        if (record === null) break;
        records.push(record);
      }
      if (records.length !== account.records.length) continue;
      caches.set(credentialKey, {
        accountKey: account.accountKey,
        sinceMs: account.sinceMs,
        untilMs: account.untilMs,
        fetchedAtMs: account.fetchedAtMs,
        records
      });
    }
    return caches;
  }

  // t3-source/entry.ts
  function cursorRateModel(model) {
    const base = model.replace(/^cursor-/, "").replace(/(?:-thinking)?(?:-(?:none|minimal|low|medium|high|xhigh|max))?(?:-fast)?$/, "");
    return base.startsWith("grok-") ? "xai/" + base : base;
  }
  function poolJSON(json) {
    const input = JSON.parse(json);
    const groups = collectLimitPools(input.accounts, input.now);
    return JSON.stringify(groups.map((group) => ({ driver: group.driver, windows: displayLimitWindows(group).map((window) => {
      const details = group.driver === "cursor" ? cursorUsageWindowDetails(window.id, group) : void 0;
      return {
        id: window.id,
        label: details?.label === null ? "" : details?.label ?? window.label,
        description: details?.description,
        remaining: window.remainingPercent,
        pace: window.pace,
        segments: window.columns.map((member) => member.window === null ? null : { key: member.account.key, name: member.account.displayName ?? member.account.email ?? member.account.key, remaining: remainingPercent(member.window), used: member.window.usedPercent, pace: paceRemainingPercent(member.window, input.now), reset: member.window.resetsAt, resetLabel: formatResetsIn(member.window, input.now), refill: member.refillPercent, credits: member.account.limits.resetCredits?.availableCount ?? 0 })
      };
    }) })));
  }
  function parseTranscript(input) {
    const records = [];
    const state = initialCodexScanState();
    for (const line of input.lines) records.push(...input.provider === "claude" ? parseClaudeLine(line) : parseCodexLine(line, state));
    return records;
  }
  function parseTranscriptJSON(json) {
    return JSON.stringify(parseTranscript(JSON.parse(json)));
  }
  var historyFiles = /* @__PURE__ */ new Map();
  function summaryJSON(json) {
    const input = JSON.parse(json);
    const rates = parseRateTable(input.rates);
    const aggregator = new UsageAggregator({ ...input.sinceTimeMs === void 0 ? {} : { resolution: "hour", sinceTimeMs: input.sinceTimeMs, untilTimeMs: input.now }, timeZone: input.timeZone, sinceDay: input.sinceDay, untilDay: input.untilDay, rates, priceOverrides: createOverrideRateTable(input.settings?.usagePriceOverrides ?? {}), modelAliases: resolveModelAliases(input.settings?.usageModelAliases ?? {}), modelFilter: input.settings?.usageModelFilter ?? void 0 });
    const providers = /* @__PURE__ */ new Set();
    const sessions = /* @__PURE__ */ new Map();
    for (const file of input.files ?? historyFiles.values()) {
      for (const record of file.records) {
        if (input.provider && record.provider !== input.provider) continue;
        providers.add(record.provider);
        let set = sessions.get(record.provider);
        if (!set) {
          set = /* @__PURE__ */ new Set();
          sessions.set(record.provider, set);
        }
        if (aggregator.add(record, record.provider) && record.sessionId) set.add(record.sessionId);
      }
    }
    if (input.cursorCache && (!input.provider || input.provider === "cursor")) for (const cache of decodeCursorAccountCaches(input.cursorCache).values()) {
      providers.add("cursor");
      let set = sessions.get("cursor");
      if (!set) {
        set = /* @__PURE__ */ new Set();
        sessions.set("cursor", set);
      }
      for (const record of cache.records) {
        if (aggregator.add(record, "cursor") && record.sessionId) set.add(record.sessionId);
      }
    }
    const buckets = aggregator.finish().buckets;
    const sources = [...providers].map((provider) => ({ fingerprint: { hostId: "local", provider, resolvedHomePath: provider, volumeId: "local" }, status: "ok", scannedFiles: 1, skippedFiles: 0, malformedRecords: 0, distinctSessions: sessions.get(provider)?.size ?? 0, message: null }));
    const merged = mergeUsage([{ environmentId: "local", label: "This Mac", summary: { contractVersion: 6, readAt: new Date(input.now).toISOString(), buckets, sources, modelFilter: input.settings?.usageModelFilter ?? void 0 } }], 6);
    return JSON.stringify({ costUsd: merged.costUsd, totalTokens: merged.totalTokens, records: merged.records, sessions: merged.sessions, providers: merged.providers, models: merged.models, costQuality: merged.costQuality, categoryCost: merged.categoryCost });
  }
  function decodeCache(root) {
    const files = [];
    if (!Number.isInteger(root.version) || root.version < 4 || root.version > 15 || !Array.isArray(root.models) || !Array.isArray(root.sessions)) throw Error("Unsupported T3 usage cache");
    const speeds = ["standard", "fast", "ultrafast"];
    for (const [path, file] of Object.entries(root.files ?? {})) {
      const records = [];
      let valid = true;
      for (const row of [...file.r ?? [], ...file.t ?? []]) {
        const [timestampMs, modelIndex, sessionIndex, uncached, cached, creation, output, reasoning, key, cost, speedIndex, rateModelIndex, unresolved, creation1h = 0] = row;
        const model = root.models[modelIndex], speed = speeds[speedIndex];
        if (![timestampMs, uncached, cached, creation, output, reasoning, creation1h].every(Number.isFinite) || typeof model !== "string" || !speed) {
          valid = false;
          break;
        }
        if (file.p === "claude" && model === "<synthetic>") continue;
        records.push({ provider: file.p, timestampMs, model, sessionId: root.sessions[sessionIndex] ?? "", totals: { uncachedInputTokens: uncached, cachedInputTokens: cached, cacheCreationTokens: creation, outputTokens: output, reasoningTokens: reasoning }, reportedCostUsd: typeof cost === "number" ? cost : null, speed, dedupeKey: typeof key === "string" ? key : null, ...rateModelIndex == null ? {} : { rateModel: root.models[rateModelIndex] }, ...creation1h > 0 ? { cacheCreation1hTokens: creation1h } : {} });
      }
      if (valid) files.push({ path, provider: file.p, size: file.s, mtimeMs: file.m, records });
    }
    return files;
  }
  function decodeCacheJSON(json) {
    return JSON.stringify(decodeCache(JSON.parse(json)));
  }
  function loadHistoryCacheJSON(json) {
    for (const file of decodeCache(JSON.parse(json))) {
      if ((historyFiles.get(file.path)?.mtimeMs ?? 0) <= file.mtimeMs) historyFiles.set(file.path, file);
    }
    return JSON.stringify([...historyFiles.values()].map(({ path, provider, size, mtimeMs }) => ({ path, provider, size, mtimeMs })));
  }
  function updateHistoryTranscriptJSON(json) {
    const input = JSON.parse(json);
    historyFiles.set(input.path, { path: input.path, provider: input.provider, size: input.size, mtimeMs: input.mtimeMs, records: parseTranscript(input) });
    return "{}";
  }
  return __toCommonJS(entry_exports);
})();
