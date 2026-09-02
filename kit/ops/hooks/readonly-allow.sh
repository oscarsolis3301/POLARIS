#!/usr/bin/env bash
# POLARIS v5 — Claude Code PreToolUse auto-approver for provably read-only Bash.
#
# WHY THIS EXISTS
#   Plan mode is where an agent reads the repo to build a plan, and every read it makes through
#   Bash used to stop and ask a human. Allowlists cannot fix that: `Bash(grep:*)` matches only a
#   SINGLE command, and Claude Code decomposes `find … | xargs wc -l | sort | head` into its parts,
#   asking about each one it does not recognise. Measured 2026-07-25: a machine with 123 allow
#   entries still prompted, because ~110 of them were one-off literal command strings captured
#   from past "yes" clicks and could never match again. An allowlist also starts EMPTY in every
#   new repo and on every new machine — so it can never satisfy "never ask me again, anywhere".
#   This hook can: it ships inside the kit, installs with it, and needs no per-user setup.
#
# THE CONTRACT — the only thing that keeps this safe
#   Deny by default. We emit an "allow" decision ONLY for a command we have fully parsed and
#   proven read-only, token by token. ANY doubt — an unknown verb, an unparsed construct, a
#   redirection we do not recognise, a quote that never closes — produces NO OUTPUT AT ALL, and
#   Claude Code's normal permission flow runs untouched. So the worst bug in here costs a
#   prompt that would have happened anyway. It can never grant something it did not understand.
#
#   Corollary, and the reason two obvious verbs are missing below: `python -c` and `node -e` run
#   ARBITRARY CODE. They are not read-only and are deliberately NOT whitelisted, however common
#   they are in an agent's reading. Same for `bash -c`. `tee`, `sort -o`, `sed -i` and
#   `find -exec` are refused for the same reason — they are the write doors on otherwise-read
#   verbs, and each one is closed by name below.
#
# SPEED
#   This runs before EVERY Bash call, so it forks nothing and calls no interpreter — pure bash,
#   one pass over the command string. It must never call `ops/polaris`: that path costs ~2.2s of
#   startup (see ops/polaris:42-66) and would tax every command to save a prompt on some.
#   Measured 2026-07-25 (Windows/Git Bash): 251ms per call end to end, of which ~148ms is bash
#   process start itself — so the parser is ~100ms and the floor is whatever the OS charges to
#   spawn a shell (~5ms on Linux/macOS). Cheap against the seconds-to-minutes a human prompt costs.
#
# TESTING
#   `readonly-allow.sh --test '<command>'` prints `allow` or `ask` and skips the JSON layer.
#   ops/tests/readonly-allow.cmd feeds it a fixed battery of allow AND refuse cases and diffs the
#   verdicts, so `polaris check` re-proves this parser on every run, for zero tokens.
set -u

SEP=$'\001'          # token separator: a control char no real command contains
VERDICT=ask          # deny by default; only an exhaustive proof flips this

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

# ---------------------------------------------------------------- per-verb gates
# Each returns 0 only when this specific invocation cannot write or execute.

# find(1): every door out of "walk the tree and print" is an action predicate.
# `-exec` is the ONE that is only conditionally a door: `find . -name '*.md' -exec wc -l {} +` is
# among the most common ways an agent reads a repo, and refusing it outright cost a prompt on pure
# reads (measured: it is what stopped a plan-mode session on 2026-07-26). So -exec RECURSES into
# verb_ok, exactly as xargs_ok does below and for exactly the same reason — a launcher is precisely
# as safe as the thing it launches. Deny-by-default survives untouched: an unrecognised verb after
# -exec falls through verb_ok's final `*) return 1` and still prompts.
#   -execdir/-ok/-okdir stay refused: -ok/-okdir prompt on a tty we do not have, and -execdir
#   changes the working directory per match, so the command a human reads is not the one that runs.
# The outer loop deliberately keeps scanning AFTER the recursion, so a tail like
# `-exec wc -l {} + -o -delete` is still caught by the -delete arm.
find_ok() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -execdir|-ok|-okdir|-delete|-fls|-fprint|-fprintf) return 1;;
      -exec)
        shift
        [ $# -gt 0 ] || return 1          # `-exec` with nothing after it is not something we parsed
        verb_ok "$@" || return 1;;
    esac
    shift
  done
  return 0
}

# sed(1): -i rewrites in place; the `w`/`W` commands and the s///w flag open a file for writing;
# the `e` command and the s///e flag execute the pattern space as a shell command.
# Patterns live in variables: bash 3.2 mis-parses escapes written inline inside [[ =~ ]].
SED_WRITE_CMD='(^|[;{}!]|[[:space:]])[wW][[:space:]]'
SED_EXEC_CMD='(^|[;{}!]|[[:space:]])e([[:space:]]|$)'
SED_BAD_FLAG='/[a-zA-Z0-9]*[we]([;}]|[[:space:]]|$)'
sed_ok() {
  local a
  for a in "$@"; do
    case "$a" in
      -i|--in-place|-i*) return 1;;
    esac
    [[ "$a" =~ $SED_WRITE_CMD ]] && return 1
    [[ "$a" =~ $SED_EXEC_CMD ]]  && return 1
    [[ "$a" =~ $SED_BAD_FLAG ]]  && return 1
  done
  return 0
}

# awk(1): comparisons like `$1 > 5` are legitimate, so `>` cannot be banned outright — we ban the
# constructs that actually leave the process: redirect-to-file, pipe-to-command, and system().
AWK_REDIR='(print|printf)[^;}]*>'
AWK_REDIR2='>[[:space:]]*"'
AWK_SYSTEM='system[[:space:]]*\('
AWK_PIPECMD='\|[[:space:]]*"'
AWK_CLOSE='close[[:space:]]*\('
awk_ok() {
  local a skip=0 seen_prog=0
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in
      -F|-v|-f) skip=1; continue;;                  # flag takes a value; the value is not a program
      -*) continue;;
    esac
    [ "$seen_prog" = 1 ] && continue
    seen_prog=1
    [[ "$a" =~ $AWK_REDIR ]]   && return 1
    [[ "$a" =~ $AWK_REDIR2 ]]  && return 1
    [[ "$a" =~ $AWK_SYSTEM ]]  && return 1
    [[ "$a" =~ $AWK_PIPECMD ]] && return 1
    [[ "$a" =~ $AWK_CLOSE ]]   && return 1
  done
  return 0
}

# git(1): read plumbing and porcelain only. Subcommands that mutate refs, the index, the worktree
# or a remote are absent by omission; the four that are read-only ONLY in some forms are gated.
git_ok() {
  while [ $# -gt 0 ]; do                             # skip pre-subcommand options
    case "$1" in
      -C|-c|--git-dir|--work-tree|--namespace) shift 2>/dev/null || return 1; shift 2>/dev/null || return 1; continue;;
      --git-dir=*|--work-tree=*|--no-pager|--no-replace-objects|--literal-pathspecs|-p|--paginate) shift; continue;;
      -*) return 1;;
      *) break;;
    esac
  done
  [ $# -gt 0 ] || return 1
  local sub="$1"; shift
  case "$sub" in
    log|diff|show|status|blame|grep|shortlog|describe|whatchanged|reflog)         return 0;;
    rev-parse|rev-list|ls-files|ls-tree|ls-remote|cat-file|show-ref|for-each-ref) return 0;;
    merge-base|name-rev|count-objects|check-ignore|check-attr|verify-pack|var)    return 0;;
    diff-tree|diff-index|diff-files|symbolic-ref|help|version)                    return 0;;
    branch)   # bare or --list is a listing; -d/-D/-m/-M/--set-upstream mutate refs
      while [ $# -gt 0 ]; do
        case "$1" in
          -a|-r|-v|-vv|--list|--all|--remotes|--show-current|--contains|--merged|--no-merged|--sort=*|--format=*|--color|--no-color) shift;;
          -*) return 1;;
          *) shift;;
        esac
      done
      return 0;;
    tag)      case "${1:-}" in ''|-l|--list|-n*) return 0;; *) return 1;; esac;;
    worktree) case "${1:-}" in list) return 0;; *) return 1;; esac;;
    stash)    case "${1:-}" in list|show) return 0;; *) return 1;; esac;;
    remote)   case "${1:-}" in ''|-v|--verbose|show|get-url) return 0;; *) return 1;; esac;;
    config)   # --get/--list read; a bare `git config k v` writes
      while [ $# -gt 0 ]; do
        case "$1" in
          --get|--get-all|--get-regexp|-l|--list) return 0;;
          --global|--local|--system|--worktree|-f|--file) shift;;
          *) return 1;;
        esac
      done
      return 1;;
    *) return 1;;
  esac
}

# ops/polaris: the read commands only. `claim`, `handoff`, `land`, `seal`, `done`, `update`,
# `uninstall` and friends mutate the board, a branch or the installed kit — they keep their prompt.
# `route` joins the plain readers: it derives a tier from task frontmatter and CONVENTIONS and
# writes nothing at all.
polaris_ok() {
  case "${1:-}" in
    find|show|board-fm|status|brain|metrics|why|drift|rules|version|help|history|report|triage|pack|route|--help|-h|'') return 0;;
    # `slim` bare is a report and writes nothing; `--apply`/`--restore` MOVE files under ~/.claude,
    # so they keep their prompt. Same split as check vs check --update.
    slim) case "${2:-}" in '') return 0;; *) return 1;; esac;;
    # `bg` splits the same way, and it is why this gate matters: agents run these reads INSIDE
    # compound lines (`bg status x && …`), where a settings.json allow rule cannot match at all.
    # `status`/`tail`/`wait` only read the job registry. `bg run` spawns a detached process and
    # writes that registry, so it keeps its prompt — as does a bare `bg` and any word we do not
    # know, by the same deny-by-default that governs every other arm here.
    bg)   case "${2:-}" in status|tail|wait) return 0;; *) return 1;; esac;;
    # `check` bare and `check --only <glob>` are reads; `--update` rewrites the goldens from
    # actual output and `--scaffold` writes new pairs — observe.sh's own help calls these
    # "ALWAYS a human/Builder decision, never automatic" (T-072). Both keep their prompt in
    # every position and combination; anything outside that read shape fails closed, the same
    # deny-by-default that governs every other arm here.
    check)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --update|--scaffold) return 1;;
          --only) shift; case "${1:-}" in ''|--*) return 1;; esac;;
          *) return 1;;
        esac
        shift
      done
      return 0;;
    # `next` is `triage` for a session: it reads the board and prints the one verb this context does
    # next, writing nothing — and every role now runs it at EVERY boundary, so a prompt here would
    # be the loudest in the kit. `--brief` is the same read, re-anchoring a compacted chat. `--do`
    # promotes backlog→ready under the board lock, so it keeps its prompt, and so does any word we
    # have not proven — the same deny-by-default that governs every other arm here.
    next) case "${2:-}" in ''|--brief) return 0;; *) return 1;; esac;;
    *) return 1;;
  esac
}

# xargs(1) is a launcher: it is exactly as safe as the command it launches, so recurse.
# With no command it defaults to echo.
xargs_ok() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -I|-i|-n|-P|-d|-s|-L|-a|-E|--max-args|--max-procs|--delimiter|--replace|--arg-file)
        shift 2>/dev/null || return 0; shift 2>/dev/null || return 0; continue;;
      -*) shift; continue;;
      *) break;;
    esac
  done
  [ $# -gt 0 ] || return 0
  verb_ok "$@"
}

# ---------------------------------------------------------------- the verb gate
verb_ok() {
  local v="$1"; shift
  case "$v" in
    # Pure readers. No flag of theirs writes a file or runs a program.
    cat|head|tail|wc|cut|tr|uniq|comm|paste|join|nl|rev|tac|fold|expand|unexpand|column|\
    basename|dirname|realpath|readlink|pwd|echo|printf|seq|date|true|false|test|'['|:|\
    file|stat|du|df|cksum|md5sum|sha1sum|sha256sum|strings|od|hexdump|xxd|\
    ls|tree|grep|egrep|fgrep|rg|ag|ack|diff|cmp|jq|yq|whoami|id|groups|hostname|uname|\
    printenv|locale|tty|uptime|ps|pgrep|which|type|command|cd|pushd|popd|dirs|sleep|wait)
      return 0;;
    sort)   while [ $# -gt 0 ]; do case "$1" in -o|--output|-o*|--output=*) return 1;; esac; shift; done; return 0;;
    find)   find_ok "$@";;
    sed)    sed_ok "$@";;
    awk|gawk|mawk|nawk) awk_ok "$@";;
    git)    git_ok "$@";;
    xargs)  xargs_ok "$@";;
    ops/polaris|./ops/polaris) polaris_ok "$@";;
    bash|sh) # only as the documented launcher for our own read commands
      case "${1:-}" in
        ops/polaris|./ops/polaris) shift; polaris_ok "$@";;
        *) return 1;;
      esac;;
    # Everything else — including python, node, tee, cp, mv, rm — falls through to a prompt.
    *) return 1;;
  esac
}

# ---------------------------------------------------------------- segment check
check_segment() {
  local toks="$1" OLDIFS="$IFS"
  [ -n "$toks" ] || return 0
  IFS="$SEP"
  # shellcheck disable=SC2086
  set -- $toks
  IFS="$OLDIFS"
  while [ $# -gt 0 ]; do                      # strip leading VAR=val and harmless prefixes
    case "$1" in
      time|nice|nohup|'!') shift; continue;;
      *=*) case "${1%%=*}" in
             *[!A-Za-z0-9_]*) break;;
             '') break;;
             *) shift; continue;;
           esac;;
      *) break;;
    esac
  done
  [ $# -gt 0 ] || return 0
  verb_ok "$@"
}

# ---------------------------------------------------------------- the scanner
# ONE pass over the command. Tracks quoting, refuses every construct that can reach a shell
# (substitution, subshell, background, process substitution), validates each redirection, and
# hands finished segments to check_segment. Returns 1 the moment anything is not understood.
scan() {
  local cmd="$1"                 # separate statement: `local a=$1 b=${#a}` is not portable
  local len=${#cmd}
  local i=0 c n st=none tok='' toks='' target
  while [ "$i" -lt "$len" ]; do
    c="${cmd:i:1}"
    case "$st" in
      single) if [ "$c" = "'" ]; then st=none; else tok="$tok$c"; fi; i=$((i + 1)); continue;;
      double)
        case "$c" in
          '"') st=none;;
          '\') i=$((i + 1)); tok="$tok${cmd:i:1}";;
          '`') return 1;;
          '$') [ "${cmd:i+1:1}" = "(" ] && return 1; tok="$tok$c";;
          *)   tok="$tok$c";;
        esac
        i=$((i + 1)); continue;;
    esac

    n="${cmd:i+1:1}"
    case "$c" in
      "'")  st=single; i=$((i + 1));;
      '"')  st=double; i=$((i + 1));;
      '\')  i=$((i + 1)); tok="$tok${cmd:i:1}"; i=$((i + 1));;
      '`')  return 1;;
      '$')  [ "$n" = "(" ] && return 1; tok="$tok$c"; i=$((i + 1));;
      '{')
        # `{}` is find(1)'s placeholder, and it is NOT a brace group: bash requires whitespace
        # after `{` to open one, so an immediately-closed `{}` can never be command syntax. Accept
        # exactly that two-character token and nothing else — `{ rm -rf x; }` still returns 1 below.
        if [ "$n" = "}" ]; then tok="$tok{}"; i=$((i + 2)); continue; fi
        return 1;;
      '(' | ')' | '}') return 1;;                            # subshells and groups: not parsed
      '&')
        if [ "$n" = "&" ]; then                              # && — segment boundary
          [ -n "$tok" ] && toks="$toks$SEP$tok"; tok=''
          check_segment "${toks#$SEP}" || return 1
          toks=''; i=$((i + 2))
        elif [ "$n" = ">" ]; then                            # &> — redirect, handled below
          i=$((i + 1))
          case "${cmd:i+1:1}" in '>') i=$((i + 1));; esac
          i=$((i + 1))
          while [ "${cmd:i:1}" = " " ]; do i=$((i + 1)); done
          target=''; while [ "$i" -lt "$len" ]; do
            case "${cmd:i:1}" in ' '|'	'|'|'|';') break;; esac
            target="$target${cmd:i:1}"; i=$((i + 1))
          done
          case "$target" in /dev/null|/dev/stdout|/dev/stderr) ;; *) return 1;; esac
        else
          return 1                                           # backgrounding
        fi;;
      '|')
        [ -n "$tok" ] && toks="$toks$SEP$tok"; tok=''
        check_segment "${toks#$SEP}" || return 1
        toks=''
        if [ "$n" = "|" ]; then i=$((i + 2)); else i=$((i + 1)); fi;;
      ';' | $'\n')
        [ -n "$tok" ] && toks="$toks$SEP$tok"; tok=''
        check_segment "${toks#$SEP}" || return 1
        toks=''; i=$((i + 1));;
      '<')
        [ "$n" = "<" ] && return 1                           # heredoc / herestring
        [ "$n" = "(" ] && return 1                           # process substitution
        [ -n "$tok" ] && { toks="$toks$SEP$tok"; tok=''; }
        i=$((i + 1))
        while [ "${cmd:i:1}" = " " ]; do i=$((i + 1)); done
        while [ "$i" -lt "$len" ]; do                        # consume the source file
          case "${cmd:i:1}" in ' '|'	'|'|'|';') break;; esac
          i=$((i + 1))
        done;;
      '>')
        # A file descriptor prefix (the 2 of `2>`) is part of the redirect, not a token.
        case "$tok" in ''|*[!0-9]*) [ -n "$tok" ] && { toks="$toks$SEP$tok"; tok=''; };; *) tok='';; esac
        i=$((i + 1))
        [ "${cmd:i:1}" = ">" ] && i=$((i + 1))               # >>
        if [ "${cmd:i:1}" = "&" ]; then                      # >&1 / >&2 — no file is written
          i=$((i + 1))
          case "${cmd:i:1}" in 1|2) i=$((i + 1)); continue;; *) return 1;; esac
        fi
        while [ "${cmd:i:1}" = " " ]; do i=$((i + 1)); done
        target=''; while [ "$i" -lt "$len" ]; do
          case "${cmd:i:1}" in ' '|'	'|'|'|';') break;; esac
          target="$target${cmd:i:1}"; i=$((i + 1))
        done
        case "$target" in /dev/null|/dev/stdout|/dev/stderr) ;; *) return 1;; esac;;
      ' ' | '	')
        [ -n "$tok" ] && { toks="$toks$SEP$tok"; tok=''; }
        i=$((i + 1));;
      *) tok="$tok$c"; i=$((i + 1));;
    esac
  done
  [ "$st" = none ] || return 1                               # unterminated quote
  [ -n "$tok" ] && toks="$toks$SEP$tok"
  check_segment "${toks#$SEP}" || return 1
  return 0
}

# ---------------------------------------------------------------- entry
if [ "${1:-}" = "--test" ]; then
  scan "${2:-}" && echo allow || echo ask
  exit 0
fi

IN="$(cat)"
jstr tool_name "$IN" || exit 0
[ "$REPLY" = "Bash" ] || exit 0
jstr command "${IN#*\"tool_input\"}" || exit 0
CMD="$REPLY"
[ -n "$CMD" ] || exit 0

scan "$CMD" || exit 0
VERDICT=allow

# Claude Code reads this and skips the prompt. Any other output shape is ignored, which is
# another reason a bug here degrades to "ask" rather than to "allow".
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"POLARIS: every segment proven read-only"}}\n' "$VERDICT"
exit 0
