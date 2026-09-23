#!/usr/bin/env bash
# sync_analysis.sh — refresh SITE/analysis/ from the canonical analysis folder.
#
#   tools/sync_analysis.sh            # copy
#   tools/sync_analysis.sh --dry-run  # show what would change
#
# Copies R/, notes/, outputs/, CONVENTIONS.md, and data_raw/ files that are already tracked
# in git plus new ones under 20 MB. Never copies WORKLOG.md or 00_START_HERE.md (internal
# team information) or data_raw/_hourprofile_parts/. Nothing is deleted on the site side.
set -euo pipefail
SITE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${RESTROOM_SRC:-$HOME/Desktop/MBA/PMBA6093 Analytics for Managers/Final Project/Restroom_Rebuild}"
DST="$SITE/analysis"
DRY=""; [[ "${1:-}" == "--dry-run" ]] && DRY="--dry-run"
[[ -d "$SRC/R" ]] || { echo "source not found: $SRC" >&2; exit 1; }

EXC=(--exclude 'WORKLOG.md' --exclude '00_START_HERE.md' --exclude '.DS_Store' --exclude '_hourprofile_parts/')
rsync -a $DRY -i "${EXC[@]}" "$SRC/R/"       "$DST/R/"
rsync -a $DRY -i "${EXC[@]}" "$SRC/notes/"   "$DST/notes/"
rsync -a $DRY -i "${EXC[@]}" "$SRC/outputs/" "$DST/outputs/"
rsync -a $DRY -i "$SRC/CONVENTIONS.md" "$DST/CONVENTIONS.md"

# data_raw: files already tracked in git (any size) + new top-level files under 20 MB
LIST="$(mktemp)"; trap 'rm -f "$LIST"' EXIT
( cd "$SITE" && git ls-files analysis/data_raw | sed 's|^analysis/data_raw/||' ) > "$LIST"
( cd "$SRC/data_raw" && find . -maxdepth 1 -type f ! -name '.DS_Store' -size -20M | sed 's|^\./||' ) >> "$LIST"
sort -u "$LIST" -o "$LIST"
# keep only names that exist in the source
FILT="$(mktemp)"; while IFS= read -r f; do [[ -f "$SRC/data_raw/$f" ]] && echo "$f"; done < "$LIST" > "$FILT"
rsync -a $DRY -i --files-from="$FILT" "$SRC/data_raw/" "$DST/data_raw/"
rm -f "$FILT"
echo "sync done${DRY:+ (dry run)}: $SRC -> $DST"
