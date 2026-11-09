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
import collections
import difflib
import fnmatch
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
import types

try:
    import sqlite3
except ImportError:                                   # tier 3
    sqlite3 = None

if hasattr(sys.stdout, "reconfigure"):                # Windows cp1252 would mangle UTF-8 paths
    try:
        # newline="\n": Windows writes every "\n" as "\r\n" otherwise, and no golden could compare
        # this output byte for byte. Any file index.py writes opens with newline="\n" too, same reason.
        sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace", newline="\n")
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
    # ...and with the repo facts build() passes (ops/contracts/save-hops.md § 1.1). The aliases come
    # from the same _aliases build() uses, fed config text carrying what real ones do: comments,
    # trailing commas, and a "@/*" that a naive comment strip would eat.
    paths2 = {"src/components/Cart.tsx": 11, "src/components/CartItem.tsx": 12,
              "src/hooks/index.ts": 13, "web/lib/fmt/money.js": 14,
              "src/shop/__init__.py": 15, "src/shop/cart.py": 16, "src/shop/pay/__init__.py": 17}
    bybase2 = {}
    for _p, _i in paths2.items():
        bybase2.setdefault(os.path.basename(_p), []).append((_p, _i))
    aliases = _aliases({
        "tsconfig.json": '{\n  "compilerOptions": {\n    "paths": {"@/*": ["src/*"],},  /* the app */\n'
                         '    "baseUrl": ".", // the root\n  },\n}\n',
        "web/jsconfig.json": '{"compilerOptions": {"baseUrl": "lib"}}'})
    fact_cases = [
        ("@/components/Cart", "src/pages/home.tsx", 11),   # paths alias, extension tried
        ("@/hooks", "src/app.ts", 13),                     # alias to a folder: its index.ts
        ("fmt/money", "web/app.js", 14),                   # bare baseUrl: web/ + lib/ + spec
        ("@/components/Cart", "web/app.js", None),         # nearest config wins: web/'s has no @/*
        ("react", "src/app.ts", None),                     # baseUrl "." never makes a package local
        ("shop.cart", "tests/test_cart.py", 16),           # python src/ root
        ("shop.pay", "tests/test_pay.py", 17),             # python package: its __init__.py
        ("shop", "tests/test_shop.py", 15),                # one segment is a dotted name too
    ]
    for raw, src, want in fact_cases:
        got = resolve_import(raw, src, paths2, bybase2, aliases=aliases, pyroots=["src"])
        if got != want:
            print("FAIL resolve %r from %s: expected %r, got %r" % (raw, src, want, got))
            bad += 1
    # path mentions: which non-code lines NAME a path, the second half of `find --importers`
    cart = "src/components/Cart.tsx"
    men_cases = [
        (cart, "package.json", '{\n  "main": "src/components/Cart.tsx"\n}\n', [2]),
        (cart, "Dockerfile.web", "FROM node:20\nCOPY src/components/Cart.tsx /app/\n", [2]),
        (cart, "docs/ui.md", "Rows live in components/CartItem.\n", []),   # CartItem is not Cart
        (cart, "docs/ui.md", "old: mycomponents/Cart\n", []),              # nor is mycomponents
        (cart, "src/pages/home.tsx", "// see components/Cart\n", []),      # code: its imports are edges
        ("src/main.ts", "README.md", "Run main to start.\n", []),          # a bare word names nothing
        ("kit/ops/index.py", ".github/workflows/ci.yml", "- run: python kit/ops/index.py\n", [1]),
    ]
    for path, rel, text, want in men_cases:
        got = _mentioned(path, rel, text)
        if got != want:
            print("FAIL mention %s in %s: expected %r, got %r" % (path, rel, want, got))
            bad += 1
    if bad:
        print("selfcheck FAILED (%d)" % bad)
        return 1
    print("selfcheck ok (%d language fixtures, %d import cases, %d resolve cases, %d mention cases)"
          % (len(FIXTURES), len(imp_cases), len(res_cases) + len(fact_cases), len(men_cases)))
    return 0


# ---------------------------------------------------------------- repo / db
def sh(args, cwd, stdin=None):
    try:
        p = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           input=None if stdin is None else stdin.encode("utf-8"))
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


def resolve_import(raw, src, paths, bybase, aliases=None, pyroots=None):
    """Best-effort import spec -> indexed path. Unresolvable = external package = NULL.

    Deliberately conservative: a wrong edge is worse than a missing one, because --importers
    is used to decide what a change can break.

    aliases (every tsconfig/jsconfig, see _aliases) and pyroots (["src"] in a src/-layout python
    repo) are the repo facts build() passes; left at None, every rule behaves exactly as before them.
    """
    raw = raw.strip().strip("'\"")
    if not raw:
        return None
    d = os.path.dirname(src)
    rel_ext = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".py", ".sh", ".css")
    idx_ext = (".ts", ".tsx", ".js", ".jsx")
    # `@/components/Cart` and baseUrl specs mean nothing without the importer's config, and only
    # JS/TS read one — so only a JS/TS importer's non-relative spec tries them, ahead of all else.
    if aliases and not raw.startswith(".") and lang_of(src) in ("js", "ts"):
        for b in _alias_bases(raw, src, aliases):
            for c in [b] + [b + e for e in rel_ext] + [b + "/index" + e for e in idx_ext]:
                if c in paths:
                    return paths[c]
    cands = []
    if raw.startswith("."):
        if raw.startswith("./") or raw.startswith("../"):        # js/ts/sh relative
            base = os.path.normpath(os.path.join(d, raw)).replace("\\", "/")
            cands += [base] + [base + e for e in rel_ext]
            cands += [base + "/index" + e for e in idx_ext]
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
    elif ("." in raw and not raw.endswith((".h", ".hpp"))) or lang_of(src) == "py":
        # dotted module: py/java/cs. A python name (one segment counts: `import shop`) is a module,
        # else a package's __init__.py — at the root first, then under each source root (src/).
        mod = raw.replace(".", "/")
        for r in [""] + [p + "/" for p in pyroots or ()]:
            cands += [r + mod + ".py", r + mod + "/__init__.py"]
        cands.append(mod + ".java")
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


def _rel(*parts):
    """Join + normalize to a repo-relative `/` path; the repo root is ""."""
    p = os.path.normpath(os.path.join(*parts)).replace("\\", "/")
    return "" if p == "." else p


def _jsonc(text):
    """tsconfig/jsconfig text -> dict, or None. Those files are JSON plus `//` and `/* */` comments
    and trailing commas. Each pass matches a whole string FIRST at every position, so `"@/*"` and
    `"http://x"` survive — a naive comment regex eats `/*": ["src/*` straight out of a paths map."""
    s = re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/', lambda m: m.group(1) or "",
               text.lstrip("\ufeff"), flags=re.S)
    s = re.sub(r'("(?:\\.|[^"\\])*")|,(?=\s*[}\]])', lambda m: m.group(1) or "", s)
    try:
        v = json.loads(s)
    except ValueError:
        return None
    return v if isinstance(v, dict) else None


def _aliases(configs):
    """{tsconfig.json or jsconfig.json path: its text} -> {its folder: (baseUrl dir or None,
    [(pattern, [target, ...]), ...])}, every dir repo-relative, `paths` targets joined to baseUrl
    (no baseUrl: to the config's folder, as TypeScript 4.1+ does).

    A config governs the files under its folder and the nearest one wins — even one with no paths,
    and tsconfig.json over a jsconfig.json beside it, as tsserver picks.
    `extends` is NOT followed: a config that inherits its paths resolves only what it states itself.
    """
    out = {}
    for cfg in sorted(configs, key=lambda p: (os.path.dirname(p),
                                              os.path.basename(p) != "tsconfig.json")):
        d = os.path.dirname(cfg)
        if d in out:
            continue
        opts = (_jsonc(configs[cfg]) or {}).get("compilerOptions")
        opts = opts if isinstance(opts, dict) else {}
        base = opts.get("baseUrl")
        base = _rel(d, base) if isinstance(base, str) else None
        rules = []
        pmap = opts.get("paths")
        for pat, targets in (pmap.items() if isinstance(pmap, dict) else ()):
            if isinstance(targets, list):
                rules.append((pat, [_rel(d if base is None else base, t)
                                    for t in targets if isinstance(t, str)]))
        out[d] = (base, rules)
    return out


def _alias_bases(raw, src, aliases):
    """What a non-relative JS/TS spec names through its importer's nearest config: the best `paths`
    pattern's targets (an exact pattern, else the longest prefix before the `*` — TypeScript's own
    rule), then `<baseUrl>/<spec>`. Extensionless: the caller tries each like a relative import."""
    d = os.path.dirname(src)
    while d not in aliases:
        if not d:
            return []
        d = os.path.dirname(d)
    base, rules = aliases[d]
    best = None                                    # (prefix length, targets, what the * matched)
    for pat, targets in rules:
        pre, star, suf = pat.partition("*")
        if not star:
            if raw == pat:                         # an exact pattern beats every wildcard
                best = (len(raw) + 1, targets, "")
                break
        elif (raw.startswith(pre) and raw.endswith(suf) and len(raw) >= len(pre) + len(suf)
              and (best is None or len(pre) > best[0])):
            best = (len(pre), targets, raw[len(pre):len(raw) - len(suf)])
    out = [_rel(t.replace("*", best[2])) for t in best[1]] if best else []
    if base is not None:
        out.append(_rel(base, raw))
    return [c for c in out if c]


def _tail(path):
    """`src/components/Cart.tsx` -> `components/Cart`: the path as configs, docs and Dockerfiles
    write it — extension and one leading `src/` (the python source root) dropped. None when no `/`
    is left: a bare word like `main` would match half the prose in the repo."""
    t = os.path.splitext(path)[0]
    t = t[4:] if t.startswith("src/") else t
    return t if "/" in t else None


def _mention_src(rel):
    """The non-code files that name paths in plain text: docs, configs, CI, Dockerfiles, Makefiles."""
    base = os.path.basename(rel)
    return (rel.startswith(".github/") or base.startswith("Dockerfile") or base == "Makefile"
            or os.path.splitext(base)[1].lower() in (".md", ".json", ".yml", ".yaml", ".toml",
                                                     ".ini", ".cfg", ".txt", ".mk"))


def _mentioned(path, rel, text):
    """The 1-based lines where non-code file `rel` names `path` by its tail. The character after the
    tail is not a letter, digit or `_` (or the line ends) — so `components/CartItem` never names
    `components/Cart` — and neither is the one before it (`toolkit/ops/x` does not name `kit/ops/x`)."""
    tail = _tail(path)
    if not tail or rel == path or not _mention_src(rel) or tail not in text:
        return []
    pat = re.compile(r"(?<!\w)%s(?!\w)" % re.escape(tail))
    return [ln for ln, line in enumerate(text.splitlines(), 1)
            if len(line) <= MAXLINE and pat.search(line)]


def _mentions(root, path):
    """[(file, line)] for every tracked non-code file naming `path`. Read live, not from the index:
    most of those files (.ini, Dockerfile, Makefile) are not code and the index never stores them."""
    out = []
    if _tail(path):
        for rel in tracked(root):
            if _mention_src(rel) and rel != path:
                out += [(rel, ln) for ln in _mentioned(path, rel, read(root, rel) or "")]
    return out


def _resolver_facts(root, paths, text=None):
    """{indexed path: id} -> (bybase, aliases, pyroots): what resolve_import needs beyond the edge
    itself. One home, because build() and `hops` must resolve an import to the SAME file: the
    basename buckets, every tsconfig/jsconfig's aliases, and python's src/ root when a package or
    module sits directly under src/ (ops/contracts/save-hops.md § 1.1). `text` reads a config from
    another tree than the disk — `hops --proof` resolves the base's imports from the base's configs."""
    bybase = {}
    for p, i in paths.items():
        bybase.setdefault(os.path.basename(p), []).append((p, i))
    text = text or (lambda p: read(root, p))
    aliases = _aliases({p: text(p) or "" for p in paths
                        if os.path.basename(p) in ("tsconfig.json", "jsconfig.json")})
    pyroots = ["src"] if any(p.startswith("src/") and re.match(r"src/[^/]+(?:/__init__)?\.py$", p)
                             for p in paths) else []
    return bybase, aliases, pyroots


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
        byid = {i: p for p, i in paths.items()}
        bybase, aliases, pyroots = _resolver_facts(root, paths)
        upd = []
        # fetchall() first: re-using `cur` for a lookup INSIDE its own iteration silently resets
        # the outer result set, which is why every edge resolved to NULL before this.
        for eid_src, line, raw in cur.execute(
                "SELECT src_id,line,raw FROM edges WHERE dst_id IS NULL").fetchall():
            src = byid.get(eid_src)
            if not src:
                continue
            dst = resolve_import(raw, src, paths, bybase, aliases=aliases, pyroots=pyroots)
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
        # Several globs (`--api g1 g2 ...`) share this ONE build(): each glob's block prints in
        # argument order, sorted and de-duplicated within itself, so the output is byte-identical
        # to one call per glob, concatenated. `pack` asks for every owned path in one call (T-180).
        hit = False
        for q in args:
            pat = q.replace("*", "%") if "*" in q else "%" + q + "%"
            seen = set()
            rows = []
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
            for r in rows:                   # NEVER truncated by -n: a partial surface is a lie
                print(r[3])
            hit = hit or bool(rows)
        return 0 if hit else 1
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
            edge_at = set()
            for path, line, raw in cur.execute(
                    "SELECT f.path,e.line,e.raw FROM edges e JOIN files f ON f.id=e.src_id "
                    "WHERE e.dst_id=?", (f[0],)):
                rows.append((0, path, line, "%s:%d\t%s" % (path, line, raw)))
                edge_at.add((path, line))
            # then every non-code line that NAMES it (configs, docs, CI, Dockerfiles), sort key 1 so
            # they follow all the edges: a path nobody mentions prints byte for byte as before
            for path, line in _mentions(root, q):
                if (path, line) not in edge_at:
                    rows.append((1, path, line, "%s:%d\tmention %s" % (path, line, _tail(q))))
        else:
            # fetchall(): the path lookup below re-uses `cur`, which silently ended this loop at the
            # first RESOLVED edge (same trap as build()'s) — rare while few edges resolved, routine now
            for raw, line, dst in cur.execute(
                    "SELECT raw,line,dst_id FROM edges WHERE src_id=?", (f[0],)).fetchall():
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


# ---------------------------------------------------------------- hops
# `polaris hops` (ops/contracts/save-hops.md § 1): how many folders ONE change touches, and where a
# feature scattered across components/, hooks/ and utils/ should live instead. Read-only and no LLM —
# git history and the import graph in, a report out; it never edits code. It lives in this file
# because index.py already ships to every installed repo, and a new file would not.
_HOPS_USAGE = ("⛔ usage: polaris hops [--tsv | --propose | --stale | --due | --questions | --facts <dir>]"
               " [--score | --owned | --proof | --remap <moves.tsv>]\n")
# words too generic to name a feature: a cluster called "utils" tells nobody where to look
_HOPS_STOP = frozenset((
    "index main test tests spec util utils helper helpers common shared component components hook "
    "hooks service services type types model models view views page pages style styles lib src "
    "core base impl mock mocks data config constants").split())
_HOPS_TOKEN = re.compile(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+")    # words, camelCase split
_HOPS_CITE = re.compile(r"`([^`]+)`")
_GUIDE_OPEN, _GUIDE_CLOSE = "<!-- polaris:guide -->", "<!-- /polaris:guide -->"
_WHERE_OPEN, _WHERE_CLOSE = "<!-- polaris:where -->", "<!-- /polaris:where -->"
_HOPS_PLAN = ("--score", "--owned", "--proof", "--remap")     # the flags that read a <moves.tsv>
_HOPS_ENTRY = ("main", "module", "exports", "bin")           # what makes a package.json published
_HOPS_FROM = re.compile(r"""^\s*\}\s*from\s*['"](?P<n>[^'"]+)['"]""")   # a multi-line import's last line
_HOPS_LOOKS = ("app", "pages", "routes")                     # framework-ROUTED only under a config
_HOPS_FRAMEWORK = ("next.config.*", "nuxt.config.*", "svelte.config.*", "remix.config.*",
                   "astro.config.*")                         # the configs that route by folder
_HOPS_WHY = ("generated", "vendored", "guarded", "test map", "kept", "public")   # § 12.6, first wins
_HOPS_CAP = 25                                               # one pass moves at most this many files


def _hops_cfg(conv, key, default=""):
    """core.sh `cfg` over CONVENTIONS.md text: the first `key:` line wins, a ` # comment` is cut,
    and a value that is nothing but a comment reads empty — so the default."""
    for line in conv.split("\n"):
        if line.startswith(key + ":"):
            v = line[len(key) + 1:].rstrip("\r").lstrip(" \t")
            v = "" if v.startswith("#") else re.sub(r"[ \t]#.*", "", v)
            return v.rstrip(" \t") or default
    return default


def _hops_rows(root, rel):
    """The data lines of a TAB-separated state file (RULES, SURFACES, LAYOUT), split into fields."""
    return [line.rstrip("\r").split("\t") for line in (read(root, rel) or "").split("\n")
            if line.strip() and not line.startswith("#")]


def _hops_match(path, pat):
    """THE files_owned matcher (ownership.sh match_one): `dir/` is a prefix; anything else is a glob
    whose `*` crosses `/` — an exact path being a glob with no wildcard in it."""
    return path.startswith(pat) if pat.endswith("/") else fnmatch.fnmatchcase(path, pat)


def _hops_task(root):
    """§ 12.1: the <ID> when the tree at root is a task worktree — its HEAD is the branch
    feat/<ID> — else "". What such a tree changes is the pass's own work, never somebody else's."""
    b = sh(["git", "symbolic-ref", "-q", "--short", "HEAD"], root).strip()
    return b[len("feat/"):] if b.startswith("feat/") else ""


def _hops_in_flight(root, base, task=""):
    """§ 1.4 rule 10 as § 12.1 amends it: the paths somebody ELSE has unmerged work on, FIXED for
    this pass only — every path git status names (`dir/` for an untracked folder it reports whole),
    unless the tree is task <task>'s own worktree; and every path a local or remote branch changed
    in commits <base> lacks: an open ship PR counts. Never the board ref, the task's own feat/<ID>,
    or the feat/<ID> of a task already in done/ on the board (done keeps a live worktree's branch
    for sweep) — local or on any remote. The refs are filtered HERE and handed to git log on stdin:
    one --exclude per finished task would pass Windows' 32 KB command line on a board this old."""
    out = set()
    st = [] if task else sh(["git", "status", "--porcelain", "-z"], root).split("\0")
    i = 0
    while i < len(st):
        e, i = st[i], i + 1
        if len(e) > 3:
            out.add(e[3:])
            if "R" in e[:2] or "C" in e[:2]:       # -z puts a rename's source in the next field
                out.add(st[i] if i < len(st) else "")
                i += 1
    done = sh(["git", "ls-tree", "--name-only", "refs/heads/polaris/board", "--", "ops/board/done/"],
              root).split("\n")
    mine = {"feat/" + p.rpartition("/")[2][:-3] for p in done if p.endswith(".md")}
    mine.update(["feat/" + task] if task else [])
    refs = []
    for r in sh(["git", "for-each-ref", "--format=%(refname)", "refs/heads/", "refs/remotes/"],
                root).split("\n"):
        kind, _, name = r[len("refs/"):].partition("/")      # heads|remotes, then the branch
        if ((kind == "heads" and not fnmatch.fnmatchcase(name, "polaris/*") and name not in mine)
                or (kind == "remotes" and not fnmatch.fnmatchcase(name, "*/polaris/*")
                    and name.partition("/")[2] not in mine)):    # <remote>/<branch>
            refs.append(r)
    if refs:
        out.update(sh(["git", "-c", "core.quotePath=false", "log", "--name-only", "--format=",
                       "--stdin", "^" + base, "--"], root, "\n".join(refs) + "\n").split("\n"))
    out.discard("")
    return out


def _hops_toml(text):
    """A pyproject.toml read just far enough for rule 9 — python 3.8 has no tomllib: (every [table]
    header, the module of every [project.scripts] entry). `name = "pkg.mod:fn"` gives pkg.mod; the
    inline `scripts = { … }` form inside [project] counts the same."""
    tables, mods, cur = [], [], ""
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("[["):                       # an array of tables: never project's
            cur = ""
            continue
        m = re.match(r"\[\s*([^\[\]]+?)\s*\](?:\s*#.*)?$", s)
        if m:
            cur = re.sub(r"[\s\"']", "", m.group(1))
            tables.append(cur)
        elif cur == "project.scripts":
            m = re.match(r"""[^=]+=\s*(["'])([^"']+)\1""", s)
            mods += [m.group(2)] if m else []
        elif cur == "project" and re.match(r"scripts\s*=\s*\{", s):
            mods += [v for _, v in re.findall(r"""=\s*(["'])([^"']+)\1""", s[s.index("{"):])]
    return tables, [x.split(":")[0].strip() for x in mods]


def _hops_leaves(v):
    """Every string inside a package.json value — `exports` nests conditions and subpaths."""
    if isinstance(v, str):
        return [v]
    if isinstance(v, dict):
        v = list(v.values())
    return [s for x in v for s in _hops_leaves(x)] if isinstance(v, list) else []


def _hops_public(root, files, edges):
    """§ 1.4 rule 9 (a)-(b), the public surface: (paths, folder prefixes, globs) that another repo
    or a runtime reaches BY NAME, so a move breaks callers this repo cannot see. (a) a published
    package — a package.json without "private": true that has main, module, exports or bin: the
    manifest itself, the files those name (an exports `*` stays a glob, so a file moved INTO it
    would turn public), and everything they reach by resolved imports; (b) a pyproject.toml with a
    [project] table: every package folder (it holds an __init__.py) directly under its own folder
    or that folder's src/, and every module [project.scripts] names."""
    have = set(files)
    named, prefixes, globs = set(), [], []
    for pj in files:
        if pj.rpartition("/")[2] != "package.json":
            continue
        meta = _jsonc(read(root, pj) or "") or {}
        if meta.get("private") is True or not any(k in meta for k in _HOPS_ENTRY):
            continue
        d = pj.rpartition("/")[0]
        named.add(pj)
        for spec in _hops_leaves([meta.get(k) for k in _HOPS_ENTRY]):
            p = _rel(d, spec) + ("/*" if spec.endswith("/") else "")    # "./lib/": the whole folder
            if "*" in p:
                globs.append(p)
                continue
            for c in ([p] + [p + e for e in (".js", ".mjs", ".cjs", ".json", ".ts", ".tsx", ".jsx")]
                      + [p + "/index" + e for e in (".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx")]):
                if c in have:
                    named.add(c)
                    break
    named.update(p for p in files if any(fnmatch.fnmatchcase(p, g) for g in globs))
    out = {}
    for a, b in edges:
        out.setdefault(a, []).append(b)
    todo = list(named)
    while todo:                                  # the closure: whatever a published file imports
        for b in out.get(todo.pop(), ()):
            if b not in named:
                named.add(b)
                todo.append(b)
    for pp in files:
        if pp.rpartition("/")[2] != "pyproject.toml":
            continue
        tables, mods = _hops_toml(read(root, pp) or "")
        if not any(t == "project" or t.startswith("project.") for t in tables):
            continue
        pre = pp[:-len("pyproject.toml")]
        for p in files:
            rest = p[len(pre):].split("/") if p.startswith(pre) and p.endswith("/__init__.py") else []
            if len(rest) == 2 or (len(rest) == 3 and rest[0] == "src"):
                prefixes.append(pre + "/".join(rest[:-1]) + "/")
        for m in mods:
            m = m.replace(".", "/")
            named.update(pre + c for c in (m + ".py", m + "/__init__.py", "src/" + m + ".py",
                                           "src/" + m + "/__init__.py") if pre + c in have)
    return named, tuple(prefixes), globs


def _hops_assembly(files):
    """§ 1.4 rule 9 (d): path -> the nearest .asmdef or .asmref above it (None outside every Unity
    assembly). A move whose two ends answer differently changes which assembly compiles the file —
    its references, platforms and defines with it — so it is never proposed. An .asmref counts as
    a boundary too: it hands its folder to another assembly, and two answers that might agree are
    still kept apart, which is the safe side of the guess."""
    asm = {}
    for f in sorted(files):
        if f.endswith((".asmdef", ".asmref")):
            asm.setdefault(f.rpartition("/")[0], f)

    def _near(p):
        d = p.rpartition("/")[0]
        while d not in asm:
            if not d:
                return None
            d = d.rpartition("/")[0]
        return asm[d]
    return _near


def _hops_lasting(root, files=(), edges=()):
    """The § 1.4 rules that hold a path for good, as ONE answer per path: the first of `generated`
    (rule 4) · `vendored` (3) · `guarded` (5) · `test map` (6) · `kept` (7) · `public` (9 a-c), in
    _HOPS_WHY's order, or "" for none. FIXED is these plus where a path sits (rules 1, 2, 8) and
    somebody's unmerged work (10); --facts' `leave alone:` line names these alone (§ 12.6) — a
    guide says why a file stays put for good, never that a branch happens to touch it today."""
    conv = read(root, "ops/CONVENTIONS.md") or ""
    gen = _hops_cfg(conv, "generated").split()                                         # 4
    gal = _hops_cfg(conv, "gallery").strip("/")
    gen += [gal + "/"] if gal else []
    guard = [r[0] for r in _hops_rows(root, "ops/RULES.tsv")                           # 5
             if len(r) > 1 and r[1] in ("path", "ask")]
    tmap = [g for r in _hops_rows(root, "ops/SURFACES.tsv")                            # 6
            for g in r[:2] if g not in ("", "-")]
    keep = [r[0] for r in _hops_rows(root, "ops/LAYOUT.tsv")                           # 7
            if len(r) > 1 and r[1] == "keep"]
    named, pkgs, globs = _hops_public(root, files, edges)                              # 9 (a) (b)
    rules = (lambda p: any(_hops_match(p, x) for x in gen),
             lambda p: bool(VENDOR.search(p)),
             lambda p: any(_hops_match(p, x) for x in guard),
             lambda p: any(_hops_match(p, x) for x in tmap),
             lambda p: any(_hops_match(p, x) for x in keep),
             # 9 (c): a Go, Java or Kotlin file's folder IS its package name
             lambda p: (p in named or p.startswith(pkgs) or p.endswith((".go", ".java", ".kt"))
                        or any(fnmatch.fnmatchcase(p, g) for g in globs)))

    def _why(p):
        return next((w for w, hit in zip(_HOPS_WHY, rules) if hit(p)), "")
    return _why


def _hops_fixed(root, base, files=(), edges=(), task=""):
    """§ 1.4 rules 1-10 as ONE predicate over a path: True = never proposed as a `from` or a `to`,
    and not counted in the score. Rule 9 (d), a move across Unity assemblies, is a property of the
    move rather than of one path: _hops_assembly answers it where the MOVE rows are made. <task> =
    the tree's own task (_hops_task), whose work rule 10 never holds."""
    lasting = _hops_lasting(root, files, edges)                                        # 3-7, 9
    flight = _hops_in_flight(root, base, task)                                         # 10
    held = tuple(p for p in flight if p.endswith("/"))
    # 2: app/ pages/ routes/ are framework-ROUTED under a next/nuxt/svelte/remix/astro config at
    # the root and framework-LOOKING without one — nothing moves in or out of either this pass.
    # `loose` answers as if that one clause were gone: --questions asks about a framework-looking
    # folder only when nothing else would hold its files anyway (§ 1.7).
    routed = {"migrations", "public", "static"} | set(_HOPS_LOOKS)
    relaxed = routed.difference(_HOPS_LOOKS)
    unity = {"Resources", "StreamingAssets", "Editor", "Plugins"}                      # 8

    def _fixed(p, loose=False):
        segs = p.split("/")[:-1]
        return (not segs or segs[0] in ("ops", ".claude", ".github", ".polaris", "archive")  # 1
                or bool((relaxed if loose else routed).intersection(segs))                  # 2
                or bool(unity.intersection(segs)) or p.endswith((".meta", ".asmdef", ".asmref"))
                or p in flight or p.startswith(held) or bool(lasting(p)))
    return _fixed


def _hops_history(root, base, tracked, head=False):
    """§ 1.3 + § 12.2: the last 300 non-merge changes on <base> — on HEAD when <head> (a task
    worktree, --facts) — each as the set of TODAY's tracked paths it touched. Renames map old
    names onto today's — chains too: the log runs newest first, so every rename is seen before the
    older changes that still use the old name — and a path gone since drops out. A change of more
    than 40 paths (a mass rename, a vendored drop) or one only under ops/ says nothing about how
    the features are laid out, so it is skipped. So is a layout pass's own work: a commit in
    <base>..HEAD (the task's own) and any commit touching ops/LAYOUT.tsv (a pass's land) map their
    renames and are never a change — a pass that counted itself would weld every feature it moved
    through the one file that imports them all."""
    own = set(sh(["git", "rev-list", base + "..HEAD", "--"], root).split()) if head else set()
    out = sh(["git", "-c", "core.quotePath=false", "log", "-n", "300", "--no-merges", "-M",
              "--name-status", "--format=%x1e%H", "HEAD" if head else base, "--"], root)
    commits = []
    for line in out.split("\n"):
        if line.startswith("\x1e"):
            commits.append((line[1:].strip(), []))
        elif commits and "\t" in line:
            f = line.split("\t")
            commits[-1][1].append((f[0][:1], f[1], f[2] if len(f) > 2 else ""))
    alias, kept = {}, []
    for sha, rows in commits:
        raw = [new or old for _, old, new in rows]
        names = {alias.get(p, p) for p in raw}
        for st, old, new in rows:
            if st == "R" and new:
                alias[old] = alias.get(new, new)
        if (len(rows) > 40 or all(p.startswith("ops/") for p in raw) or sha in own
                or any("ops/LAYOUT.tsv" in (old, new) for _, old, new in rows)):
            continue
        kept.append(names & tracked)
    return kept


def _hops_edges(root):
    """[(a, b)]: file a imports file b, for every import edge in the index — § 1.3's static
    coupling, rule 9's published closure and --owned's importers all read this one list. Each edge
    is resolved AFRESH from its raw spec rather than trusting the stored dst_id: build() re-inserts
    an edited file under a new id and never re-resolves the edges still pointing at the old one
    (the stale-edge line in IDEAS.md), so the stored graph quietly loses the edges into the files
    that change most — the very files this report is about. Same resolver, same facts."""
    con, _, _, _ = build(root)
    try:
        byid = dict(con.execute("SELECT id,path FROM files").fetchall())
        paths = {p: i for i, p in byid.items()}
        bybase, aliases, pyroots = _resolver_facts(root, paths)
        out = []
        for sid, raw in con.execute("SELECT src_id,raw FROM edges").fetchall():
            a = byid.get(sid)
            b = a and byid.get(resolve_import(raw, a, paths, bybase, aliases=aliases, pyroots=pyroots))
            if b and b != a:
                out.append((a, b))
    finally:
        con.close()
    return out


def _hops_clusters(commits, pairs):
    """§ 1.5: w(a,b) = changes touching both + 2 when either imports the other; clusters are the
    connected components over the edges with w >= 3, so an import alone never links two files — it
    takes a change they shared as well. -> ([sorted cluster], {file: sum of its w >= 3 weights})"""
    w = {}
    for c in commits:
        c = sorted(c)
        for i, a in enumerate(c):
            for b in c[i + 1:]:
                w[(a, b)] = w.get((a, b), 0) + 1
    for k in pairs:
        w[k] = w.get(k, 0) + 2
    up, strength = {}, {}

    def _top(x):
        while up.get(x, x) != x:
            up[x] = up.get(up[x], up[x])
            x = up[x]
        return x
    for (a, b), n in sorted(w.items()):
        if n >= 3:
            strength[a] = strength.get(a, 0) + n
            strength[b] = strength.get(b, 0) + n
            ra, rb = _top(a), _top(b)
            if ra != rb:
                up[max(ra, rb)] = min(ra, rb)
    groups = {}
    for f in strength:
        groups.setdefault(_top(f), []).append(f)
    return [sorted(g) for g in groups.values()], strength


def _hops_name(files, strength):
    """§ 1.5: the most frequent lowercase token of the files' names (extension dropped, camelCase
    split), at least 4 letters and not a generic word; ties alphabetical. No such token: the stem of
    the most-connected file."""
    n = {}
    for p in files:
        stem = os.path.splitext(p.rpartition("/")[2])[0]
        for t in {m.lower() for m in _HOPS_TOKEN.findall(stem)}:
            if len(t) >= 4 and t.isalpha() and t not in _HOPS_STOP:
                n[t] = n.get(t, 0) + 1
    if n:
        return min(n, key=lambda t: (-n[t], t))
    return os.path.splitext(min(files, key=lambda p: (-strength.get(p, 0), p)).rpartition("/")[2])[0]


def _hops_home(files, name, folders):
    """§ 1.5: <deepest common parent of the files>/<name>/ — under src/ when that parent is the root
    and src/ holds any of them. A folder of that name that already exists is used as is, spelled the
    way it is on disk (a case-insensitive disk would merge the two spellings anyway)."""
    common = []
    for segs in zip(*[p.split("/")[:-1] for p in files]):
        if any(s != segs[0] for s in segs):
            break
        common.append(segs[0])
    parent = "/".join(common)
    if not parent and any(p.startswith("src/") for p in files):
        parent = "src"
    home = (parent + "/" if parent else "") + name
    if home not in folders:
        same = sorted(d for d in folders if d.lower() == home.lower())
        home = same[0] if same else home
    return home + "/"


def _hops_guides(root, files):
    """§ 0.1: {dir: [its block's lines]} for every TRACKED <dir>/CLAUDE.md (dir is never the root)
    holding the marker line; the block runs to the closing marker, or to EOF. Text outside the
    block is the owner's and is never read."""
    out = {}
    for p in files:
        if p.endswith("/CLAUDE.md"):
            lines = [x.rstrip("\r") for x in (read(root, p) or "").split("\n")]
            if _GUIDE_OPEN in lines:
                body = lines[lines.index(_GUIDE_OPEN) + 1:]
                if _GUIDE_CLOSE in body:
                    body = body[:body.index(_GUIDE_CLOSE)]
                out[p[:-len("/CLAUDE.md")]] = body
    return out


def _hops_purpose(root, d, guides):
    """A folder's purpose for MAP and --facts: its guide's purpose line (§ 0.1), else the first
    heading of its README.md, else `-`. A guide headed `# <d>/ — <text>` (the template's shape)
    gives <text>: the folder's own name goes, once and only when text follows (§ 12.3 — the rule
    guide_purpose keeps too), so no report says it twice. Never a TAB: --tsv is TAB-separated."""
    for line in guides.get(d, ()):
        s = re.sub(r"^[# ]+", "", line)
        if s.strip(" \t"):
            pre = d + "/ — "
            if s.startswith(pre) and s[len(pre):].strip(" \t"):
                s = s[len(pre):]
            return s.replace("\t", " ")
    for line in (read(root, d + "/README.md") or "").split("\n"):
        m = re.match(r"#+\s+(\S.*)", line.rstrip("\r"))
        if m:
            return m.group(1).replace("\t", " ")
    return "-"


def _hops_stale(root, guides):
    """§ 0.1: [(guide, citation)] for every citation nothing on disk answers. A citation is a backtick
    span with no whitespace, `://` or `*`, not starting with -, $ or <, that holds a `/` or ends in
    a 1-8 character extension; it resolves against the guide's folder, then the repo root, and a
    trailing `/` asks for a folder. Guides only: no history, no index — drift calls this."""
    out = []
    for d in sorted(guides):
        seen = set()
        for line in guides[d]:
            for c in _HOPS_CITE.findall(line):
                if (c in seen or re.search(r"\s", c) or "://" in c or "*" in c or c[0] in "-$<"
                        or not ("/" in c or re.search(r"\.[A-Za-z0-9]{1,8}$", c))):
                    continue
                seen.add(c)
                at = [os.path.join(root, d, c.lstrip("/")), os.path.join(root, c.lstrip("/"))]
                if not any(os.path.isdir(x) if c.endswith("/") else os.path.exists(x) for x in at):
                    out.append((d + "/CLAUDE.md", c))
    return out


def _hops_mean(commits, ren=None):
    """§ 1.3 folders per change: the mean count of distinct parent folders over the kept changes,
    each path renamed through `ren` first when one is given (--score's after)."""
    ren = ren or {}
    return (sum(len({ren.get(p, p).rpartition("/")[0] for p in c}) for c in commits) / len(commits)
            if commits else 0.0)


def _hops_survey(root, files):
    """Everything the report and --score stand on, measured once (§ 1.3-§ 1.5): the FIXED
    predicate, the movable files, the kept changes as sets of movable paths, the clusters with
    their strengths, movable files per folder, every folder, and the guides. In a task worktree
    (§ 12.1-§ 12.2) the history is HEAD's and the task's own work is never in flight, so a pass
    measures the layout it has made so far exactly as <base> will once it lands."""
    s = types.SimpleNamespace(files=files, tracked=set(files))
    s.base = _hops_cfg(read(root, "ops/CONVENTIONS.md") or "", "base", "main")
    s.task = _hops_task(root)
    s.edges = _hops_edges(root)
    s.fixed = _hops_fixed(root, s.base, files, s.edges, s.task)
    s.movable = {p for p in files if not s.fixed(p)}
    hist = _hops_history(root, s.base, s.tracked, bool(s.task))
    s.commits = [c for c in (k & s.movable for k in hist) if c]
    s.clusters, s.strength = _hops_clusters(
        s.commits, {(min(a, b), max(a, b)) for a, b in s.edges if a in s.movable and b in s.movable})
    s.per, s.folders = {}, set()
    for p in files:
        segs = p.split("/")[:-1]
        s.folders.update("/".join(segs[:i]) for i in range(1, len(segs) + 1))
        if p in s.movable and segs:
            d = "/".join(segs)
            s.per[d] = s.per.get(d, 0) + 1
    s.dirs = sorted(s.per, key=lambda d: (-s.per[d], d))
    s.guides = _hops_guides(root, files)
    s.big = [d for d in s.dirs if s.per[d] >= 5]
    s.missing = [d for d in s.big if d not in s.guides]
    return s


def _hops_proposals(root, s):
    """§ 1.5 -> (SCATTER rows [(name, folders, home, files)], MOVE rows [(from, to, name)]).
    SCATTER: a cluster spanning 3+ folders, the biggest win first — (folders - 1) x the changes
    that touched it — then by name. MOVE: each file not yet in its home goes to <home><basename>,
    unless two would land on one name, the target exists or is FIXED, the two ends sit in
    different Unity assemblies (rule 9 d), or the home would pass 30 files (one giant folder must
    never win the score). A 30+ file cluster gets no MOVE rows."""
    asm = _hops_assembly(s.files)
    scat = []
    for cl in s.clusters:
        k = len({p.rpartition("/")[0] for p in cl})
        if k >= 3:
            name = _hops_name(cl, s.strength)
            touched = sum(1 for c in s.commits if c.intersection(cl))
            scat.append((-(k - 1) * touched, name, cl, k))
    scat.sort()
    rows, moves, claimed = [], [], set()
    for _, name, cl, k in scat:
        home = _hops_home(cl, name, s.folders)
        rows.append((name, k, home, cl))
        if len(cl) > 30 or os.path.isfile(os.path.join(root, home[:-1])):
            continue
        want = {}
        for p in cl:
            if not p.startswith(home):
                want.setdefault(home + p.rpartition("/")[2], []).append(p)
        mv = sorted((ps[0], t) for t, ps in want.items()
                    if len(ps) == 1 and t not in s.tracked and t not in claimed and not s.fixed(t)
                    and asm(ps[0]) == asm(t) and not os.path.lexists(os.path.join(root, t)))
        inside = sum(1 for p in s.files if p.rpartition("/")[0] == home[:-1])
        if mv and inside + len(mv) <= 30:
            moves += [(f, t, name) for f, t in mv]
            claimed.update(t for _, t in mv)
    return rows, moves


def _hops_cut(moves):
    """§ 12.4, the next pass's moves (--propose, and the after-score --due weighs): the MOVE rows
    in their order, a cluster at a time — a run of rows with one name, the 4th --tsv field — taken
    WHOLE while the total stays within _HOPS_CAP. A cluster that would pass it waits whole for the
    next pass and the walk goes on, so a smaller one behind it still fits: cut mid-feature, a
    pass leaves a feature in two places, findable in neither."""
    runs = []
    for m in moves:
        if runs and runs[-1][-1][2] == m[2]:
            runs[-1].append(m)
        else:
            runs.append([m])
    out = []
    for r in runs:
        out += r if len(out) + len(r) <= _HOPS_CAP else []
    return out


def _hops_loc(root, p):
    """A file's lines as an editor counts them (a last line without its newline still counts);
    None for a binary or unreadable file — no merge or split is ever about one."""
    t = read(root, p)
    return None if t is None else t.count("\n") + (1 if t and not t.endswith("\n") else 0)


def _hops_merges(root, s, moves):
    """§ 1.7 MERGE -> [(from, into, changes together, from's lines, into's lines)], the pairs that
    change together most first. Two movable files of at most 40 lines each, touched together in 3+
    changes AND in 75%+ of the changes touching either: the smaller folds into the larger (equal
    sizes: the first name into the second). Never a MOVE row — merging a file away needs the
    human's yes up front, so a MERGE only ever becomes one of --questions. Two filters keep those
    questions worth asking: a file a MOVE row already moves is never paired (one pass cannot both
    move and merge a file — § 0.3 refuses that plan), and the two files are one kind — the same
    extension, tests or not tests alike — since folding a stylesheet into a component, or a test
    into the code it tests, is no merge anybody would say yes to."""
    moved = {f for f, _, _ in moves}
    seen, both = collections.Counter(), collections.Counter()
    for c in s.commits:
        c = sorted(p for p in c if p not in moved)
        seen.update(c)
        both.update((a, b) for i, a in enumerate(c) for b in c[i + 1:])
    loc, out = {}, []
    for (a, b), k in sorted(both.items()):
        if (k < 3 or 4 * k < 3 * (seen[a] + seen[b] - k)
                or os.path.splitext(a)[1] != os.path.splitext(b)[1]
                or bool(TESTY.search(a)) != bool(TESTY.search(b))):
            continue
        for p in (a, b):
            if p not in loc:
                loc[p] = _hops_loc(root, p)
        if loc[a] is None or loc[b] is None or max(loc[a], loc[b]) > 40:
            continue
        f, t = (a, b) if loc[a] <= loc[b] else (b, a)
        out.append((f, t, k, loc[f], loc[t]))
    return sorted(out, key=lambda r: (-r[2], r[0], r[1]))


def _hops_splits(root, s):
    """§ 1.7 SPLIT -> [(path, its lines or files, the folders it pulls in or None)] — reported, never
    acted on. A movable file of 600+ lines whose changes also touch 4+ other folders, each in 2+ of
    them (never its own folder or one above it: a change there says nothing), biggest first; then
    every folder holding more than 40 movable files directly inside, biggest first."""
    pulls = {}
    for c in s.commits:
        dirs = {p.rpartition("/")[0] for p in c}
        for p in c:
            up = p.split("/")[:-1]
            pulls.setdefault(p, collections.Counter()).update(
                dirs.difference("/".join(up[:i]) for i in range(len(up) + 1)))
    big = []
    for p in sorted(pulls):
        k = sum(1 for n in pulls[p].values() if n >= 2)
        n = _hops_loc(root, p) if k >= 4 else None
        if n is not None and n >= 600:
            big.append((p, n, k))
    big.sort(key=lambda r: (-r[1], r[0]))
    return big + [(d + "/", s.per[d], None) for d in s.dirs if s.per[d] > 40]


def _hops_file(p):
    """A path a moves file may hold (§ 0.3): repo-relative, `/`-separated, a file — never a
    folder, and never a .meta, which travels with its asset."""
    return (bool(p) and "\\" not in p and not re.match(r"[A-Za-z]:", p) and not p.endswith(".meta")
            and all(x not in ("", ".", "..") for x in p.split("/")))


def _hops_plan(root, arg):
    """§ 0.3: <moves.tsv> -> [(kind, from, to)], or None when it is missing or malformed. A relative
    path is the current directory's first, then the primary's (root) — so the plan in the
    primary's .polaris/ answers from a tidy task's worktree. Malformed: a row that is not
    `move|merge<TAB><file><TAB><file>`, a path _hops_file refuses, a file moved twice, two moves
    onto one name, or a path that is moved and is also a destination."""
    p = arg
    if not os.path.isabs(arg):
        p = next((x for x in (os.path.join(os.getcwd(), arg), os.path.join(root, arg))
                  if os.path.isfile(x)), "")
    try:
        with open(p, "rb") as fh:
            text = fh.read().decode("utf-8")
    except (OSError, ValueError):
        return None
    rows = []
    for line in text.lstrip("﻿").split("\n"):
        line = line.rstrip("\r")
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != 3 or f[0] not in ("move", "merge") or f[1] == f[2] or not all(map(_hops_file, f[1:])):
            return None
        rows.append((f[0], f[1], f[2]))
    froms = [f for _, f, _ in rows]
    tos = [t for k, _, t in rows if k == "move"]
    into = {t for k, _, t in rows if k == "merge"}
    if (len(set(froms)) < len(froms) or len(set(tos)) < len(tos)
            or set(froms) & (set(tos) | into) or set(tos) & into):
        return None
    return rows


def _hops_score(root, rows, files):
    """--score <moves> (§ 1.6): folders per change before and after — the same history with every
    from renamed to its to (a merge's to its into) — then, for each cluster the moves touch, how
    many folders one change of it spans now and how many after."""
    s = _hops_survey(root, files)
    ren = {f: t for _, f, t in rows}
    f0, f1 = _hops_mean(s.commits), _hops_mean(s.commits, ren)
    pct = int(math.floor(100 * (f0 - f1) / f0 + 0.5)) if f0 else 0
    print("score: %.2f → %.2f folders per change (%d%% fewer) · guides %d/%d"
          % (f0, f1, pct, len([d for d in s.big if d in s.guides]), len(s.big)))
    hit = []
    for cl in s.clusters:
        if any(p in ren for p in cl):
            k = len({p.rpartition("/")[0] for p in cl})
            touched = sum(1 for c in s.commits if c.intersection(cl))
            hit.append((-(k - 1) * touched, _hops_name(cl, s.strength), k,
                        len({ren.get(p, p).rpartition("/")[0] for p in cl})))
    for _, name, k, k2 in sorted(hit):
        print("change %s: %d folders → %d" % (name, k, k2))
    return 0


def _hops_owned(root, rows, files):
    """--owned <moves> (§ 12.5): a tidy task's WHOLE files_owned, one path per line, sorted and
    unique — each from, to and into; the tracked .meta of a Unity asset and its future name; every
    tracked file whose resolved import names a from (aliases included); every tracked non-code file
    naming a from by its tail (§ 1.1); the guides the pass will write, <dir>/CLAUDE.md for the
    first 8 folders the GUIDES rule names once the moves are made (5+ movable files directly
    inside and no guide, largest first — a from counted in its to's folder, a merged from in
    none); and CLAUDE.md and ops/LAYOUT.tsv, which every pass writes. An empty plan is the
    guides-only pass. All of it is read from the tree POLARIS_ROOT names, its index rebuilt for
    it: asked from a task worktree halfway through a pass, every importer is named where it lives
    NOW — the primary's index still names it where it used to be (F7)."""
    have = set(files)
    froms = {f for _, f, _ in rows}
    edges = _hops_edges(root)
    fixed = _hops_fixed(root, _hops_cfg(read(root, "ops/CONVENTIONS.md") or "", "base", "main"),
                        files, edges, _hops_task(root))
    out = {"CLAUDE.md", "ops/LAYOUT.tsv"}
    for kind, f, t in rows:
        out.update((f, t))
        if f + ".meta" in have:
            out.update((f + ".meta", t + ".meta") if kind == "move" else (f + ".meta",))
    out.update(a for a, b in edges if b in froms and a in have)
    for rel in files:
        if _mention_src(rel) and rows:
            text = read(root, rel) or ""
            if any(_mentioned(f, rel, text) for f in froms):
                out.add(rel)
    ren = {f: (t if kind == "move" else "") for kind, f, t in rows}      # a merged from: nowhere
    after = {ren.get(p, p) for p in files if not fixed(p)}               # each movable file, once
    per = collections.Counter(p.rpartition("/")[0] for p in after)
    guides = _hops_guides(root, files)
    out.update(d + "/CLAUDE.md" for d in sorted(
        (d for d in per if d and per[d] >= 5 and d not in guides), key=lambda d: (-per[d], d))[:8])
    for p in sorted(out):
        print(p)
    return 0


def _hops_remap(root, rows):
    """--remap <moves> (§ 1.6, G8): the harness baseline follows the moves. In its `modules`, an
    entry naming a from — a python module (dotted, from the .py path, as the harness lists it) or a
    node module (its path) — becomes its to, and a merged from's entry is dropped; `routes`,
    `scripts` and the order stay as they are. Never a refresh: a module that truly vanished is
    still listed, so the harness still fails on it. An unreadable baseline is none at all, exactly
    as the harness itself reads it."""
    rel = ".polaris/harness-baseline.json"
    path = os.path.join(root, rel)
    try:
        with open(path, encoding="utf-8-sig") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = None
    if not isinstance(data, dict):
        print("remap: no %s — nothing to remap" % rel)
        return 1
    ren, drop = {}, set()
    for kind, f, t in rows:
        py = f.endswith(".py") and t.endswith(".py")
        if kind == "merge":
            drop.update([f] + ([_hops_dotted(f[:-3])] if f.endswith(".py") else []))
            continue
        ren[f] = t
        if py:
            ren[_hops_dotted(f[:-3])] = _hops_dotted(t[:-3])
    mods, out, n = data.get("modules"), [], 0
    for m in mods if isinstance(mods, list) else ():
        hit = isinstance(m, str) and (m in drop or m in ren)
        n += hit
        if not (hit and m in drop):
            out.append(ren[m] if hit else m)
    if n:
        data["modules"] = out
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    print("remap: %d module names moved in %s" % (n, rel))
    return 0


def _hops_dotted(p):
    """`a/b/c` -> `a.b.c`, the module a python import names; a package's `a/b/__init__` -> `a.b`."""
    d = p.replace("/", ".")
    return d[:-len(".__init__")] if d.endswith(".__init__") else d


def _hops_forms(f, t):
    """[(old name, new name)]: the ways a line can name file f, each paired with how it names t
    once f has moved there — the path; its tail (§ 1.1: extension and one leading src/ dropped —
    the new tail drops src/ only where the old one did, so a root-relative mention stays
    root-relative); and for a python file the dotted module of both (`a/b/c.py` ↔ `a.b.c`). A
    tail or a module that is one bare word names nothing: `main` is half the prose in a repo."""
    nf, nt = os.path.splitext(f)[0], os.path.splitext(t)[0]
    tf, tt = (nf[4:], nt[4:] if nt.startswith("src/") else nt) if f.startswith("src/") else (nf, nt)
    out = [(f, t)] + ([(tf, tt)] if "/" in tf else [])
    if f.endswith(".py") and t.endswith(".py"):
        out += [(_hops_dotted(a), _hops_dotted(b)) for a, b in ((nf, nt), (tf, tt))
                if "." in _hops_dotted(a)]
    return out


def _hops_sub(to):
    """{from: its new path} -> the (a) rewrite of one line: every name _hops_forms gives a moved
    file, longest first, in ONE left-to-right pass (a new name is never rewritten again), and
    each bounded — no letter, digit, _ or . before it and no letter, digit or _ after — so
    `components/CartItem` is not `components/Cart` and `x.shop.cart` is not `shop.cart`. A name
    two moves would rewrite differently is ambiguous, and left alone."""
    forms = {}
    for f, t in to.items():
        for a, b in _hops_forms(f, t):
            forms[a] = b if forms.get(a, b) == b else None
    forms = {a: b for a, b in forms.items() if b is not None and a != b}
    if not forms:
        return lambda line: line
    rx = re.compile(r"(?<![\w.])(?:%s)(?!\w)" % "|".join(
        re.escape(a) for a in sorted(forms, key=lambda a: (-len(a), a))))
    return lambda line: rx.sub(lambda m: forms[m.group(0)], line)


def _hops_spec(line, lang):
    """(start, end) of the module an import line names, or None when the line imports nothing:
    the index's own IMPORTS patterns (js/ts import mid-line too: `const x = require(…)`), and the
    `} from "./x"` that closes a multi-line JS/TS import."""
    ire = IMP_RE.get(lang)
    m = ire and (ire[0].match(line) or (ire[0].search(line) if lang in ("js", "ts") else None))
    if not m and lang in ("js", "ts"):
        m = _HOPS_FROM.match(line)
    for k, v in (m.groupdict().items() if m else ()):
        if v and (k == "n" or k.startswith(("n_", "n2_"))):
            return m.span(k)
    return None


def _hops_blobs(repo, rev, paths):
    """{path: bytes} for every path that exists at rev — ONE `git cat-file --batch` however many."""
    paths = sorted(set(paths))
    try:
        out = subprocess.run(["git", "cat-file", "--batch"], cwd=repo, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL,
                             input="".join("%s:%s\n" % (rev, p) for p in paths).encode("utf-8")).stdout
    except Exception:
        return {}
    res, i = {}, 0
    for p in paths:
        nl = out.find(b"\n", i)
        if nl < 0:
            break
        head, i = out[i:nl].split(), nl + 1
        if len(head) == 3 and head[2].isdigit():      # "<sha> <type> <size>", the bytes, a LF
            if head[1] == b"blob":
                res[p] = out[i:i + int(head[2])]
            i += int(head[2]) + 1
    return res


def _hops_disk(repo, p):
    try:
        with open(os.path.join(repo, p), "rb") as fh:
            return fh.read()
    except OSError:
        return None


def _hops_text(b):
    """bytes -> text, or None for no file or a binary one (a NUL early on: read()'s test)."""
    return None if b is None or b"\0" in b[:8000] else b.decode("utf-8", "replace")


def _hops_numbered(path, text):
    """[(line number, line)] as --proof weighs a file: split on LF, a CR before it dropped (an
    autocrlf checkout has CRLF on disk and LF in the repo), no line after a final newline. A
    CLAUDE.md loses what the pass owns there — a folder's guide block, the root's map block, each
    to its closing marker or the end — and its blank lines: whitespace round a block is the block's."""
    ls = text.split("\n")
    if ls and ls[-1] == "":
        ls.pop()
    out = [(n, x[:-1] if x.endswith("\r") else x) for n, x in enumerate(ls, 1)]
    if path != "CLAUDE.md" and not path.endswith("/CLAUDE.md"):
        return out
    o, c = (_WHERE_OPEN, _WHERE_CLOSE) if path == "CLAUDE.md" else (_GUIDE_OPEN, _GUIDE_CLOSE)
    keep, inside = [], False
    for n, x in out:
        if not inside and x == o:
            inside = True
        elif inside:
            inside = x != c
        elif x.strip():
            keep.append((n, x))
    return keep


def _hops_fits(A, B, bodies):
    """True when B is A with every body inserted WHOLE, in its own order, somewhere: a merge folds
    each from in one piece. Each line of A and of a body is the versions it may take — as it was,
    or with the moved names rewritten — so a line nobody touched passes as it does in a move. The
    search runs over (place in B, bodies used): the place in A follows from those two, so it stays
    small however long the files are."""
    bodies = [b for b in bodies if b]
    lens = [len(b) for b in bodies]
    full, seen, todo = (1 << len(bodies)) - 1, set(), [(0, 0)]
    while todo:
        j, used = todo.pop()
        if (j, used) in seen:
            continue
        seen.add((j, used))
        i = j - sum(n for k, n in enumerate(lens) if used >> k & 1)
        if j == len(B) and i == len(A) and used == full:
            return True
        if i < len(A) and j < len(B) and B[j] in A[i]:
            todo.append((j + 1, used))
        for k, b in enumerate(bodies):
            if (not used >> k & 1 and j + lens[k] <= len(B)
                    and all(B[j + x] in b[x] for x in range(lens[k]))):
                todo.append((j + lens[k], used | 1 << k))
    return False


def _hops_proof(rows):
    """--proof <moves> — the guarantee (§ 1.6). In the repository of the CURRENT directory (a tidy
    task's worktree): its working tree — staged and unstaged, so a step is proven before its
    commit — against `git merge-base <base> HEAD`. Green iff every deleted path is a planned from
    and every added path a planned to (a Unity asset's .meta travels with it); every to exists and
    its from does not — "exists" is what a commit of the tree would hold: tracked and on disk, so
    an untracked copy is still missing; and every changed line pair is (a) the old line once each
    moved file's names point at its new place (_hops_sub), or (b) an import of the moved
    counterpart of the file it imported. A merge's into may gain only its froms' lines and import
    edits. Guide blocks, the root-map block and ops/LAYOUT.tsv are never weighed. Only the listed
    rows count: a partial plan proves exactly the steps it lists. One RED line per offence — per
    path, or per changed block at its first bad line. Read-only."""
    repo = sh(["git", "rev-parse", "--show-toplevel"], ".").strip()
    base = _hops_cfg(read(repo, "ops/CONVENTIONS.md") or "", "base", "main") if repo else ""
    mb = sh(["git", "merge-base", base, "HEAD"], repo).strip() if repo else ""
    if not mb:
        sys.stderr.write(_HOPS_USAGE)
        return 2

    def _z(*args):
        return [p for p in sh(["git"] + list(args), repo).split("\0") if p]
    old = set(_z("ls-tree", "-r", "-z", "--name-only", mb))
    now = {p for p in _z("ls-files", "-z") if os.path.lexists(os.path.join(repo, p))}
    st = _z("diff", "--no-renames", "--no-ext-diff", "--name-status", "-z", mb, "--")
    status = dict(zip(st[1::2], (x[:1] for x in st[0::2])))
    move = {f: t for k, f, t in rows if k == "move"}
    merge = {f: t for k, f, t in rows if k == "merge"}
    for f, t in list(move.items()):
        if f + ".meta" in old:
            move[f + ".meta"] = t + ".meta"
    metas = {f + ".meta" for f in merge if f + ".meta" in old}     # a merged asset's .meta just goes
    to = dict(move)
    to.update(merge)
    came = {t: f for f, t in move.items()}
    bad, changed = set(), [0]
    for f, t in sorted(move.items()) + sorted(merge.items()):
        if t not in now:
            bad.add((f, 1, "%s missing" % t))
        if f in now:
            bad.add((t, 1, "%s still exists" % f))
    bad.update((m, 1, "%s still exists" % m) for m in metas if m in now)
    blob = _hops_blobs(repo, mb, [p for p in old if p in status or p in to or p in merge.values()
                                  or p.rpartition("/")[2] in ("tsconfig.json", "jsconfig.json")])
    sides = {}
    for side, have, text in (("old", old, lambda p: _hops_text(blob.get(p))),
                             ("new", now, lambda p: _hops_text(_hops_disk(repo, p)))):
        paths = {p: p for p in have}
        _, aliases, pyroots = _resolver_facts(repo, paths, text)
        sides[side] = (paths, aliases, pyroots)
    sub = _hops_sub(to)

    def _target(spec, src, side):
        # no basename buckets: an import proves only when it names its file outright
        p, aliases, pyroots = sides[side]
        return resolve_import(spec, src, p, {}, aliases=aliases, pyroots=pyroots)

    def _pair(o, n, so, sn):
        """(a) or (b) for one changed line pair: line o of file so at the base, n of sn now."""
        if sub(o) == n:
            return True
        i, j = _hops_spec(o, lang_of(so)), _hops_spec(n, lang_of(sn))
        if not i or not j or sub(o[:i[0]]) != n[:j[0]] or sub(o[i[1]:]) != n[j[1]:]:
            return False
        a, b = _target(o[i[0]:i[1]], so, "old"), _target(n[j[0]:j[1]], sn, "new")
        return bool(a and b and to.get(a, a) == b)

    def _check(label, so, sn, a, b):
        """so at the base (bytes a) -> sn now (bytes b): every changed line a path change."""
        ta, tb = _hops_text(a), _hops_text(b)
        if ta is None or tb is None:              # binary: only a byte-for-byte copy proves
            if a != b:
                bad.add((label, 1, "logic changed"))
            return
        A, B = _hops_numbered(so, ta), _hops_numbered(sn, tb)
        sm = difflib.SequenceMatcher(None, [x for _, x in A], [x for _, x in B], autojunk=False)
        for op, i1, i2, j1, j2 in sm.get_opcodes():
            if op == "equal":
                continue
            if op != "replace" or i2 - i1 != j2 - j1:
                bad.add((label, B[min(j1, len(B) - 1)][0] if B else 1, "logic changed"))
                continue
            for k in range(i2 - i1):
                if not _pair(A[i1 + k][1], B[j1 + k][1], so, sn):
                    bad.add((label, B[j1 + k][0], "logic changed"))
                    break
                changed[0] += 1

    def _split(path, text, side):
        # -> (body lines, import lines, the files it imports, the outside packages it imports)
        body, imps, files, outside = [], [], set(), set()
        for n, x in _hops_numbered(path, text):
            sp = _hops_spec(x, lang_of(path)) if x.strip() else None
            if x.strip() and sp is None:
                body.append((n, x))
            elif sp:
                imps.append(x)
                t = _target(x[sp[0]:sp[1]], path, side)
                if t:
                    files.add(to.get(t, t) if side == "old" else t)
                else:
                    outside.add(x[sp[0]:sp[1]])
        return body, imps, files, outside

    def _merge(i, fs):
        """into i gains its froms: each from's body WHOLE and in order (after the rewrite), and
        import edits that leave it importing exactly what it and its froms imported before."""
        texts = [_hops_text(blob.get(i, b"")), _hops_text(_hops_disk(repo, i) or b"")]
        texts += [_hops_text(blob.get(f, b"")) for f in fs]
        if None in texts:
            bad.add((i, 1, "logic changed"))
            return
        ob, oi, of, ox = _split(i, texts[0], "old")
        nb, ni, nf, nx = _split(i, texts[1], "new")
        bodies, orig = [], [x for _, x in ob]
        for f, t in zip(fs, texts[2:]):
            fb, _, ff, fx = _split(f, t, "old")
            bodies.append([(x, sub(x)) for _, x in fb])
            orig += [x for _, x in fb]
            of, ox = of | ff, ox | fx
        B = [x for _, x in nb]
        if not _hops_fits([(x, sub(x)) for _, x in ob], B, bodies):
            j = next((j1 for op, _, _, j1, _ in difflib.SequenceMatcher(
                None, [x for _, x in ob], B, autojunk=False).get_opcodes() if op != "equal"), 0)
            bad.add((i, nb[min(j, len(nb) - 1)][0] if nb else 1, "logic changed"))
        if nf != of - {i} or nx != ox:
            bad.add((i, 1, "logic changed"))
        # path lines: the folded or kept lines that took their rewritten version, and the new imports
        changed[0] += (sum((collections.Counter(B) - collections.Counter(orig)).values())
                       + len(set(ni) - set(oi)))

    into = {}
    for f, i in merge.items():
        if f in old:
            into.setdefault(i, []).append(f)
    for p in sorted(status):
        s = status[p]
        if p == "ops/LAYOUT.tsv":
            continue
        if s == "D":
            if p not in to and p not in metas:
                bad.add((p, 1, "not in the moves"))
        elif s == "A" and p not in came:
            t = _hops_text(_hops_disk(repo, p) or b"")
            if not ((p == "CLAUDE.md" or p.endswith("/CLAUDE.md")) and t is not None
                    and not _hops_numbered(p, t)):      # a new guide: nothing but its block
                bad.add((p, 1, "not in the moves"))
        elif s == "A":
            _check(p, came[p], p, blob.get(came[p], b""), _hops_disk(repo, p) or b"")
        elif p not in to and p not in into:               # still here: changed in place
            _check(p, p, p, blob.get(p, b""), _hops_disk(repo, p) or b"")
    for i, fs in sorted(into.items()):
        _merge(i, sorted(fs))
    if bad:
        for p, n, why in sorted(bad):
            print("proof: RED %s:%d — %s" % (p, n, why))
        return 1
    print("proof: ok — %d moved, %d merged, %d lines changed, every one a path"
          % (sum(1 for k, _, _ in rows if k == "move"), len(merge), changed[0]))
    return 0


def _hops_due(root, files):
    """--due (§ 1.7, G17 N3): is ONE layout pass worth running now? Five steps in order, each one
    final: `hops: off` → no · under 20 tracked files → no · POLARIS's own source (kit/ops/pack.py
    tracked, the tell `update --auto` skips itself on) → no · under 30 changes on <base> since the
    last pass, its newest commit touching ops/LAYOUT.tsv → no, so a pass whose every move was
    reverted cannot fire again and again · else due when the moves --propose prints (§ 12.4: whole
    features, one pass's cap; keep rows and FIXED are out already) cut folders per change by 15%+,
    or 3+ folders of 5+ files have no guide. Due: ONE line, rc 0. Not due: silence, rc 1. EVERY
    run rewrites the verdict cache (§ 0.5) — `next`, `triage` and the update hint read that file
    and never run hops, so a verdict that went stale must be overwritten, never left behind."""
    conv = read(root, "ops/CONVENTIONS.md") or ""
    base = _hops_cfg(conv, "base", "main")
    sha = sh(["git", "rev-parse", "--verify", "-q", base], root).strip()
    why = []
    if (sha and _hops_cfg(conv, "hops") != "off" and len(files) >= 20
            and "kit/ops/pack.py" not in files):
        last = sh(["git", "log", "-1", "--format=%H", base, "--", "ops/LAYOUT.tsv"], root).strip()
        since = sh(["git", "rev-list", "--count", "--no-merges", last + ".." + base],
                   root).strip() if last else ""
        if not (since.isdigit() and int(since) < 30):
            s = _hops_survey(root, files)
            ren = {f: t for f, t, _ in _hops_cut(_hops_proposals(root, s)[1])}
            # folders summed over every kept change, before and after: the mean's numerators, so
            # the 15% line is decided in whole numbers, never by a float landing a hair under it
            a, b = (sum(len({r.get(p, p).rpartition("/")[0] for p in c}) for c in s.commits)
                    for r in ({}, ren))
            if a and 100 * (a - b) >= 15 * a:
                why.append("~%d%% fewer folders per change" % ((200 * (a - b) + a) // (2 * a)))
            if len(s.missing) >= 3:
                why.append("%d folders of 5+ files have no guide" % len(s.missing))
    line = "layout pass due — " + " · ".join(why) if why else ""
    try:
        os.makedirs(os.path.join(root, ".polaris"), exist_ok=True)
        with open(os.path.join(root, ".polaris", "hops-due"), "w", encoding="utf-8",
                  newline="\n") as fh:
            fh.write("%s\t%d\t%s\n" % (sha or "-", 0 if why else 1, line or "-"))
    except OSError:
        pass                     # a cache nobody can write is one nobody reads: not due, in silence
    if why:
        print(line)
    return 0 if why else 1


def _hops_facts(root, files, arg):
    """--facts <dir> (§ 1.7, G16): at most 15 lines a folder's guide is written from, so a pass never
    explores a folder to describe it — its files and purpose, the files the most others import, its
    symbols in find's own ranking, the folders that change with it, the tests that import it, what
    to leave alone (§ 12.6: its files FIXED for good, each with the first of _HOPS_WHY's reasons,
    in that order, then by name), then one line per file, the most imported first, at most 9.
    Symbols leave out private `_` names and the folder's own CLAUDE.md: the guide is what these
    facts write, and outside its block that file is the owner's text, which hops never reads
    (§ 0.1). The folder is the files DIRECTLY inside it, as MAP counts one; a label with nothing to
    show says `-`. A path that is no folder of tracked files is a usage error, rc 2. Everything is
    read from the tree POLARIS_ROOT names, its history from that tree's HEAD: pointed at a tidy
    task's worktree, the facts describe the layout AFTER its moves — a brand-new home included,
    its files' past followed through the renames, and the pass's own commits counted as renames
    only (§ 12.2)."""
    d = arg.strip()
    while d.startswith("./"):
        d = d[2:]
    d = d.rstrip("/")
    if (not d or "\\" in d or re.match(r"[A-Za-z]:", d)
            or any(x in ("", ".", "..") for x in d.split("/"))
            or not any(p.startswith(d + "/") for p in files)):
        sys.stderr.write(_HOPS_USAGE)
        return 2
    here = {p for p in files if p.rpartition("/")[0] == d}
    edges = set(_hops_edges(root))
    fan = collections.Counter(b for _, b in edges)                  # importers, each counted once
    tests = collections.Counter(a for a, b in edges if b in here and TESTY.search(a))
    con, _ = connect(root)
    try:
        rows = con.execute("SELECT s.name,s.kind,s.line,f.path,f.churn,f.fanin,f.flags FROM symbols s"
                           " JOIN files f ON f.id=s.file_id WHERE f.path LIKE ?", (d + "/%",)).fetchall()
    finally:
        con.close()
    key, top = [], {}
    for _, p, _, n in sorted((-score(n, "", k, ch, fi, fl), p, ln, n)
                             for n, k, ln, p, ch, fi, fl in rows
                             if p in here and not n.startswith("_") and p != d + "/CLAUDE.md"):
        key += [] if n in key else [n]
        t = top.setdefault(p, [])
        t += [] if n in t or len(t) >= 3 else [n]
    co = collections.Counter()
    base = _hops_cfg(read(root, "ops/CONVENTIONS.md") or "", "base", "main")
    for c in _hops_history(root, base, set(files), True):
        if here.intersection(c):
            co.update({p.rpartition("/")[0] for p in c}.difference((d, "")))
    loc = {p: _hops_loc(root, p) for p in here}

    def _name(p):
        return p.rpartition("/")[2]
    print("facts %s/ — %d files · purpose: %s"
          % (d, len(here), _hops_purpose(root, d, _hops_guides(root, files))))
    print("entry files: " + (" · ".join("%s (%d importers)" % (_name(p), fan[p]) for p in sorted(
        (p for p in here if fan[p]), key=lambda p: (-fan[p], p))[:3]) or "-"))
    print("key symbols: " + (" · ".join(key[:8]) or "-"))
    print("changes with: " + (" · ".join("%s/ (%d×)" % (x, co[x]) for x in sorted(
        co, key=lambda x: (-co[x], x))[:4]) or "-"))
    print("tests: " + (" · ".join(sorted(tests, key=lambda x: (-tests[x], x))[:4]) or "-"))
    why = _hops_lasting(root, files, edges)
    left = sorted((_HOPS_WHY.index(w), _name(p), w) for p, w in ((p, why(p)) for p in here) if w)
    print("leave alone: " + (" · ".join("%s (%s)" % (n, w) for _, n, w in left[:4]) or "-")
          + (" · +%d" % (len(left) - 4) if len(left) > 4 else ""))
    for p in sorted((p for p in here if loc[p] is not None), key=lambda p: (-fan[p], -loc[p], p))[:9]:
        print("- %s — %d lines · %s" % (_name(p), loc[p], ", ".join(top.get(p, ())) or "-"))
    return 0


def _hops_questions(root, s, moves):
    """--questions (§ 1.7): at most 3 pick-one questions for the run's ONE up-front round, the safe
    answer first and the default — every MERGE row (a merge deletes a file, so it needs a yes),
    then every framework-LOOKING folder: app/, pages/ or routes/ with no next/nuxt/svelte/remix/
    astro config at the root to say they are routed, asked about only when that rule alone holds
    their files (a keep row, an in-flight edit or any other rule answers it already). Nothing to
    ask: silence, rc 1."""
    qs = ["merge %s into %s? — no | yes (default: no)" % r[:2] for r in _hops_merges(root, s, moves)]
    look = set()
    if not any("/" not in p and fnmatch.fnmatchcase(p, g) for p in s.files for g in _HOPS_FRAMEWORK):
        for p in s.files:
            segs = p.split("/")[:-1]
            i = next((i for i, x in enumerate(segs) if x in _HOPS_LOOKS), -1)
            if i >= 0 and s.fixed(p) and not s.fixed(p, loose=True):
                look.add("/".join(segs[:i + 1]))
    qs += ["is %s/ routed by a framework (keep it where it is)? — keep | allow moves (default: keep)"
           % x for x in sorted(look)]
    for n, q in enumerate(qs[:3], 1):
        print("Q%d: %s" % (n, q))
    return 0 if qs else 1


def cmd_hops(root, args):
    """hops [--tsv | --propose | --stale | --due | --questions | --facts <dir>] · hops --score |
    --owned | --proof | --remap <moves.tsv> — the layout report, the next pass's moves, when a pass
    is worth it, and the four checks on a plan of moves (ops/contracts/save-hops.md § 1.2-§ 1.7,
    § 12.4-§ 12.6).

    bare: the screen, at most 40 lines · --tsv: every row, TAB-separated, nothing capped ·
    --propose: the next pass's moves as plan rows, whole features only, at most 25 · --stale:
    only the STALE rows, rc 0 when there is one and 1 when there is none · --due: the verdict, rc 0
    due / 1 not, always rewriting .polaris/hops-due · --questions: at most 3, rc 1 with none ·
    --facts <dir>: the 15 lines a guide is written from · --score --owned --proof --remap: § 1.6,
    each reading ONE moves file (§ 0.3). A moves file or folder that is missing or malformed, or
    anything else, is a usage line on stderr and rc 2 — never a traceback. It never edits code: the
    files it writes are the index cache build() keeps for `find` anyway, the verdict cache
    (--due) and, for --remap only, the harness baseline.
    """
    if len(args) == 2 and args[0] in _HOPS_PLAN:
        rows = _hops_plan(root, args[1])
        if rows is None:
            sys.stderr.write(_HOPS_USAGE)
            return 2
        if args[0] == "--proof":
            return _hops_proof(rows)
        if args[0] == "--remap":
            return _hops_remap(root, rows)
        files = [p for p in sh(["git", "ls-files", "-z"], root).split("\0") if p]
        return (_hops_owned if args[0] == "--owned" else _hops_score)(root, rows, files)
    if not (not args or (len(args) == 1 and args[0] in ("--tsv", "--propose", "--stale", "--due",
                                                        "--questions"))
            or (len(args) == 2 and args[0] == "--facts")):
        sys.stderr.write(_HOPS_USAGE)
        return 2
    mode = args[0] if args else ""
    files = [p for p in sh(["git", "ls-files", "-z"], root).split("\0") if p]
    if mode == "--facts":
        return _hops_facts(root, files, args[1])
    if mode == "--stale":
        stale = _hops_stale(root, _hops_guides(root, files))
        for g, c in stale:
            print("STALE\t%s\t%s" % (g, c))
        return 0 if stale else 1
    if mode == "--due":
        return _hops_due(root, files)
    if len(files) < 20:
        # Too small to measure, and cheap to say so: no git log, no index build. --tsv prints no
        # rows at all — a SCORE over a handful of files would be a number nobody should act on —
        # --propose no move, and --questions has nothing to ask.
        if not mode:
            print("hops — %d tracked files: too small to measure" % len(files))
        return 1 if mode == "--questions" else 0
    s = _hops_survey(root, files)
    rows, moves = _hops_proposals(root, s)
    if mode == "--questions":
        return _hops_questions(root, s, moves)
    if mode == "--propose":
        for f, t, _ in _hops_cut(moves):
            print("move\t%s\t%s" % (f, t))
        return 0
    merges, splits = _hops_merges(root, s, moves), _hops_splits(root, s)
    per, dirs, guides, missing = s.per, s.dirs, s.guides, s.missing
    stale = _hops_stale(root, guides)
    head = ("%.2f" % _hops_mean(s.commits), len(s.commits),
            len([d for d in s.big if d in guides]), len(s.big))
    if mode == "--tsv":
        out = ["SCORE\t%s\t%d\t%d\t%d" % head]
        out += ["MAP\t%s/\t%d\t%s\t%s" % (d, per[d], _hops_purpose(root, d, guides),
                                          "yes" if d in guides else "no") for d in dirs]
        out += ["SCATTER\t%s\t%d\t%s\t%s" % (n, k, h, ",".join(cl)) for n, k, h, cl in rows]
        out += ["MOVE\t%s\t%s\t%s" % m for m in moves]
        out += ["MERGE\t%s\t%s\t%d" % m[:3] for m in merges]
        out += ["SPLIT\t%s\t%d\t%s" % (p, n, "-" if k is None else k) for p, n, k in splits]
        out += ["GUIDES\t%s/\t%d" % (d, per[d]) for d in missing]
        out += ["STALE\t%s\t%s" % x for x in stale]
        print("\n".join(out))
        return 0
    print("hops — %s folders per change over %d changes · guides %d/%d folders of 5+ files" % head)
    for d in dirs[:12]:
        print("MAP       %s/ · %d files · %s · guide %s" % (
            d, per[d], _hops_purpose(root, d, guides), "yes" if d in guides else "no"))
    if len(dirs) > 12:
        print("MAP       +%d more folders" % (len(dirs) - 12))
    for n, k, h, cl in rows[:8]:
        print("SCATTER   %s: %d folders → %s (%d files)%s"
              % (n, k, h, len(cl), " … too big for one pass" if len(cl) > 30 else ""))
    for f, t, c, la, lb in merges[:4]:
        print("MERGE     %s + %s (%d+%d lines, together %d×)" % (f, t, la, lb, c))
    for p, n, k in splits[:4]:
        print("SPLIT     %s (%d %s)" % (p, n, "files" if k is None
                                         else "lines, pulls in %d folders" % k))
    if missing:
        print("GUIDES    missing: %s%s" % (" · ".join("%s/ (%d)" % (d, per[d]) for d in missing[:8]),
                                          " · +%d" % (len(missing) - 8) if len(missing) > 8 else ""))
    for g, c in stale[:4]:
        print("STALE     %s cites %s (missing)" % (g, c))
    if len(stale) > 4:
        print("STALE     +%d more" % (len(stale) - 4))
    print("next: bash ops/polaris hops --tsv lists every row · ops/roles/TIDY.md runs the pass")
    return 0


def usage():
    sys.stderr.write(
        "usage: index.py find <symbol>|-f <glob>|-t <text>|--importers <path>|--imports <path>\n"
        "                       |--api <glob>...   [-n N]\n"
        "       index.py show <path>#<symbol> | <path>:<line>\n"
        "       index.py hops [--tsv | --propose | --stale | --due | --questions | --facts <dir>]\n"
        "                       | --score|--owned|--proof|--remap <moves.tsv>\n"
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
    if cmd == "hops":
        return cmd_hops(root, argv[1:])
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
