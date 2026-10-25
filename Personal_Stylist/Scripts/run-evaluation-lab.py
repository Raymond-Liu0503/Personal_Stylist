#!/usr/bin/env python3
"""Start the real evaluation lab using the existing private OpenRouter config.

No inference is dispatched by this launcher. The browser's Run button starts
paid calls, subject to the lab's existing $10/$15 pilot limits.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    repo = Path(__file__).resolve().parents[2]
    photos = Path.home() / "StylistEvaluationData"
    live = photos / "live"
    config = repo / "supabase/functions/.env"
    node = shutil.which("node")
    if not node:
        versions = list((Path.home() / ".nvm/versions/node").glob("v*/bin/node"))
        versions.sort(key=lambda p: tuple(int(n) for n in p.parents[1].name[1:].split(".")))
        node = str(versions[-1]) if versions else None
    if not node:
        raise RuntimeError("Install Node 22.13 or newer, then run this command again.")
    if not config.is_file():
        raise RuntimeError(f"The private provider configuration is missing: {config}")
    if not (photos / "dataset.json").is_file():
        raise RuntimeError(f"The downloaded dataset is missing: {photos}")
    if not (repo / "node_modules/tsx").exists():
        raise RuntimeError(f"Run npm install in {repo}, then try again.")

    # This live workspace uses the licensed real photos already downloaded for
    # this pilot. Preserve the original mock manifest, ledger, and attempts.
    snapshot = json.loads((photos / "dataset.json").read_text())
    snapshot["mockOnly"] = False
    manifest = live / "dataset.json"
    if manifest.exists() and json.loads(manifest.read_text()) != snapshot:
        raise RuntimeError("The live dataset is already frozen and differs from the source. Restore the source manifest; do not reset the pilot ledger.")
    if (live / "lab.lock").exists():
        raise RuntimeError("The live lab already has a server lock. Open http://127.0.0.1:8787 if it is running; otherwise check the process in live/lab.lock before removing a stale lock.")
    if not manifest.exists():
        # A new ledger is valid here only because the previous workspace was a
        # mock run. Never reset paid pilot spending through this launcher.
        for path in (photos / "attempts").glob("*.json"):
            if json.loads(path.read_text()).get("live"):
                raise RuntimeError("Paid attempts exist in the original workspace. Keep its budget ledger before configuring another workspace.")
        ledger_path = photos / "ledger.json"
        if ledger_path.exists():
            entries = json.loads(ledger_path.read_text()).get("entries", [])
            if any(e.get("actual") not in (0,) or e.get("reserved") != 0 for e in entries):
                raise RuntimeError("The original workspace has paid or uncertain spending. Its ledger must be preserved.")

    env = os.environ.copy()
    # Explicit live launch of the user's licensed public-photo pilot. Source
    # attribution and any missing model releases remain recorded in the data.
    env.update(EVAL_LIVE="true", EVAL_RIGHTS_CONFIRMED="true", LAB_PORT="8787")
    args = [node, f"--env-file={config}", "--import", "tsx"]
    subprocess.run(args + [str(repo / "Personal_Stylist/Scripts/LabPreflight.mjs")], cwd=repo, env=env, check=True)
    live.mkdir(mode=0o700, exist_ok=True)
    if not manifest.exists():
        with manifest.open("x") as file:
            file.write(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n")
        manifest.chmod(0o600)
    print("LIVE lab: http://127.0.0.1:8787", flush=True)
    print("Clicking Run sends the selected photos to OpenRouter. Pilot ceiling: $10 development + $15 held-out.", flush=True)
    print(f"Live results: {live}. Earlier mock results remain in {photos}.", flush=True)
    os.chdir(repo)
    os.execve(node, args + ["evals/lab/server.ts", str(live), str(photos)], env)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Could not start the lab: {error}", file=sys.stderr)
        sys.exit(1)
