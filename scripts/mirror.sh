#!/usr/bin/env bash
# Mirror https://ziglang.org/download/index.json into public/.
# Writes nothing if the upstream payload is byte-identical to what we already have,
# so the git history only records real upstream changes.
set -euo pipefail

UPSTREAM="${UPSTREAM:-https://ziglang.org/download/index.json}"
OUT_DIR="${OUT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/public}"
INDEX="$OUT_DIR/index.json"
META="$OUT_DIR/meta.json"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
body="$tmp_dir/index.json"
headers="$tmp_dir/headers.txt"

curl --fail --silent --show-error --location \
	--retry 5 --retry-delay 5 --retry-all-errors \
	--max-time 60 \
	--dump-header "$headers" \
	--output "$body" \
	"$UPSTREAM"

# Reject anything that is not a JSON object keyed by version (guards against
# error pages or truncated responses getting mirrored). meta.json is built from
# .master.version and .master.date, so require both rather than writing "null".
if ! jq -e '
	type == "object"
	and (keys | length) > 1
	and ((.master.version? // "") | type == "string" and length > 0)
	and ((.master.date? // "") | type == "string" and length > 0)
' "$body" >/dev/null 2>&1; then
	echo "refusing to mirror: $UPSTREAM returned a payload that is not a Zig index" >&2
	echo "first 200 bytes:" >&2
	head -c 200 "$body" >&2
	echo >&2
	exit 1
fi

master_version=$(jq -r '.master.version' "$body")
master_date=$(jq -r '.master.date' "$body")

mkdir -p "$OUT_DIR"

# This guard also keeps CI honest: without it, meta.json's mirrored_at would
# change on every run and the workflow's `git diff` would commit every run.
if [ -f "$INDEX" ] && cmp -s "$body" "$INDEX"; then
	echo "unchanged: $master_version"
	exit 0
fi

header() { tr -d '\r' <"$headers" | awk -v k="$1" 'tolower($1) == tolower(k) ":" { $1=""; sub(/^ /, ""); print }' | tail -n 1; }

# Headers upstream did not send become null, not "".
jq -n \
	--arg upstream "$UPSTREAM" \
	--arg mirrored_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--arg last_modified "$(header Last-Modified)" \
	--arg etag "$(header ETag)" \
	--arg master "$master_version" \
	--arg master_date "$master_date" \
	'{upstream: $upstream, mirrored_at: $mirrored_at, last_modified: $last_modified, etag: $etag, master: {version: $master, date: $master_date}}
	| (.last_modified, .etag) |= (if . == "" then null else . end)' \
	>"$tmp_dir/meta.json"

# Publish both files only after both exist, so a failure midway cannot leave a
# fresh index.json next to a stale or empty meta.json.
cp "$body" "$INDEX"
cp "$tmp_dir/meta.json" "$META"

echo "updated: $master_version"
