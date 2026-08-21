# zig-index-cors

CORS-enabled mirror of [`https://ziglang.org/download/index.json`](https://ziglang.org/download/index.json).

Upstream serves the index without any `Access-Control-Allow-Origin` header, so browsers
cannot fetch it. GitHub Pages serves every file with `Access-Control-Allow-Origin: *`.

## Endpoints

| URL | Contents |
| --- | --- |
| <https://mlafeldt.github.io/zig-index-cors/index.json> | Byte-for-byte copy of the upstream index |
| <https://mlafeldt.github.io/zig-index-cors/meta.json> | Fetch timestamp, upstream `Last-Modified` and `ETag`, current master version |

```js
const index = await (
  await fetch("https://mlafeldt.github.io/zig-index-cors/index.json")
).json();
console.log(index.master.version);
```

GitHub Pages serves both files with `Cache-Control: max-age=600`, so a fresh mirror can
take up to ten more minutes to reach you through the CDN. Both files also carry an
`ETag`, so conditional requests are cheap.

## How it works

`.github/workflows/mirror.yml` runs `scripts/mirror.sh` on a schedule:

1. `curl` the upstream index (retries on transient failures).
2. Sanity-check it with `jq` — must be a JSON object holding more than one version,
   with a non-empty `master.version` and `master.date`, so error pages, truncated
   bodies, and payloads that would produce a `null`-filled `meta.json` never get
   mirrored.
3. If the bytes are identical to `public/index.json`, stop. Otherwise write
   `index.json` + `meta.json`, commit, and push.
4. Deploy `public/` to GitHub Pages — but scheduled runs skip this unless step 3
   actually changed something, so identical bytes are never republished.

Commits are made with `GITHUB_TOKEN`, which does not trigger workflows, so the `push`
trigger cannot loop. The git history doubles as a changelog of upstream index changes.

`mirrored_at` in `meta.json` records when the current payload was fetched, not when the job
last ran — the job only writes on a real change. So a stale `mirrored_at` means upstream
has been quiet, not that the mirror is broken. A broken mirror surfaces as a failed
scheduled run, which GitHub emails to the repository owner.

Run it locally with `./scripts/mirror.sh`; `OUT_DIR=/tmp/x ./scripts/mirror.sh` writes
somewhere else.

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

So the schedule is shaped around that signal rather than blanketing the clock:

```yaml
- cron: "20 5-10 * * *"   # dense across the nightly publish window
- cron: "50 */6 * * *"    # tagged releases + recovery from skipped runs
```

That's ~10 fetches a day. The extra runs beyond one exist because GitHub delays and
sometimes drops scheduled workflows under load — a single daily cron that gets skipped
means a full day of staleness with no retry. The fetches are cheap; the Pages deploy is
the expensive part, and it only fires on real changes (roughly once a day).

## Used by

- [What Zig Is It?](https://mathias.blog/tools/whatzigisit)

## License

MIT — see [LICENSE](LICENSE).

---

*This project was proudly built with AI.*
