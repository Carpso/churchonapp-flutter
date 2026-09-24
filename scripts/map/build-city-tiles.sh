#!/usr/bin/env bash
# build-city-tiles.sh â€” reproducible city-level PMTiles pipeline (POSIX twin of
# build-city-tiles.ps1). Countries z0-15 + metros z13-19, uploaded to R2 via
# scripts/map/r2-put.mjs.
#
# Usage:
#   ./scripts/map/build-city-tiles.sh [--countries zambia,zimbabwe] [--cities lusaka,harare|all]
#                                     [--scratch /var/tiles] [--force] [--skip-download]
#                                     [--skip-upload] [--date-stamp YYYYMMDD] [--use-docker]
#                                     [--planetiler-jar /path/planetiler.jar] [--only-fetch-ways]
#
# Re-run / resume: Planetiler cannot resume a partial run. If the output file
# already exists the step is skipped, so a re-run continues after the last
# COMPLETED source. --force rebuilds a completed source from scratch.
#
# Prerequisites: java 17+ OR docker, node 18+, curl.
# Credentials: R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
#   (or VITE_R2_* in the sibling churchonapp/.env).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R2PUT="$HERE/r2-put.mjs"
MetrosJson="$HERE/metros.json"

Scratch="${Scratch:-$HOME/mapbuild}"
Countries="zambia,zimbabwe"
Cities=""
PlanetilerJar="${PLANETILER_JAR:-}"
UseDocker=0
CountryHeapGb=8
CityHeapGb=6
SkipDownload=0
SkipUpload=0
Force=0
DateStamp=""
KeyPrefix="tiles"
OnlyFetchWays=0
ExtraArgs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --countries) Countries="$2"; shift 2 ;;
    --cities) Cities="$2"; shift 2 ;;
    --scratch) Scratch="$2"; shift 2 ;;
    --planetiler-jar) PlanetilerJar="$2"; shift 2 ;;
    --country-heap) CountryHeapGb="$2"; shift 2 ;;
    --city-heap) CityHeapGb="$2"; shift 2 ;;
    --date-stamp) DateStamp="$2"; shift 2 ;;
    --key-prefix) KeyPrefix="$2"; shift 2 ;;
    --use-docker) UseDocker=1; shift ;;
    --skip-download) SkipDownload=1; shift ;;
    --skip-upload) SkipUpload=1; shift ;;
    --force) Force=1; shift ;;
    --only-fetch-ways) OnlyFetchWays=1; shift ;;
    --extra-arg) ExtraArgs+=("$2"); shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -30; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$Scratch"
ReportPath="$Scratch/build-report.json"
Stamp="${DateStamp:-$(date -u +%Y%m%d)}"
has() { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }
bytes_h() {
  local n="$1"
  if   (( n >= 1073741824 )); then awk -v n="$n" 'BEGIN{printf "%.2f GB", n/1073741824}'
  elif (( n >= 1048576 ));    then awk -v n="$n" 'BEGIN{printf "%.1f MB", n/1048576}'
  elif (( n >= 1024 ));       then awk -v n="$n" 'BEGIN{printf "%.1f KB", n/1024}'
  else echo "$n B"; fi
}
size_of() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }
bbox_csv() { # JSON array [south, west, north, east] -> "s,w,n,e"
  node -e 'process.stdout.write(JSON.parse(process.argv[1]).join(","))' "$1"
}
country_field() { # country_field <id> <field>
  node -e '
    const fs = require("fs");
    const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const row = d.countries.find((c) => c.id === process.argv[2]);
    if (!row) { console.error("metros.json: unknown country " + process.argv[2]); process.exit(1); }
    const v = row[process.argv[3]];
    process.stdout.write(typeof v === "string" ? v : JSON.stringify(v));
  ' "$MetrosJson" "$1" "$2"
}
metro_field() { # metro_field <id> <field>
  node -e '
    const fs = require("fs");
    const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const row = d.metros.find((m) => m.id === process.argv[2]);
    if (!row) { console.error("metros.json: unknown metro " + process.argv[2]); process.exit(1); }
    const v = row[process.argv[3]];
    process.stdout.write(typeof v === "string" ? v : JSON.stringify(v));
  ' "$MetrosJson" "$1" "$2"
}
list_ids() { # list_ids <countries|metros>
  node -e '
    const fs = require("fs");
    const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(d[process.argv[2]].map((r) => r.id).join(","));
  ' "$MetrosJson" "$1"
}
jget() { # jget <json-file> <JS expression over `d`>  (prints the result)
  node -e "
    const fs = require('fs');
    const d = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    const v = (new Function('d', 'return (' + process.argv[2] + ');'))(d);
    process.stdout.write(typeof v === 'string' ? v : JSON.stringify(v));
  " "$1" "$2"
}

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v node  >/dev/null || { echo "node 18+ is required" >&2; exit 1; }
[[ -f "$MetrosJson" ]] || { echo "missing $MetrosJson" >&2; exit 1; }

ReportTmp="$(mktemp)"
trap 'rm -f "$ReportTmp"' EXIT

log()  { printf '\n=== %s ===\n' "$1"; }
skip() { printf '  skip: %s\n' "$1"; }

fetch_pbf() { # fetch_pbf <id>
  local id="$1" url pbf
  url="$(country_field "$id" geofabrik)"
  pbf="$Scratch/$(country_field "$id" pbf)"
  if [[ $SkipDownload -eq 0 ]]; then
    if [[ -s "$pbf" && $(size_of "$pbf") -gt 1048576 ]]; then
      skip "already downloaded: $(basename "$pbf") ($(bytes_h "$(size_of "$pbf")"))"
    else
      echo "  downloading $url"
      curl -L -C - --retry 4 --retry-delay 2 -o "$pbf" "$url"
    fi
  fi
  [[ -f "$pbf" ]] || { echo "missing PBF: $pbf (re-run without --skip-download)" >&2; exit 1; }
  [[ $(size_of "$pbf") -gt 1048576 ]] || { echo "PBF truncated: $pbf" >&2; exit 1; }
  echo "$pbf"
}

run_planetiler() { # run_planetiler <out> <heapGb> <args...>
  local out="$1" heap="$2"; shift 2
  local args=("$@")
  [[ $OnlyFetchWays -eq 1 ]] && args+=("--only_fetch_ways=true")
  [[ $Force -eq 1 ]] && args+=("--force")
  [[ ${#ExtraArgs[@]} -gt 0 ]] && args+=("${ExtraArgs[@]}")

  if [[ $UseDocker -eq 1 ]]; then
    command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
    local dargs=() a
    for a in "${args[@]}"; do dargs+=("${a//"$Scratch"/\/data}"); done
    echo "  docker run $DockerImage"
    docker run --rm -v "$Scratch:/data" --memory="${heap}g" "${DockerImage:-ghcr.io/onthegomap/planetiler:latest}" "${dargs[@]}"
  else
    command -v java >/dev/null || { echo "java 17+ not found, or pass --use-docker" >&2; exit 1; }
    [[ -f "$PlanetilerJar" ]] || { echo "planetiler.jar not found at '$PlanetilerJar'" >&2; exit 1; }
    echo "  java -Xmx${heap}g -jar $PlanetilerJar"
    java "-Xmx${heap}g" -jar "$PlanetilerJar" "${args[@]}"
  fi
  [[ -f "$out" ]] || { echo "planetiler produced no output: $out" >&2; exit 1; }
}

upload() { # upload <local> <key>
  [[ $SkipUpload -eq 1 ]] && { skip "upload disabled: $2"; return 0; }
  node "$R2PUT" "$1" "$2"
}
copy_obj() { # copy_obj <src> <dst>
  [[ $SkipUpload -eq 1 ]] && return 0
  node "$R2PUT" --copy "$1" "$2"
}
publish() { # publish <local> <name> -> echoes stable key
  local local_file="$1" name="$2" key="$KeyPrefix/$name.pmtiles"
  if [[ -n "$DateStamp" ]]; then
    local dated="$KeyPrefix/$name/$DateStamp.pmtiles"
    upload "$local_file" "$dated"
    copy_obj "$dated" "$key"
  else
    upload "$local_file" "$key"
  fi
  echo "$key"
}
add_report() { # add_report <id> <label> <bboxJson> <minZ> <maxZ> <path> <key>
  node -e '
    const [id, label, bbox, minZ, maxZ, p, key] = process.argv.slice(1);
    const { statSync } = require("fs");
    console.log(JSON.stringify({
      id, name: label, path: p, bytes: statSync(p).size, bbox: JSON.parse(bbox),
      min_zoom: Number(minZ), max_zoom: Number(maxZ), key,
      url: "https://maps.churchonapp.com/" + key,
      built_at: new Date().toISOString(), date: process.env.__STAMP__,
    }));
  ' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$ReportTmp"
}

export __STAMP__="$Stamp"
echo "Scratch : $Scratch"
echo "Stamp   : $Stamp"
echo "Countries: $Countries"
echo "Metros  : ${Cities:-(none)}"
echo "Upload  : $([[ $SkipUpload -eq 1 ]] && echo disabled || echo "enabled -> $KeyPrefix")"

declare -A PbfFor=()

# ----------------------------------------------------------- 1. country bases
IFS=',' read -ra COUNTRY_IDS <<< "$Countries"
for cid in "${COUNTRY_IDS[@]}"; do
  [[ "$cid" == "all" ]] && { IFS=',' read -ra COUNTRY_IDS <<< "$(list_ids countries)"; break; }
done
for cid in "${COUNTRY_IDS[@]}"; do
  cname="$(country_field "$cid" name)"
  bbox="$(country_field "$cid" bbox)"
  log "Country: $cname (z0-15)"
  pbf="${PbfFor[$cid]:-}"
  if [[ -z "$pbf" ]]; then pbf="$(fetch_pbf "$cid")"; PbfFor[$cid]="$pbf"; fi
  out="$Scratch/$cid-z0-15.pmtiles"
  if [[ -f "$out" && $Force -eq 0 ]]; then
    skip "output exists (use --force to rebuild): $out"
  else
    run_planetiler "$out" "$CountryHeapGb" \
      "--area=$pbf" "--bounds=$(bbox_csv "$bbox")" \
      --minzoom=0 --maxzoom=15 "--output=$out"
  fi
  echo "  size: $(bytes_h "$(size_of "$out")")"
  key="$(publish "$out" "$cid-z0-15")"
  add_report "$cid" "$cname" "$bbox" 0 15 "$out" "$key"
done

# ------------------------------------------------------------- 2. metro clips
if [[ -n "$Cities" ]]; then
  IFS=',' read -ra CITY_IDS <<< "$Cities"
  [[ "${CITY_IDS[0]}" == "all" ]] && IFS=',' read -ra CITY_IDS <<< "$(list_ids metros)"
  for mid in "${CITY_IDS[@]}"; do
    mname="$(metro_field "$mid" name)"
    mcoun="$(metro_field "$mid" country)"
    bbox="$(metro_field "$mid" bbox)"
    log "Metro: $mname (z13-19, country=$mcoun)"
    pbf="${PbfFor[$mcoun]:-}"
    if [[ -z "$pbf" ]]; then pbf="$(fetch_pbf "$mcoun")"; PbfFor[$mcoun]="$pbf"; fi
    out="$Scratch/$mid-z13-19.pmtiles"
    if [[ -f "$out" && $Force -eq 0 ]]; then
      skip "output exists (use --force to rebuild): $out"
    else
      run_planetiler "$out" "$CityHeapGb" \
        "--area=$pbf" "--bounds=$(bbox_csv "$bbox")" \
        --minzoom=13 --maxzoom=19 "--output=$out"
    fi
    echo "  size: $(bytes_h "$(size_of "$out")")"
    key="$(publish "$out" "$mid-z13-19")"
    add_report "$mid" "$mname" "$bbox" 13 19 "$out" "$key"
  done
fi

# ----------------------------------------------------------------- 3. report
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/).filter(Boolean);
  const sources = lines.map((l) => JSON.parse(l));
  const report = {
    generated_at: new Date().toISOString(),
    date_stamp: process.argv[3],
    sources,
  };
  fs.writeFileSync(process.argv[2], JSON.stringify(report, null, 2));
  console.log("\n=== Build report ===");
  console.log("  " + process.argv[2]);
  for (const e of sources) {
    const sz = e.bytes >= 1024 ** 3
      ? (e.bytes / 1024 ** 3).toFixed(2) + " GB"
      : (e.bytes / 1024 ** 2).toFixed(1) + " MB";
    console.log(`  ${e.name.padEnd(16)} z${e.min_zoom}-${e.max_zoom}  ${sz.padEnd(9)} ${e.key}`);
  }
' "$ReportTmp" "$ReportPath" "$Stamp"

if [[ $SkipUpload -eq 0 ]]; then
  printf '\nNext: run scripts/map/refresh-maps.sh to publish the latest.json manifest.\n'
fi
