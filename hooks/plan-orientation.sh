#!/usr/bin/env bash
# SessionStart hook (startup/resume/compact). Surfaces open durable-plan
# tasks for the active project so a fresh context or a compaction doesn't
# lose track of work in flight. Silent (no output) when there's nothing open.
set -u
_dir="$PWD"
_input="$(cat 2>/dev/null || true)"
if [[ "$_input" =~ \"project_dir\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  _dir="${BASH_REMATCH[1]}"
fi
[ -d "$_dir" ] || exit 0
_helper="$(dirname "${BASH_SOURCE[0]}")/plan-state.sh"
[ -f "$_helper" ] || exit 0
. "$_helper" 2>/dev/null || exit 0
plan_state "$_dir" || exit 0
if [ "${PLAN_OK:-0}" = "1" ] && [ "${PLAN_OPEN_PLANS:-0}" -gt 0 ]; then
  echo "Open durable plan(s) in this project: ${PLAN_OPEN_PLANS} plan(s), ${PLAN_OPEN_TASKS} open task(s) — first: ${PLAN_SLUG} (T${PLAN_DONE}/${PLAN_TOTAL} done)."
  echo "Read docs/plans/${PLAN_SLUG}/plan.md and resume from the first unchecked task — don't re-plan from zero."
fi
exit 0
