# Personal Stylist: Supabase and API-key setup

Start with **local mock mode** below. It lets you test the native app without buying AI credits or configuring Sign in with Apple. Once that works, you can turn on real AI, configure Apple, or move the backend to hosted Supabase.

## 1. Know which folder you are configuring

The native app and its backend now live in this single repository:

| Location (relative to the repository root) | Purpose |
| --- | --- |
| `Personal_Stylist/` | SwiftUI app |
| `Personal_Stylist/LocalConfig.plist` | Public Supabase connection settings for iOS |
| `supabase/` | Database migrations and backend Edge Function |
| `supabase/functions/.env` | Private backend configuration, including `OPENROUTER_API_KEY` |

Run backend commands from `/Users/raymondliu/Projects/Personal_Stylist`, the repository root. Open `Personal_Stylist/Personal Stylist.xcodeproj` for the native app. The previous separate backend checkout is no longer needed for this setup.

The native app calls the backend, which calls the AI provider. Private keys in `LocalConfig.plist` would be bundled into the iPhone app. `.env` is ignored by Git and stays outside the iOS source folder. Finder hides dotfiles; press **Command–Shift–.** to reveal it.

## 2. Credential map: where each value comes from

| Value | Where you get it | Where it goes |
| --- | --- | --- |
| `SUPABASE_URL` | Local: `npx supabase status` → API URL. Hosted: your Supabase project's Connect dialog. | iOS `LocalConfig.plist` |
| `SUPABASE_PUBLISHABLE_KEY` | Local: `npx supabase status` → **anon** or **publishable** key. Hosted: Connect dialog or Settings → API Keys → publishable key. | iOS `LocalConfig.plist` |
| Local test email and password | Run `npm run local:user` in the repository root after migrations. | Enter into the app's **Local test login** fields |
| `REPORT_SIGNING_SECRET` | Generate it yourself with `openssl rand -hex 32`. It signs receipts used to save reports. | Backend `.env`; hosted Edge Function Secrets later |
| `OPENROUTER_API_KEY` | Create a key at [OpenRouter → Settings → Keys](https://openrouter.ai/settings/keys). Used only for real AI. | Backend `.env`; hosted Edge Function Secrets later |
| `APPLE_CLIENT_ID` | This native app's registered Apple bundle ID, currently `com.personalstylist.beta`. | Backend `.env` for account deletion; also register the bundle ID in Supabase's Apple provider |
| `APPLE_CLIENT_SECRET` | Generate an Apple client-secret JWT using your Apple Team ID, Key ID, and private `.p8` signing key. See section 6. | Backend `.env` for account deletion; hosted Edge Function Secrets later |
| Supabase service-role/server key | Available to the function through the Supabase runtime. | The CLI/platform supplies it; do not put it in the iOS config |

The public Supabase key is different from a user's password, a database password, and a Supabase CLI access token. The native app does not need those other credentials. The name `SUPABASE_PUBLISHABLE_KEY` also accepts the legacy public **anon** key used by this repository's pinned CLI. Supabase explains the key types and dashboard locations in its [API key guide](https://supabase.com/docs/guides/getting-started/api-keys).

## 3. Start the local backend

This route does not require creating a hosted project on supabase.com. The CLI starts a separate Supabase instance on your Mac and provides its local connection credentials.

### A. Install the backend tools

You need Node.js and a running Docker-compatible container runtime on the Mac. The repository root pins Node **22.23.2** in `.nvmrc`, and installs Supabase CLI **2.75.0** through npm. Xcode does not install these tools for you.

Open Terminal and run:

```sh
cd /Users/raymondliu/Projects/Personal_Stylist
```

If you already use `nvm`, run `nvm install` and `nvm use` here to select the pinned Node version. Otherwise install that Node version through your preferred Node installer. Install/start Docker Desktop or a compatible runtime before the next step. See [Supabase's local development guide](https://supabase.com/docs/guides/local-development/cli/getting-started) for container-runtime setup.

### B. Install dependencies and start Supabase

Run these commands in the **repository root**:

```sh
npm install
npm run skills:build
npx supabase start
```

For your first setup of a disposable local database, apply the migrations:

```sh
npx supabase db reset
```

`db reset` clears that local database, so do not repeat it when you want to keep local test accounts and saved reports. This repository already has a `supabase/config.toml`; you do not need `supabase init`.

### C. Create the backend environment file

Still in the repository root, create the real `.env` file if it does not exist:

```sh
test -f supabase/functions/.env || cp supabase/functions/.env.example supabase/functions/.env
open -e supabase/functions/.env
```

Generate a signing secret in Terminal:

```sh
openssl rand -hex 32
```

Copy its output into `REPORT_SIGNING_SECRET`. For this first mock setup, the important settings in that file are:

```dotenv
APP_ENV=local
AI_PROVIDER=mock
MOCK_SCENARIO=success
ANALYSIS_ENABLED=true
OUTFIT_ENABLED=true
REPORT_SIGNING_SECRET=PASTE_THE_RANDOM_VALUE_YOU_JUST_GENERATED
OPENROUTER_CONFIG_APPROVED=false
OPENROUTER_API_KEY=
APPLE_CLIENT_ID=
APPLE_CLIENT_SECRET=
```

There is also an annotated template in [backend.local.env.example](backend.local.env.example). It is documentation; the backend reads `supabase/functions/.env` at the repository root. Keep the same signing secret across restarts if you want previously issued save receipts to remain valid.

The local CLI supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to the function. You do not need to copy these server values yourself. See [Supabase's function environment-variable guide](https://supabase.com/docs/guides/functions/secrets).

### D. Run the API

For local Deep analysis, align the gateway timeout before serving. The Supabase CLI's default gateway cuts requests off at 150 seconds, before the backend's 180-second deadline. From the repository root:

```sh
npm run backend:gateway-timeout
npx supabase functions serve api --env-file supabase/functions/.env
```

Leave this Terminal running. After changing `.env`, stop it with Control-C and run the serve command again.

The gateway helper validates and gracefully reloads only the local gateway configuration, setting the functions read timeout to 195 seconds, and verifies the active setting. It makes no model calls and does not modify database data. Re-run it whenever Supabase recreates its gateway container; `npm run backend:start` runs it automatically. This is a local-only adjustment, not a way to change hosted Supabase limits. The iOS app must include the 200-second Deep request timeout and 210-second resource limit.

## 4. Get the credentials and connect Xcode

### A. Show your local Supabase connection details

Open a **second Terminal**, and run:

```sh
cd /Users/raymondliu/Projects/Personal_Stylist
npx supabase status
```

Look for:

- **API URL:** normally `http://127.0.0.1:54321`.
- **anon key** or **publishable key:** this is the public value you copy into the iOS app. The pinned CLI may show a long JWT beginning `eyJ`; newer CLIs may show `sb_publishable_…`.
- **Studio URL:** normally `http://127.0.0.1:54323`. This opens the local database dashboard in your browser.

Do not select **service_role**, **secret key**, or **JWT secret** for the iOS app.

### B. Edit the iOS config

Open **`Personal Stylist.xcodeproj` in this native folder**, then open `LocalConfig.plist` in the project navigator. Its four entries should be:

| Key | Value for local simulator testing |
| --- | --- |
| `SUPABASE_URL` | `http://127.0.0.1:54321` |
| `SUPABASE_PUBLISHABLE_KEY` | The public anon/publishable key from the previous step |
| `API_VERSION` | `v1` |
| `ENVIRONMENT` | `local` |

Use the base URL above, without appending `/rest/v1` or `/functions/v1`. The app builds the endpoint paths itself. If `LocalConfig.plist` is missing, copy `LocalConfig.example.plist` to that name. Rebuild/run the app after editing it.

### C. Create a user to sign in with

Back in the backend Terminal:

```sh
npm run local:user
```

This prints an email and password for a newly created local test user and enables their beta access. It also exempts that user from the daily analysis limit. These are **user credentials**, separate from the public project key.

Run the **Personal Stylist** scheme in Xcode using Debug and an iPhone simulator. In the app:

1. Turn on **I am 18 or older** and **I consent to AI photo processing**.
2. Expand **Local test login**.
3. Enter the email/password printed by `npm run local:user`.
4. Choose a photo and analyze it. The app should display **MOCK** and return sample feedback.

This confirms that the app, authentication, database, and Edge Function are connected. The sample feedback does not evaluate the photo's actual outfit.

For a physical iPhone, use the Mac's private LAN address, such as `http://192.168.1.20:54321`, instead of `127.0.0.1`. The phone and Mac need to be on the same reachable network. Allow local-network access on the phone. Local test login appears only in Debug with `ENVIRONMENT=local` and a localhost/private-LAN HTTP backend on port 54321.

Debug builds omit the Sign in with Apple entitlement so a free Apple Personal Team can sign the app for local device testing. Select your team in Xcode and use **Local test login**. Release builds retain the entitlement. To test Apple sign-in in Debug with a supported developer team, set the app target's Debug **Code Signing Entitlements** build setting to `Config/PersonalStylist.entitlements`; regenerating the project restores the local Debug default.

## 5. Add the real AI key when you are ready

The existing backend uses **OpenRouter**. It does not ask the native app for separate OpenAI or Gemini API keys.

1. Create an OpenRouter account, create an API key in [Settings → Keys](https://openrouter.ai/settings/keys), and arrange credits for real inference. See the [OpenRouter quickstart](https://openrouter.ai/docs/quickstart).
2. Put that key in **the backend's** `supabase/functions/.env`:

   ```dotenv
   OPENROUTER_API_KEY=YOUR_OPENROUTER_KEY
   AI_PROVIDER=openrouter
   OPENROUTER_MODEL=google/gemini-3.1-flash-lite
   OPENROUTER_PROVIDERS=google-vertex/global
   ```

3. For local development, keep `APP_ENV=local`. The source backend supports the real provider locally, so you can continue using the local test account.
4. Review the configured model/provider route before setting `OPENROUTER_CONFIG_APPROVED=true`. The backend requires image input, tools, structured output, the expected reasoning parameters, and its configured zero-data-retention route. It checks availability and refuses to start analysis if the route is incompatible. The [backend release guide](../../docs/backend/release.md) describes the provider review.
5. Set `ANALYSIS_ENABLED=true` and `OUTFIT_ENABLED=true`, restart the function server, and refresh account access in the app. Results should stop showing the mock label when the live provider is configured successfully.

You can copy the variable names from [backend.live.env.example](backend.live.env.example), but its defaults deliberately leave analysis/approval disabled. Only enable them when the real-provider configuration is ready. Never copy the OpenRouter key into `LocalConfig.plist`.

## 6. Configure Apple sign-in and account deletion

You can skip this entire section for the local mock path.

For native Apple sign-in:

1. In your Apple Developer account, register the app's bundle ID, currently `com.personalstylist.beta`, and enable **Sign in with Apple** for that App ID.
2. In Xcode → **PersonalStylist target → Signing & Capabilities**, select your development team and verify the Sign in with Apple capability. If you use a different bundle ID, use that same ID in every following Apple/Supabase setting.
3. Enable/configure the Apple provider in Supabase Authentication, with that native bundle ID as an allowed client ID. For the local stack, the `[auth.external.apple]` section in the backend's `supabase/config.toml` currently has `enabled=false`; native Apple testing needs the local provider configured too. The local email test path avoids this requirement.
4. Sign in on a configured device. For an Apple user, enable beta access after the user exists, using their UUID from Supabase Authentication → Users:

   ```sql
   insert into public.beta_access(user_id, enabled)
   values ('PASTE_USER_UUID_HERE', true)
   on conflict (user_id) do update set enabled = true;
   ```

Supabase's [Apple sign-in guide](https://supabase.com/docs/guides/auth/social-login/auth-apple) explains the native provider configuration. Native token sign-in itself differs from browser OAuth configuration.

**This project's account-deletion flow additionally exchanges and revokes a fresh Apple grant.** That backend flow requires:

- `APPLE_CLIENT_ID`: the native bundle ID matching the authorization code.
- `APPLE_CLIENT_SECRET`: an Apple client-secret **JWT**, generated using the Sign in with Apple `.p8` private key, its Key ID, and your Apple Team ID. It is not the contents of the `.p8` file and is not a Supabase API key.

Create the signing key through Apple Developer → Certificates, Identifiers & Profiles → Keys. Follow [Apple's token exchange documentation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens) when generating the JWT. Store the resulting JWT in the backend environment and renew it before its expiry. Keep the private `.p8` file outside the app and source control. Until these server credentials are configured, native account deletion will return a configuration error even if sign-in works.

## 7. Use a hosted Supabase project later

Local Supabase and hosted Supabase are separate databases with different keys and users. Creating a project on supabase.com does not populate the database or deploy this app's function automatically.

1. Create/select your project at [Supabase Dashboard](https://supabase.com/dashboard). Save its database password for CLI database operations; the native app does not need it.
2. In the repository root, authenticate the CLI and link the hosted project using its project reference:

   ```sh
   npx supabase login
   npx supabase link --project-ref YOUR_PROJECT_REF
   npx supabase db push --linked
   npm run skills:build
   ```

   The reference is the project identifier used in its default URL, `https://YOUR_PROJECT_REF.supabase.co`. These commands apply migrations to the hosted database; use a development project first.

3. Create `supabase/functions/.env.development` in the repository root using the variables in [backend.live.env.example](backend.live.env.example). Use a fresh signing secret, `APP_ENV=development`, your OpenRouter key, and Apple revocation credentials. Keep analysis/approval disabled until the provider review is complete. The existing backend allows its deterministic mock provider only with `APP_ENV=local`.
4. Set the hosted function's private values and deploy its code:

   ```sh
   npx supabase secrets set --env-file supabase/functions/.env.development
   npx supabase functions deploy api
   ```

   Alternatively, enter the variables in the hosted Dashboard's **Edge Functions → Secrets** screen. The platform supplies its own `SUPABASE_*` defaults; do not upload local Supabase keys or try to create reserved `SUPABASE_*` secrets. See [Supabase's secrets guide](https://supabase.com/docs/guides/functions/secrets).

5. In the hosted project's **Connect** dialog, copy its project URL and public/publishable key. Update native `LocalConfig.plist` to those two hosted values and `ENVIRONMENT=development` (`API_VERSION` stays `v1`). Use values from the same project. [Supabase's API-key guide](https://supabase.com/docs/guides/getting-started/api-keys) lists the dashboard locations.
6. Configure hosted Apple authentication and beta access using section 6. The local email test-login UI is unavailable for hosted URLs; hosted app sign-in uses Apple.
7. For ongoing hosted use, schedule `select public.maintain_analysis()` once per minute with Supabase Cron, as required by this backend's reservation cleanup.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| “Add your public Supabase configuration” | Replace the placeholder in `LocalConfig.plist`, then rebuild. Check that this file belongs to the native project you opened. |
| `npx supabase start` fails | Start the container runtime; run from the repository root containing `supabase/config.toml`. |
| No local test-login section | Use Debug, `ENVIRONMENT=local`, and a private/local HTTP URL on port 54321. |
| Sign-in fails with the printed email/password | Use the local URL and public key; hosted and local accounts are separate. A database reset removes local accounts, so provision another user afterward. |
| Phone cannot connect | On a phone, localhost means the phone. Use the Mac's LAN IP, allow local-network access, and check firewall/network reachability. |
| Sign-in works but analysis is paused | Confirm the function server is running and `.env` has the right provider, flags, and a random `REPORT_SIGNING_SECRET` of at least 32 characters. Restart the server after edits. |
| Invitation awaiting activation | Run `npm run local:user` for local testing, or enable the signed-in hosted user's beta access using the SQL above. |
| Real AI remains unavailable | Check the OpenRouter key, credits, approval flag, and configured model/provider compatibility. |
| Saving returns an invalid-receipt error | Keep the backend signing secret stable; save within 24 hours while the report is still open. |
| Account deletion requires Apple configuration | Configure backend `APPLE_CLIENT_ID` and `APPLE_CLIENT_SECRET`; local email test accounts cannot exercise Apple revocation. |
