#!/usr/bin/env bash
# POLARIS v6 — Claude Code PreToolUse guard: the primary checkout is not yours to switch.
#
# WHY THIS EXISTS
#   N sessions share ONE primary checkout. Every one of them can today run `git switch`, `git
#   reset` or `git stash` in it and move the ground under the other four — that is exactly how one
#   PR silently carried another session's commits (2026-08-23, plan enforced-isolation). The task
#   worktrees at .polaris/wt/<ID> exist so nobody has to: a Builder's whole life happens there.
#   This hook makes that the enforced default instead of a convention nobody can see.
#
# THE CONTRACT — deny is narrow, silence is the default
#   We DENY exactly one thing: a checkout-mutating git invocation issued from the PRIMARY
#   worktree. Read-only git, every non-git command, and ALL of these same commands inside
#   .polaris/wt/<ID> produce NO OUTPUT AT ALL and the normal permission flow runs untouched.
#   Because a deny costs real work, the parser errs the other way from readonly-allow.sh's: any
#   token it cannot read confidently as a command-position `git` is left alone. `echo "git switch
#   main"` is allowed on purpose. This is a tripwire, not the authority — `polaris verify` and
#   `polaris handoff` remain that, and they see the diff rather than the command line.
#
#   It is NOT wired into ops/hooks/readonly-allow.sh, and must never be: that hook's safety
#   contract is that it only ever ALLOWS, so its worst bug costs a prompt that would have happened
#   anyway. Deny lives in its own file. The two never disagree — readonly-allow's git_ok
#   whitelists read verbs only, and every verb denied here falls through its final `*) return 1`
#   and produces nothing. (`git stash list`/`show` ARE read-only, so they are excluded below.)
#
# SPEED
#   This runs before EVERY Bash call, so it forks NOTHING on the common path — no interpreter, no
#   `ops/polaris` (~2.2s of startup), no git. The three gates are ordered by cost: a substring test
#   for `git` at all, a substring test for a `/.polaris/wt/` segment in cwd (which is by itself
#   proof we are in a task worktree — see wt_path() in ops/lib/core.sh), then the pure-bash parse.
#   ONE `git rev-parse` runs only when a deny is otherwise about to fire. The lesson is
#   ownership-guard's: at 2x its budget that hook was killed and FAILED OPEN, silently dropping
#   its gate. A guard that is slow is a guard that is not there.
#
# TESTING
#   `checkout-guard.sh --test '<cwd>|<command>'` prints `deny:<subcommand>` or `allow` and skips
#   the JSON layer, mirroring readonly-allow.sh --test. Goldens ride on that (drill checkoutguard).
set -u

HIT=''                    # set by mutating_git: the git subcommand that fired (--test only)
# Pinned by ops/contracts/shared-checkout.md § v2.1 — ONE LINE, byte-exact, greppable.
MSG="the primary checkout is shared by every session — never switch it: work in your task's worktree (bash ops/polaris claim, then cd .polaris/wt/<ID>); a dirty tree is parked (bash ops/polaris park), never switched around"
TESTMODE=0

# ---------------------------------------------------------------- the refusal
# Emits the PreToolUse decision on stdout and never returns. $1 = the git subcommand that fired,
# used only by --test so a golden can say WHICH rule caught a line.
deny() {
  if [ "$TESTMODE" = 1 ]; then printf 'deny:%s\n' "$1"; exit 0; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$MSG"
  exit 0
}

# ---------------------------------------------------------------- JSON string read
# Extract a complete JSON string value for "$1" from "$2" into REPLY.
# Returns 1 on ANY irregularity — a missing key, an escape we do not decode, or a closing quote
# that is not followed by , or } . That last check is what makes a truncated read impossible:
# without it a mis-parse could hand back `grep foo` from `grep foo > /etc/passwd` and allow it.
jstr() {
  local key="$1" s="$2" rest ch out='' i=0 len after
  rest="${s#*\"$key\"}"
  [ "$rest" = "$s" ] && return 1
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [ "${rest:0:1}" = ":" ] || return 1
  rest="${rest:1}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [ "${rest:0:1}" = '"' ] || return 1
  rest="${rest:1}"
  len=${#rest}
  while [ "$i" -lt "$len" ]; do
    ch="${rest:i:1}"
    if [ "$ch" = '\' ]; then
      i=$((i + 1)); ch="${rest:i:1}"
      case "$ch" in
        n)        out="$out
";;
        t)        out="$out	";;
        r)        ;;                      # a bare CR changes nothing we parse
        '"'|'\'|/) out="$out$ch";;
        *)        return 1;;              # \u, \b, \f — refuse to guess
      esac
      i=$((i + 1)); continue
    fi
    if [ "$ch" = '"' ]; then
      after="${rest:i+1}"
      after="${after#"${after%%[![:space:]]*}"}"
      case "${after:0:1}" in
        ','|'}') REPLY="$out"; return 0;;
        *)       return 1;;
      esac
    fi
    out="$out$ch"; i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------- the parse
# rc 0 = "$1" contains a checkout-mutating git invocation; HIT names its subcommand.
# rc 1 = it does not, or we could not read it confidently — and those two are deliberately the
# same answer. A false negative here costs nothing (verify/handoff still see the diff); a false
# positive blocks work that was never wrong. So every doubt resolves to 1.
#
# Whitespace tokenizing only, and a git token counts ONLY at command position: the start of the
# line, or after a separator, carried through `VAR=val`, env/time/nice/nohup/command and the
# keywords that can precede a command. A token carrying a quote character is opaque — that is what
# keeps `echo "git switch main"` allowed. `set -f` stops the shell globbing `*.c` against the disk
# while we split.
mutating_git() {
  local cmd="$1" tok sub nxt cmdpos=1 wasglob=0
  HIT=''
  case "$-" in *f*) wasglob=1;; esac
  set -f
  local IFS=$' \t\n'
  set -- $cmd
  [ "$wasglob" = 1 ] || set +f
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    # a quoted stretch is data, not a command line — never read a git out of it
    case "$tok" in *\"*|*\'*) cmdpos=0; continue;; esac
    # `a;git …`, `&&`, `|`: what follows the LAST separator inside the token is a fresh command
    case "$tok" in
      *[\;\|\&]*) cmdpos=1; tok="${tok##*[;|&]}"; [ -n "$tok" ] || continue;;
    esac
    if [ "$cmdpos" = 1 ]; then
      case "$tok" in
        git|git.exe|*/git|*/git.exe)
          while [ $# -gt 0 ]; do                       # pre-subcommand options
            case "$1" in
              *[\;\|\&]*) break;;                        # a separator ends this invocation
              -C|-c|--git-dir|--work-tree|--namespace) shift; shift;;
              -*) shift;;
              *) break;;
            esac
          done
          # `git fetch;git rebase x`: the separator rides on the subcommand token. Read the
          # subcommand out of it but DO NOT consume the token — hand it back to the outer loop at
          # command position, which is what makes the second invocation visible at all.
          sub="${1:-}"; nxt=''
          case "$sub" in
            *[\;\|\&]*) cmdpos=1; sub="${sub%%[;|&]*}";;
            *) [ $# -gt 0 ] && shift
               nxt="${1:-}"; nxt="${nxt%%[;|&]*}"      # the subcommand's own first argument
               cmdpos=0;;
          esac
          case "$sub" in
            switch|checkout|reset|merge|rebase|cherry-pick) HIT="$sub"; return 0;;
            # list/show are the two read-only stash forms — the same two readonly-allow.sh allows
            stash)    case "$nxt" in list|show) ;; *) HIT=stash; return 0;; esac;;
            worktree) case "$nxt" in add) HIT=worktree; return 0;; esac;;
            branch)   while [ $# -gt 0 ]; do           # -d/-D/-m/-M anywhere in THIS invocation
                        case "$1" in
                          *[\;\|\&]*) break;;
                          -d|-D|-m|-M) HIT=branch; return 0;;
                        esac
                        shift
                      done;;
          esac
          continue;;
      esac
      case "$tok" in
        env|time|nice|nohup|command|'('|'{'|'!'|then|else|do) continue;;   # still command position
        [A-Za-z_]*=*) continue;;                                          # VAR=val prefix
      esac
    fi
    cmdpos=0
  done
  return 1
}

# ---------------------------------------------------------------- entry
if [ "${1:-}" = "--test" ]; then
  TESTMODE=1
  ARG="${2:-}"
  CWD="${ARG%%|*}"
  CMD="${ARG#*|}"
  [ "$CMD" = "$ARG" ] && CMD=''            # no `|` in the argument: nothing to judge
else
  IN="$(cat)"
  # No tool_name test: the settings.json matcher is `Bash`, and a payload with no
  # tool_input.command is not a command line whatever tool sent it.
  jstr command "${IN#*\"tool_input\"}" || exit 0
  CMD="$REPLY"
  CWD=''
  jstr cwd "$IN" && CWD="$REPLY"
fi

# One-shot block: every `break` is an allow, and the only way out the bottom is a deny.
while : ; do
  [ -n "$CMD" ] || break
  case "$CMD" in *git*) ;; *) break;; esac              # gate 1: no forks, no git, nothing to do
  [ -n "$CWD" ] || CWD="$(pwd)"
  # gate 2: still no forks. A /.polaris/wt/ segment in cwd IS proof of a task worktree — every
  # one of them lives at <primary>/.polaris/wt/<ID> (wt_path(), ops/lib/core.sh), so no probe can
  # tell us anything the path has not already said. Backslashes fold to slashes first, because
  # Claude Code hands us a Windows cwd.
  case "${CWD//\\//}" in */.polaris/wt/*) break;; esac
  mutating_git "$CMD" || break                           # gate 3: no forks — pure-bash parse
  # Only now is a fork worth paying for. In the primary, --git-dir and --git-common-dir are the
  # same directory; in a linked worktree --git-dir is <common>/worktrees/<name>. Unreadable (not a
  # repo, no git, an ancient git) fails CLOSED: a checkout-mutating command we cannot place is
  # refused, because the cost of being wrong runs the other way here.
  GD="$(git -C "$CWD" rev-parse --git-common-dir --git-dir 2>/dev/null)" || GD=''
  if [ -n "$GD" ]; then
    case "$GD" in
      *$'\n'*) [ "${GD%%$'\n'*}" = "${GD#*$'\n'}" ] || break;;   # differ → linked worktree → allow
      *) ;;                                                      # one line only → cannot tell → deny
    esac
  fi
  deny "$HIT"
done

[ "$TESTMODE" = 1 ] && echo allow
exit 0
