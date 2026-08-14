#!/usr/bin/env bash
# Source-only helper (not executable on its own). Scans docs/plans/*/plan.md
# for open/done task counts, matching the `durable-plan` skill's checklist
# format (`- [ ] T1: ...` / `- [x] T1: ...`).
plan_state() {
  PLAN_OK=1 PLAN_OPEN_PLANS=0 PLAN_OPEN_TASKS=0
  PLAN_SLUG="" PLAN_DONE=0 PLAN_TOTAL=0
  local _root="$1" _f _line _open _done
  local _files=("$_root"/docs/plans/*/plan.md)
  [ -e "${_files[0]}" ] || return 0
  if [ "${#_files[@]}" -gt 50 ]; then PLAN_OK=0; return 0; fi
  for _f in "${_files[@]}"; do
    _open=0 _done=0
    while IFS= read -r _line || [ -n "$_line" ]; do
      if [[ "$_line" =~ ^[[:space:]]*-\ \[\ \]\ T[0-9]+: ]]; then
        _open=$((_open + 1))
      elif [[ "$_line" =~ ^[[:space:]]*-\ \[x\]\ T[0-9]+: ]]; then
        _done=$((_done + 1))
      fi
    done < "$_f" 2>/dev/null || { PLAN_OK=0; return 0; }
    if [ "$_open" -gt 0 ]; then
      PLAN_OPEN_PLANS=$((PLAN_OPEN_PLANS + 1))
      PLAN_OPEN_TASKS=$((PLAN_OPEN_TASKS + _open))
      if [ -z "$PLAN_SLUG" ]; then
        PLAN_SLUG="$(basename "$(dirname "$_f")")"
        PLAN_DONE="$_done"
        PLAN_TOTAL=$((_open + _done))
      fi
    fi
  done
  return 0
}
