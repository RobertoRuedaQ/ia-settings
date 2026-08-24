#!/usr/bin/env bash
# PreToolUse/Bash hook that blocks git commit/add/push invocations carrying
# a secret-shaped literal or a sensitive filename, PLUS a standalone scan
# mode reused by the `project-security-bootstrap` skill so the pattern set
# lives in exactly one place. See docs/plans/security-data-privacy-baseline/
# spec.md for the full design rationale — in particular:
#   - "Pending-change scanning": why this does NOT just diff `--cached`.
#     `git commit -a`/`-am` stages during the commit itself, and a chained
#     `git add x && git commit -y` runs entirely *after* this hook fires —
#     both leave `--cached` empty at scan time. `git diff HEAD` (staged +
#     unstaged vs HEAD) covers the `-a`/`-am` case; explicit `git add`
#     targets are resolved and their on-disk content scanned separately
#     because they aren't staged yet when the hook runs.
#   - "Push scanning": why this scans `git log --branches --not --remotes`
#     instead of guessing `@{u}`/`origin/main` — that guess can pick the
#     wrong range (explicit differing refspec) or miss everything on a
#     brand-new repo's first push. This degenerates correctly to "all local
#     commits" when no remote-tracking refs exist yet.
# This is a heuristic, not a parser: command-shape matching is regex-based
# and can over-trigger (e.g. `git commit-tree`) — harmless, it just causes
# an extra scan. It does NOT see through shell indirection (`$GIT commit`,
# an eval'd string) or any write path outside the Bash tool (e.g. an MCP
# call) — named as accepted risk in spec.md, not solved here.
set -uo pipefail

# ---- shared pattern set — single source of truth for both modes ----
PATTERNS=(
  'AKIA[0-9A-Z]{16}'                                             # AWS access key
  'gh[pousr]_[A-Za-z0-9]{36,}'                                    # GitHub token
  'xox[baprs]-[0-9A-Za-z-]{10,}'                                  # Slack token
  'sk_(live|test)_[0-9A-Za-z]{16,}'                               # Stripe key
  '\-\-\-\-\-BEGIN [A-Z ]*PRIVATE KEY\-\-\-\-\-'                  # PEM private key header
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' # JWT-shaped
)
# Generic catch-all: only these two (double- and single-quoted) — kept
# separate from PATTERNS because it's the only reference-suppression-
# eligible one (see scan_text). Provider-specific PATTERNS above always
# fire regardless of surrounding context.
GENERIC_DQ='(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*"[^"]{12,}"'
GENERIC_SQ="(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*'[^']{12,}'"

# Filename patterns that are sensitive on their own, independent of content
# (also the .gitignore baseline list — kept in sync with spec.md's
# Constraints section by hand; both list the same set intentionally).
SENSITIVE_NAME_GLOBS=(
  '.env' '.env.*' '*.key' '*.pem' '*credentials*' '*.tfstate'
  '.aws/credentials*' '*.p12' '*service-account*.json'
)

is_sensitive_name() {
  local f="$1" base pat
  base="$(basename -- "$f")"
  for pat in "${SENSITIVE_NAME_GLOBS[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$f" == $pat || "$base" == $pat ]]; then
      return 0
    fi
  done
  return 1
}

# scan_text <label> <text> — prints one finding line per hit to stdout,
# returns 1 if anything was found, 0 if clean. Caller decides where the
# output goes (stderr+exit2 for the hook path, stdout for standalone).
scan_text() {
  local label="$1" text="$2" pat line val found=0
  [[ -z "$text" ]] && return 0

  for pat in "${PATTERNS[@]}"; do
    if printf '%s\n' "$text" | grep -qE -- "$pat"; then
      line="$(printf '%s\n' "$text" | grep -nE -- "$pat" | grep -v 'secret-scan:allow' | head -1)"
      if [[ -n "$line" ]]; then
        printf 'secret-shaped literal (pattern: %s) in %s — %s\n' "$pat" "$label" "$line"
        found=1
      fi
    fi
  done

  while IFS= read -r line; do
    [[ "$line" == *"secret-scan:allow"* ]] && continue
    if printf '%s' "$line" | grep -qE -- "$GENERIC_DQ"; then
      val="$(printf '%s' "$line" | grep -oE '"[^"]{12,}"' | tail -1 | tr -d '"')"
      if ! [[ "$val" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        printf 'secret-shaped assignment in %s — %s\n' "$label" "$line"
        found=1
      fi
    fi
    if printf '%s' "$line" | grep -qE -- "$GENERIC_SQ"; then
      val="$(printf '%s' "$line" | grep -oE "'[^']{12,}'" | tail -1 | tr -d "'")"
      if ! [[ "$val" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        printf 'secret-shaped assignment in %s — %s\n' "$label" "$line"
        found=1
      fi
    fi
  done <<< "$text"

  [[ "$found" -eq 0 ]]
}

# ============================== standalone mode ==============================
# Used by skills/project-security-bootstrap to scan a project's current
# state without blocking anything. Never exits non-zero on findings.
if [[ "${1:-}" == "--scan-path" ]]; then
  dir="${2:-.}"
  any=0

  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    files="$(git -C "$dir" ls-files --cached --others --exclude-standard)"
  else
    files="$(cd "$dir" 2>/dev/null && find . -type f -not -path '*/.git/*')"
  fi

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if is_sensitive_name "$f"; then
      printf 'FINDING (filename): %s\n' "$f"
      any=1
    fi
    if [[ -f "$dir/$f" ]] && file -b --mime-encoding "$dir/$f" 2>/dev/null | grep -qv binary; then
      hits="$(scan_text "$f" "$(cat "$dir/$f" 2>/dev/null)")" || { printf '%s\n' "$hits"; any=1; }
    fi
  done <<< "$files"

  if [[ "$any" -eq 0 ]]; then
    printf 'CLEAN: no secret-shaped literals or sensitive filenames found under %s\n' "$dir"
  fi
  exit 0
fi

# ================================ hook mode ==================================
input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ -n "$cwd" ]] || cwd="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
[[ -n "$cmd" ]] || exit 0

# The harness's `.cwd` is the SESSION's base directory — it does NOT
# reflect a `cd` inside this command, since nothing in the command has
# executed yet at hook-fire time. An agent-issued `cd /project && git
# commit ...` is extremely common, so resolve a literal (non-variable)
# leading `cd <path>` ourselves. Deliberately does NOT eval/execute any
# part of the command to resolve a variable-based `cd "$VAR"` — that would
# mean running untrusted shell as a side effect of a security check.
# Confirmed necessary by a live test (see test-log.md T3, test6b): a
# `cd "<literal path>"` in the same call was silently ignored before this
# fix, scanning the wrong repository entirely.
norm_cmd="$(printf '%s' "$cmd" | sed -E 's/&&|;/\n/g')"
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//')"
  if [[ "$seg" =~ ^cd[[:space:]]+([^[:space:]]+) ]]; then
    tgt="${BASH_REMATCH[1]}"
    tgt="${tgt%\"}"; tgt="${tgt#\"}"; tgt="${tgt%\'}"; tgt="${tgt#\'}"
    if [[ "$tgt" != *'$'* ]]; then
      if [[ "$tgt" == /* && -d "$tgt" ]]; then
        cwd="$tgt"
      elif [[ -d "$cwd/$tgt" ]]; then
        cwd="$cwd/$tgt"
      fi
    fi
    break
  fi
done <<< "$norm_cmd"

# Only act on commands shaped like a git commit/add/push. Heuristic, not a
# parser — see header comment. Zero-or-more short flag groups after `git`,
# then the subcommand.
SHAPE_RE='git([[:space:]]+-[A-Za-z0-9_-]+([[:space:]]+[^[:space:]&;|]+)?)*[[:space:]]+(commit|add|push)([[:space:]]|$)'
[[ "$cmd" =~ $SHAPE_RE ]] || exit 0

# --- assemble the pending change set ---
diff_text="$(git -C "$cwd" diff HEAD -- . 2>/dev/null || true)"
diff_names="$(git -C "$cwd" diff HEAD --name-only -- . 2>/dev/null || true)"

add_content=""
add_names=""
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+add[[:space:]]+(-A|--all|\.)([[:space:]]|$)'; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    add_names+="$f"$'\n'
    [[ -f "$cwd/$f" ]] && add_content+="$(cat "$cwd/$f" 2>/dev/null)"$'\n'
  done < <(git -C "$cwd" status --porcelain 2>/dev/null | awk '{print $2}')
elif printf '%s' "$cmd" | grep -qE 'git[[:space:]]+add[[:space:]]'; then
  seg="$(printf '%s' "$cmd" | grep -oE 'git[[:space:]]+add[[:space:]]+[^&;|]+' | head -1)"
  seg="${seg#*add }"
  for tok in $seg; do
    [[ "$tok" == -* ]] && continue
    add_names+="$tok"$'\n'
    [[ -f "$cwd/$tok" ]] && add_content+="$(cat "$cwd/$tok" 2>/dev/null)"$'\n'
  done
fi

push_text=""
push_names=""
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push'; then
  push_text="$(git -C "$cwd" log --branches --not --remotes -p 2>/dev/null || true)"
  push_names="$(git -C "$cwd" log --branches --not --remotes --name-only --pretty=format: 2>/dev/null || true)"
fi

all_names="$diff_names"$'\n'"$add_names"$'\n'"$push_names"
# The raw command string itself is a required scan target, not optional:
# when a chained invocation *creates* the file in the same Bash call
# (`printf '...secret...' > f.py && git add f.py && git commit ...`, a
# heredoc, `echo ... >> f`), nothing has executed yet at hook-fire time —
# disk-based checks above see an empty/nonexistent file. Any literal being
# written this way has to appear in the command string itself, so scanning
# `cmd` directly is what actually catches it. Confirmed necessary by a live
# test where the disk-based checks alone missed it (see test-log.md T3).
all_text="$diff_text"$'\n'"$add_content"$'\n'"$push_text"$'\n'"$cmd"

# --- filename check first (cheap, and catches content-free binary secrets) ---
while IFS= read -r fname; do
  [[ -z "$fname" ]] && continue
  if is_sensitive_name "$fname"; then
    printf 'BLOCKED by secret-scan.sh: sensitive filename about to be committed/pushed: %s\nIf this is a false positive, rename is not required — add "# secret-scan:allow" is NOT supported for filenames; ask the user before proceeding.\n' "$fname" >&2
    exit 2
  fi
done <<< "$all_names"

# --- content check ---
if ! findings="$(scan_text "pending change" "$all_text")"; then
  printf 'BLOCKED by secret-scan.sh — secret-shaped content in what this command would commit/push:\n%s\nIf this is a known-harmless collision (e.g. a documentation example key), add a trailing "# secret-scan:allow" comment on that line and re-run.\n' "$findings" >&2
  exit 2
fi

exit 0
