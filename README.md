# zig-index-cors

CORS-enabled mirror of [`https://ziglang.org/download/index.json`](https://ziglang.org/download/index.json).

Upstream serves the index without any `Access-Control-Allow-Origin` header, so browsers
cannot fetch it. GitHub Pages serves every file with `Access-Control-Allow-Origin: *`.

Originally built for [What Zig Is It?](https://mathias.blog/tools/whatzigisit), but useful
to anyone who needs the index from a browser.

## Why not just fix upstream?

Upstream used to send `Access-Control-Allow-Origin: *`, then dropped it
([ziglang/www.ziglang.org#208](https://github.com/ziglang/www.ziglang.org/issues/208),
opened 2022). The issue was closed as won't-fix in Sept 2024: "I don't want to have to care
about adding this header, sorry". Asking again is unlikely to change the answer.

The header is still missing as of Nov 2026: the index comes from nginx with no
`Access-Control-Allow-Origin`, and an `OPTIONS` preflight gets `405 Not Allowed`. To check:

```sh
curl -s -o /dev/null -D - -H "Origin: https://example.com" \
  https://ziglang.org/download/index.json | grep -i access-control
```

There is no CDN in front: `ziglang.org` is a single self-hosted nginx box at Hetzner.
Adding the header would be one `add_header` line, so the refusal is a policy choice, not a
technical one. The one plausible downside (never stated upstream): with CORS, any website
could make every visitor's browser fetch the ~90 KB index straight from that server, using
it as a free backend. That would fit Zig moving downloads to
[community mirrors](https://ziglang.org/news/announcing-community-mirrors/) over bandwidth
costs. This mirror shifts that load onto GitHub Pages.

CORS only applies in browsers, so native tools (`zigup`, `zvm`, `curl`, …) are not
affected. Browser-based tools are the ones that break, and they need a mirror like this
one. If upstream ever adds the header back, this project can be retired.

## Endpoints

| URL | Contents |
| --- | --- |
| <https://mlafeldt.github.io/zig-index-cors/index.json> | Byte-for-byte copy of the upstream index |
| <https://mlafeldt.github.io/zig-index-cors/meta.json> | Fetch timestamp, upstream `Last-Modified` and `ETag`, current master version |

Use it from any page:

```js
const res = await fetch(
  "https://mlafeldt.github.io/zig-index-cors/index.json",
);
const index = await res.json();
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
  only entry that moves regularly. Observed cadence is roughly **once a day**, at varying
  times clustered around 01:00 and 11:00–15:00 UTC.
- The build's `date` field trails the publish time by 1–3 days, so builds are not strictly
  nightly — gaps appear when master CI isn't green.
- Zig master takes ~10 commits/day (`0.16.0-dev.2471` on 2026-02-03 → `0.16.0-dev.3153`
  on 2026-04-12 ≈ 682 commits in 68 days), but only the newest one lands in the index.
- Tagged releases (`0.15.2`, `0.16.0`, …) change every few months.

So one fetch a day, after both clusters, picks up most builds the same day:

```yaml
- cron: "30 15 * * *"
```

The trade-off: GitHub delays and sometimes drops scheduled workflows under load, and a
skipped run means a full day of staleness with no retry. Trigger the workflow manually
(`workflow_dispatch`) if you need a fresher index sooner.

## License

MIT — see [LICENSE](LICENSE).

---

*This project was proudly built with AI.*
