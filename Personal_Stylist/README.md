# Personal Stylist — native iOS

SwiftUI client for the existing Personal Stylist Supabase `/v1` API. Targets iPhone on iOS 17+. The Expo app and backend in `/Users/raymondliu/Projects/personal-stylist` are unchanged.

## Open and run

Open **this folder's** `Personal Stylist.xcodeproj`, select **Personal Stylist**, and choose an iPhone simulator. The project one directory above is the original starter; open the renamed project here for the native app.

Start with **[the native iOS setup guide](docs/setup.md)**. It explains local setup, exactly where to get each credential, where to put it, and how to enable real AI or hosted Supabase later.

The app needs only the Supabase URL and public key in `LocalConfig.plist`. Private keys belong in the backend repository's `supabase/functions/.env` file. Local mock mode needs no OpenRouter or Apple credentials.

## What is implemented

- Home, Saved, and Account tabs; cream/burgundy styling, serif headings, native controls, Dynamic Type, and accessibility labels.
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
- iOS app, unit tests, and UI tests: compiled for the iOS simulator SDK; execution requires an available simulator.
- Release app: compiled successfully for the iPhone device SDK with signing disabled.
- Simulator execution: unavailable in the restricted environment because CoreSimulator could not connect and no runtime was discoverable.
- Real local-backend smoke: not run; Docker, Node, local backend configuration, and test credentials were unavailable here.
- Physical-device camera, Apple sign-in, and account deletion: require a signed device build and configured Apple services.

TestFlight distribution, hosted deployment, and paid inference activation are outside this local migration milestone.
