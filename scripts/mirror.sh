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
# error pages or truncated responses getting mirrored).
jq -e 'type == "object" and has("master") and (keys | length) > 1' "$body" >/dev/null

mkdir -p "$OUT_DIR"

if [ -f "$INDEX" ] && cmp -s "$body" "$INDEX"; then
	echo "unchanged: $(jq -r '.master.version' "$INDEX")"
	exit 0
fi

header() { tr -d '\r' <"$headers" | awk -v k="$1" 'tolower($1) == tolower(k) ":" { $1=""; sub(/^ /, ""); print }' | tail -n 1; }

cp "$body" "$INDEX"

jq -n \
	--arg upstream "$UPSTREAM" \
	--arg mirrored_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--arg last_modified "$(header Last-Modified)" \
	--arg etag "$(header ETag)" \
	--arg master "$(jq -r '.master.version' "$INDEX")" \
	--arg master_date "$(jq -r '.master.date' "$INDEX")" \
	'{upstream: $upstream, mirrored_at: $mirrored_at, last_modified: $last_modified, etag: $etag, master: {version: $master, date: $master_date}}' \
	>"$META"

echo "updated: $(jq -r '.master.version' "$INDEX")"
