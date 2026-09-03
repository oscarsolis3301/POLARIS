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
#   Four more commands destroy another session's work just as completely, so the hook learned them
#   too (v2.5): `git worktree remove|prune|move` (one session deleting another's whole workspace),
#   `git clean` in the shared checkout (which takes the gitignored .polaris/ with it — every
#   worktree, the index, the bg logs), `rm -rf .polaris` in any of its spellings, and process kills
#   that select by NAME (`taskkill /IM`, `pkill`, `killall`, `npx kill-port`) — five sessions share
#   this machine, so a launcher reclaiming a port takes down whoever held it. Deleting an origin
#   `feat/<ID>` by hand joins them: it may still be a live worktree's base.
#
# THE CONTRACT — deny is narrow, silence is the default
#   We DENY a short, named list: a checkout-mutating git invocation issued from the PRIMARY
#   worktree, and the destroyers above. Read-only git, every unrelated command, and the
#   checkout-mutating ones inside .polaris/wt/<ID> produce NO OUTPUT AT ALL and the normal
#   permission flow runs untouched. You may always kill a pid you started, dry-run a clean, push a
#   branch, or delete something that is not .polaris.
#   Because a deny costs real work, the parsers err the other way from readonly-allow.sh's: any
#   token they cannot read confidently at command position is left alone. `echo "git switch
#   main"` is allowed on purpose. This is a tripwire, not the authority — `polaris verify` and
#   `polaris handoff` remain that, and they see the diff rather than the command line.
#   Every class carries its own pinned one-line message and its own --test label, and none of them
#   ships without its lines in ops/tests/checkout-guard-denies.expected.
#
#   It is NOT wired into ops/hooks/readonly-allow.sh, and must never be: that hook's safety
#   contract is that it only ever ALLOWS, so its worst bug costs a prompt that would have happened
#   anyway. Deny lives in its own file. The two never disagree — readonly-allow's git_ok
#   whitelists read verbs only, and every verb denied here falls through its final `*) return 1`
#   and produces nothing. (`git stash list`/`show` ARE read-only, so they are excluded below.)
#
# SPEED
#   This runs before EVERY Bash call, so it forks NOTHING on the common path — no interpreter, no
#   `ops/polaris` (~2.2s of startup), no git. The gates are ordered by cost: one substring test for
#   any of the words our classes need at all, a substring test for a `/.polaris/wt/` segment in cwd
#   (which is by itself proof we are in a task worktree — see wt_path() in ops/lib/core.sh), then
#   the pure-bash parses. Widening gate 1 costs nothing: it is still one `case`, and the extra
#   commands it lets through die in a parse that never forks either. The beat touch in gate 2 is
#   string ops and a `: >` redirect — no new process. ONE `git rev-parse` runs only when a deny is
#   otherwise about to fire, and only for the classes whose verdict depends on WHERE you are. The
#   lesson is ownership-guard's: at 2x its budget that hook was killed and FAILED OPEN, silently
#   dropping its gate. A guard that is slow is a guard that is not there.
#
# TESTING
#   `checkout-guard.sh --test '<cwd>|<command>'` prints `deny:<class>` or `allow` and skips
#   the JSON layer, mirroring readonly-allow.sh --test. Goldens ride on that (drill checkoutguard).
set -u

HIT=''                    # set by the parsers: the class that fired (--test only)
# Pinned by ops/contracts/shared-checkout.md § v2.1 / § v2.5 — ONE LINE each, byte-exact, greppable.
MSG="the primary checkout is shared by every session — never switch it: work in your task's worktree (bash ops/polaris claim, then cd .polaris/wt/<ID>); a dirty tree is parked (bash ops/polaris park), never switched around"
MSG_WT="a task worktree may be another session's whole working state — never remove, prune, move or clean one by hand: bash ops/polaris sweep --fix reaps idle worktrees safely, and done/release archive dirty ones"
MSG_PUSH="a remote feat/<ID> may still be a live worktree's base — never delete origin refs by hand: done and sweep --fix delete landed branches with proof"
MSG_KILL="never kill by name or kill the whole tree — five sessions share this machine and their suites: kill one pid you own (kill <pid> · taskkill /PID <pid> · Stop-Process -Id <pid>)"
TESTMODE=0

# ---------------------------------------------------------------- the refusal
# Emits the PreToolUse decision on stdout and never returns. $1 = the class that fired, used only
# by --test so a golden can say WHICH rule caught a line. $2 = the refusal text: ONE emitter, the
# message a variable, so a new class costs a pinned string and nothing else.
deny() {
  if [ "$TESTMODE" = 1 ]; then printf 'deny:%s\n' "$1"; exit 0; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$2"
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
  local cmd="$1" tok sub nxt cmdpos=1 wasglob=0 dry
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
            # `list` is the read-only worktree form and stays silent; the other three END another
            # session's working state, so they are denied from EVERY checkout (see the entry block).
            worktree) case "$nxt" in
                        add)    HIT=worktree; return 0;;
                        remove) HIT=worktree-remove; return 0;;
                        prune)  HIT=worktree-prune; return 0;;
                        move)   HIT=worktree-move; return 0;;
                      esac;;
            clean)    dry=0                            # -n/--dry-run anywhere in THIS invocation
                      while [ $# -gt 0 ]; do
                        case "$1" in
                          *[\;\|\&]*) break;;
                          --dry-run)  dry=1;;
                          --*)        ;;
                          -*n*)       dry=1;;          # -n, and -n folded into a flag cluster
                        esac
                        shift
                      done
                      [ "$dry" = 1 ] || { HIT=clean; return 0; };;
            push)     while [ $# -gt 0 ]; do           # --delete/-d/:ref anywhere in THIS invocation
                        case "$1" in
                          *[\;\|\&]*)   break;;
                          --delete|-d)  HIT=push-delete; return 0;;
                          :*)           HIT=push-delete; return 0;;
                        esac
                        shift
                      done;;
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

# ---------------------------------------------------------------- the parse, part two
# The destroyers that are not git: recursive deletes aimed at .polaris (which holds EVERY session's
# worktree, index and bg logs) and process kills that select by NAME rather than by pid (the "port
# 8001 instance vanished" incident — a launcher reclaiming a port killed whoever held it).
# Same rc contract, same tokenizer, same bias as mutating_git: every doubt resolves to 1. You may
# always kill what you started — `kill <pid>`, `taskkill /PID <pid>`, `Stop-Process -Id <pid>` — and
# you may always delete something that is not .polaris.
mutating_other() {
  local cmd="$1" tok cmdpos=1 wasglob=0 rec pol
  HIT=''
  case "$-" in *f*) wasglob=1;; esac
  set -f
  local IFS=$' \t\n'
  set -- $cmd
  [ "$wasglob" = 1 ] || set +f
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in *\"*|*\'*) cmdpos=0; continue;; esac
    case "$tok" in
      *[\;\|\&]*) cmdpos=1; tok="${tok##*[;|&]}"; [ -n "$tok" ] || continue;;
    esac
    if [ "$cmdpos" = 1 ]; then
      case "$tok" in
        rm|rm.exe|*/rm)                                # recursive AND aimed at .polaris
          rec=0; pol=0
          while [ $# -gt 0 ]; do
            case "$1" in
              *[\;\|\&]*)   break;;
              --recursive)  rec=1;;
              --*)          ;;
              -*[rR]*)      rec=1;;
            esac
            case "$1" in *.polaris*) pol=1;; esac
            shift
          done
          [ "$rec" = 1 ] && [ "$pol" = 1 ] && { HIT=rm-polaris; return 0; }
          continue;;
        Remove-Item|remove-item)
          rec=0; pol=0
          while [ $# -gt 0 ]; do
            case "$1" in
              *[\;\|\&]*) break;;
              -[Rr]ec*)   rec=1;;
            esac
            case "$1" in *.polaris*) pol=1;; esac
            shift
          done
          [ "$rec" = 1 ] && [ "$pol" = 1 ] && { HIT=rm-polaris; return 0; }
          continue;;
        taskkill|taskkill.exe|*/taskkill)              # /IM selects by image name; /PID is yours
          while [ $# -gt 0 ]; do
            case "$1" in
              *[\;\|\&]*)             break;;
              /[Ii][Mm]|/[Ii][Mm]:*)  HIT=kill-broad; return 0;;
            esac
            shift
          done
          continue;;
        Stop-Process|stop-process)                     # -Id is pid-targeted; -Name and a bare
          rec=0                                        # `Get-Process x | Stop-Process` are not
          while [ $# -gt 0 ]; do
            case "$1" in
              *[\;\|\&]*)       break;;
              -[Ii]d|-[Ii]d:*)  rec=1;;
            esac
            shift
          done
          [ "$rec" = 1 ] || { HIT=kill-broad; return 0; }
          continue;;
        pkill|killall|*/pkill|*/killall) HIT=kill-broad; return 0;;
        kill|*/kill)                                   # `kill -9 -1` is the whole session tree
          while [ $# -gt 0 ]; do
            case "$1" in
              *[\;\|\&]*) break;;
              -1)         HIT=kill-broad; return 0;;
            esac
            shift
          done
          continue;;
        fuser|*/fuser)                                 # -k kills whoever holds the port
          while [ $# -gt 0 ]; do
            case "$1" in
              *[\;\|\&]*) break;;
              --kill)     HIT=kill-broad; return 0;;
              --*)        ;;
              -*k*)       HIT=kill-broad; return 0;;
            esac
            shift
          done
          continue;;
        npx|npx.cmd|*/npx)                             # npx kill-port <port> — a name kill by proxy
          while [ $# -gt 0 ]; do
            case "$1" in
              *[\;\|\&]*) break;;
              kill-port)  HIT=kill-broad; return 0;;
            esac
            shift
          done
          continue;;
      esac
      case "$tok" in
        env|time|nice|nohup|command|'('|'{'|'!'|then|else|do) continue;;   # still command position
        [A-Za-z_]*=*) continue;;                                          # VAR=val prefix
      esac
    fi
    cmdpos=0
  done
  HIT=''
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
  # gate 1: no forks. Nothing here can be one of our classes, so nothing else runs.
  case "$CMD" in *git*|*rm*|*Remove-Item*|*kill*|*Stop-Process*|*fuser*) ;; *) break;; esac
  [ -n "$CWD" ] || CWD="$(pwd)"
  # gate 2: still no forks. A /.polaris/wt/ segment in cwd IS proof of a task worktree — every
  # one of them lives at <primary>/.polaris/wt/<ID> (wt_path(), ops/lib/core.sh), so no probe can
  # tell us anything the path has not already said. Backslashes fold to slashes first, because
  # Claude Code hands us a Windows cwd. Being inside a worktree excuses switching THAT checkout,
  # never removing/pruning/moving one or killing another session's processes — those fall through.
  # The same branch is where a worktree that only ever edits files still proves it is alive: touch
  # the liveness beat (worktree-liveness.md § beat writers) with string ops and a `: >`, best
  # effort, before any verdict — a missing dir is silently skipped and the answer never changes.
  # `2>/dev/null` sits BEFORE the `>`: redirections are applied left to right, so the contract's
  # literal order suppresses nothing and a missing worktrees dir would print on every Bash call.
  case "${CWD//\\//}" in
    */.polaris/wt/*)
      _p="${CWD//\\//}"; _w="${_p##*/.polaris/wt/}"; _w="${_w%%/*}"; : 2>/dev/null > "${_p%%/.polaris/wt/*}/.git/worktrees/$_w/polaris-beat" || true
      case "$CMD" in *worktree*|*rm*|*Remove-Item*|*kill*|*Stop-Process*|*fuser*) ;; *) break;; esac;;
  esac
  # gate 3: no forks — the two pure-bash parses. Either one sets HIT.
  mutating_git "$CMD" || mutating_other "$CMD" || break
  # gate 4: placement. Some classes end another session's work from ANY checkout — there is no
  # cwd where removing a worktree, deleting .polaris or killing by name is the right move — so
  # they skip the probe entirely and cost nothing.
  case "$HIT" in
    worktree-remove|worktree-prune|worktree-move|rm-polaris|kill-broad) ;;
    *)
      # Only now is a fork worth paying for. In the primary, --git-dir and --git-common-dir are the
      # same directory; in a linked worktree --git-dir is <common>/worktrees/<name>. Unreadable (not
      # a repo, no git, an ancient git) fails CLOSED: a checkout-mutating command we cannot place is
      # refused, because the cost of being wrong runs the other way here.
      GD="$(git -C "$CWD" rev-parse --git-common-dir --git-dir 2>/dev/null)" || GD=''
      if [ -n "$GD" ]; then
        case "$GD" in
          *$'\n'*) [ "${GD%%$'\n'*}" = "${GD#*$'\n'}" ] || break;; # differ → linked worktree → allow
          *) ;;                                                    # one line only → cannot tell → deny
        esac
      fi;;
  esac
  case "$HIT" in
    worktree-remove|worktree-prune|worktree-move|clean|rm-polaris) deny "$HIT" "$MSG_WT";;
    push-delete)                                                   deny "$HIT" "$MSG_PUSH";;
    kill-broad)                                                    deny "$HIT" "$MSG_KILL";;
    *)                                                             deny "$HIT" "$MSG";;
  esac
done

[ "$TESTMODE" = 1 ] && echo allow
exit 0
