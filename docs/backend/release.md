# Beta release checklist

This code is not a release approval. The following gates require evidence, not checked boxes inferred from source code.

- Supply actual Apple developer identity, bundle ID, Xcode signing and hosted Supabase environments. Test native nonce sign-in, large secure sessions, expiry, sign-out and deletion on iPhone.
- Run the photo-only path on iPhone with camera and library inputs, front/back capture, crop, HEIC/PNG orientation, JPEG metadata inspection, 2 MiB cap, cancellation and force-quit/startup cleanup. Verify VoiceOver, Dynamic Type and contrast.
- Deploy and inspect RLS, database content, no-store headers, function logging/settings, crash handling, maintenance and backup retention. Confirm no image-bearing application logs or storage. Test report receipt alteration, expiry, cross-user reads and deletion.
- Review the exact OpenRouter model/provider endpoint, tools, image support, structured output, reasoning parameters and ZDR terms. Set the explicit allowlist only after approval. Run one consented live request with content-free log inspection. Confirm the maximum two-round cost is within the reservation. Configure a restricted $20 key and server kill switches.
- Validate Apple grant revocation, failed-revocation retry, failed-Supabase-deletion retry, and deletion of all user-linked tables. Account deletion must work before beta distribution.
- Replace the draft editorial knowledge review status with fashion-professional review. Do not present draft entries as externally validated professional advice.
- Supply at least 100 diverse licensed/consented outfit fixtures outside the repository. Two reviewers assess invention/actionability/serious failures and repeatability; obtain fashion-professional review before public release. Run `evals/runner/gates.mjs` against completed review data. Example manifests are templates, not completed evaluations.
- Meet ≥90% without material invention, ≥80% actionable/relevant advice, ≥90% repeated-score range ≤1, zero unresolved serious safety failures; median <10 s, p95 <25 s, mean complete-agent cost <$0.01.
- Review dependency audit findings and resolve applicable issues before shipping. Validate native release changes using a fresh Xcode archive. Submit preview to TestFlight only once the gates above pass.

Roll back by disabling `ANALYSIS_ENABLED` or `OUTFIT_ENABLED`, then deploying a reviewed earlier version. Keep `/api/v1` stable for installed beta clients. Do not migrate to a different unreviewed model as an automatic recovery measure.
