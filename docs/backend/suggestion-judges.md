# Independent judges for outfit suggestions

Recorded 2026-09-12. Status: future experiment; not implemented or enabled.

## Motivation

The current generator proposes actions and assigns their impact. The server trusts those labels when reranking, so a familiar action such as a tuck can win repeatedly if the generator calls it high impact. Independent review could challenge unsupported diagnoses, inflated impact, and repetitive advice.

## Proposed approach

1. Generate candidates from the photo and the user's goal and constraints.
2. Have an independent judge inspect the original photo, user context, and candidate actions. Hide the generator's ranking and impact labels, and randomize candidate order while preserving stable IDs.
3. Assess each action for visible grounding, expected outfit-level benefit, practicality, and constraint compliance. Evaluate the candidate set for duplication and contradiction. Permit rejection of every candidate.
4. Let the server select from the judged candidates and enforce user constraints and recent-technique preferences.

Standardize impact before judging: high addresses a dominant visible issue with a substantial outfit-level benefit; medium improves a noticeable relationship; low refines a small detail. Do not equate effort, expense, or relative rank with impact. Uncertain evidence cannot justify high impact. These criteria are proposed, not yet implemented.

## Start with one judge

Run an evaluation-only comparison before changing user-facing results. Compare the existing selector with a single independent judge using the same candidate pools and human review. Separately test a stronger generator with the prompt held fixed; avoid changing generator and judge simultaneously when measuring their effects.

If one judge helps and unresolved disagreements justify more complexity, explore a council with independent assessments of visual evidence, styling benefit, and user constraints. Every judge evaluating grounding needs the original photo. Different roles or models do not guarantee independent errors, and majority agreement is not proof of correctness. Define and test aggregation and disagreement handling before deployment.

## Evaluation and adoption

Use consented fixtures covering repeated similar outfits, tucked and untucked tops, minimalism, maximalism, accessories, footwear, colour, layering, texture, care, and limited visibility. Human reviewers should compare grounding, usefulness, repetition, distinction between alternatives, and invented details. Test order sensitivity and agreement with human judgments.

Measure the full pipeline's latency, cost, failure rate, and repair frequency against the existing gates in [outfit-upgrade-verification.md](outfit-upgrade-verification.md). Define timeout and judge-failure behavior before introducing a judge into production. Keep evaluation photos and candidate/judge prose outside the repository; production persistence currently remains selected technique codes only. Any additional provider receiving photos requires review under the existing provider approval process.

Open decisions: judge model, scoring rubric and calibration, aggregation, handling disagreements, fallback behavior, and whether any measured quality gain justifies deployment overhead.
