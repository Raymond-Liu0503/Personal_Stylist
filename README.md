# Personal Stylist — native iOS and backend

This repository contains the SwiftUI iOS app and the Supabase backend it calls.

- Open `Personal_Stylist/Personal Stylist.xcodeproj` in Xcode for the native app.
- In Xcode, select **Backend API Keys (.env)** in the project navigator. Add your OpenRouter key to `supabase/functions/.env` on the `OPENROUTER_API_KEY=` line. This local file is ignored by Git. In Finder, press **Command–Shift–.** to show hidden files.
- Put only the public Supabase URL and publishable key in `Personal_Stylist/LocalConfig.plist`.
- Follow [the setup guide](Personal_Stylist/docs/setup.md) to start the backend and connect the app.

The local `.env` starts in mock mode and has a generated report-signing secret. Adding an OpenRouter key does not activate live AI: follow section 5 of the setup guide to configure and review the provider, then switch to `AI_PROVIDER=openrouter`.

## Local backend

Install the Node version in `.nvmrc` and start Docker, then run these commands from this repository root:

```sh
npm install
npm run skills:build
npm run backend:start
npm run backend:serve
```

On a fresh checkout, first copy `supabase/functions/.env.example` to `supabase/functions/.env` and replace `REPORT_SIGNING_SECRET` with the output of `openssl rand -hex 32`.

In a second Terminal, run `npx supabase status` for the public connection details and `npm run local:user` to create a local test login. Restart `backend:serve` after changing `.env`.

## Verification

Backend: `npm test`, `npm run typecheck`, `npm run lint`, `npm run check:edge`, and `npm run test:edge`. With Supabase running, also run `npm run test:db`.

Native host tests: `cd Personal_Stylist && swift test`. See the [native README](Personal_Stylist/README.md) for simulator and end-to-end smoke checks.

Backend migrations, contracts, AI evaluation tools, and backend tests were copied from the original project. Expo UI code and its client-only tests were excluded; native client tests remain in `Personal_Stylist/Tests/`. Backend release and architecture notes live in `docs/backend/`.

## Styling evaluation lab (deferred)

See [the local evaluation lab](evals/lab/README.md) for mock setup, blind comparisons, critic calibration, and the capped $25 pilot. The evaluation lab and Deep pipeline are preserved but deferred while the product adds Everyday / Expert and Quick / Deep modes. No new model-comparison experiments are part of this milestone.
