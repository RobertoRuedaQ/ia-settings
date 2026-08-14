#!/usr/bin/env bash
# statusLine command. Renders: model  [bar] NN% ctx  repo · mid-plan (...).
# Falls back gracefully — an unreadable/absent project or plan state degrades
# to the plain context line, never an error.
set -u
_input="$(cat 2>/dev/null || true)"

_pct=""
if [[ "$_input" =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  _pct="${BASH_REMATCH[1]}"
fi
[ -n "$_pct" ] || { printf 'ctx —\n'; exit 0; }

_dir=""
if [[ "$_input" =~ \"project_dir\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  _dir="${BASH_REMATCH[1]}"
fi

_norm="$_pct"
while [ "${#_norm}" -gt 1 ] && [ "${_norm:0:1}" = "0" ]; do _norm="${_norm:1}"; done
if [ "${#_norm}" -gt 3 ]; then
  _filled=10
else
  _filled=$(( 10#${_norm} / 10 ))
  [ "$_filled" -gt 10 ] && _filled=10
fi
_bar=""
_i=0
while [ "$_i" -lt "$_filled" ]; do _bar="${_bar}#"; _i=$((_i + 1)); done
_i=0
while [ "$_i" -lt $((10 - _filled)) ]; do _bar="${_bar}-"; _i=$((_i + 1)); done

_charset_re='^[A-Za-z0-9 ._()/-]+$'

_model=""
if [[ "$_input" =~ \"display_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  _model="${BASH_REMATCH[1]}"
fi
if [ -z "$_model" ] || [ "${#_model}" -gt 40 ] || ! [[ "$_model" =~ $_charset_re ]]; then
  _model=""
fi

_pick_repo() {
  local p="$1" t
  [ -n "$p" ] || return 1
  t="$p"
  while [ "${#t}" -gt 1 ] && [ "${t: -1}" = "/" ]; do t="${t%/}"; done
  t="${t##*/}"
  if [ -n "$t" ] && [ "${#t}" -le 64 ] && [[ "$t" =~ $_charset_re ]]; then
    printf '%s' "$t"
    return 0
  fi
  return 1
}
_cur=""
if [[ "$_input" =~ \"current_dir\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  _cur="${BASH_REMATCH[1]}"
fi
_repo="$(_pick_repo "$_cur" 2>/dev/null)" || _repo="$(_pick_repo "$_dir" 2>/dev/null)" || _repo=""

_head=""
[ -n "$_model" ] && _head="${_model}  "
_head="${_head}[${_bar}] ${_norm}% ctx"
[ -n "$_repo" ] && _head="${_head}  ${_repo}"

_seg=""
if [ -n "$_dir" ] && [ -d "$_dir" ]; then
  _helper="$(dirname "${BASH_SOURCE[0]}")/plan-state.sh"
  if [ -f "$_helper" ] && . "$_helper" 2>/dev/null; then
    plan_state "$_dir" || true
    if [ "${PLAN_OK:-0}" = "1" ] && [ "${PLAN_OPEN_PLANS:-0}" -gt 0 ]; then
      if [ "$PLAN_OPEN_PLANS" = "1" ]; then
        _seg=" · mid-plan (${PLAN_SLUG} T${PLAN_DONE}/${PLAN_TOTAL})"
      else
        _seg=" · mid-plan (${PLAN_OPEN_PLANS} plans · ${PLAN_OPEN_TASKS} open)"
      fi
    elif [ "${PLAN_OK:-0}" = "1" ] && [ "$_pct" -ge 60 ]; then
      _seg=" · compact-safe"
    fi
  fi
fi

printf '%s\n' "${_head}${_seg}"
exit 0
