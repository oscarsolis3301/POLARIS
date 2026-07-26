#!/usr/bin/env python3
"""POLARIS code index — the 1-hop answer to "where is X".

Zero LLM, stdlib only (sqlite3 + re + os), no pip, no compiler. Mirrors dashboard.py's
constraints: any python3 >= 3.8, any platform.

Why this exists: an agent hunting for a symbol runs 6-15 Grep/Read round trips and burns
15-25k tokens. One `polaris find refreshToken` returns `src/auth/session.ts:142  fn  export
function refreshToken(...)` for ~40 tokens. The win is the OUTPUT SHAPE, not raw speed —
which is exactly why this is python and not a native binary (ops/contracts/code-index.md).

Storage: .polaris/index.db (gitignored with the rest of .polaris/).
Three tiers, all emitting byte-identical output:
  1 sqlite + FTS5   -t uses MATCH
  2 sqlite, no FTS5 -t uses LIKE over the body column
  3 no sqlite       live scan, no persistence — slower, never wrong
"""
import hashlib
import os
import re
import subprocess
import sys
import time

try:
    import sqlite3
except ImportError:                                   # tier 3
    sqlite3 = None

if hasattr(sys.stdout, "reconfigure"):                # Windows cp1252 would mangle UTF-8 paths
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

SCHEMA = 2        # 2: files.mtime/size — the stat cache that keeps `find` O(changed), not O(repo)
MAXLINE = 4000        # skip minified/generated monsters
SIGMAX = 200

# ---------------------------------------------------------------- language table
# ONE data table. Adding a language = adding rows. No per-language parsers, ever.
EXT = {
    ".py": "py", ".pyi": "py",
    ".js": "js", ".jsx": "js", ".mjs": "js", ".cjs": "js",
    ".ts": "ts", ".tsx": "ts", ".mts": "ts", ".cts": "ts",
    ".go": "go", ".rs": "rs", ".java": "java", ".kt": "kt", ".kts": "kt",
    ".c": "c", ".h": "c", ".cc": "cpp", ".cpp": "cpp", ".cxx": "cpp",
    ".hpp": "cpp", ".hh": "cpp", ".cs": "cs", ".rb": "rb", ".php": "php",
    ".sh": "sh", ".bash": "sh", ".zsh": "sh",
    ".sql": "sql", ".css": "css", ".scss": "css", ".sass": "css", ".less": "css",
    ".md": "md", ".markdown": "md", ".yml": "yaml", ".yaml": "yaml",
    ".json": "json", ".toml": "toml", ".tsv": "tsv",
}
SHEBANG = [("python", "py"), ("node", "js"), ("bash", "sh"), ("sh", "sh"), ("ruby", "rb")]

# (langs, kind, pattern) — ORDER MATTERS: first match on a line wins.
SYMS = [
    ("py", "class", r"^\s*class\s+(?P<n>\w+)"),
    ("py", "fn", r"^\s*(?:async\s+)?def\s+(?P<n>\w+)"),
    ("py", "const", r"^(?P<n>[A-Z][A-Z0-9_]{2,})\s*(?::[^=]+)?\s*="),
    ("ts", "type", r"^\s*(?:export\s+)?(?:declare\s+)?(?:type|interface|enum)\s+(?P<n>\w+)"),
    ("js ts", "class", r"^\s*(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+(?P<n>\w+)"),
    ("js ts", "fn", r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s+(?P<n>\w+)"),
    ("js ts", "fn", r"^\s*(?:export\s+)?(?:const|let|var)\s+(?P<n>\w+)\s*(?::[^=]*)?=\s*(?:async\s*)?(?:\([^)]*\)|\w+)\s*=>"),
    ("js ts", "fn", r"^\s*(?:export\s+)?(?:const|let|var)\s+(?P<n>\w+)\s*(?::[^=]*)?=\s*(?:async\s+)?function"),
    ("js ts", "const", r"^\s*export\s+(?:const|let|var)\s+(?P<n>\w+)"),
    ("go", "fn", r"^func\s+(?:\(\s*\w+\s+\*?(?P<p>\w+)\s*\)\s*)?(?P<n>\w+)"),
    ("go", "type", r"^type\s+(?P<n>\w+)"),
    ("rs", "fn", r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(?P<n>\w+)"),
    ("rs", "type", r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:struct|enum|trait|union|type)\s+(?P<n>\w+)"),
    ("rs", "impl", r"^\s*impl(?:<[^>]*>)?\s+(?:[\w:]+\s+for\s+)?(?P<n>[\w:]+)"),
    ("rs", "macro", r"^\s*macro_rules!\s*(?P<n>\w+)"),
    ("java kt cs", "type", r"^\s*(?:(?:public|private|protected|internal|abstract|final|sealed|static|open|data|partial)\s+)*(?:class|interface|enum|record|object|struct)\s+(?P<n>\w+)"),
    ("kt", "fn", r"^\s*(?:(?:public|private|internal|protected|open|override|suspend|inline|operator)\s+)*fun\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?(?P<n>\w+)\s*\("),
    ("java", "fn", r"^\s+(?:(?:public|protected|private|static|final|synchronized|abstract|native|default)\s+)+[\w<>\[\].,?]+\s+(?P<n>\w+)\s*\("),
    ("cs", "fn", r"^\s*(?:(?:public|private|protected|internal|static|virtual|override|async|sealed|partial)\s+)+[\w<>\[\],.?]+\s+(?P<n>\w+)\s*\("),
    ("c cpp", "macro", r"^\s*#\s*define\s+(?P<n>\w+)"),
    ("c cpp", "type", r"^\s*(?:typedef\s+)?(?:struct|union|enum|class|namespace)\s+(?P<n>\w+)"),
    ("rb", "class", r"^\s*(?:class|module)\s+(?P<n>[\w:]+)"),
    ("rb", "fn", r"^\s*def\s+(?:self\.)?(?P<n>[\w?!=\[\]]+)"),
    ("php", "class", r"^\s*(?:(?:abstract|final)\s+)?(?:class|interface|trait|enum)\s+(?P<n>\w+)"),
    ("php", "fn", r"^\s*(?:(?:public|private|protected|static|abstract|final)\s+)*function\s+(?P<n>\w+)"),
    ("sh", "fn", r"^\s*(?:function\s+)?(?P<n>[A-Za-z_][\w:.-]*)\s*\(\)\s*\{"),
    # (?i:...) scoped, NOT a leading (?i) — a global flag mid-union is a DeprecationWarning in 3.11+
    ("sql", "table", r"^(?i:\s*CREATE\s+(?:OR\s+REPLACE\s+)?(?:TEMP\w*\s+)?(?:VIRTUAL\s+)?(?:TABLE|VIEW|INDEX|FUNCTION|PROCEDURE|TRIGGER)\s+(?:IF\s+NOT\s+EXISTS\s+)?)(?P<n>[\w.\"`\[\]]+)"),
    ("css", "var", r"^\s*(?P<n>--[\w-]+)\s*:"),
    ("css", "rule", r"^\s*(?P<n>[.#][\w-]+)[^{}]*\{"),
    ("md", "heading", r"^(?P<p>#{1,4})\s+(?P<n>.+?)\s*#*$"),
    ("yaml toml", "key", r"^(?P<n>[A-Za-z_][\w.-]*)\s*[:=]"),
    ("tsv", "key", r"^(?P<n>[^\t#][^\t]*)\t"),
]

IMPORTS = [
    ("py", r"^\s*(?:from\s+(?P<n>[.\w]+)\s+import|import\s+(?P<n2>[.\w]+))"),
    ("js ts", r"""^\s*(?:import\b[^'"]*|export\b[^'"]*from\s*)['"](?P<n>[^'"]+)['"]"""),
    ("js ts", r"""require\(\s*['"](?P<n>[^'"]+)['"]\s*\)"""),
    ("go", r'^\s*(?:import\s+)?(?:[\w.]+\s+)?"(?P<n>[\w./-]+)"'),
    ("rs", r"^\s*(?:pub\s+)?use\s+(?P<n>[\w:]+)"),
    ("java kt", r"^\s*import\s+(?:static\s+)?(?P<n>[\w.]+)"),
    ("c cpp", r"""^\s*#\s*include\s+["<](?P<n>[^">]+)[">]"""),
    ("cs", r"^\s*using\s+(?:static\s+)?(?P<n>[\w.]+)"),
    ("rb", r"""^\s*require(?:_relative)?\s+['"](?P<n>[^'"]+)['"]"""),
    ("php", r"""^\s*(?:use|require(?:_once)?|include(?:_once)?)\s+['"]?(?P<n>[\w\\/.]+)"""),
    ("sh", r"^\s*(?:\.|source)\s+(?P<n>\S+)"),
    ("css", r"""^\s*@import\s+['"](?P<n>[^'"]+)['"]"""),
]

KIND_W = {"fn": 10, "class": 10, "type": 10, "impl": 10, "method": 6,
          "const": 3, "var": 3, "macro": 3, "table": 3,
          "heading": 1, "key": 1, "rule": 1}

TESTY = re.compile(r"(^|/)(tests?|spec|__tests__)/|(^|/)test_|_test\.|\.test\.|\.spec\.")
VENDOR = re.compile(r"(^|/)(vendor|node_modules|dist|build|target|archive|third_party)/|\.min\.")


def _compile(table):
    """One union regex per language. Named groups are uniquified so the union stays legal.

    Measured 833k lines/s union vs 591k for a naive per-pattern loop — and the gap widens
    with every rule added, so this is what keeps the table cheap to extend.
    """
    bylang = {}
    for i, row in enumerate(table):
        langs, rest = row[0], row[1:]
        for lang in langs.split():
            bylang.setdefault(lang, []).append((i,) + rest)
    out = {}
    for lang, rows in bylang.items():
        parts, meta = [], {}
        for idx, (i, *rest) in enumerate(rows):
            kind = rest[0] if len(rest) == 2 else None
            pat = rest[-1]
            tag = "r%d" % idx
            # uniquify inner group names so several patterns can share 'n'
            pat = re.sub(r"\(\?P<(\w+)>", lambda m, t=tag: "(?P<%s_%s>" % (m.group(1), t), pat)
            parts.append("(?P<%s>%s)" % (tag, pat))
            meta[tag] = kind
        out[lang] = (re.compile("|".join(parts)), meta)
    return out


SYM_RE = _compile(SYMS)
IMP_RE = _compile(IMPORTS)


def lang_of(path, first=""):
    ext = os.path.splitext(path)[1].lower()
    if ext in EXT:
        return EXT[ext]
    if first.startswith("#!"):
        for needle, lang in SHEBANG:
            if needle in first:
                return lang
    return ""


def scan_text(text, lang):
    """-> (symbols, imports). symbols: (name, kind, line, sig). imports: (raw, line)."""
    syms, imps = [], []
    sre = SYM_RE.get(lang)
    ire = IMP_RE.get(lang)
    if not sre and not ire:
        return syms, imps
    for ln, line in enumerate(text.splitlines(), 1):
        if len(line) > MAXLINE:
            continue
        if sre:
            m = sre[0].match(line)
            if m:
                for tag, kind in sre[1].items():
                    if m.groupdict().get(tag) is None:
                        continue
                    name = m.groupdict().get("n_%s" % tag)
                    if name:
                        sig = line.strip().replace("\t", " ")[:SIGMAX]
                        syms.append((name, kind, ln, sig))
                    break
        if ire:
            m = ire[0].match(line) or (ire[0].search(line) if lang in ("js", "ts") else None)
            if m:
                d = m.groupdict()
                raw = None
                for k, v in d.items():
                    if v and (k.startswith("n_") or k.startswith("n2_")):
                        raw = v
                        break
                if raw:
                    imps.append((raw, ln))
    return syms, imps


# ---------------------------------------------------------------- selfcheck
FIXTURES = [
    ("a.py", "class Alpha:\n    def beta(self):\n        pass\n", [("Alpha", "class", 1), ("beta", "fn", 2)]),
    ("a.ts", "export function gamma(x: number) {}\nexport const delta = (y) => y\ninterface Eps {}\n",
     [("gamma", "fn", 1), ("delta", "fn", 2), ("Eps", "type", 3)]),
    ("a.go", "func Zeta() {}\ntype Eta struct{}\n", [("Zeta", "fn", 1), ("Eta", "type", 2)]),
    ("a.rs", "pub fn theta() {}\npub struct Iota;\n", [("theta", "fn", 1), ("Iota", "type", 2)]),
    ("a.sh", "kappa() {\n  :\n}\n", [("kappa", "fn", 1)]),
    ("a.rb", "class Lambda\n  def mu\n  end\nend\n", [("Lambda", "class", 1), ("mu", "fn", 2)]),
    ("a.java", "public class Nu {\n    public void xi() {}\n}\n", [("Nu", "type", 1), ("xi", "fn", 2)]),
    ("a.cs", "public class Omicron {\n    public void Pi() {}\n}\n", [("Omicron", "type", 1), ("Pi", "fn", 2)]),
    ("a.c", "#define SIGMA 1\nstruct Tau { int x; };\n", [("SIGMA", "macro", 1), ("Tau", "type", 2)]),
    ("a.php", "<?php\nclass Upsilon {\n  public function phi() {}\n}\n", [("Upsilon", "class", 2), ("phi", "fn", 3)]),
    # own-line declarations — the shape the var/rule patterns target (inline `{ --x: 1px }` is
    # deliberately not matched: it would need a full CSS parser to do without false positives)
    ("a.css", ":root {\n  --chi: 1px;\n}\n.psi { color: red; }\n", [("--chi", "var", 2), (".psi", "rule", 4)]),
    ("a.md", "# Omega\n## Alpha2\n", [("Omega", "heading", 1), ("Alpha2", "heading", 2)]),
    ("a.kt", "class Beta2 {\n    fun gamma2() {}\n}\n", [("Beta2", "type", 1), ("gamma2", "fn", 2)]),
    ("a.sql", "CREATE TABLE delta2 (id INT);\n", [("delta2", "table", 1)]),
]


def selfcheck():
    bad = 0
    for name, text, want in FIXTURES:
        lang = lang_of(name)
        got, _ = scan_text(text, lang)
        got_set = {(n, k, l) for n, k, l, _ in got}
        for w in want:
            if w not in got_set:
                print("FAIL %s: expected %r, got %r" % (name, w, sorted(got_set)))
                bad += 1
    imp_cases = [("a.py", "from x.y import z\n", "x.y"),
                 ("a.ts", "import a from './core'\n", "./core"),
                 ("a.sh", ". ops/lib/core.sh\n", "ops/lib/core.sh"),
                 ("a.go", 'import "fmt"\n', "fmt")]
    for name, text, want in imp_cases:
        _, imps = scan_text(text, lang_of(name))
        if not any(r == want for r, _ in imps):
            print("FAIL import %s: expected %r, got %r" % (name, want, imps))
            bad += 1
    # resolve_import cases. The scanner above only proves we EXTRACT an import spec; these prove we
    # turn it into the right file, which is what `find --importers` actually answers. Pure-function,
    # so they cost nothing to run, and they pin the two rules that are easy to get subtly wrong:
    # a variable-built path resolving through its literal tail, and a self-hosting repo's mirrored
    # trees resolving to their OWN copy instead of each other's.
    paths = {"src/lib/util.js": 1, "vendor/src/lib/util.js": 2, "src/lib/helper.sh": 3,
             "ops/lib/core.sh": 4, "kit/ops/lib/core.sh": 5,
             "app/a/conf.js": 6, "app/b/conf.js": 7}
    bybase = {}
    for _p, _i in paths.items():
        bybase.setdefault(os.path.basename(_p), []).append((_p, _i))
    res_cases = [
        ('"$ROOT/src/lib/helper.sh"', "run.sh", 3),        # variable prefix, literal tail
        ("./lib/util.js", "src/app.js", 1),                # relative, same tree
        ("./lib/util.js", "vendor/src/app.js", 2),         # relative, mirrored tree stays its own
        ('"$OPS_DIR/lib/core.sh"', "ops/polaris", 4),      # self-hosting: nearest tree wins
        ('"$OPS_DIR/lib/core.sh"', "kit/ops/polaris", 5),  # ...and the mirror gets its own
        ('"$R/a/conf.js"', "app/main.js", 6),              # tail disambiguates where basename cannot:
                                                           # two conf.js are EQUALLY close to app/,
                                                           # so tree distance ties and only the
                                                           # literal tail "a/conf.js" is unique
        ("core.sh", "ops/polaris", 4),                     # bare basename (`. core.sh`, `#include
                                                           # "core.h"`): ambiguous in a self-hosting
                                                           # repo, and only tree distance decides it
        ('"$OPS_DIR/lib/$_m.sh"', "ops/polaris", None),    # no literal tail -> honestly unresolved
        ("os", "a.py", None),                              # stdlib is external, and stays NULL
    ]
    for raw, src, want in res_cases:
        got = resolve_import(raw, src, paths, bybase)
        if got != want:
            print("FAIL resolve %r from %s: expected %r, got %r" % (raw, src, want, got))
            bad += 1
    if bad:
        print("selfcheck FAILED (%d)" % bad)
        return 1
    print("selfcheck ok (%d language fixtures, %d import cases, %d resolve cases)"
          % (len(FIXTURES), len(imp_cases), len(res_cases)))
    return 0


# ---------------------------------------------------------------- repo / db
def sh(args, cwd):
    try:
        p = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return p.stdout.decode("utf-8", "replace")
    except Exception:
        return ""


def tracked(root):
    out = sh(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], root)
    return [p for p in out.split("\0") if p and not p.startswith(".polaris/")]


def read(root, rel):
    try:
        with open(os.path.join(root, rel), "rb") as f:
            b = f.read()
        if b"\0" in b[:8000]:
            return None
        return b.decode("utf-8", "replace")
    except Exception:
        return None


def fts_ok(con):
    try:
        con.execute("CREATE VIRTUAL TABLE IF NOT EXISTS _p USING fts5(x)")
        con.execute("DROP TABLE _p")
        return True
    except Exception:
        return False


DDL = """
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS files(
  id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, hash TEXT NOT NULL,
  lang TEXT NOT NULL, loc INTEGER NOT NULL, churn INTEGER DEFAULT 0,
  fanin INTEGER DEFAULT 0, flags INTEGER DEFAULT 0,
  mtime REAL DEFAULT 0, size INTEGER DEFAULT -1);
CREATE INDEX IF NOT EXISTS files_lang ON files(lang);
CREATE TABLE IF NOT EXISTS symbols(
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, lname TEXT NOT NULL, kind TEXT NOT NULL,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  line INTEGER NOT NULL, sig TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS symbols_lname ON symbols(lname);
CREATE INDEX IF NOT EXISTS symbols_file ON symbols(file_id);
CREATE TABLE IF NOT EXISTS edges(
  src_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  line INTEGER NOT NULL, raw TEXT NOT NULL, dst_id INTEGER);
CREATE INDEX IF NOT EXISTS edges_src ON edges(src_id);
CREATE INDEX IF NOT EXISTS edges_dst ON edges(dst_id);
"""


def connect(root, create=True):
    d = os.path.join(root, ".polaris")
    if create:
        os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "index.db")
    if not create and not os.path.exists(p):
        return None, False
    con = sqlite3.connect(p)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA synchronous=NORMAL")
    con.execute("PRAGMA foreign_keys=ON")
    con.executescript(DDL)
    have = fts_ok(con)
    if have:
        con.execute("CREATE VIRTUAL TABLE IF NOT EXISTS ftext USING fts5(body)")
    else:
        con.execute("CREATE TABLE IF NOT EXISTS ftext(rowid INTEGER PRIMARY KEY, body TEXT)")
    con.execute("INSERT OR REPLACE INTO meta VALUES('fts',?)", ("1" if have else "0",))
    return con, have


def resolve_import(raw, src, paths, bybase):
    """Best-effort import spec -> indexed path. Unresolvable = external package = NULL.

    Deliberately conservative: a wrong edge is worse than a missing one, because --importers
    is used to decide what a change can break.
    """
    raw = raw.strip().strip("'\"")
    if not raw:
        return None
    d = os.path.dirname(src)
    cands = []
    if raw.startswith("."):
        if raw.startswith("./") or raw.startswith("../"):        # js/ts/sh relative
            base = os.path.normpath(os.path.join(d, raw)).replace("\\", "/")
            cands += [base] + [base + e for e in
                               (".ts", ".tsx", ".js", ".jsx", ".mjs", ".py", ".sh", ".css")]
            cands += [base + "/index" + e for e in (".ts", ".tsx", ".js", ".jsx")]
        else:                                                     # python relative: .mod / ..pkg.mod
            up = len(raw) - len(raw.lstrip("."))
            rest = raw[up:].replace(".", "/")
            base = d
            for _ in range(up - 1):
                base = os.path.dirname(base)
            cands.append(os.path.normpath(os.path.join(base, rest)).replace("\\", "/") + ".py")
    elif "/" in raw:                                              # repo-relative (sh source, c include)
        cands += [raw, os.path.normpath(os.path.join(d, raw)).replace("\\", "/")]
        cands += [raw + e for e in (".ts", ".js", ".py", ".sh")]
    elif "." in raw and not raw.endswith((".h", ".hpp")):         # dotted module: py/java/cs
        cands.append(raw.replace(".", "/") + ".py")
        cands.append(raw.replace(".", "/") + ".java")
    for c in cands:
        if c in paths:
            return paths[c]

    # Variable-built paths. Shell sources its modules as `. "$OPS_DIR/lib/search.sh"`, and CI and
    # Makefiles do the same with $(VAR) — none of which is a literal path, so every edge in a repo
    # written that way resolved to NULL. This repo indexed 38 edges and resolved 0 of them, which
    # silently broke `find --importers`, the command PLANNER.md names as the way to prove
    # files_owned disjointness. Drop the variable segments and match on the literal tail; a segment
    # that is ITSELF a variable (`lib/$_m.sh`) leaves no usable tail and stays unresolved, which is
    # the correct answer rather than a guess.
    tail = ""
    if "$" in raw:
        segs = [s for s in raw.split("/") if s and "$" not in s]
        tail = "/".join(segs)
    if tail:
        direct = os.path.normpath(os.path.join(d, tail)).replace("\\", "/")
        if tail in paths:
            return paths[tail]
        if direct in paths:
            return paths[direct]
        best = _closest([p for p in paths if p.endswith("/" + tail)], src)
        if best:
            return paths[best]

    # last resort: unique basename match (catches `#include "core.h"`, `source core.sh`)
    hits = bybase.get(os.path.basename(raw), [])
    if len(hits) == 1:
        return hits[0][1]
    if len(hits) > 1:
        best = _closest([h[0] for h in hits], src)
        if best:
            return dict(hits).get(best) or paths.get(best)
    return None


def _closest(candidates, src):
    """The candidate sharing the longest directory prefix with src, or None if it is a tie.

    A self-hosting repo has the same file twice — `ops/lib/search.sh` and its source
    `kit/ops/lib/search.sh` — so a basename or tail match is routinely ambiguous. The right answer
    is the one in the SAME tree as the importer, and when two are equally close there is no right
    answer and we return None: an edge into the wrong tree would make --importers point a Planner
    at the mirror of the file that actually changed.
    """
    if not candidates:
        return None
    sd = os.path.dirname(src).split("/")
    scored = []
    for c in candidates:
        cd = os.path.dirname(c).split("/")
        n = 0
        for a, b in zip(sd, cd):
            if a != b:
                break
            n += 1
        scored.append((n, c))
    scored.sort(key=lambda t: -t[0])
    if len(scored) > 1 and scored[0][0] == scored[1][0]:
        return None
    return scored[0][1]


def flags_for(path):
    f = 0
    if TESTY.search(path):
        f |= 1
    if VENDOR.search(path):
        f |= 2
    return f


def build(root, full=False):
    con, have_fts = connect(root)
    cur = con.cursor()
    ver = cur.execute("SELECT v FROM meta WHERE k='schema'").fetchone()
    if not ver or int(ver[0]) != SCHEMA:
        # A schema change alters the table SHAPE, and `DELETE FROM` cannot add a missing column —
        # an older db would then fail every query with "no such column". Discard the file and
        # reconnect: a schema bump means a full rebuild regardless, so nothing is lost but time.
        con.close()
        d = os.path.join(root, ".polaris")
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(os.path.join(d, "index.db" + suffix))
            except OSError:
                pass
        con, have_fts = connect(root)
        cur = con.cursor()
        cur.execute("INSERT OR REPLACE INTO meta VALUES('schema',?)", (str(SCHEMA),))
    elif full:
        for t in ("symbols", "edges", "files", "ftext"):
            try:
                cur.execute("DELETE FROM %s" % t)
            except Exception:
                pass
    known = {p: (i, h, mt, sz) for i, p, h, mt, sz
             in cur.execute("SELECT id,path,hash,mtime,size FROM files")}
    seen, changed = set(), 0
    # `find` calls build() on EVERY lookup, so this loop is the hot path and it scales with the
    # REPO, not the change. Reading + SHA-1ing every tracked file cost 0.100s here (128 files) and
    # would cost ~4s on a 5k-file repo — per lookup. So: stat() first (~100x cheaper than read+hash)
    # and skip untouched files entirely. Same trick, same reason, as git's stat cache.
    now = time.time()
    for rel in tracked(root):
        # `git ls-files --cached` lists a file DELETED from the worktree but not yet staged. Adding
        # it to `seen` kept it in the index with all its symbols, so `find` went on reporting code
        # that no longer existed and a deleted file never reddened a golden. Stat first: no stat,
        # no `seen`, and the prune below removes it.
        try:
            st = os.stat(os.path.join(root, rel))
        except OSError:
            continue
        seen.add(rel)
        prev = known.get(rel)
        if prev:
            # "Racily clean" (git's term): a file written in the last second may share its mtime
            # with the indexed copy while differing in content, and same-second same-size edits do
            # happen (a scripted sed, a formatter). Below that age we do not trust stat — we hash.
            if (st.st_size == prev[3] and st.st_mtime == prev[2]
                    and now - st.st_mtime > 1.0):
                continue
        text = read(root, rel)
        if text is None:
            continue
        first = text[:200].split("\n", 1)[0]
        lang = lang_of(rel, first)
        if not lang:
            continue
        h = hashlib.sha1(text.encode("utf-8", "replace")).hexdigest()
        if prev and prev[1] == h:
            # Content is identical but stat drifted (checkout, touch, clock skew). Re-stamp the
            # stat pair so the NEXT lookup takes the cheap path instead of re-hashing forever.
            cur.execute("UPDATE files SET mtime=?,size=? WHERE id=?",
                        (st.st_mtime, st.st_size, prev[0]))
            continue
        changed += 1
        if prev:
            cur.execute("DELETE FROM files WHERE id=?", (prev[0],))
            try:
                cur.execute("DELETE FROM ftext WHERE rowid=?", (prev[0],))
            except Exception:
                pass
        loc = text.count("\n") + 1
        cur.execute("INSERT INTO files(path,hash,lang,loc,flags,mtime,size) VALUES(?,?,?,?,?,?,?)",
                    (rel, h, lang, loc, flags_for(rel), st.st_mtime, st.st_size))
        fid = cur.lastrowid
        syms, imps = scan_text(text, lang)
        if syms:
            cur.executemany(
                "INSERT INTO symbols(name,lname,kind,file_id,line,sig) VALUES(?,?,?,?,?,?)",
                [(n, n.lower(), k, fid, l, s) for n, k, l, s in syms])
        if imps:
            cur.executemany("INSERT INTO edges(src_id,line,raw) VALUES(?,?,?)",
                            [(fid, l, r) for r, l in imps])
        try:
            cur.execute("INSERT INTO ftext(rowid,body) VALUES(?,?)", (fid, text))
        except Exception:
            pass
    gone = set(known) - seen
    for rel in gone:
        cur.execute("DELETE FROM files WHERE id=?", (known[rel][0],))
        try:
            cur.execute("DELETE FROM ftext WHERE rowid=?", (known[rel][0],))
        except Exception:
            pass
    # churn: commits touching each path in the last 180 days (ranking only, never correctness)
    if full or changed:
        log = sh(["git", "log", "--since=180.days", "--name-only", "--pretty=format:"], root)
        counts = {}
        for line in log.split("\n"):
            line = line.strip()
            if line:
                counts[line] = counts.get(line, 0) + 1
        if counts:
            cur.executemany("UPDATE files SET churn=? WHERE path=?",
                            [(v, k) for k, v in counts.items()])
        cur.execute("UPDATE files SET fanin=(SELECT COUNT(DISTINCT src_id) FROM edges "
                    "WHERE edges.dst_id=files.id)")
    # resolve import edges -> dst_id. Without this --importers/--imports return nothing, since
    # dst_id starts NULL. Unresolved (external package) legitimately stays NULL.
    if full or changed or gone:
        paths = {p: i for i, p in cur.execute("SELECT id,path FROM files")}
        bybase = {}
        for p, i in paths.items():
            bybase.setdefault(os.path.basename(p), []).append((p, i))
        byid = {i: p for p, i in paths.items()}
        upd = []
        # fetchall() first: re-using `cur` for a lookup INSIDE its own iteration silently resets
        # the outer result set, which is why every edge resolved to NULL before this.
        for eid_src, line, raw in cur.execute(
                "SELECT src_id,line,raw FROM edges WHERE dst_id IS NULL").fetchall():
            src = byid.get(eid_src)
            if not src:
                continue
            dst = resolve_import(raw, src, paths, bybase)
            if dst and dst != eid_src:          # never self-edge
                upd.append((dst, eid_src, line, raw))
        if upd:
            cur.executemany("UPDATE edges SET dst_id=? WHERE src_id=? AND line=? AND raw=?", upd)
        cur.execute("UPDATE files SET fanin=(SELECT COUNT(DISTINCT src_id) FROM edges "
                    "WHERE edges.dst_id=files.id)")
    head = sh(["git", "rev-parse", "HEAD"], root).strip()
    cur.execute("INSERT OR REPLACE INTO meta VALUES('head',?)", (head,))
    con.commit()
    return con, have_fts, changed, len(gone)


# ---------------------------------------------------------------- queries
def score(name, q, kind, churn, fanin, flags):
    s = 0
    if name == q:
        s += 100
    if name.lower() == q.lower():
        s += 80
    if name.lower().startswith(q.lower()):
        s += 50
    if q.lower() in name.lower():
        s += 20
    s += KIND_W.get(kind, 0)
    s += min(churn, 20) + min(2 * fanin, 20)
    if flags & 1:
        s -= 15
    if flags & 2:
        s -= 25
    return s


def cmd_find(root, args):
    con, have_fts, _, _ = build(root)
    cur = con.cursor()
    n = 20
    if "-n" in args:
        i = args.index("-n")
        n = int(args[i + 1])
        del args[i:i + 2]
    if not args:
        return usage()
    mode = "sym"
    if args[0] in ("-f", "-t", "--importers", "--imports", "--api"):
        mode, args = args[0], args[1:]
    if not args:
        return usage()
    q = args[0]
    rows = []
    if mode == "--api":
        # The one output shape STABLE enough to be a golden (ops/tests/): the public symbol surface
        # of a path glob, `path<TAB>kind<TAB>name`, sorted, with every volatile field left out.
        # Line numbers move when anything above them is edited and `churn` moves with git history,
        # so both are excluded on purpose — a lock that reds on unrelated commits gets deleted.
        # Leading-underscore names are dropped as private (py/js/ts/sh convention alike).
        # Goes red exactly when a public symbol is added, removed, renamed, or moved file.
        pat = q.replace("*", "%") if "*" in q else "%" + q + "%"
        seen = set()
        for path, kind, name in cur.execute(
                "SELECT f.path,s.kind,s.name FROM symbols s JOIN files f ON f.id=s.file_id "
                "WHERE f.path LIKE ?", (pat,)):
            if name.startswith("_"):
                continue
            key = (path, kind, name)
            if key in seen:
                continue
            seen.add(key)
            rows.append((0, path, 0, "%s\t%s\t%s" % (path, kind, name)))
        rows.sort(key=lambda r: r[3])
        if not rows:
            return 1
        for r in rows:                       # NEVER truncated by -n: a partial surface is a lie
            print(r[3])
        return 0
    if mode == "sym":
        like = "%" + q.lower() + "%"
        for name, kind, line, sig, path, churn, fanin, flags in cur.execute(
                "SELECT s.name,s.kind,s.line,s.sig,f.path,f.churn,f.fanin,f.flags "
                "FROM symbols s JOIN files f ON f.id=s.file_id WHERE s.lname LIKE ?", (like,)):
            rows.append((-score(name, q, kind, churn, fanin, flags), path, line,
                         "%s:%d\t%s\t%s\t%s" % (path, line, kind, name, sig)))
    elif mode == "-f":
        pat = "%" + q.replace("*", "%") + "%" if "*" not in q else q.replace("*", "%")
        for path, loc, lang, churn, fanin in cur.execute(
                "SELECT path,loc,lang,churn,fanin FROM files WHERE path LIKE ?", (pat,)):
            rows.append((-churn, path, 0, "%s\t%d\t%s\tchurn:%d\tin:%d" % (path, loc, lang, churn, fanin)))
    elif mode == "-t":
        ids = []
        if have_fts:
            try:
                ids = [r[0] for r in cur.execute("SELECT rowid FROM ftext WHERE ftext MATCH ?", (q,))]
            except Exception:
                ids = []
        if not ids:
            ids = [r[0] for r in cur.execute("SELECT rowid FROM ftext WHERE body LIKE ?",
                                             ("%" + q + "%",))]
        for fid in ids[:50]:
            r = cur.execute("SELECT path FROM files WHERE id=?", (fid,)).fetchone()
            if not r:
                continue
            text = read(root, r[0]) or ""
            for ln, line in enumerate(text.splitlines(), 1):
                if q.lower() in line.lower():
                    rows.append((0, r[0], ln, "%s:%d\t%s" % (r[0], ln, line.strip()[:160])))
    else:
        f = cur.execute("SELECT id FROM files WHERE path=?", (q,)).fetchone()
        if not f:
            return 1
        if mode == "--importers":
            for path, line, raw in cur.execute(
                    "SELECT f.path,e.line,e.raw FROM edges e JOIN files f ON f.id=e.src_id "
                    "WHERE e.dst_id=?", (f[0],)):
                rows.append((0, path, line, "%s:%d\t%s" % (path, line, raw)))
        else:
            for raw, line, dst in cur.execute(
                    "SELECT raw,line,dst_id FROM edges WHERE src_id=?", (f[0],)):
                d = "-"
                if dst:
                    r = cur.execute("SELECT path FROM files WHERE id=?", (dst,)).fetchone()
                    d = r[0] if r else "-"
                rows.append((0, d, line, "%s\t%s\t%d" % (d, raw, line)))
    rows.sort(key=lambda r: (r[0], r[1], r[2]))
    if not rows:
        return 1
    for r in rows[:n]:
        print(r[3])
    if len(rows) > n:
        print("# %d more — polaris find %s -n %d" % (len(rows) - n, q, min(len(rows), 200)))
    return 0


def cmd_show(root, spec):
    if "#" in spec:
        path, sym = spec.split("#", 1)
        con, _, _, _ = build(root)
        r = con.execute("SELECT s.line,s.kind FROM symbols s JOIN files f ON f.id=s.file_id "
                        "WHERE f.path=? AND s.name=? ORDER BY s.line", (path, sym)).fetchone()
        if not r:
            return 1
        start, kind = r[0], r[1]
    elif ":" in spec:
        path, _, ln = spec.rpartition(":")
        start, kind, sym = int(ln), "-", "-"
    else:
        return usage()
    text = read(root, path)
    if text is None:
        return 1
    lines = text.splitlines()
    base = lines[start - 1] if start <= len(lines) else ""
    indent = len(base) - len(base.lstrip())
    end = start
    for i in range(start, min(len(lines), start + 400)):
        s = lines[i]
        if not s.strip() or s.lstrip().startswith(("#", "//")):
            continue
        if len(s) - len(s.lstrip()) <= indent and i > start - 1:
            # the dedented line that ends the block IS part of it when it is just a closing
            # delimiter (`}`, `)`, `end`, `fi`) — otherwise `show` prints a function without
            # its own closing brace, which reads as truncated output.
            if s.strip() in ("}", ")", "};", ");", "end", "fi", "done", "esac", "}}"):
                end = i + 1
            break
        end = i + 1
    print("%s:%d-%d\t%s\t%s" % (path, start, end, kind, sym if "#" in spec else "-"))
    for s in lines[start - 1:end]:
        print(s)
    return 0


def cmd_stats(root):
    con, have_fts, _, _ = build(root)
    cur = con.cursor()
    nf = cur.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    ns = cur.execute("SELECT COUNT(*) FROM symbols").fetchone()[0]
    langs = ",".join(r[0] for r in cur.execute(
        "SELECT lang FROM files GROUP BY lang ORDER BY COUNT(*) DESC LIMIT 6"))
    print("files:%d\tsymbols:%d\tlangs:%s\ttier:%s" %
          (nf, ns, langs, "fts5" if have_fts else "like"))
    return 0


def usage():
    sys.stderr.write(
        "usage: index.py find <symbol>|-f <glob>|-t <text>|--importers <path>|--imports <path>\n"
        "                       |--api <glob>   [-n N]\n"
        "       index.py show <path>#<symbol> | <path>:<line>\n"
        "       index.py stats | refresh | rebuild | selfcheck\n")
    return 2


def main(argv):
    if not argv:
        return usage()
    cmd = argv[0]
    if cmd == "selfcheck":
        return selfcheck()
    if sqlite3 is None:
        sys.stderr.write("polaris find: this python has no sqlite3 module\n")
        return 3
    root = os.environ.get("POLARIS_ROOT") or sh(["git", "rev-parse", "--show-toplevel"], ".").strip()
    if not root:
        sys.stderr.write("polaris find: not inside a git repo\n")
        return 3
    if cmd == "find":
        return cmd_find(root, argv[1:])
    if cmd == "show":
        return cmd_show(root, argv[1]) if len(argv) > 1 else usage()
    if cmd == "stats":
        return cmd_stats(root)
    if cmd in ("refresh", "rebuild"):
        con, fts, ch, gone = build(root, full=(cmd == "rebuild"))
        print("index %s: %d changed, %d removed, tier %s" %
              (cmd + "ed", ch, gone, "fts5" if fts else "like"))
        return 0
    return usage()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
