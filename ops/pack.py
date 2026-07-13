#!/usr/bin/env python3
"""POLARIS kit packer — builds the single transportable polaris-v5.zip.

    python ops/pack.py                  build polaris-v5.zip from HEAD
    python ops/pack.py --bump minor     bump ops/VERSION, then commit + re-run
    python ops/pack.py --allow-dirty    build from a dirty worktree (escape hatch)

Why this exists as Python and not `zip`:
  * Git Bash ships no `zip` binary, and PowerShell's Compress-Archive cannot store
    unix permissions at all.
  * Three kit files are mode 100755 (ops/polaris, ops/install.sh,
    ops/hooks/ownership-guard.sh). An archive that loses the exec bit delivers a
    kit that is dead on arrival. zipfile can set it; nothing else available here can.

Contents come from `git ls-files -s`, which gives the file list AND the authoritative
mode in one shot — and excludes .git/ and the ignored zip for free. Bytes are
normalised to LF, because bash cannot execute a CRLF script and Windows checkouts
with autocrlf=true would otherwise poison the archive.

Kit-repo tool only: ops/install.sh's copy list is explicit, so this never ships to a target.
"""
import subprocess
import sys
import zipfile
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
PREFIX = "polaris-v5"                      # top-level folder inside the zip
OUT = KIT / f"{PREFIX}.zip"
VERSION_FILE = KIT / "ops" / "VERSION"
EXEC_MODE = 0o100755                       # S_IFREG | rwxr-xr-x
DATA_MODE = 0o100644                       # S_IFREG | rw-r--r--


def git(*args):
    return subprocess.run(
        ["git", "-C", str(KIT), *args],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def read_version(text):
    """First `version:` line wins. Comments (#) are ignored."""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#") or ":" not in line:
            continue
        key, _, val = line.partition(":")
        if key.strip() == "version":
            return val.split("#")[0].strip()
    return None


def bump(part):
    text = VERSION_FILE.read_text(encoding="utf-8")
    current = read_version(text)
    if not current:
        sys.exit("no `version:` line in ops/VERSION")
    try:
        major, minor, patch = (int(n) for n in current.split("."))
    except ValueError:
        sys.exit(f"version {current!r} is not X.Y.Z")

    if part == "major":
        major, minor, patch = major + 1, 0, 0
    elif part == "minor":
        minor, patch = minor + 1, 0
    elif part == "patch":
        patch += 1
    else:
        sys.exit("--bump takes: major | minor | patch")

    new = f"{major}.{minor}.{patch}"
    VERSION_FILE.write_text(
        text.replace(f"version: {current}", f"version: {new}", 1),
        encoding="utf-8", newline="\n",
    )
    print(f"✅ ops/VERSION  {current} → {new}")
    print(f"   next: update CHANGELOG.md, commit, then  git tag v{new} && git push --tags")
    print("   CI builds and attaches the zip; installed kits see the bump on their next daily check.")


def build(allow_dirty):
    if git("status", "--porcelain") and not allow_dirty:
        sys.exit(
            "⛔ worktree is dirty — commit first, so the zip maps to a real commit.\n"
            "   (escape hatch: python ops/pack.py --allow-dirty)"
        )

    # `git ls-files` reads the INDEX, so an uncommitted new file is silently absent from the
    # archive. Only --allow-dirty can reach this, and a zip quietly missing a file is worse
    # than no zip — say so loudly.
    untracked = git("ls-files", "--others", "--exclude-standard").splitlines()
    if untracked:
        print("⚠ NOT in the zip — untracked (git add them first):")
        for path in untracked:
            print(f"   ?? {path}")

    sha = git("rev-parse", "--short", "HEAD")
    # Commit date, not wall-clock: the same commit always packs to the same bytes.
    built = git("show", "-s", "--format=%cs", "HEAD")
    stamp = tuple(int(n) for n in git("show", "-s", "--format=%cd",
                                      "--date=format:%Y %m %d %H %M %S", "HEAD").split())

    version = read_version(VERSION_FILE.read_text(encoding="utf-8"))
    if not version:
        sys.exit("no `version:` line in ops/VERSION")

    entries, execs = [], []
    for line in git("ls-files", "-s").splitlines():
        meta, path = line.split("\t", 1)
        mode = meta.split()[0]
        blob = (KIT / path).read_bytes()
        is_exec = mode == "100755"

        # LF-normalise text only. A blanket \r\n→\n would corrupt any binary that ever
        # entered the kit (a stray .pyc did exactly that once). NUL = binary, same
        # heuristic git uses.
        if b"\x00" not in blob:
            blob = blob.replace(b"\r\n", b"\n")

        if path == "ops/VERSION":
            # Provenance is stamped into the emitted copy only. Writing the sha into
            # the tracked file would change the tree, which changes the sha.
            blob += f"commit: {sha}\nbuilt: {built}\n".encode()

        entries.append((path, blob, is_exec))
        if is_exec:
            execs.append(path)

    if not entries:
        sys.exit("⛔ git ls-files returned nothing — is this the kit repo?")

    # __main__.py at the ARCHIVE ROOT is what makes this a Python zipapp: `python
    # polaris-v5.zip` then runs it directly, so a drag-and-drop install needs no unzip step.
    # It must sit at the root, not under the prefix — that's the whole contract.
    entries.append(("__main__.py", (KIT / "ops" / "bootstrap.py").read_bytes()
                    .replace(b"\r\n", b"\n"), False))

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        # Archive comment: `unzip -z polaris-v5.zip` prints this. It's the zero-setup fallback
        # that lets a human (or an agent) discover how to run the kit without opening it.
        z.comment = (
            f"POLARIS {version} — parallel-sprint protocol for coding agents.\n"
            "Install: drop this file in your project and run:  python polaris-v5.zip\n"
            "Teach Claude Code to do it for you:               python polaris-v5.zip --claude-skill\n"
            "No Python? unzip polaris-v5.zip && bash polaris-v5/ops/install.sh\n"
            "https://github.com/oscarsolis3301/POLARIS\n"
        ).encode()
        for path, blob, is_exec in sorted(entries):
            name = path if path == "__main__.py" else f"{PREFIX}/{path}"
            info = zipfile.ZipInfo(name, date_time=stamp)
            info.create_system = 3                              # Unix — required, or the
            info.external_attr = (EXEC_MODE if is_exec          # permission bits below
                                  else DATA_MODE) << 16         # are ignored on extract
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, blob)

    print(f"✅ {OUT.name}  v{version} @ {sha}  ({len(entries)} files, {OUT.stat().st_size:,} bytes)")
    for path in sorted(execs):
        print(f"   +x {PREFIX}/{path}")
    print("   drop it in any project and run:  python polaris-v5.zip")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--bump":
        bump(args[1] if len(args) > 1 else "")
    elif args and args[0] == "--allow-dirty":
        build(allow_dirty=True)
    elif args:
        sys.exit(__doc__)
    else:
        build(allow_dirty=False)
