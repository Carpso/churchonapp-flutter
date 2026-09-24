#!/usr/bin/env bash
# refresh-maps.sh — scheduled map refresh (POSIX twin of refresh-maps.ps1).
# Rebuild sources, publish a dated snapshot, promote the stable keys, and
# upload tiles/latest.json.
#
# Usage:
#   ./scripts/map/refresh-maps.sh [--countries zambia,zimbabwe] [--cities lusaka]
#                                 [--scratch /var/tiles] [--force]
#                                 [--skip-build] [--skip-upload] [--date-stamp YYYYMMDD]
#
# Scheduling (cron, weekly Sunday 03:00):
#   crontab -e
#   0 3 * * 0 /opt/churchonapp_flutter/scripts/map/refresh-maps.sh \
#             --scratch /var/tiles >> /var/log/tile-refresh.log 2>&1

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BuildScript="$HERE/build-city-tiles.sh"
R2PUT="$HERE/r2-put.mjs"

Scratch="${Scratch:-$HOME/mapbuild}"
Countries="zambia,zimbabwe"
Cities=""
Force=0
SkipBuild=0
SkipUpload=0
UseDocker=0
DateStamp=""
KeyPrefix="tiles"
ManifestKey="latest.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --countries) Countries="$2"; shift 2 ;;
    --cities) Cities="$2"; shift 2 ;;
    --scratch) Scratch="$2"; shift 2 ;;
    --date-stamp) DateStamp="$2"; shift 2 ;;
    --key-prefix) KeyPrefix="$2"; shift 2 ;;
    --force) Force=1; shift ;;
    --skip-build) SkipBuild=1; shift ;;
    --skip-upload) SkipUpload=1; shift ;;
    --use-docker) UseDocker=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -20; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$Scratch"
Stamp="${DateStamp:-$(date -u +%Y%m%d)}"
ReportPath="$Scratch/build-report.json"
ManifestPath="$Scratch/latest.json"

if [[ $SkipBuild -eq 0 ]]; then
  echo "=== Building (stamp $Stamp) ==="
  args=(--scratch "$Scratch" --countries "$Countries" --date-stamp "$Stamp" --key-prefix "$KeyPrefix")
  [[ -n "$Cities" ]] && args+=(--cities "$Cities")
  [[ $Force -eq 1 ]] && args+=(--force)
  [[ $SkipUpload -eq 1 ]] && args+=(--skip-upload)
  [[ $UseDocker -eq 1 ]] && args+=(--use-docker)
  bash "$BuildScript" "${args[@]}"
fi

[[ -f "$ReportPath" ]] || { echo "No build report at $ReportPath" >&2; exit 1; }

echo ""
echo "=== Publishing manifest ==="
node -e '
  const fs = require("fs");
  const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));  const stamp = process.argv[3];
  const manifest = {
    generated_at: new Date().toISOString(),
    date_stamp: stamp,
    bucket: "church-on-app-maps",
    base_url: "https://maps.churchonapp.com/",
    sources: (report.sources || []).map((s) => {
      // Dated snapshot layout written by build-city-tiles: tiles/<stem>/<stamp>.pmtiles
      const dir = s.key.slice(0, s.key.lastIndexOf("/"));
      const stem = s.key.slice(s.key.lastIndexOf("/") + 1).replace(/\.pmtiles$/, "");
      return {
        id: s.id, name: s.name,
        url: `https://maps.churchonapp.com/${s.key}`,
        bbox: s.bbox, min_zoom: s.min_zoom, max_zoom: s.max_zoom,
        bytes: s.bytes, key: s.key,
        dated: `https://maps.churchonapp.com/${dir}/${stem}/${stamp}.pmtiles`,
        built_at: s.built_at,
      };
    }),
  };
  fs.writeFileSync(process.argv[2], JSON.stringify(manifest, null, 2));
  console.log(`  entries: ${manifest.sources.length}`);
' "$ReportPath" "$ManifestPath" "$Stamp"

if [[ $SkipUpload -eq 0 ]]; then
  command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
  node "$R2PUT" "$ManifestPath" "$KeyPrefix/$ManifestKey"
  echo "  remote: https://maps.churchonapp.com/$KeyPrefix/$ManifestKey"
else
  echo "  upload skipped (--skip-upload)"
fi

echo ""
echo "=== Scheduling ==="
cat <<EOF
  cron (weekly Sun 03:00):
    0 3 * * 0 $HERE/refresh-maps.sh --scratch $Scratch >> /var/log/tile-refresh.log 2>&1

  Windows equivalent (see refresh-maps.ps1 for the schtasks line).

  Roll back: repoint MAPS_ZAMBIA_URL / MAPS_EXTRA_SOURCES in .env at a dated
  URL (tiles/<name>/<yyyyMMdd>.pmtiles) and redeploy - no rebuild needed.
EOF
