# Local styling evaluation lab

The lab runs the existing TypeScript analysis runtime and an experimental Deep review pipeline. It does **not** enable Deep in the app or claim that a frontier model improves advice. Complete the human-reviewed pilot before selecting production configurations.

## Try it without photos or API keys

From the repository root, with Node 22.13 or newer:

```sh
npm run lab:demo -- /tmp/stylist-evaluation-demo
npm run lab -- /tmp/stylist-evaluation-demo /tmp/stylist-evaluation-demo/photos
```

Open `http://127.0.0.1:8787`. The generated gray tile tests transport and workflow only; it contains no outfit. The demo manifest explicitly prohibits live inference. Run a generator experiment, then a review/Deep experiment with the first experiment's ID in **Reuse candidate pool**. Compare their reports, record a preference, inspect critic decisions, and label actions. Mock outputs are deterministic and provide no evidence about styling quality.

The server binds only to loopback, checks Host/Origin, accepts mutations only as same-origin JSON, and serves no third-party scripts. API keys never enter the browser. Photos are sanitized JPEGs (up to 1,600 pixels, 2 MiB). Photos, manifests, prompts, checkpoints, review labels and budgets must live **outside every Git checkout**; permissions on created files are owner-only. Existing source folders' permissions are not changed.

## Real pilot dataset

Create an external `dataset.json` using `dataset.example.json`. Use 30 outfit groups: 12 development and 18 held-out. Multiple related images share one `group` and one `split`; do not split a person's same outfit or near-duplicate photos across groups. Smaller manifests work while assembling the pilot. The code enforces group limits and split consistency; people must establish which photos are related. `metadata` uses the app's existing brief/constraint contract. Leave unspecified intent empty instead of inventing an occasion. Record image rights and source attribution in `rights` or an external referenced record. Human curation must confirm suitability; the lab cannot infer consent or age from a file name.

Both CLI and UI freeze the manifest on first use. Image hashes, configuration hashes, source-code hashes, complete prompt snapshots, route snapshots, individual call outputs/usage, candidate revisions, critic verdicts, events, final reports and failures are retained. Changing prompts/settings requires a new experiment ID. Resume skips every recorded attempt, including failures and interruptions; intentionally retry with a new ID. Never delete the spending ledger to retry. A hard crash leaves `lab.lock`; confirm the recorded process has exited before removing that lock. Unsettled spend remains reserved.

### Online image sources

[Fashionpedia](https://fashionpedia.github.io/home/index.html) is the first candidate: it provides garment/attribute annotations and public [downloads](https://github.com/cvdfoundation/fashionpedia). Its annotation license is not a blanket image license: [image rights depend on each original source](https://fashionpedia.github.io/home/data_license.html). Curate a 30-group subset and retain source URLs, attribution and applicable license records before sending images to inference providers. No dataset has been downloaded or rights-cleared by this implementation.

[DeepFashion](https://mmlab.ie.cuhk.edu.hk/projects/DeepFashion/DeepFashionAgreement.pdf) restricts use to noncommercial research. [ModaNet](https://github.com/eBay/modanet) also uses noncommercial terms. Neither is automatically cleared for product evaluation. Dataset garment labels can help judge visible grounding, but are not labels of good styling advice. Public benchmarks can also overlap model training data, so later validate on user-provided photos.

## Experiment sequence

1. Compare `baseline` (existing runtime, including its one generation repair) against `generator` runs using provisional Flash Lite, Gemini Pro and Claude Opus settings. A generator-only run makes exactly one call and uses existing validation/scoring/selection.
2. Reuse a generator experiment's candidate pool with `review` (two critics, no repair). Compare its final report to the original generator report. This controls for generation variance.
3. Reuse the same pool with `deep` (two critics, at most one repair, then two rechecks). In Blind comparison select original versus repaired candidate sets. This exposes all proposed actions, rather than confusing repair quality with final selection.
4. Repeat `review` on that identical source pool with different critic settings. Start with the other frontier family for both roles: Google generation / Anthropic critics, or vice versa. Shared failure modes remain possible.

Models and pinned provider routes are provisional, not winners. The catalog keeps the existing Flash Lite and Gemini Pro IDs and proposes `anthropic/claude-opus-4.6`; live execution must verify each requested route. A route that lacks a requested parameter, image input, strict structured output, output capacity or ZDR is rejected. No model is silently substituted. Newer Opus models are not automatically added to this pilot.

`outfit-v1` uses the existing frozen skill bundle; `review-v1` separates evidence/constraint and styling/diversity roles. To test another prompt, place `VERSION.txt` in external `DATA_ROOT/prompts` and select that version. A custom critic prompt supplies shared additional instructions; role names and mandatory review protocol remain in the system message. Prompt contents and their hashes are checkpointed. Do not modify held-out examples to improve prompts after inspecting their outcomes.

Headless experiments invoke the same code:

```sh
npm run lab:run -- /external/lab /external/photos /external/experiment.json
```

Use `experiment.example.json` as the configuration format. No keys are stored there.

## Live budget and routes

Live inference is off by default. Configure only the server environment:

```sh
export EVAL_LIVE=true
export EVAL_RIGHTS_CONFIRMED=true
export OPENROUTER_CONFIG_APPROVED=true
# Set OPENROUTER_API_KEY privately, outside Git.
npm run lab -- /external/lab /external/photos
```

Before dispatch the ledger reserves the **entire worst-case pipeline** using verified endpoint context length, the highest published price tier, output token bounds, and request fees. This intentionally overestimates small photos. Some frontier Deep configurations may therefore not fit the $10 development allowance at all. The server refuses those runs: reduce the experiment matrix/configuration, or implement and independently verify tighter model-specific image/token cost bounds. Do not bypass the ledger or raise the $25 ceiling. Endpoint verification does not guarantee a provider's availability at dispatch; failures remain recorded. No paid request was made during implementation.

Known usage is summed across every call. Unknown/ambiguous charges retain the full reservation, including after restart. A charge above the verified bound blocks further work. The ledger is process-locked, and the UI serializes experiments. Development can use at most $10, held-out at most $15; unused development funding is not silently transferred. Physical HTTP retries are limited to the existing provider's one explicit 429 retry; no ambiguous request is retried.

## Deep publication behavior

Generation produces at most six candidates. Two critics each receive the photo, brief, constraints, recent techniques, supporting assessment and the entire candidate set. Generator identity and self-rated impact are excluded; ordering is reproducibly shuffled. Each critic must return exactly one verdict for every current candidate ID/revision. Unknown, duplicate, missing or stale verdicts invalidate that review.

Only actions passed by both critics at their current revision can reach final selection (maximum three, potentially zero). Critics can reject material assessment evidence, not just actions. One repair can correct evidence/actions or address a missed opportunity. Repairs preserve IDs explicitly, introduce `n1`–`n6` for new actions, and increment revisions; both critics recheck the complete revised set. Failed repair can fall back only to the originally approved subset with a still-valid original assessment. Outages produce an internal `unvalidated` result, never a successful reviewed report or an irrelevant retake request. Only initial generation can return a photo-retake result.

The pipeline has one 90-second signal and six logical calls maximum; it does not call the baseline's repair loop. Cancellation reaches both parallel critics. Events describe actual generation/review/revision/recheck stages and do not expose draft advice to a product client. The lab intentionally shows internal reasoning for evaluator inspection. It is not a production endpoint.

## Reading results

Blind preference records A/B/tie/neither and free-text reasons. Final blind reports omit model/version/run identity. Critic inspection supports useful-action labels, grounding errors, constraint failures and semantic redundancy for each exact revision. Results expose preference counts, empty/unvalidated reports, repair counts, latency, known/unknown costs, and false approvals/rejections. Useful-action coverage is currently **dual-critic retention among labelled useful candidates**, not recall of all possible improvements in a photo. Unlabelled actions are unknown. Labels and outcomes are descriptive pilot evidence; repeated photos and related groups are not independent samples. One reviewer and 30 outfit groups do not establish universal quality. Mock outputs must not be mixed with live conclusions.

## Verification and remaining rollout gates

```sh
npm run check:lab
npm run test:lab
```

Targeted tests cover disagreement, missing/stale verdicts, parallel review, repair/recheck limits, invalid evidence, empty sets, outages, cancellation/partial timeouts, signed-report compatibility, budget exhaustion, resume, pool reuse, blind identity stripping and external-path protection. The mock HTTP workflow also checks setup, generation, pool reuse, preference recording, labels, results, photo delivery and origin rejection. A real-provider run and a visual browser review remain separate acceptance checks.

At implementation time the broader repository test suite already had a failing legacy React reducer test in `tests/core.test.ts` (`analysisReducer`/`state` no longer exist). Root typecheck also reports its missing names and the pre-existing untyped `scripts/compile-skills.mjs` import. The isolated lab typecheck passes; these unrelated failures have not been hidden or rewritten.

Next gates, in order:

- Curate the external dataset; run the capped pilot and collect blind preferences/action labels.
- Calibrate critics against false approvals **and** false rejections; pick Quick/Deep configurations only from measured quality/latency tradeoffs.
- Then integrate optional `analysisDepth`, an independent analysis-options endpoint, capability-gated photo-review selector, opt-in progress streaming, signed final responses, 90-second server / 120-second client timeouts, cancellation, operational config IDs, and a migration for configured worst-case reservations with one user quota charge. Production API/iOS behavior is unchanged here.
- Later add an offline Python [GEPA](https://github.com/gepa-ai/gepa) adapter around `lab:run`, with a **separate explicit experiment ledger and budget covering reflection calls**, and distinct training/validation/final-test groups. Calibrate/freeze critics before optimizing generators. The $25 pilot ledger is not a GEPA budget, and no optimizer runs in this version.
