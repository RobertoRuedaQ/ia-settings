#!/usr/bin/env bash
# Stop/SubagentStop hook: mechanically captures ```learning fenced blocks
# from the assistant's final message into <project>/docs/learnings/LEARNINGS.md.
# This extracts a marker already present in the hook's own JSON payload
# (`.last_assistant_message`) — it doesn't ask the model to decide anything
# new at write time, and it doesn't need to parse transcript_path at all,
# unlike token-cost-report.sh. Confirmed via Claude Code hooks docs
# (docs/plans/aws-ai-engineer-env/spec.md, Open questions) that `.cwd` is a
# common field present on every hook event, including Stop/SubagentStop —
# no git-rev-parse fallback needed, but one is kept for safety.
#
# Marker grammar (fixed — see spec.md sección B for the design rationale):
#   ```learning
#   type: gotcha|pattern
#   title: <one line>
#   body: <free text, no nested ``` fences — use single backticks or
#          indentation for any code shown>
#   ```
# Multiple blocks in one message each become a separate entry. No
# deduplication across events — a duplicate between Stop and a SubagentStop
# in the same turn is an accepted limitation, not a bug.
set -uo pipefail

label="${1:-Tarea}"   # "Tarea" for Stop, "Subagente" for SubagentStop

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
session="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"

if [ -z "$cwd" ]; then
  cwd="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
fi
[ -n "$msg" ] || exit 0

learnings_dir="$cwd/docs/learnings"
learnings_file="$learnings_dir/LEARNINGS.md"
date_str="$(date +%Y-%m-%d)"
count=0

in_block=0
in_body=0
type="" title="" body=""

flush_block() {
  [ -n "$title" ] || title="(sin título)"
  [ -n "$type" ] || type="gotcha"
  mkdir -p "$learnings_dir"
  if [ ! -f "$learnings_file" ]; then
    printf '# Learnings\n\nAppend-only log captured automatically by `learnings-capture.sh` from fenced `learning` blocks in the assistant response. See docs/plans/aws-ai-engineer-env/spec.md for the marker grammar.\n' > "$learnings_file"
  fi
  {
    printf '\n## %s — %s (%s)\n\n' "$date_str" "$title" "$type"
    printf '%s\n\n' "$body"
    printf '_session: %s · %s_\n' "$session" "$label"
  } >> "$learnings_file"
  count=$((count + 1))
}

while IFS= read -r line || [ -n "$line" ]; do
  if [ "$in_block" = 0 ]; then
    if [[ "$line" =~ ^\`\`\`learning[[:space:]]*$ ]]; then
      in_block=1; in_body=0; type=""; title=""; body=""
    fi
    continue
  fi

  if [[ "$line" =~ ^\`\`\`[[:space:]]*$ ]]; then
    flush_block
    in_block=0; in_body=0
    continue
  fi

  if [ "$in_body" = 1 ]; then
    body="${body:+$body$'\n'}$line"
    continue
  fi

  if [[ "$line" =~ ^type:[[:space:]]*(.*)$ ]]; then
    type="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "$line" =~ ^title:[[:space:]]*(.*)$ ]]; then
    title="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "$line" =~ ^body:[[:space:]]*(.*)$ ]]; then
    in_body=1
    body="${BASH_REMATCH[1]}"
    continue
  fi
  # unrecognized line before "body:" — ignore
done <<< "$msg"

if [ "$count" -gt 0 ]; then
  jq -n --arg m "📝 $count aprendizaje(s) capturado(s) en docs/learnings/LEARNINGS.md" '{systemMessage: $m}'
fi
