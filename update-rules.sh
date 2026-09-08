#!/bin/bash
# Downloads the filter lists and converts/validates them into Safari rules (JSON). Output: rules/<ext>.json, rules/<ext>.meta.json
#   ./update-rules.sh                  download + convert
#   SKIP_DOWNLOAD=1 ./update-rules.sh  convert only, from the files already in filters/sources (e.g. after editing custom.txt)
# Run ./install.sh afterwards so Safari picks up the new rules.
set -euo pipefail
cd "$(dirname "$0")"
export LC_ALL=en_US.UTF-8
SRC=filters/sources
mkdir -p "$SRC" rules

fetch() {  # fetch <URL> <file name>
  if [ "${SKIP_DOWNLOAD:-0}" = 1 ]; then return 0; fi
  local tmp; tmp=$(mktemp)
  if curl -fsSL --max-time 120 -o "$tmp" "$1"; then
    mv "$tmp" "$SRC/$2"
    echo "Downloaded: $2 ($(wc -l < "$SRC/$2" | tr -d ' ') lines)"
  else
    rm -f "$tmp"
    if [ -f "$SRC/$2" ]; then
      echo "Download failed: $1 — using the existing $2" >&2
    else
      echo "Download failed: $1" >&2; return 1
    fi
  fi
}

fetch https://easylist.to/easylist/easylist.txt easylist.txt
fetch https://easylist.to/easylist/easyprivacy.txt easyprivacy.txt
# List-KR (filterslist-KO) — the Safari-flavoured build distributed by AdGuard's filter server
fetch https://filters.adtidy.org/extension/safari/filters/227.txt list-kr.txt
fetch https://raw.githubusercontent.com/yous/YousList/master/youslist.txt youslist.txt

if [ ! -x tools/validate ] || [ tools/validate.swift -nt tools/validate ]; then
  echo "Building the validator…"
  swiftc -O -o tools/validate tools/validate.swift -framework WebKit
fi

convert() { python3 tools/convert.py --validator tools/validate "$@"; }
convert --name "Ad Blocking"              --out rules/Ads.json     --meta rules/Ads.meta.json     filters/custom.txt "$SRC/easylist.txt"
convert --name "Tracker Blocking"         --out rules/Privacy.json --meta rules/Privacy.meta.json "$SRC/easyprivacy.txt"
convert --name "Korean Sites Ad Blocking" --out rules/Korea.json   --meta rules/Korea.meta.json   "$SRC/list-kr.txt" "$SRC/youslist.txt"
# Apply the result in a real WKWebView: ad script and image must be blocked, the control must load, ad_display must be none
if [ ! -x tools/smoke-test ] || [ tools/smoke-test.swift -nt tools/smoke-test ]; then
  swiftc -O -o tools/smoke-test tools/smoke-test.swift -framework WebKit
fi
echo "Smoke test (rules/Ads.json): $(tools/smoke-test rules/Ads.json 2>/dev/null)"
echo "Done. Run ./install.sh to install the new rules."
