# Two stylist tiers with Quick and Deep modes

## Context
Replace the immediate evaluation/experiment roadmap with a research-backed product rollout: an accessible everyday stylist and a higher-capability Expert, each offering Quick and Deep analysis. Expert may become paid later. Planning only; no implementation or paid model calls.

## Findings so far
- Native SwiftUI app calls the sibling `../supabase/` backend; shared contracts and evaluation tooling also live in the parent repository.
- Production model is currently `google/gemini-3.1-flash-lite` with low reasoning and 3,600 output tokens (`../supabase/functions/_shared/agents/model-config.ts`). Gemini 3.1 Pro Preview is a local-only comparison model.
- Provider configuration already checks image support, required request parameters, approved Google Vertex routes, zero-data-retention eligibility, and available API credit. Preserve these safeguards rather than simply accepting arbitrary client model IDs.
- iOS wire schemas reject unknown fields. Contract evolution and deployment compatibility need explicit handling.
- Reports preserve original JSON for signed saves; do not reconstruct or casually extend signed report data.
- Existing evaluation lab is documented and independently launched. Sideline it without deleting useful infrastructure.

## Approach
Implement four server-controlled profiles behind **Everyday / Expert** and **Quick / Deep**. Use **GPT-5.6 Luna via Azure for Everyday** and **Claude Opus 5 via Google Vertex for Expert**, subject to live route preflight and a basic integration smoke check before activation. Quick reuses `runOutfit`; Deep reuses `runDeep` with the selected tier's model for generator and both critics. Do not silently substitute tiers or providers. Both tiers remain available without payment gating.

This is a research-backed starting configuration, not a claim that a model has been proven best at styling. Models remain replaceable server-side without changing product names. Preserve current Flash Lite configuration as a manually selectable rollback profile, not an automatic fallback.

## Confirmed product decisions
- Names: **Everyday / Expert**. Default to Everyday + Quick.
- Deep may take noticeably longer; prioritize a more considered assessment rather than verbosity.
- Both tiers available to everyone who can currently analyze; no paid gating, separate Expert allowance, StoreKit, or subscription work. Existing consent/beta/global quota safeguards remain.

## Additional discoveries
- Production currently calls only `runOutfit`; `runDeep` already exists with two parallel critics, one optional repair and recheck (up to six calls). Reuse it rather than introduce a second critique engine.
- Handler deadline is 45 seconds, but existing Deep has a 90-second internal deadline: simply wiring it in would prematurely cancel Deep.
- Existing accounting uses one boolean for in-flight inference; parallel critics require per-call accounting/uncertainty tracking.
- Public OpenRouter catalog fetched without inference on 2026-10-25. Flash Lite GA is $0.25/$1.50 per million input/output tokens; Flash Preview $0.50/$3; Pro Preview $2/$12; GPT-5.4 $2.50/$15; Sonnet 4.6 $3/$15; Opus 4.6 $5/$25. These are base token prices, not per-photo quotes. Reasoning and repeated image inputs add cost. Research is ongoing; no styling-specific superiority has been established.

## Model research and recommendation
Research snapshot: **2026-10-25**, using OpenRouter's public catalog, per-model endpoints, and ZDR endpoint list. No paid inference, dataset evaluation, or experiments were run. Search tooling required authentication, so research used direct public HTTPS sources instead.

| Candidate | Base input/output USD per 1M tokens | Findings and decision |
|---|---:|---|
| `openai/gpt-5.6-luna` | $0.20 / $1.20 | **Everyday recommendation.** Catalog describes fast, cost-efficient, latency-sensitive use. Image input, reasoning effort, strict structured output; active Azure ZDR routes. Lower base price than existing Flash Lite and stronger general intelligence index in the catalog. Requires a completion-token parameter adapter. |
| `google/gemini-3.1-flash-lite` | $0.25 / $1.50 | Existing production model; keep for explicit rollback. No evidence it remains the best current value merely because it is already integrated. |
| `google/gemini-3.5-flash-lite` | $0.30 / $2.50 | Current low-cost Google candidate; image/structured-output/ZDR support. Less compelling general capability/value signal than Luna. |
| `google/gemini-3.7-flash` | $0.75 / $3.75 | Strong fast-model candidate with Vertex ZDR. Catalog general intelligence index 39.6 versus Luna 37.3, at materially higher token prices. No measured styling advantage or latency comparison. |
| `google/gemini-3.1-pro-preview` | $2 / $12 | Existing comparison candidate, but not automatically the current best Expert choice. Preview lifecycle adds maintenance risk. |
| `openai/gpt-5.6-sol` | $4 / $20 | Current OpenAI flagship, image-capable with Azure ZDR routes; credible Expert candidate. Catalog general intelligence index 47.0. |
| `anthropic/claude-opus-5` | $5 / $25 | **Expert recommendation.** Flagship with explicit visual-analysis positioning; image and strict output support; active Vertex ZDR. Catalog general intelligence index 50.8 supports selecting it for capability-first use over the cheaper candidates, but does not establish fashion quality. |
| `anthropic/claude-fable-5` | $10 / $50 | No matching ZDR routes in the snapshot; exclude regardless of capability. |

Also checked GPT-5.4, Sonnet 4.6, and Opus 4.6 before discovering newer catalog entries. Do not base the rollout on the repository's older two-model shortlist. Exclude image-generation, batch, flex, free/automatic-router and Pro-mode variants: this is synchronous image understanding, not image synthesis or unconstrained reasoning.

### Source links and caveats
- [OpenRouter live model catalog](https://openrouter.ai/api/v1/models): IDs, modalities, prices, effort options and catalog-reported benchmark summaries.
- [Luna endpoint metadata](https://openrouter.ai/api/v1/models/openai/gpt-5.6-luna/endpoints), [Opus 5 endpoint metadata](https://openrouter.ai/api/v1/models/anthropic/claude-opus-5/endpoints), [Gemini 3.7 Flash endpoint metadata](https://openrouter.ai/api/v1/models/google/gemini-3.7-flash/endpoints).
- [ZDR endpoint list](https://openrouter.ai/api/v1/endpoints/zdr): intersect exact model ID and provider tag, not vendor name alone.
- [Reasoning tokens](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens): reasoning is billed output and generally shares the completion limit; omit reasoning text from responses with `reasoning.exclude`.
- [Supabase function limits](https://supabase.com/docs/guides/functions/limits): 150-second free-worker duration and request idle timeout constrain synchronous Deep execution.

These are catalog claims and compatibility observations, not independently reproduced benchmarks. Neither selected route exposed usable latency/throughput measurements in the snapshot. Azure showed a short-window availability dip despite active status; do not promise faster wall-clock results or guaranteed availability. Recheck metadata immediately before activation. No account-specific entitlement or end-to-end strict-schema success has been verified yet.

### Four profiles
| Profile | Model | Effort | Pipeline | Initial completion budget per call |
|---|---|---|---|---:|
| Everyday Quick (default) | Luna | low | One assessment; at most one existing validation repair | 8,192 |
| Everyday Deep | Luna | high | Generate, two parallel critics, at most one revision + two rechecks | 16,384 |
| Expert Quick | Opus 5 | low | One assessment; at most one existing validation repair | 8,192 |
| Expert Deep | Opus 5 | high | Same bounded Deep pipeline, all calls using Opus 5 | 16,384 |

Budgets include reasoning, not just visible report text. Keep the existing concise report schema and suggestion selection limits; Deep improves scrutiny, not output length. Initial settings are engineering defaults, not tuned optima. No promise that Expert Quick is faster than Everyday Deep.

Illustrative cost only: at 5,000 total billed input and 3,000 billed output tokens per call, Luna is $0.0046 and Opus is $0.10. A six-call Deep run at those same per-call counts is approximately $0.0276 / $0.60 respectively. Actual image tokens, repeated context, reasoning and repair change those amounts; this is not a spending cap.

## Files to modify
Paths below are relative to this native-app directory; backend changes are in the same parent repository.
- `../packages/contracts/src/index.ts`: selection enums, optional request selection, capability schema.
- `../supabase/functions/_shared/agents/model-config.ts`, `registry.ts`: typed profile registry, version metadata, legacy compatibility exports.
- `../supabase/functions/_shared/providers/{config,types,openrouter,mock}.ts`: per-profile route preflight, request-parameter adapters, mock Deep support, usage handling.
- `../supabase/functions/_shared/agents/{runtime,deep}.ts`: explicit profile settings, deadline/call bounds and safe error handling.
- `../supabase/functions/api/handler.ts`, `../supabase/functions/_shared/security/input.ts`: selection/capability routing, request budgets, accounting and validation.
- New `../supabase/migrations/202610250001_stylist_profiles.sql`: profile-aware reservations and operational selection metadata; modify the latest function definitions, preserving test quota exemption behavior.
- `Core/Contracts.swift`, `Core/Transport.swift`, `Services/AppModel.swift`, `Services/UITestSupport.swift`, `Views/AnalysisViews.swift`: choices, snapshotting, capabilities, timeouts, fixtures, result labels.
- `../tests/{core,deep,provider-config}.test.ts`, backend Deno tests and DB tests; `Tests/` and `UITests/`: extend existing suites rather than create an eval framework.
- `README.md`, `docs/setup.md`, `docs/backend.live.env.example`, `docs/backend.local.env.example`, `../supabase/functions/.env.example`, and parent roadmap/docs referencing evaluation as the next milestone. Never edit real credential files.
- `Scripts/generate_project.py` / Xcode project membership only if new Swift source files are introduced.

## Reuse
- `providerConfig`, `validateRoute`, `configuredProvider` in `../supabase/functions/_shared/providers/config.ts`.
- `assessmentVersions` in `../supabase/functions/_shared/agents/registry.ts`.
- `Contracts`, `Bootstrap`, `AnalysisResult.saveBody()` in `Core/Contracts.swift`.

## Steps

### 1. Define server-owned selection and capability contracts
- [x] Add optional `stylistTier: everyday | expert` and `analysisDepth: quick | deep` request metadata, defaulting missing values to Everyday Quick. Reject invalid values and arbitrary model/provider/token settings before claiming quota.
- [x] Add authenticated `GET /analysis-options` with four profile capabilities (tier, depth, enabled flag, safe unavailable reason). Keep `/bootstrap` unchanged in shape so older strict clients still decode it. `features.outfit` should mean at least one analysis profile is operational, not that only the legacy model preflight succeeded.
- [x] New client hides/blocks unsupported profiles; a 404 from an older backend enables only legacy Everyday Quick and omits new metadata. Revalidate availability on submission; do not silently change the selected tier/depth.
- [x] Keep an access-check function server-side which currently permits both tiers for every analysis-eligible account. No purchase UI, subscription tables, or paid entitlement service. Existing consent, beta and quota checks remain unchanged.

### 2. Implement profile configuration and provider adapters
- [x] Define immutable four-profile configuration with model, exact provider allowlist, effort, completion cap, call cap, pipeline version, request deadline and reservation. Preserve `productionModel`/comparison exports needed by dormant lab tooling; do not make live API behavior depend on experiment configuration.
- [x] Permit Luna only on approved `azure` route and Opus only on `google-vertex/global` initially. Preserve `allow_fallbacks:false`, `zdr:true`, `data_collection:deny`, `require_parameters:true` and API-key validation. No automatic substitution to non-ZDR endpoints.
- [x] Replace universal `REQUIRED_PARAMETERS` with parameters actually sent for the chosen profile. Azure advertises `max_completion_tokens`, not `max_tokens`; Opus Vertex advertises `max_tokens`. Neither selected route advertises temperature, so make temperature optional and omit it. Do not require tools/tool_choice for tool-free calls.
- [x] Validate exact model/image/structured-output/effort support and route token caps. Cache successful checks by complete route/profile configuration, deduplicate concurrent checks, and isolate failures so an Expert outage does not disable Everyday. Keep secrets out of logs and API capabilities.
- [x] Send `reasoning.exclude:true`; never log reasoning, photos or reports. Inspect finish reason and preserve usage even for empty/truncated/invalid JSON. Keep existing limited explicit-429 retry; never retry ambiguous network errors or transparently launch a new analysis.

### 3. Wire Quick and Deep without duplicating assessment logic
- [x] Pass captured generation settings to `runOutfit` for Quick. For Deep, call `runDeep` with the same tier provider for generator/evidence critic/styling critic, recent technique memory, and request ID as deterministic seed.
- [x] Reuse `calculateOutfitScore`, `selectSuggestions`, `forbidsPurchases`, `parseModelOutput`, `validateReview`, `approved`, `finalizeAssessment`, receipt signing, and technique persistence. Keep identical scoring rubric across all profiles; Expert must not mean inflated scores.
- [x] Deep allows one generation, two parallel reviews, one conditional revision and two rechecks (six model calls maximum, apart from explicit rejected 429 attempts). Initial retake ends the run immediately. Critics see the original image. No recursively nested Quick repair loops inside Deep.
- [x] Map internal `unvalidated` to existing `INVALID_MODEL_OUTPUT` with useful copy; never send a new unsupported wire response, fabricate a retake, or silently downgrade to Quick. Preserve the existing safe fallback to a previously approved original assessment when revision fails.
- [x] Extend mock provider fixtures to return valid critic/revision schemas as well as report/retake objects. Cover all profiles offline.

### 4. Make deadlines and spend safe
- [x] Use 45 seconds for Quick and **110 seconds total for Deep**, including auth/upload/preflight, with a shared absolute deadline and bounded settlement headroom. Remove the conflicting hardcoded 90-second Deep timeout in favor of remaining caller budget. Keep non-analysis endpoints at 45 seconds. Do not start repair if insufficient deadline remains; an already-reviewed safe original can be finalized, otherwise fail clearly.
- [x] Set iOS analysis request timeout to 60 seconds Quick / 130 seconds Deep and session resource ceiling to at least 140 seconds; keep ordinary requests at 60 seconds. Preserve cancellation and auth-generation guards. Do not show fabricated stage progress: current API is non-streaming. Use “Reviewing your outfit more carefully; this may take longer.”
- [x] Keep the total below hosted Supabase's 150-second limits and the database's two-minute stale-run sweep. Verify those boundaries with delayed mocks. If real Expert Deep cannot reliably finish within this bound, do not blindly lengthen it: disable that profile until a separately scoped asynchronous-job design is approved.
- [x] Replace the database's hardcoded $0.10-only reservation validation with trusted profile/version-specific reserves. Initial conservative reserves: Everyday Quick $0.10, Everyday Deep $0.25, Expert Quick $1.20, Expert Deep $5.00. These reserve headroom, not charges; settle to actual reported usage and release the difference.
- [x] Those reserves assume a conservatively enforced ceiling of 64K billable input tokens per call and the completion/call caps above. Before enabling profiles, implement a conservative input bound for text, image-token rules and repair/review context; if a trustworthy bound cannot be established, increase the reservation or refuse dispatch, not silently underestimate it. Validate pricing from the selected route and fail closed when approved cost bounds are exceeded. No unbounded prompts or tool calls.
- [x] Update the latest `claim_analysis` migration definition, not just the foundation SQL; preserve daily-quota exemptions, atomic monthly-budget locking, one-active-run and idempotency behavior. No automatic increase to the existing $20 monthly budget. A large Expert reserve can temporarily block new work near that ceiling; explain this as a safety reserve.
- [x] Move usage accumulation into a single provider wrapper shared by every call. Track per-call in-flight, resolved usage and ambiguous failures; a successful parallel critic must not erase another call's uncertainty. Wait for all parallel calls to settle/abort before final accounting. Handle swallowed review/repair errors and missing usage conservatively. Charge daily allowance once per dispatched user analysis, not per model call.
- [x] Retain accounting's independent bounded cleanup signal; failures/cancellations retain conservative reservations when final provider cost is unknown. Test known, unknown, malformed and partial-parallel outcomes.

### 5. Add clear, lightweight product UI
- [x] Put two labeled controls on photo review above the optional styling-intent disclosure: **Stylist: Everyday / Expert** and **Analysis: Quick / Deep**. Keep them distinct from the existing “Everyday” occasion preset. Use accessible stacked layout at large text sizes.
- [x] Copy: Everyday = “Fast, practical outfit advice”; Expert = “Our most capable stylist”; Quick = “A direct assessment”; Deep = “Extra checks for detail and useful suggestions.” Do not promise exact wait times, higher scores, or guaranteed accuracy.
- [x] Default to Everyday Quick. Remember choices in current session across retakes/new photos; reset on sign-out/relaunch. No new persistent preference storage in this release.
- [x] Snapshot tier/depth alongside prompt and intent before the async submission. Disable selection while submitting; retries are explicit new requests and use the captured selection unless the user returns to review and changes it. Capability refresh must not mutate an in-flight run.
- [x] Show submitted tier/depth on processing and current-result screens using immutable submission context. Keep report JSON and receipts unchanged. Saved history continues to show the existing report without inventing a tier/depth label from the currently configured model. Persist tier/depth/profile revision in server operational run metadata for diagnostics, not as unsigned modifications to saved reports.

### 6. Roll out and pause evaluation work
- [x] Apply DB migration, deploy backward-compatible backend with profiles initially disabled, then install updated client. Missing selection still invokes Everyday Quick. New backend must continue reading/saving old reports and verifying their original receipts.
- [x] Recheck exact route metadata and run contract/mock tests. Enable Everyday/Expert profiles only after explicitly authorized, bounded integration smoke calls confirm actual account access, parameter mapping, schema output and settlement. This is integration acceptance, not a model-quality comparison project.
- [x] Provide independent profile kill switches and an explicit legacy Flash Lite rollback; no automatic downgrade on an unavailable selection. Rollback must not corrupt active reservations or old reports.
- [x] Mark evaluation-lab docs/roadmap as deferred; retain scripts, datasets, prior results and existing tests. No new eval datasets, blind comparisons, experiment ledger, or benchmark dashboard. Keep operational timing/cost/error logging only, with tier/depth/profile revision and no user content.

## Reuse (additional)
- `runOutfit` (`../supabase/functions/_shared/agents/runtime.ts`) and `runDeep` plus review/finalization helpers (`deep.ts`).
- `calculateOutfitScore` (`scoring.ts`) and suggestion selection/recent technique memory (`suggestions.ts`).
- `parseAnalysis` (`security/input.ts`), `signReceipt`/`verifyReceipt` (`security/receipts.ts`).
- Existing `claim_analysis`, `dispatch_analysis`, `settle_analysis`, `maintain_analysis` SQL functions and quota-exemption migration.
- `AppModel.submit`, cancellation epochs and refresh guards; `Multipart.encode`, `APIClient.analyze`; existing review, processing, and result views.

## Verification
- [x] Parent repo: `npm run typecheck`, `npm test`, `npm run lint`, `npm run check:edge`, `npm run test:edge`, `npm run test:db`. Run with existing dependencies; do not accidentally invoke lab/live runners.
- [x] Native: `swift test`; Xcode scheme unit/UI tests on an installed simulator. Regenerate project only if Swift file membership changed.
- [x] Contract tests: four selections, omitted defaults, invalid/client model injection, old-backend capabilities 404, profile disabled between refresh and submit, old bootstrap/report/history decode, signed save roundtrip untouched.
- [x] Provider fixtures: exact model/provider/token-parameter mapping, omitted temperature, strict output, reasoning exclusion, ZDR failures, cached checks isolated by profile, truncation/usage preservation, explicit 429-only retries, route price/input bounds.
- [x] Deep fixtures: normal three-call completion, all six calls, retake, invalid/stale review IDs, rejected evidence, missed opportunity, revision failure, critic outage, empty approved suggestions, timeout and cancellation. Assert same deterministic scoring and suggestion safety as Quick.
- [x] DB/accounting: four reservations, one quota unit for six calls, exemption preserved, concurrent claims, duplicate requests, budget exhaustion, release of unused reserve, parallel mixed success/ambiguous failures, cancellation, independent settlement, stale-run maintenance and account deletion.
- [ ] UI: all four choices, accessible labels/large text, distinction from occasion, in-flight snapshotting, retake/retry behavior, unavailable profiles, slow Deep >60 seconds, cancellation/no stale result, sign-out reset, old saved report rendering.
- [ ] Live acceptance only with explicit authorization: one bounded request per enabled profile using an owned test image, checking valid output, routing and accounting rather than relative quality. Record actual latency/cost without asserting a benchmark. No image/report persistence beyond existing user-requested text saves.

## Out of scope
Payments, paywalls, StoreKit, subscriptions, new daily allowance systems, chats, automatic paid upgrades, persistent photo/job storage, streaming progress, model experiments and a new evaluation program. Future paid Expert needs server-verified entitlements before dispatch, not merely an iOS toggle; the selection/access seam above leaves that possible without implementing it now.
