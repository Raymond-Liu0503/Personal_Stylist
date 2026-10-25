# Architecture

`packages/contracts` is the public boundary: platform-independent Zod schemas, types, policy version, and errors. Deno imports its source using relative `.ts` paths; the Swift client implements the same wire contracts in `Personal_Stylist/Core/Contracts.swift`. No mobile module imports backend instructions, tools, or keys.

`Personal_Stylist/` contains the SwiftUI client, URLSession API transport, Keychain-backed authentication, AVFoundation camera, and PhotosPicker integration. Prepared JPEGs use protected temporary files. Results remain in memory until explicitly saved.

The versioned Edge handler authenticates all endpoints. Bootstrap/profile/consent/history use strict contracts. User-scoped database clients enforce RLS for reads; allowlisted, validated mutations use the backend client with an explicitly injected owner ID because direct authenticated writes are forbidden. Report ownership never comes from client metadata. Beta access, quota, budget, and accounting functions are service-role-only.

Analysis order: authenticate and gate access → stream-limited multipart parsing → JPEG marker and metadata validation → preferences → atomic reservation → dispatch marker → bounded specialist → schema and deterministic scoring → settlement → receipt. The overall 45-second signal propagates to network requests. A separate five-second accounting signal permits settlement after client cancellation. Worker failures leave reservations for maintenance.

The runtime registers one specialist with compiled Markdown/JSON instructions and a SHA-256 skill version. It permits two model rounds and one batch of at most three guidance calls. Final-round tool requests are rejected. Invalid output can be repaired only within the two-round ceiling. Unvalidated output never becomes UI prose. The model supplies only criterion assessments and supporting intent evidence; runtime computes the overall score and verdict. Core criteria are always applicable but may have null scores; only intent is conditionally applicable. A saved preference can count as explicit context, while the default prompt cannot fabricate an occasion.

Daily usage counts dispatched analyses, including retakes and failed dispatched requests. Atomic user locks and a monthly ledger row enforce one active analysis and a $20 budget. Every run reserves $0.10 for the maximum reviewed execution. Completed request IDs cannot dispatch again. There is no unsaved-result recovery cache. Settlement is idempotent. Uncertain billing retains cost reservations while releasing active state. User deletion conservatively settles outstanding reservations before cascading rows.

Reports are strict bounded plain-text JSON, saved only with a 24-hour HMAC receipt binding owner, run, canonical report hash, and expiry. A unique owner/run key makes repeated Save operations idempotent. Cursor pagination orders by timestamp and UUID. Feedback is structured and may reference only an owned saved report.

Account deletion obtains fresh native Apple authorisation, exchanges its code directly with Apple, checks the returned subject against the authenticated Apple identity, revokes the returned grant, records a revocation checkpoint, then deletes Supabase Auth. A provider or auth failure returns a resumable error; the next user retry obtains fresh Apple authorisation. No Apple grant token is persisted by the application backend.

Future specialists add a registry entry, contract, reviewed skill package, tool allowlist and evaluations. No placeholder specialists, unused wardrobe tables, image generation or durable conversations exist.
