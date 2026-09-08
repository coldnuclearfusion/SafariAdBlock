#!/bin/bash
# Build → install to /Applications/SafariAdBlock.app → register the extensions → launch
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

APP=/Applications/SafariAdBlock.app
pkill -x SafariAdBlock 2>/dev/null || true
rm -rf "$APP"
cp -R build/SafariAdBlock.app "$APP"

# Register the extensions so Safari (pluginkit) notices them right away
for ext in Ads Privacy Korea VideoAdSkip; do
  pluginkit -a "$APP/Contents/PlugIns/$ext.appex" 2>/dev/null || true
done
open "$APP" --args --reload   # launching with --reload pushes the new rules to Safari
echo "Installed: $APP"
echo "Turn on 'Ad Blocking', 'Tracker Blocking', 'Korean Sites Ad Blocking' and 'Video Ad Skipper' in Safari › Settings › Extensions."
