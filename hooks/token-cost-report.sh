#!/usr/bin/env bash
# Stop hook: report tokens consumed + estimated cost for the task that just finished.
# Model-aware: groups usage by .message.model and applies per-model pricing, so a
# turn that mixes Opus / Sonnet / Haiku is priced correctly. Reports the delta since
# the previous Stop (just this task's turn), not the cumulative session.
#
# Pricing (USD per 1M tokens) — input / output / cache-write(5m, 1.25x) / cache-read(0.1x):
#   Opus 4.8 (incl. 1M context, no premium): 5.00 / 25.00 / 6.25 / 0.50
#   Sonnet 4.6:                              3.00 / 15.00 / 3.75 / 0.30
#   Haiku 4.5:                               1.00 /  5.00 / 1.25 / 0.10
#   Unknown model: falls back to Opus rates and flags the id with "?"
set -uo pipefail

label="${1:-Tarea}"   # "Tarea" for the main thread, "Subagente" for SubagentStop

input="$(cat)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
session="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"

[ -n "$transcript" ] || exit 0
[ -f "$transcript" ] || exit 0

# Current cumulative usage grouped by model → lines: "<model> <in> <out> <cw> <cr>"
cur="$(jq -rs '
  map(select(.message.usage != null)
      | { m: (.message.model // "unknown"),
          i: (.message.usage.input_tokens // 0),
          o: (.message.usage.output_tokens // 0),
          w: (.message.usage.cache_creation_input_tokens // 0),
          r: (.message.usage.cache_read_input_tokens // 0) })
  | group_by(.m)
  | map({ m: .[0].m,
          i: (map(.i) | add), o: (map(.o) | add),
          w: (map(.w) | add), r: (map(.r) | add) })
  | .[] | "\(.m) \(.i) \(.o) \(.w) \(.r)"' "$transcript" 2>/dev/null)"

# Key state by transcript (not just session_id) — main thread and subagents may
# share a session_id but have distinct transcript files; this keeps deltas separate.
tkey="$(printf '%s' "$transcript" | cksum | tr -cd '0-9' | cut -c1-16)"
state="${TMPDIR:-/tmp}/claude-tokens-${session}-${tkey}"
[ -f "$state" ] || : > "$state"

tmp="$(mktemp "${TMPDIR:-/tmp}/claude-tokens-cur.XXXXXX")"
printf '%s\n' "$cur" > "$tmp"

result="$(awk -v sf="$state" '
  FILENAME==sf { if (NF>=5) { pin[$1]=$2; pout[$1]=$3; pcw[$1]=$4; pcr[$1]=$5 } next }
  NF<5 { next }
  {
    m=$1
    din=$2-pin[m]; dout=$3-pout[m]; dcw=$4-pcw[m]; dcr=$5-pcr[m]
    if(din<0)din=0; if(dout<0)dout=0; if(dcw<0)dcw=0; if(dcr<0)dcr=0
    if (m ~ /opus/)        { ri=5; ro=25; rw=6.25; rr=0.50; lbl="opus" }
    else if (m ~ /sonnet/) { ri=3; ro=15; rw=3.75; rr=0.30; lbl="sonnet" }
    else if (m ~ /haiku/)  { ri=1; ro=5;  rw=1.25; rr=0.10; lbl="haiku" }
    else                   { ri=5; ro=25; rw=6.25; rr=0.50; lbl=m"?" }
    c=(din*ri + dout*ro + dcw*rw + dcr*rr)/1000000
    tok=din+dout+dcw+dcr
    if (tok>0) { totcost+=c; tottok+=tok; parts[++n]=sprintf("%s %d ($%.4f)", lbl, tok, c) }
  }
  END {
    if (tottok==0) exit 0
    br=""
    for (i=1;i<=n;i++) br=br (i>1 ? " · " : "") parts[i]
    printf "%.4f\t%d\t%s\n", totcost, tottok, br
  }
' "$state" "$tmp")"

mv -f "$tmp" "$state"

[ -n "$result" ] || exit 0

cost="$(printf '%s' "$result" | cut -f1)"
tok="$(printf '%s' "$result" | cut -f2)"
brk="$(printf '%s' "$result" | cut -f3)"

msg="$(printf '📊 %s: $%s USD · %s tokens — %s' "$label" "$cost" "$tok" "$brk")"
jq -n --arg m "$msg" '{systemMessage: $m}'
