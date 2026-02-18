#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_DIR}" ]]; then
  echo "Error: run this inside a git repository." >&2
  exit 1
fi

NOTES_DIR="${REPO_DIR}/lab-notes"
MANIFEST="${REPO_DIR}/manifest.jsonl"
INDEX="${REPO_DIR}/INDEX.md"

# Push behavior: set PUSH=1 to push after commit, otherwise no push.
PUSH="${PUSH:-0}"

# Slug prompt (default: "lab-session")
DEFAULT_SLUG="lab-session"

# ---------- Helpers ----------
escape_json() {
  # Minimal JSON string escaper (quotes/backslashes/newlines/tabs).
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo -n "$s"
}

secret_sanity_check() {
  # Very lightweight checks. Not perfect, but catches common oopsies.
  local hits=0
  local patterns=(
    "AKIA[0-9A-Z]{16}"                 # AWS Access Key ID (common)
    "BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY"
    "xox[baprs]-"                      # Slack tokens
    "ghp_[A-Za-z0-9]{30,}"             # GitHub classic token
    "-----BEGIN PRIVATE KEY-----"
  )

  # Scan staged + unstaged diffs (what would be committed).
  local diff_content
  diff_content="$(git -C "$REPO_DIR" diff)"
  diff_content+=$'\n'
  diff_content+="$(git -C "$REPO_DIR" diff --cached)"

  for pat in "${patterns[@]}"; do
    if echo "$diff_content" | grep -E -n "$pat" >/dev/null 2>&1; then
      echo "⚠️  Possible secret pattern matched: $pat" >&2
      hits=$((hits+1))
    fi
  done

  if [[ $hits -gt 0 ]]; then
    echo "Refusing to proceed until potential secrets are removed/redacted." >&2
    exit 2
  fi
}

update_index() {
  # Keeps INDEX.md small and useful: latest 10 AAR links.
  local title="## Latest AARs"
  local header="# Index"$'\n\n'"${title}"$'\n'
  local tmp="${REPO_DIR}/.index.tmp"

  # Collect latest 10 note files by filename sort (works with YYYY-MM-DD--HHMM--slug).
  local links=""
  mapfile -t files < <(ls -1 "${NOTES_DIR}"/*.md 2>/dev/null | sort -r | head -n 10 || true)
  for f in "${files[@]}"; do
    local base
    base="$(basename "$f")"
    # Link text: remove extension
    local label="${base%.md}"
    links+="- [${label}](${NOTES_DIR##*/}/${base})"$'\n'
  done

  if [[ -z "$links" ]]; then
    links="- (none yet)"$'\n'
  fi

  printf "%s%s\n" "$header" "$links" > "$tmp"
  mv "$tmp" "$INDEX"
}

# ---------- Main ----------
mkdir -p "$NOTES_DIR"
touch "$MANIFEST"

DATE="$(date +%F)"
TIME="$(date +%H%M)"

read -rp "Session slug (kebab-case) [${DEFAULT_SLUG}]: " SLUG
SLUG="${SLUG:-$DEFAULT_SLUG}"
# Normalize spaces to dashes, lower-case-ish (best effort)
SLUG="${SLUG// /-}"
SLUG="$(echo "$SLUG" | tr '[:upper:]' '[:lower:]')"

SESSION_ID="${DATE}--${TIME}--${SLUG}"
AAR_FILE="${NOTES_DIR}/${SESSION_ID}.md"

# Tags + systems are metadata the agent will use later.
read -rp "Tags (comma-separated) [linux,security]: " TAGS
TAGS="${TAGS:-linux,security}"
read -rp "Systems (comma-separated) [ubuntu,local]: " SYSTEMS
SYSTEMS="${SYSTEMS:-ubuntu,local}"

# Create AAR if new
if [[ ! -f "$AAR_FILE" ]]; then
cat > "$AAR_FILE" <<EOF
---
id: ${SESSION_ID}
type: aar
date: ${DATE}
start: ${TIME:0:2}:${TIME:2:2}
tags: [$(echo "$TAGS" | sed 's/, */, /g')]
systems: [$(echo "$SYSTEMS" | sed 's/, */, /g')]
status: draft
related:
  runbooks: []
  artifacts: []
---

# After Action Report — ${SESSION_ID}

## Summary
-

## What I Worked On
-

## Troubleshooting Log
- **Symptom:**
- **Hypothesis:**
- **Test:**
- **Result:**
- **Fix:**

## Commands / Evidence
\`\`\`bash
# paste key commands here
\`\`\`

## Security Notes
-

## Next Actions
- [ ]
EOF
fi

# Open for editing (approval prep)
"${EDITOR:-nano}" "$AAR_FILE"

# Update index (optional but handy for humans + agents)
update_index

# Stage changes (but keep status as draft until approval)
git -C "$REPO_DIR" add "$AAR_FILE" "$INDEX" >/dev/null 2>&1 || true

echo "---- git status ----"
git -C "$REPO_DIR" status --porcelain

echo "---- git diff (staged + unstaged) ----"
git -C "$REPO_DIR" diff
echo
git -C "$REPO_DIR" diff --cached

# Ask approval
read -rp "Publish this session? This will set status=published and commit. (yes/no) " yn
if [[ "$yn" != "yes" ]]; then
  echo "Leaving as draft (no commit)."
  exit 0
fi

# Flip status draft -> published
# (simple replace of first occurrence)
perl -0777 -i -pe 's/status:\s*draft/status: published/' "$AAR_FILE"

git -C "$REPO_DIR" add "$AAR_FILE" "$INDEX"

# Generate a manifest entry (append-only)
# NOTE: commit hash added after commit; we’ll append placeholder now, then add the real hash in a second line.
files_json="[\"lab-notes/$(basename "$AAR_FILE")\",\"INDEX.md\"]"
tags_json="$(echo "$TAGS" | awk -F',' '{for (i=1;i<=NF;i++){gsub(/^ +| +$/,"",$i); printf "\"%s\"%s",$i,(i<NF?",":"")}}')"
systems_json="$(echo "$SYSTEMS" | awk -F',' '{for (i=1;i<=NF;i++){gsub(/^ +| +$/,"",$i); printf "\"%s\"%s",$i,(i<NF?",":"")}}')"

line="{\"session\":\"$(escape_json "$SESSION_ID")\",\"date\":\"$DATE\",\"type\":\"aar\",\"tags\":[${tags_json}],\"systems\":[${systems_json}],\"files\":${files_json},\"status\":\"published\",\"commit\":\"PENDING\"}"
echo "$line" >> "$MANIFEST"
git -C "$REPO_DIR" add "$MANIFEST"

# Final safety check before commit
secret_sanity_check

# Commit message with trailers
SUBJECT="docs(aar): ${SLUG//-/ }"
FILES_TRAILER="lab-notes/$(basename "$AAR_FILE"),INDEX.md"

git -C "$REPO_DIR" commit -m "$SUBJECT" \
  -m "Session: ${SESSION_ID}" \
  -m "Type: aar" \
  -m "Tags: ${TAGS}" \
  -m "Status: published" \
  -m "Files: ${FILES_TRAILER}"

COMMIT_HASH="$(git -C "$REPO_DIR" rev-parse HEAD)"

# Append a second manifest line with the real commit hash (keeps append-only integrity)
line2="{\"session\":\"$(escape_json "$SESSION_ID")\",\"date\":\"$DATE\",\"type\":\"aar\",\"tags\":[${tags_json}],\"systems\":[${systems_json}],\"files\":${files_json},\"status\":\"published\",\"commit\":\"${COMMIT_HASH}\"}"
echo "$line2" >> "$MANIFEST"
git -C "$REPO_DIR" add "$MANIFEST"
git -C "$REPO_DIR" commit -m "chore(manifest): finalize commit hash for ${SESSION_ID}"

echo "✅ Published session ${SESSION_ID}"
echo "Commit: ${COMMIT_HASH}"

if [[ "$PUSH" == "1" ]]; then
  git -C "$REPO_DIR" push
  echo "🚀 Pushed to origin."
else
  echo "ℹ️  Not pushed. To push: git push"
  echo "   Or run with: PUSH=1 tools/session-closeout.sh"
fi
