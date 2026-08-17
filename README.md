# zig-build-index

CORS-enabled mirror of [`https://ziglang.org/download/index.json`](https://ziglang.org/download/index.json).

Upstream serves the index without any `Access-Control-Allow-Origin` header, so browsers
cannot fetch it. GitHub Pages serves every file with `Access-Control-Allow-Origin: *`.

## Endpoints

| URL | Contents |
| --- | --- |
| <https://mlafeldt.github.io/zig-build-index/index.json> | Byte-for-byte copy of the upstream index |
| <https://mlafeldt.github.io/zig-build-index/meta.json> | Fetch timestamp, upstream `Last-Modified` and `ETag`, current master version |

```js
const index = await (
  await fetch("https://mlafeldt.github.io/zig-build-index/index.json")
).json();
console.log(index.master.version);
```

## How it works

`.github/workflows/mirror.yml` runs `scripts/mirror.sh` every hour:

1. `curl` the upstream index (retries on transient failures).
2. Sanity-check it with `jq` — must be a JSON object with a `master` key and more than
   one version, so error pages or truncated bodies never get mirrored.
3. If the bytes are identical to `public/index.json`, stop. Otherwise write
   `index.json` + `meta.json`, commit, and push.
4. Deploy `public/` to GitHub Pages.

Commits are made with `GITHUB_TOKEN`, which does not trigger workflows, so the `push`
trigger cannot loop. The git history doubles as a changelog of upstream index changes.

Run it locally with `./scripts/mirror.sh`.

## How often does upstream change?

Measured against live headers and Wayback Machine snapshots (Aug 2026):

- The index is rewritten when a new **master (nightly) build** is published — that's the
  only entry that moves regularly. Observed cadence is roughly **once a day**, published
  in the early UTC morning (e.g. `Last-Modified: Mon, 17 Aug 2026 07:58:47 GMT` for a
  build dated `2026-08-16`).
- The build's `date` field trails the publish time by 1–3 days, so builds are not strictly
  nightly — gaps appear when master CI isn't green.
- Zig master takes ~10 commits/day (`0.16.0-dev.2471` on 2026-02-03 → `0.16.0-dev.3153`
  on 2026-04-12 ≈ 682 commits in 68 days), but only the newest one lands in the index.
- Tagged releases (`0.15.2`, `0.16.0`, …) change every few months.

Hourly polling is therefore well above the real change rate; it exists to cut worst-case
staleness (and GitHub's cron scheduler is delayed under load anyway). Drop the schedule to
`0 */6 * * *` if hourly runs feel wasteful.

## Setup

GitHub Pages must be set to **Build and deployment → Source: GitHub Actions** in the
repository settings.
