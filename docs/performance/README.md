# Performance validation

Changes: byte-based JSONL marker/newline searches; one buffer removal per chunk; chunk-scoped autorelease pools; a retained, actor-isolated usage engine; records kept inside JavaScriptCore instead of serialized into Swift and back; unchanged disk caches skipped by modification time and size. T3's pricing, aggregation, pooling and transcript parsing remain unchanged.

The OpenCode warning banner is hidden as requested. Its underlying error remains available to diagnostics; other provider errors stay visible.

## Profile

A two-second sample of a real release-build refresh found the worker spending most sampled time in `T3History.projectedLines`: 103 samples in Unicode-aware `String.contains`, 47 in per-line Data replacement/copying, out of 176 worker samples. This profile is diagnostic only, not a timing comparison.

## Controlled scanner comparison

Build/run: `swiftc -O docs/performance/benchmark-transcripts.swift -o /tmp/quota-scanner-benchmark`, then execute the binary. The benchmark contains the previous reader and the optimized production reader, and writes a temporary synthetic Codex-shaped log with Unicode non-usage messages. It warms both implementations, alternates before/after five times, consumes every result and verifies canonical JSON equality on each run.

Fixture: 8,661,000 bytes, 12,600 input lines, 600 projected usage lines. Zero errors; both readers returned identical canonical output. Full measurements: `scanner-results.json`.

- Previous reader: median 2,681.78 ms; range 2,256.42–3,504.01 ms.
- Optimized reader: median 85.78 ms; range 70.91–108.61 ms.

This comparison applies to the scanner on this fixture, not the whole application. The host had 8 logical cores and shared workload; implementations were interleaved to reduce that noise. The large gap exceeds the observed variation. File I/O, irrelevant-message rejection, JSON projection and output construction are included; fixture creation and correctness checking are outside the timed region.

## Correctness and runtime scope

Thirteen tests pass, including real extracted-engine arithmetic; native toggle-to-number rendering; chunk-boundary, Unicode, malformed/invalid UTF-8 and partial-write behavior; engine-private history state; preservation of newer local records when an older disk cache is loaded; repeated-summary stability; and cache invalidation on explicit refresh.

Live release probes issue actual quota requests and read actual history. They include network latency and a changing local dataset, so single-run elapsed time/RSS are diagnostic observations, not a reproducible whole-app speedup claim. No provider inference is requested and no T3 data is modified. A physical mouse interaction and sustained idle-energy measurement remain unverified.
