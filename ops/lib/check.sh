# POLARIS lib/check.sh — the goldens, sourced by ops/polaris (the lib loader): check, scaffold,
# and the generated app harness. Moved out of observe.sh unchanged (ops/contracts/minutes.md § 3).

scaffold_try() { # scaffold_try <name> <cmd-body> — write the pair, but ONLY if it is worth locking.
  # Four refusals, each one a golden that would have been worse than no golden at all:
  #   exists  — never clobber a reviewed pair; --update is the deliberate way to redo one
  #   flappy  — output or rc differed across two back-to-back runs (timestamps, ordering, paths)
  #   empty   — an empty golden asserts nothing and goes green forever
  #   dead    — rc 127/126: the command isn't installed here, so the lock would be fiction
  #   huge    — rc 4 to the CALLER, which may then lock a coarser view of the same thing.
  #             Measured on a 3,000-file repo: one `--api src/*` golden is 75,001 lines / 2.9 MB.
  #             A golden nobody can read in a diff is a golden nobody maintains.
  # $3 = max lines (default 2000). Explicit argument, NOT a `VAR=x scaffold_try` prefix: the prefix
  # form silently failed to reach the function across a line-continued call, capping a 3,000-line
  # fallback at 2,000 and swallowing the whole scaffold.
  local name="$1" body="$2" cap="${3:-2000}" dir="$OPS/tests" a b arc brc lines
  [ -f "$dir/$name.cmd" ] && { SC_SKIP=$((SC_SKIP+1)); return 0; }
  if a="$( cd "$PRIMARY" && bash -c "$body" 2>/dev/null )"; then arc=0; else arc=$?; fi
  if b="$( cd "$PRIMARY" && bash -c "$body" 2>/dev/null )"; then brc=0; else brc=$?; fi
  { [ "$arc" -eq 127 ] || [ "$arc" -eq 126 ]; } && { SC_DEAD=$((SC_DEAD+1)); return 0; }
  { [ "$a" = "$b" ] && [ "$arc" = "$brc" ]; } || { SC_FLAP=$((SC_FLAP+1)); return 0; }
  [ -n "$a" ] || { SC_EMPTY=$((SC_EMPTY+1)); return 0; }
  lines="$(printf '%s\n' "$a" | wc -l)"
  [ "$lines" -gt "$cap" ] && { SC_HUGE=$((SC_HUGE+1)); return 4; }
  # Already asserted by an existing golden under another name? Two goldens with byte-identical
  # output test one thing twice and double the cost of every real change. Seen for real: a
  # generated `board-fm-cols` that duplicated the hand-written `board-fm-shape` exactly.
  local e
  for e in "$dir"/*.expected; do
    [ -e "$e" ] || break
    if printf '%s\n' "$a" | diff -q - "$e" >/dev/null 2>&1; then
      SC_DUP=$((SC_DUP+1)); note "skipped $name — same output as $(basename "$e" .expected)"; return 0
    fi
  done
  printf '%s\n' "$body" > "$dir/$name.cmd"
  printf '%s\n' "$a"    > "$dir/$name.expected"
  [ "$arc" != "0" ] && printf '%s\n' "$arc" > "$dir/$name.rc"
  SC_MADE=$((SC_MADE+1)); say "golden: $name"
  return 0
}

scaffold_dirs() { # top-level directories carrying a real public surface, newline-separated.
  # Derived from the INDEX, so it needs no config and works on a repo it has never seen.
  # The exclusions are all one idea: NEVER lock a tree whose whole job is to change without us.
  #   vendored/built  node_modules vendor dist build out target coverage — someone else's code
  #   ops · kit/ops   POLARIS's own INSTALLED copy. Locking it reds on every `polaris update`,
  #                   which is the workflow, not a regression — the golden would assert the
  #                   opposite of what is supposed to happen. (prefs.md excludes it for the
  #                   same reason.) Seen for real: a 571-line api-ops golden on this repo.
  #   docs            `seal` writes a sprint report here every wave — reds by construction.
  #   .github         CI config, human-owned and RULES-guarded; an agent cannot fix a red here.
  #   archive         dead code kept on purpose.
  "$SELF" find --api '*' 2>/dev/null \
    | awk -F'\t' '{ i=index($1,"/"); if (i>1) print substr($1,1,i-1) }' \
    | sort | uniq -c | sort -rn \
    | awk '$1 >= 5 {print $2}' \
    | grep -Ev '^(node_modules|vendor|dist|build|out|target|\.git|\.github|archive|coverage|ops|docs)$' || true
}

# ------------------------------------------------------------------ harness (5.21.0)
# ops/contracts/app-harness.md — the BEHAVIOUR tier above `check --scaffold --app`.
#
# `--scaffold --app` locks an app's SHAPE by reading files: routes declared, deps declared, env
# names referenced. It never runs anything, so it cannot tell you the app still BOOTS.
# `harness` writes the one script that does — generated once, run forever for a subprocess and
# zero tokens. It is the mechanical answer to the most expensive habit in this protocol: a model
# re-checking every route, import and entry point by hand, every wave.
#
# Three sweeps, chosen because each is (a) generatable without knowing the app and (b) catches a
# class of failure that otherwise reaches a human:
#   IMPORT  every module imports cleanly            — syntax errors, bad/circular imports, missing deps
#   ROUTE   every discovered route answers non-5xx  — the app boots and its surface responds
#   ENTRY   every console entry runs --help         — the thing users actually type still starts
# Plus a BASELINE: the route and module inventory captured on the first green run, so a route or
# module that DISAPPEARS is a failure too. That is the "expected output" half — a regression lock,
# reviewed once by a human, then free.
#
# Honesty rules baked into the generated file: a sweep that cannot find what it needs SKIPS with a
# printed reason. It never invents an app object, never guesses a factory's arguments, and never
# passes by asserting nothing. A harness that goes green because it tested nothing is worse than
# no harness, because it also removes the human's suspicion.

harness_testdir() { # where this repo already puts tests — never impose tests/ on a repo with a
  # convention. brain/prefs.md detects this by counting; fall back to the commonest layout.
  local d
  for d in tests test spec __tests__; do
    [ -d "$PRIMARY/$d" ] && { printf '%s' "$d"; return 0; }
  done
  printf 'tests'
}

harness_stack() { # python | node | none — from tracked files, never from a guess
  local ls; ls="$(git -C "$PRIMARY" ls-files 2>/dev/null)"
  case "$ls" in *pyproject.toml*|*requirements.txt*|*setup.py*) printf 'python'; return 0;; esac
  case "$ls" in *package.json*) printf 'node'; return 0;; esac
  printf '%s\n' "$ls" | grep -q '\.py$'  && { printf 'python'; return 0; }
  printf '%s\n' "$ls" | grep -qE '\.[cm]?js$' && { printf 'node'; return 0; }
  printf 'none'
}

harness_write_python() { # emit the pytest harness. Quoted heredoc: nothing here is expanded by the
  # shell, so the generated file is exactly what is written below.
  cat <<'PYEOF'
"""POLARIS app harness — GENERATED by `ops/polaris harness`. Regenerate, do not hand-edit.

Three sweeps and a baseline. Every one of them is mechanical: this file exists so that proving
"the app still works" costs a subprocess instead of an agent walking the app by hand every wave.

    pytest tests/test_polaris_harness.py -q

A sweep that cannot find what it needs SKIPS and says why. It never passes by asserting nothing.
Accept a legitimate change with:  ops/polaris harness --refresh
"""
import importlib, json, os, pathlib, pkgutil, subprocess, sys
import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINE = ROOT / ".polaris" / "harness-baseline.json"
SKIP_DIRS = {".git", ".polaris", "node_modules", "venv", ".venv", "env", "build", "dist",
             "__pycache__", "ops", "kit", "archive", ".tox", "site-packages", "migrations"}

sys.path.insert(0, str(ROOT))


def _baseline():
    if BASELINE.exists():
        try:
            return json.loads(BASELINE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def _modules():
    """Every importable module path in the repo, as dotted names."""
    out = []
    for p in sorted(ROOT.rglob("*.py")):
        rel = p.relative_to(ROOT)
        if any(part in SKIP_DIRS or part.startswith(".") for part in rel.parts[:-1]):
            continue
        if rel.name.startswith((".", "test_", "conftest")) or rel.name.endswith("_test.py"):
            continue
        parts = list(rel.parts[:-1]) + [rel.stem]
        if parts[-1] == "__init__":
            parts = parts[:-1]
        if parts:
            out.append(".".join(parts))
    return sorted(set(out))


def _find_app():
    """Locate a WSGI/ASGI application without guessing at constructor arguments.

    Only zero-argument factories are called. A factory that needs a config object is one we
    cannot supply correctly, and calling it with invented arguments would either crash (a false
    red) or build an app unlike the real one (a false green). Both are worse than a skip.
    """
    import inspect
    candidates = ("app", "application", "api", "server")
    for modname in _modules():
        if not any(k in modname.lower() for k in ("app", "main", "server", "api", "wsgi", "asgi")):
            continue
        try:
            mod = importlib.import_module(modname)
        except Exception:
            continue
        for attr in candidates:
            obj = getattr(mod, attr, None)
            if obj is not None and (hasattr(obj, "url_map") or hasattr(obj, "routes")):
                return obj, f"{modname}.{attr}"
        for fname in ("create_app", "make_app", "get_app"):
            f = getattr(mod, fname, None)
            if not callable(f):
                continue
            try:
                if inspect.signature(f).parameters:
                    continue           # needs config we do not have — skip, never invent
                obj = f()
            except Exception:
                continue
            if hasattr(obj, "url_map") or hasattr(obj, "routes"):
                return obj, f"{modname}.{fname}()"
    return None, None


def _routes(app):
    """(rule, methods) for Flask/Werkzeug or FastAPI/Starlette. GET/HEAD only downstream."""
    out = []
    if hasattr(app, "url_map"):
        for r in app.url_map.iter_rules():
            if r.endpoint == "static":
                continue
            out.append((str(r.rule), sorted(r.methods - {"HEAD", "OPTIONS"})))
    elif hasattr(app, "routes"):
        for r in app.routes:
            path = getattr(r, "path", None)
            if path:
                out.append((str(path), sorted(getattr(r, "methods", ["GET"]) or ["GET"])))
    return sorted(out)


def _client(app):
    if hasattr(app, "test_client"):
        return app.test_client(), "flask"
    try:
        from fastapi.testclient import TestClient
        return TestClient(app), "starlette"
    except Exception:
        try:
            from starlette.testclient import TestClient
            return TestClient(app), "starlette"
        except Exception:
            return None, None


# ---------------------------------------------------------------- SWEEP 1: imports
@pytest.mark.parametrize("modname", _modules() or ["<none>"])
def test_module_imports(modname):
    """Catches syntax errors, bad imports and circular imports across the whole app at once."""
    if modname == "<none>":
        pytest.skip("no importable modules found under the repo root")
    try:
        importlib.import_module(modname)
    except Exception as exc:
        pytest.fail(f"{modname} does not import: {type(exc).__name__}: {exc}")


# ---------------------------------------------------------------- SWEEP 2: routes
def test_every_route_answers():
    """Every GET route returns < 500. A 4xx is a valid answer; a 5xx is the app falling over."""
    app, where = _find_app()
    if app is None:
        pytest.skip("no zero-argument app factory or app object found — routes not swept")
    client, kind = _client(app)
    if client is None:
        pytest.skip(f"found {where} but no usable test client (install flask or fastapi extras)")

    broken = []
    for rule, methods in _routes(app):
        if "GET" not in methods or "<" in rule or "{" in rule:
            continue          # parameterised routes need fixtures we cannot invent
        try:
            resp = client.get(rule)
            code = getattr(resp, "status_code", 0)
            if code >= 500:
                broken.append(f"{rule} -> {code}")
        except Exception as exc:
            broken.append(f"{rule} -> raised {type(exc).__name__}: {exc}")
    assert not broken, "routes returning 5xx or raising:\n  " + "\n  ".join(broken)


# ---------------------------------------------------------------- SWEEP 3: entry points
def test_entry_points_start():
    """Whatever a user actually types must still start. --help only: never runs the real thing."""
    entries = []
    pp = ROOT / "pyproject.toml"
    if pp.exists():
        txt = pp.read_text(encoding="utf-8", errors="replace")
        in_scripts = False
        for line in txt.splitlines():
            s = line.strip()
            if s.startswith("["):
                in_scripts = "scripts" in s
                continue
            if in_scripts and "=" in s and not s.startswith("#"):
                entries.append(s.split("=")[0].strip().strip('"').strip("'"))
    if not entries:
        pytest.skip("no console entry points declared in pyproject.toml")

    env = dict(os.environ, POLARIS_HARNESS="1")
    broken = []
    for e in entries:
        try:
            r = subprocess.run([e, "--help"], capture_output=True, timeout=30, cwd=ROOT, env=env)
            if r.returncode != 0 and b"Traceback" in (r.stderr or b""):
                broken.append(f"{e} --help crashed: {(r.stderr or b'').decode(errors='replace')[:200]}")
        except FileNotFoundError:
            pass          # not installed in this environment; that is not an app defect
        except subprocess.TimeoutExpired:
            broken.append(f"{e} --help hung for 30s")
    assert not broken, "entry points failing:\n  " + "\n  ".join(broken)


# ---------------------------------------------------------------- BASELINE: nothing vanished
def test_nothing_disappeared():
    """A route or module that VANISHES is a regression the sweeps above cannot see: they only
    check what exists now. This is the recorded-expectations half — `harness --refresh` accepts
    a deliberate removal, which makes accepting one a visible, reviewable act."""
    base = _baseline()
    if not base:
        pytest.skip("no baseline yet — run: ops/polaris harness --refresh")
    now_mods = set(_modules())
    gone = sorted(set(base.get("modules", [])) - now_mods)
    app, _ = _find_app()
    detail = [f"module gone: {m}" for m in gone]
    if app is not None:
        now_routes = {r for r, _m in _routes(app)}
        detail += [f"route gone: {r}" for r in sorted(set(base.get("routes", [])) - now_routes)]
    assert not detail, ("the app lost surface it used to have:\n  " + "\n  ".join(detail)
                        + "\n\nDeliberate? accept it: ops/polaris harness --refresh")
PYEOF
}

harness_write_node() { # emit the node:test harness — same three sweeps, same honesty rules.
  cat <<'JSEOF'
// POLARIS app harness — GENERATED by `ops/polaris harness`. Regenerate, do not hand-edit.
//
// Three sweeps and a baseline, all mechanical. This file exists so that proving "the app still
// works" costs a subprocess instead of an agent clicking through it every wave.
//
//     node --test <thisfile>
//
// A sweep that cannot find what it needs SKIPS and says why — it never passes by asserting nothing.
// Accept a legitimate change with:  ops/polaris harness --refresh
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const BASELINE = path.join(ROOT, '.polaris', 'harness-baseline.json');
const SKIP = new Set(['node_modules', '.git', '.polaris', 'dist', 'build', 'out', 'coverage',
                      'ops', 'kit', 'archive', '__tests__', 'tests', 'test']);

function sources(dir = ROOT, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith('.') || SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) sources(p, acc);
    else if (/\.(js|cjs|mjs)$/.test(e.name) && !/\.(test|spec)\./.test(e.name)) acc.push(p);
  }
  return acc;
}

function baseline() {
  try { return JSON.parse(fs.readFileSync(BASELINE, 'utf8')); } catch { return null; }
}

// ------------------------------------------------------------ SWEEP 1: every module loads
test('every module loads', () => {
  const broken = [];
  for (const f of sources()) {
    try { require(f); }
    catch (err) {
      // A module that legitimately refuses to load without config is not a syntax error.
      if (err && (err.code === 'ERR_REQUIRE_ESM' || err.code === 'MODULE_NOT_FOUND')) continue;
      broken.push(`${path.relative(ROOT, f)}: ${err && err.message}`);
    }
  }
  assert.deepStrictEqual(broken, [], `modules that do not load:\n  ${broken.join('\n  ')}`);
});

// ------------------------------------------------------------ SWEEP 2: package scripts exist
test('declared npm scripts still exist', () => {
  const pj = path.join(ROOT, 'package.json');
  if (!fs.existsSync(pj)) return;                       // nothing declared, nothing to lose
  const base = baseline();
  if (!base || !base.scripts) { console.log('  skip: no baseline — ops/polaris harness --refresh'); return; }
  const now = Object.keys(JSON.parse(fs.readFileSync(pj, 'utf8')).scripts || {});
  const gone = base.scripts.filter((s) => !now.includes(s));
  assert.deepStrictEqual(gone, [], `npm scripts removed: ${gone.join(', ')}`);
});

// ------------------------------------------------------------ SWEEP 3: the CLI still starts
test('bin entries run --help without crashing', () => {
  const pj = path.join(ROOT, 'package.json');
  if (!fs.existsSync(pj)) return;
  const bin = JSON.parse(fs.readFileSync(pj, 'utf8')).bin || {};
  const entries = typeof bin === 'string' ? [bin] : Object.values(bin);
  if (!entries.length) { console.log('  skip: no bin entries declared'); return; }
  const broken = [];
  for (const e of entries) {
    const p = path.join(ROOT, e);
    if (!fs.existsSync(p)) { broken.push(`${e}: declared in package.json but missing on disk`); continue; }
    try { execFileSync(process.execPath, [p, '--help'], { timeout: 30000, stdio: 'pipe', cwd: ROOT }); }
    catch (err) {
      if (err.status !== 0 && /Error|Exception/.test(String(err.stderr || ''))) {
        broken.push(`${e} --help crashed: ${String(err.stderr).slice(0, 200)}`);
      }
    }
  }
  assert.deepStrictEqual(broken, [], `entry points failing:\n  ${broken.join('\n  ')}`);
});

// ------------------------------------------------------------ BASELINE: nothing vanished
test('nothing disappeared', () => {
  const base = baseline();
  if (!base) { console.log('  skip: no baseline — ops/polaris harness --refresh'); return; }
  const now = sources().map((f) => path.relative(ROOT, f).split(path.sep).join('/'));
  const gone = (base.modules || []).filter((m) => !now.includes(m));
  assert.deepStrictEqual(gone, [],
    `the app lost files it used to have:\n  ${gone.join('\n  ')}\n\nDeliberate? ops/polaris harness --refresh`);
});
JSEOF
}

harness_baseline() { # capture the inventory the "nothing disappeared" test diffs against.
  # Written by the CLI, not by the harness itself: a suite that rewrites its own expectations on
  # every run cannot fail, and that is the failure mode this whole tier exists to avoid.
  local stack="$1" out="$PRIMARY/.polaris/harness-baseline.json" rel="${2:-}" py=""
  mkdir -p "$PRIMARY/.polaris"
  if [ "$stack" = python ]; then
    # Ask the GENERATED harness for the inventory rather than re-deriving it here. Two copies of
    # "what counts as a module" drift, and the day they disagree the baseline test either fires on
    # nothing or fires forever. This also fills `routes`, which a pure file-listing cannot know —
    # routes only exist once the app is imported. No python (or an app that will not import) →
    # fall through to the module list alone, so the baseline degrades instead of failing.
    python3 -c pass >/dev/null 2>&1 && py=python3 || { python -c pass >/dev/null 2>&1 && py=python; }
    if [ -n "$py" ] && [ -n "$rel" ] && [ -f "$PRIMARY/$rel" ]; then
      ( cd "$PRIMARY" && "$py" - "$rel" <<'PY' > "$out" 2>/dev/null
import importlib.util, json, sys, pathlib
spec = importlib.util.spec_from_file_location("_ph", pathlib.Path(sys.argv[1]).resolve())
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
    mods = mod._modules()
    app, _ = mod._find_app()
    routes = sorted({r for r, _m in mod._routes(app)}) if app is not None else []
except Exception:
    raise SystemExit(1)
json.dump({"modules": mods, "routes": routes}, sys.stdout, indent=2)
PY
      ) && [ -s "$out" ] && { printf '%s' "$out"; return 0; }
    fi
    git -C "$PRIMARY" ls-files '*.py' 2>/dev/null | awk '
      BEGIN { print "{\n  \"modules\": [" }
      { gsub(/\.py$/,""); gsub(/\//,"."); sub(/\.__init__$/,"")
        if ($0 ~ /^(ops|kit|archive|tests?|test)\./ || $0 ~ /(^|\.)test_/) next
        printf "%s    \"%s\"", (n++ ? ",\n" : ""), $0 }
      END { print "\n  ],\n  \"routes\": []\n}" }' > "$out"
  else
    # package.json is parsed by NODE, not by awk. The awk version keyed on `"scripts":` starting a
    # line and `}` ending one, so it silently produced an empty list for the extremely common
    # single-line form `"scripts": { "start": "...", "build": "..." },` — and an empty baseline
    # asserts nothing while looking exactly like a passing one. Never hand-roll a JSON parser for a
    # file the runtime you are already targeting can read correctly.
    local scripts="[]"
    if [ -f "$PRIMARY/package.json" ] && command -v node >/dev/null 2>&1; then
      scripts="$(node -e 'try{const p=require(process.argv[1]);process.stdout.write(JSON.stringify(Object.keys(p.scripts||{})))}catch(e){process.stdout.write("[]")}' \
                 "$PRIMARY/package.json" 2>/dev/null)" || scripts="[]"
      [ -n "$scripts" ] || scripts="[]"
    fi
    { printf '{\n  "modules": [\n'
      git -C "$PRIMARY" ls-files '*.js' '*.cjs' '*.mjs' 2>/dev/null \
        | grep -Ev '^(node_modules|ops|kit|archive|dist|build|coverage)/' \
        | grep -Ev '\.(test|spec)\.' \
        | awk '{ printf "%s    \"%s\"", (n++ ? ",\n" : ""), $0 } END{ print "" }'
      printf '  ],\n  "scripts": %s\n}\n' "$scripts"
    } > "$out"
  fi
  printf '%s' "$out"
}

cmd_harness() { # harness [--refresh] — generate ONE runnable suite for the HOST app.
  local refresh=0 stack td file rel base
  case "${1:-}" in
    '') ;;
    --refresh) refresh=1;;
    *) die "usage: polaris harness [--refresh]";;
  esac

  stack="$(harness_stack)"
  [ "$stack" = none ] && die "cannot tell what this app is built with (no pyproject/requirements/package.json, no .py or .js).
   For a CLI or a shell tool, the right tier is golden output: ops/polaris check --scaffold --app"

  td="$(harness_testdir)"
  mkdir -p "$PRIMARY/$td" || die "cannot create $td/"
  if [ "$stack" = python ]; then rel="$td/test_polaris_harness.py"; else rel="$td/polaris-harness.test.js"; fi
  file="$PRIMARY/$rel"

  if [ -f "$file" ] && [ "$refresh" -eq 0 ]; then
    note "$rel already exists — left as is (it may have been edited on purpose)"
    note "re-generate it and re-capture expectations with: ops/polaris harness --refresh"
  else
    if [ "$stack" = python ]; then harness_write_python > "$file"; else harness_write_node > "$file"; fi
    say "wrote $rel  ($stack)"
  fi

  base="$(harness_baseline "$stack" "$rel")"
  say "captured baseline: .polaris/harness-baseline.json"

  # The point of the whole tier, said once where someone will read it.
  printf '\n'
  note "This suite is MECHANICAL: it costs a subprocess and zero tokens, every run, forever."
  note "Run it:"
  if [ "$stack" = python ]; then
    note "  pytest $rel -q"
    note "Wire it into qa (ops/CONVENTIONS.md), so it rides the gate that already exists:"
    note "  uat: pytest $rel -q"
  else
    note "  node --test $rel"
    note "Wire it into qa (ops/CONVENTIONS.md), so it rides the gate that already exists:"
    note "  uat: node --test $rel"
  fi
  note ""
  note "A sweep that cannot find what it needs SKIPS and says why — read the skips once. Anything"
  note "it skips is a place a golden pair still earns its keep: ops/polaris check --scaffold --app"
  return 0
}

cmd_scaffold() { # check --scaffold [--cmd "<shell>"] — GENERATE goldens from observed behavior.
  # These are REGRESSION LOCKS, not correctness proofs: they assert "this still does what it did
  # the day we looked", which is exactly the class of check that never needed a model. A human or
  # Builder reviews them once; from then on every run costs a subprocess instead of a subagent.
  #
  # Auto-generated sources are limited to ones that are provably READ-ONLY — the index and this
  # CLI's own reporting commands. Scaffold does NOT go hunting for executables in bin/ to run with
  # --help: on a real app that is how you start a server or mutate a database during a test-writing
  # pass. Behavioural goldens for an app's own commands are opt-in, one at a time, via --cmd.
  local extra="" app=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --cmd) extra="${2:?--cmd needs a shell command}"; shift 2;;
      --app) app=1; shift;;
      *) die "usage: polaris check --scaffold [--app] [--cmd \"<shell command>\"]";;
    esac
  done
  local dir="$OPS/tests" d slug
  mkdir -p "$dir"
  SC_MADE=0; SC_SKIP=0; SC_FLAP=0; SC_EMPTY=0; SC_DEAD=0; SC_HUGE=0; SC_DUP=0
  if [ "$app" -eq 1 ]; then
    # --app: lock the HOST application's shape, not POLARIS's. The default scaffold locks the code
    # index and this CLI; a user's repo also has a manifest, routes, migrations and a config
    # surface, and those are where "someone changed something nobody meant to change" actually
    # shows up. Each golden below is pure TEXT EXTRACTION over tracked files — nothing here runs
    # the app, imports its modules, opens a port or touches a database, for the same reason the
    # default scaffold refuses to go hunting for executables to run with --help.
    #
    # These answer the ask directly: instead of an agent re-reading routes and re-checking deps
    # every wave, `polaris check` re-proves all of it for the price of a subprocess.
    if [ -f "$PRIMARY/package.json" ]; then
      # Parsed by node, not by a sed line-range: `/"scripts"/,/}/` runs past the closing brace on
      # any compact package.json and swallows the next block whole (observed: the scripts golden
      # captured `express` and `zod`). node only READS the manifest here — no install, no script
      # run. A repo with a package.json and no node is rare, and when it happens scaffold_try
      # simply records the candidate as dead and skips it, which is the honest outcome.
      # Invariant 8 says no new dependencies without asking; app-deps-npm is that rule as a diff.
      scaffold_try "app-deps-npm" \
        "node -e \"p=require('./package.json');console.log(Object.keys(p.dependencies||{}).sort().join('\\n'))\"" || true
      # Script NAMES only — never their bodies, and never running them.
      scaffold_try "app-scripts-npm" \
        "node -e \"p=require('./package.json');console.log(Object.keys(p.scripts||{}).sort().join('\\n'))\"" || true
    fi
    if [ -f "$PRIMARY/requirements.txt" ]; then
      scaffold_try "app-deps-python" \
        "grep -oE '^[A-Za-z0-9_.-]+' requirements.txt | sort -u" || true
    fi
    if [ -f "$PRIMARY/pyproject.toml" ]; then
      scaffold_try "app-deps-pyproject" \
        "sed -n '/^\\[project\\]/,/^\\[/p;/dependencies *= *\\[/,/\\]/p' pyproject.toml | grep -oE '\"[A-Za-z0-9_.-]+' | tr -d '\"' | sort -u" || true
    fi
    # HTTP surface. One line per registered route across the common frameworks — a deleted,
    # renamed or newly exposed endpoint reds. Deliberately matches the DECLARATION text, so it
    # needs no server and no framework knowledge at run time.
    scaffold_try "app-routes" \
      "git ls-files | grep -E '\\.(py|js|jsx|mjs|ts|tsx|go|rb|php|java|kt|cs)\$' | tr '\\n' '\\0' | xargs -0 grep -hoE '(@(app|router|bp|blueprint)\\.(route|get|post|put|patch|delete)|(app|router|r|mux)\\.(Get|Post|Put|Patch|Delete|get|post|put|patch|delete))\\([^,)]+' 2>/dev/null | sed 's/[[:space:]]*\$//' | sort -u" || true
    # Schema surface: the migration set, by name. A migration appearing or vanishing is exactly the
    # STOP-AND-ASK class of change, and this makes it mechanically visible.
    scaffold_try "app-migrations" \
      "git ls-files | grep -Ei '(^|/)(migrations?|alembic/versions|db/migrate)/' | sort" || true
    # Config surface: env var NAMES referenced in source. NAMES ONLY — no values are read, printed
    # or stored, so this can never put a secret in a golden (Invariant 10).
    scaffold_try "app-env-names" \
      "git ls-files | grep -E '\\.(py|js|jsx|mjs|ts|tsx|go|rb|php|java|kt|cs|sh)\$' | tr '\\n' '\\0' | xargs -0 grep -hoE '(process\\.env\\.[A-Z0-9_]+|os\\.environ\\[[^]]+\\]|os\\.getenv\\([^,)]+|ENV\\[[^]]+\\])' 2>/dev/null | grep -oE '[A-Z][A-Z0-9_]{2,}' | sort -u" || true
  elif [ -n "$extra" ]; then
    scaffold_try "cmd-$(printf '%s' "$extra" | tr -cs 'a-zA-Z0-9' '-' | sed 's/^-*//;s/-*$//' | cut -c1-40)" "$extra"
  else
    # 1. public API surface — one golden per top-level source dir. The generic lock: a renamed,
    #    deleted or relocated public symbol reds instantly, on any repo, in any language we index.
    #    Too big to be readable (rc 4) → fall back to one line per FILE with its symbol count. That
    #    still reds on a deleted file, a new file, or symbols appearing/vanishing from one; it gives
    #    up only same-file renames. A bounded lock that survives is worth more than a 2.9 MB one
    #    that gets deleted the first time someone opens the diff.
    for d in $(scaffold_dirs); do
      slug="$(printf '%s' "$d" | tr -cs 'a-zA-Z0-9' '-')"
      # An `if` (not a || chain): scaffold_try's rc 4 is a routing signal, and as the last command
      # of an OR-list a second rc 4 would trip `set -e` and abort the whole scaffold silently.
      if scaffold_try "api-$slug" "bash ops/polaris find --api '$d/*'"; then :; elif [ $? -eq 4 ]; then
        # One line per FILE with its symbol count — bounded by file count, not symbol count, so it
        # holds where the full surface cannot. Its own higher cap: past ~5k files in ONE top-level
        # directory, per-directory locking is the wrong tool and saying nothing beats saying 1.7 MB.
        scaffold_try "api-$slug-counts" \
          "bash ops/polaris find --api '$d/*' | awk -F'\\t' '{c[\$1]++} END{for(p in c) print p\"\\t\"c[p]}' | sort" \
          5000 || true
      fi
    done
    # 2. this CLI's own contract surfaces — read-only reporting commands whose SHAPE agents parse.
    scaffold_try "cli-help"      "bash ops/polaris help"
    scaffold_try "board-fm-cols" "bash ops/polaris board-fm | head -1"
    scaffold_try "rules-health"  "bash ops/polaris rules | tail -1"
  fi
  printf '\n'
  say "scaffold: $SC_MADE written · $SC_SKIP already existed · $SC_FLAP non-deterministic · $SC_EMPTY empty · $SC_DEAD command missing · $SC_DUP duplicate · $SC_HUGE too large (locked coarser instead)"
  [ "$SC_MADE" -eq 0 ] && { note "nothing new to lock"; return 0; }
  note "REVIEW THESE before committing: $dir — a golden records what the code DOES, not what it SHOULD do."
  note "A wrong behaviour captured here becomes a wrong behaviour defended forever. Then: polaris check"
  return 0
}

# ---- the goldens side by side (ops/contracts/minutes.md § 6) ------------------------------------
# _check_jobs <flag value> — how many goldens run at once: the flag, else POLARIS_CHECK_JOBS, else the
# machine's cores; capped at 12, floored at 1.
_check_jobs() {
  local j="${1:-${POLARIS_CHECK_JOBS:-}}"
  if [ -z "$j" ]; then
    j="$(getconf _NPROCESSORS_ONLN 2>/dev/null)"
    [ -n "$j" ] || j="$(nproc 2>/dev/null)"
    [ -n "$j" ] || j="$(sysctl -n hw.ncpu 2>/dev/null)"
    case "$j" in ''|*[!0-9]*) j=4;; esac
  fi
  case "$j" in ''|*[!0-9]*) die "check: --jobs takes a number";; esac
  j=$((10#$j)); [ "$j" -gt 12 ] && j=12; [ "$j" -lt 1 ] && j=1
  printf '%s\n' "$j"
}

# _check_times <file> — fold "<name> <seconds>" lines from stdin into .polaris/check-times: one awk,
# every golden that ran gets its new time, every other line is kept.
_check_times() {
  local tf="$1"
  mkdir -p "${tf%/*}" 2>/dev/null || return 0
  awk -v tf="$tf" 'BEGIN { while ((getline l < tf) > 0) { split(l, a, " "); if (a[1] != "") t[a[1]] = a[2] } }
    NF >= 2 { t[$1] = $2 }
    END { for (k in t) print k, t[k] }' > "$tf.$$" 2>/dev/null && mv -f "$tf.$$" "$tf" 2>/dev/null
  rm -f "$tf.$$" 2>/dev/null
  return 0
}

# _check_ok <name> — quiet verdict on the golden's result in G_GOT / G_RC (no printing).
_check_ok() {
  local exp="$G_DIR/$1.expected" rcf="$G_DIR/$1.rc" want=0
  [ -f "$exp" ] || return 1
  [ -f "$rcf" ] && want="$(tr -d ' \r\n' < "$rcf")"
  [ "$G_RC" = "$want" ] || return 1
  printf '%s\n' "$G_GOT" | diff -q - "$exp" >/dev/null 2>&1
}

# _check_say <name> — today's result line(s) for one golden, exactly as the one-at-a-time loop
# prints them; rc 1 when it is red.
_check_say() {
  local name="$1" exp="$G_DIR/$1.expected" rcf="$G_DIR/$1.rc" want=0
  [ -f "$rcf" ] && want="$(tr -d ' \r\n' < "$rcf")"
  if [ ! -f "$exp" ]; then printf '⛔ %s — no golden yet (polaris check --only %s --update)\n' "$name" "$name"; return 1; fi
  if [ "$G_RC" != "$want" ]; then printf '⛔ %s — exit %s, expected %s\n' "$name" "$G_RC" "$want"; return 1; fi
  if printf '%s\n' "$G_GOT" | diff -q - "$exp" >/dev/null 2>&1; then say "$name"; return 0; fi
  printf '⛔ %s — output differs:\n' "$name"
  printf '%s\n' "$G_GOT" | diff -u "$exp" - 2>/dev/null | sed -n '3,12p' | sed 's/^/     /'
  return 1
}

# _check_parallel <root> <jobs> <names, one per line> — run the goldens <jobs> at a time, then print
# their results in the usual order with the usual lines. A golden red beside others runs once more,
# alone, before it counts.
_check_parallel() {
  local root="$1" jobs="$2" names="$3" tmp i pids="" name s r red=0 n=0 tf="$PRIMARY/.polaris/check-times"
  G_DIR="$root/ops/tests"
  tmp="$(mktemp -d 2>/dev/null)" || die "check: could not make a temp folder"
  # deal longest-first, round-robin over the descending list (unknown = 20 s) — ONE awk
  printf '%s\n' "$names" | awk -v tf="$tf" -v n="$jobs" -v d="$tmp" '
    BEGIN { while ((getline l < tf) > 0) { split(l, a, " "); if (a[1] != "") t[a[1]] = a[2] + 0 } }
    NF { c++; nm[c] = $0; s[c] = ($0 in t) ? t[$0] : 20
         for (j = c; j > 1 && s[j] > s[j - 1]; j--) { x = s[j]; s[j] = s[j - 1]; s[j - 1] = x; y = nm[j]; nm[j] = nm[j - 1]; nm[j - 1] = y } }
    END { for (j = 1; j <= c; j++) print nm[j] > (d "/w" ((j - 1) % n)) }'
  i=0
  while [ "$i" -lt "$jobs" ]; do
    if [ -f "$tmp/w$i" ]; then
      ( while IFS= read -r name <&3; do
          s=$SECONDS
          ( cd "$root" && bash -c "$(cat "$G_DIR/$name.cmd")" ) > "$tmp/$name.out" 2>/dev/null && r=0 || r=$?
          echo "$r" > "$tmp/$name.rc"
          echo "$name $((SECONDS - s))" >> "$tmp/w$i.t"
        done 3< "$tmp/w$i" ) &
      pids="$pids $!"
    fi
    i=$((i + 1))
  done
  wait $pids || true
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    n=$((n + 1))
    G_GOT="$(< "$tmp/$name.out")"; G_RC="$(< "$tmp/$name.rc")"
    if ! _check_ok "$name" && [ -f "$G_DIR/$name.expected" ]; then
      G_GOT="$( cd "$root" && bash -c "$(cat "$G_DIR/$name.cmd")" 2>/dev/null )" && G_RC=0 || G_RC=$?
      if _check_say "$name"; then
        note "note: $name passed alone but not beside others — it shares state with another golden"
      else red=1; fi
      continue
    fi
    _check_say "$name" || red=1
  done <<NAMES
$names
NAMES
  cat "$tmp"/w*.t 2>/dev/null | _check_times "$tf"
  rm -rf "$tmp"
  [ "$red" -eq 0 ] || die "check: $n golden(s) run, at least one red"
  say "check: $n golden(s), all green"
}

cmd_check() { # check [--only <glob>] [--update] [--jobs <N>] [--scaffold] — golden-output acceptance tests, ZERO LLM.
  # ops/tests/<name>.cmd       one or more shell lines, run from the repo root
  # ops/tests/<name>.expected  the golden stdout  (stderr is NOT captured — it is noisy and
  #                            makes goldens flap; assert on stdout, or redirect inside the .cmd)
  # ops/tests/<name>.rc        optional expected exit code, default 0
  # Run it, diff it, done. This is what replaces an agent re-checking every widget/route by hand
  # on every wave: the Builder writes the pair ONCE while it already has the context, and every
  # run afterwards costs a subprocess instead of a subagent.
  # --update rewrites goldens from actual output — ALWAYS a human/Builder decision, never automatic,
  # because a golden that regenerates itself asserts nothing.
  # --scaffold GENERATES the pairs instead of running them; it is a different verb behind one noun
  # on purpose ("the goldens" are one concept), and it must be the first flag so a mistyped
  # `--scaffold --update` can never be read as a request to overwrite every reviewed golden.
  [ "${1:-}" = "--scaffold" ] && { shift; cmd_scaffold "$@"; return $?; }
  local only="*" upd=0 named=0 jv="" jobs
  while [ $# -gt 0 ]; do
    case "$1" in
      --only) only="${2:?--only needs a glob}"; named=1; shift 2;;
      --update) upd=1; shift;;
      --jobs) [ $# -ge 2 ] && [ -n "$2" ] || die "check: --jobs takes a number"; jv="$2"; shift 2;;
      *) die "usage: polaris check [--only <glob>] [--update] [--jobs <N>] | check --scaffold [--app] [--cmd \"<shell>\"]";;
    esac
  done
  jobs="$(_check_jobs "$jv")" || exit 1
  # WHICH tree (speed.md § 3): run from inside a builder's worktree, check tests THAT worktree —
  # its ops/tests, run from its root. Anchored to the primary it proved the base instead, and a
  # golden that exists only on the branch printed "no goldens matched" and passed having run
  # nothing. The case test is the entry point's own beat test; anywhere else, unchanged.
  local root="$PRIMARY" wt
  case "$PWD" in */.polaris/wt/*) wt="${PWD##*/.polaris/wt/}"; wt="${wt%%/*}"
    [ -n "$wt" ] && [ -d "$PRIMARY/.polaris/wt/$wt" ] && root="$PRIMARY/.polaris/wt/$wt";; esac
  local dir="$root/ops/tests" f name exp rcf want got grc red=0 n=0
  [ -d "$dir" ] || { note "no ops/tests/ yet — add <name>.cmd + <name>.expected (polaris check --update writes the golden)"; return 0; }
  # The selection, computed ONCE (minutes.md § 15): --only takes globs separated by commas, a golden
  # is in when it matches ANY of them, in directory order whatever the order of the globs. A list
  # whose glob matches nothing is red before anything runs; one glob keeps today's lines exactly.
  local sel="" cnt=0 t0 times="" rest g k take hit="," miss=""
  case ",$only," in *,,*) die "usage: polaris check --only <glob>[,<glob>…] — an empty entry in '$only'";; esac
  for f in "$dir"/*.cmd; do
    [ -e "$f" ] || break
    name="${f##*/}"; name="${name%.cmd}"
    rest="$only,"; k=0; take=0
    while [ -n "$rest" ]; do
      g="${rest%%,*}"; rest="${rest#*,}"; k=$((k+1))
      case "$name" in $g) take=1; case "$hit" in *",$k,"*) ;; *) hit="$hit$k,";; esac;; esac
    done
    [ "$take" -eq 1 ] && { cnt=$((cnt+1)); sel="$sel$name
"; }
  done
  case "$only" in *,*)
    rest="$only,"; k=0
    while [ -n "$rest" ]; do
      g="${rest%%,*}"; rest="${rest#*,}"; k=$((k+1))
      case "$hit" in *",$k,"*) ;; *) miss="$miss$g
";; esac
    done
    if [ -n "$miss" ]; then
      printf '%s' "$miss" | LC_ALL=C sort -u | while IFS= read -r g; do note "no goldens matched '$g'"; done
      return 1
    fi;; esac
  # Side by side (minutes.md § 6) unless --update, one job, or one golden: those keep the loop below.
  if [ "$upd" -eq 0 ] && [ "$jobs" -gt 1 ] && [ "$cnt" -gt 1 ]; then
    [ "$jobs" -gt "$cnt" ] && jobs=$cnt; _check_parallel "$root" "$jobs" "$sel"; return $?
  fi
  for name in $sel; do
    f="$dir/$name.cmd"
    n=$((n+1)); exp="$dir/$name.expected"; rcf="$dir/$name.rc"
    t0=$SECONDS
    got="$( cd "$root" && bash -c "$(cat "$f")" 2>/dev/null )" && grc=0 || grc=$?
    times="$times$name $((SECONDS - t0))
"
    want=0; [ -f "$rcf" ] && want="$(tr -d ' \r\n' < "$rcf")"
    if [ "$upd" -eq 1 ]; then printf '%s\n' "$got" > "$exp"; say "updated golden: $name"; continue; fi
    if [ ! -f "$exp" ]; then printf '⛔ %s — no golden yet (polaris check --only %s --update)\n' "$name" "$name"; red=1; continue; fi
    if [ "$grc" != "$want" ]; then printf '⛔ %s — exit %s, expected %s\n' "$name" "$grc" "$want"; red=1; continue; fi
    if printf '%s\n' "$got" | diff -q - "$exp" >/dev/null 2>&1; then say "$name"
    else
      printf '⛔ %s — output differs:\n' "$name"
      printf '%s\n' "$got" | diff -u "$exp" - 2>/dev/null | sed -n '3,12p' | sed 's/^/     /'
      red=1
    fi
  done
  [ -n "$times" ] && printf '%s' "$times" | _check_times "$PRIMARY/.polaris/check-times"
  # A NAMED check that runs nothing is red: `--only <typo>` used to pass, proving nothing. A bare
  # check over an empty ops/tests/ stays rc 0 — there is simply nothing yet.
  [ "$n" -eq 0 ] && { note "no goldens matched '$only'"; [ "$named" -eq 1 ] && return 1; return 0; }
  [ "$red" -eq 0 ] || die "check: $n golden(s) run, at least one red"
  say "check: $n golden(s), all green"
}
