# Personal Stylist — native iOS

SwiftUI client for the existing Personal Stylist Supabase `/v1` API. Targets iPhone on iOS 17+. The backend lives alongside this folder in `../supabase/`, in the same repository.

## Open and run

Open **this folder's** `Personal Stylist.xcodeproj`, select **Personal Stylist**, and choose an iPhone simulator. The project one directory above is the original starter; open the renamed project here for the native app.

Start with **[the native iOS setup guide](docs/setup.md)**. It explains local setup, exactly where to get each credential, where to put it, and how to enable real AI or hosted Supabase later.

The app needs only the Supabase URL and public key in `LocalConfig.plist`. Private keys belong in the repository root’s `supabase/functions/.env` file. Local mock mode needs no OpenRouter or Apple credentials.

## What is implemented

- Camera-first home with Saved and Account sheets; compact photo review and score-first results, cream/burgundy styling, Dynamic Type, and accessibility labels.
- Apple sign-in, Keychain persistence, serialized token refresh, consent, beta/feature/quota checks, local development login, sign-out, and Apple account deletion.
- AVFoundation front/back camera, Off/3s/10s countdowns, camera interruption/restart handling, and PhotosPicker import.
- Orientation normalization, metadata removal, 1,600-pixel/2-MiB JPEG limits, protected temporary files, and startup/cancellation cleanup.
- Intent presets, custom intent, optional questions, cancellable analysis, explicit retries, complete/partial/unrated reports, retake instructions, criteria, suggestions, and feedback.
- Receipt-preserving saves, text-only paginated history, report deletion, preferences, and consent withdrawal.

`Core` contains contracts, HTTP transport, Supabase Auth, and image processing. `Services` contains app state, Apple authorization, and camera orchestration. `Views` contains SwiftUI presentation. API and auth services accept injected transport/storage; debug-only UI fixtures require the explicit `--ui-testing` launch argument and never replace the configured backend during normal use.

**Implementation adjustment:** authentication uses [Supabase's Auth HTTP endpoints](https://github.com/supabase/auth/blob/master/openapi.yaml) through `URLSession`, with Keychain storage, instead of the proposed Supabase Swift package. Package downloads were unavailable in the implementation environment. There are no third-party runtime dependencies. The backend wire contracts and authentication provider remain unchanged.

Reports retain their original JSON values for signed saves, including required nulls and UUID spelling. Photos and unsaved reports have no persistent application cache. Auth credentials are the only user content stored durably on the device. Returning from the background refreshes account access; analysis requests are never automatically retried.

## Verification

Run host-side contract, auth, API, and image tests without a simulator:

```sh
swift test
```

Run all iOS unit and UI tests with Product → Test in the **Personal Stylist** scheme, or:

```sh
xcodebuild -project 'Personal Stylist.xcodeproj' \
  -scheme 'Personal Stylist' -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' test
```

The UI suite covers consent, review, results, signed-save UI, history, preferences, partial assessments, retakes, and invalid output using deterministic injected HTTP responses. It does not prove camera hardware or Apple-service integration.

For a real local-backend smoke check, set `STYLIST_PUBLIC_KEY`, `STYLIST_TEST_EMAIL`, and `STYLIST_TEST_PASSWORD` in your shell; optionally set `STYLIST_URL`. Then run:

```sh
zsh Scripts/smoke-local.sh
```

This uses the production Swift API client with a generated JPEG, checks mock mode, and exercises sign-in, consent, analysis, idempotent signed saves, history, feedback, and report deletion. It changes consent, consumes an analysis, and leaves feedback/operational records on the disposable test account. It removes its saved report and uses only in-memory credentials.

Before device acceptance, verify denied camera permission, switching lenses, countdown cancellation, interruptions, library cancellation, large/rotated photos, VoiceOver and large text, Apple sign-in/session restoration, and account deletion. Test backend quota/beta/disabled/timeout scenarios separately.

The Xcode project has explicit source membership. After adding or moving Swift files, regenerate it with `python3 Scripts/generate_project.py`. This resets project settings to the checked-in generator defaults; reselect your development team if necessary.

## Verification status in this workspace

- Host-side tests: 16 passing, including image rotation/metadata cleanup and concurrent auth refresh.
- Camera-first iOS verification: 25 unit tests and 8 UI scenarios passed across simulator runs, including delayed-response cancellation, refresh races, gallery dismissal, and large-text layouts.
- Release/device build: previously compiled with signing disabled; physical-device signing and camera acceptance were not repeated for this UI change.
- Simulator execution: full suite on iPhone 18 Pro; focused capture-flow and accessibility checks on iPhone 17e. Xcode simulator services required execution outside the sandbox.
- Real local-backend smoke: not run; Docker, Node, local backend configuration, and test credentials were unavailable here.
- Physical-device camera, Apple sign-in, and account deletion: require a signed device build and configured Apple services.

TestFlight distribution, hosted deployment, and paid inference activation are outside this local migration milestone.

## Evaluation lab (deferred)

Model evaluations and experiments are sidelined while the Everyday / Expert product modes are implemented. The evaluation lab, scripts, datasets and previous results remain preserved for a future, separately authorized quality-research phase. Do not run its live launcher as part of normal app verification.

## Run real model experiments in the evaluation lab (deferred reference)

From this native-app directory, run:

```sh
python3 Scripts/run-evaluation-lab.py
```

The launcher loads the existing private OpenRouter configuration from `../supabase/functions/.env`, verifies the key and Flash route without inference, and starts the browser lab at `http://127.0.0.1:8787`. It finds Node in PATH or the local nvm installation. Leave the terminal open; Ctrl-C stops the server.

Live experiment records are saved under `~/StylistEvaluationData/live`, using the downloaded photos under `~/StylistEvaluationData/images`. The earlier mock manifest and results are preserved. The live manifest is a frozen snapshot; the launcher will not reset existing spending or overwrite changed datasets.

In the browser, check that the status says **LIVE**. Start with a new ID such as `flash-live-01`, Development, the existing baseline pipeline, and the default Flash Lite model with `google-vertex/global`. Clicking **Run** starts real model calls; opening the site does not. The ledger retains the $10 development / $15 held-out limits. To compare generators, use a second experiment ID, the same split, and Gemini Pro, then select those two experiment IDs in Blind comparison. Zero human-labelled errors before reviewing results is not evidence of quality.

The downloaded photos are an exploratory collection that includes crops and crowds. Their source licenses and attribution are retained; those cases may legitimately produce retake or partial reports. Critic/Deep configurations need separately verified routes and enough budget; the launcher only preflights the Flash baseline.

## Camera-first flow and performance checks

After sign-in and consent, the camera is home. Saved and Account open from the corner buttons. Take or import a photo, optionally expand Styling options, and tap Analyze. Results retain the complete report under expandable sections; saving still stores text only. Simulator users can import a photo when capture hardware is unavailable.

The capture session keeps its configuration between screens but stops while covered or backgrounded. Returning users with camera permission can see the preview during the account check; capture and analysis remain gated by consent/access. Model settings, rubric, image encoding, output validation, and report contracts are unchanged.

Local OSLog messages in subsystem `com.personalstylist`, category `Performance`, record `local_startup`, `account_refresh`, `camera_ready`, `photo_preparation`, `analysis_request`, and `result_presentation` durations. Analysis request timing includes authentication, network, server work, and HTTP response validation; report decoding follows that interval; its request ID correlates with existing backend elapsed-time/validation logs. Camera timing ends when the session is ready, not at a measured first rendered frame. No photos, prompts, credentials, or report text enter these logs.

For device acceptance, compare cold launch and warm camera return across repeated runs on the same iPhone, with the same photo, network, and backend. Record median and slow-run timings separately for app work and analysis. Verify lens switching, timer cancellation, permissions, interruptions, background/resume, larger text, VoiceOver, and gallery import. Simulator tests do not establish camera latency or a real-provider speed improvement.
