#!/usr/bin/env bash
# downtify-catchup.sh — extract YouTube URLs from downtify logs that are NOT
# already in the original yt-dlp batch, and download them with the same settings.
#
# Usage: ./downtify-catchup.sh
#
# Prerequisites:
#   - downtify Docker container running
#   - bgutil-provider Docker container running (PO token server on :4416)
#   - yt-dlp installed and configured (~/.config/yt-dlp/config)
#   - /tmp/downtify_urls_clean.txt (original batch URLs)
#   - /tmp/downtify_archive.txt (yt-dlp download archive)

set -euo pipefail

ORIGINAL_URLS="/tmp/downtify_urls_clean.txt"
ARCHIVE="/tmp/downtify_archive.txt"
NEW_URLS="/tmp/downtify_catchup_urls.txt"
TEMP_DIR="/tmp/downtify_catchup"

mkdir -p "$TEMP_DIR"

# ---------------------------------------------------------------------------
# Step 1: Extract all current YouTube video IDs from downtify logs
# ---------------------------------------------------------------------------
echo "[1/4] Extracting YouTube video IDs from downtify logs..."

docker logs downtify 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' \
  | grep 'picked videoId=' \
  | grep -oP 'videoId=\K[^\s]+' \
  | sort -u \
  > "$TEMP_DIR/all_video_ids.txt"

TOTAL_ALL=$(wc -l < "$TEMP_DIR/all_video_ids.txt")
echo "       Found $TOTAL_ALL unique video IDs"

# ---------------------------------------------------------------------------
# Step 2: Convert video IDs to YouTube Music URLs
# ---------------------------------------------------------------------------
echo "[2/4] Converting to YouTube Music URLs..."

while IFS= read -r vid; do
  echo "https://music.youtube.com/watch?v=${vid}"
done < "$TEMP_DIR/all_video_ids.txt" \
  | sort -u \
  > "$TEMP_DIR/all_urls.txt"

# ---------------------------------------------------------------------------
# Step 3: Exclude URLs from the original batch
# ---------------------------------------------------------------------------
echo "[3/4] Excluding URLs already in original batch..."

# Exclude URLs in the original run
comm -23 <(sort "$TEMP_DIR/all_urls.txt") <(sort "$ORIGINAL_URLS") \
  > "$TEMP_DIR/new_vs_original.txt"

AFTER_ORIGINAL=$(wc -l < "$TEMP_DIR/new_vs_original.txt")
echo "       After original: ${AFTER_ORIGINAL} new URLs"

# Also exclude URLs already downloaded by yt-dlp (from archive)
if [ -f "$ARCHIVE" ] && [ -s "$ARCHIVE" ]; then
  # Extract video IDs from archive and build URLs
  awk '{print "https://music.youtube.com/watch?v="$1}' "$ARCHIVE" \
    | sort -u \
    > "$TEMP_DIR/archive_urls.txt"

  comm -23 <(sort "$TEMP_DIR/new_vs_original.txt") <(sort "$TEMP_DIR/archive_urls.txt") \
    > "$NEW_URLS"

  AFTER_ARCHIVE=$(wc -l < "$NEW_URLS")
  echo "       After archive:  ${AFTER_ARCHIVE} new URLs"
else
  cp "$TEMP_DIR/new_vs_original.txt" "$NEW_URLS"
  echo "       No archive file — skipping archive filter"
fi

FINAL_COUNT=$(wc -l < "$NEW_URLS")

# ---------------------------------------------------------------------------
# Step 4: Run yt-dlp on the remaining URLs
# ---------------------------------------------------------------------------
echo "[4/4] Downloading ${FINAL_COUNT} new URLs with yt-dlp..."

if [ "$FINAL_COUNT" -eq 0 ]; then
  echo "       Nothing new to download. Done."
  rm -rf "$TEMP_DIR"
  exit 0
fi

# Show what we're about to download
echo "       First 5:"
head -5 "$NEW_URLS" | sed 's/^/         /'
echo "       ..."
echo ""

# Run yt-dlp with the same settings as config (archive for resume)
yt-dlp \
  --download-archive "$ARCHIVE" \
  -a "$NEW_URLS" \
  2>&1 | tee "/tmp/downtify_catchup_log.txt"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$TEMP_DIR"
echo ""
echo "Done. Log: /tmp/downtify_catchup_log.txt"
echo "Archive: $ARCHIVE"
