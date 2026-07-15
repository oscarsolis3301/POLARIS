#!/usr/bin/env python3
"""POLARIS kit packer — builds the single transportable polaris-v5.zip.

    python kit/ops/pack.py               build polaris-v5.zip from HEAD
    python kit/ops/pack.py --bump minor  bump kit/ops/VERSION, then commit + re-run
    python kit/ops/pack.py --allow-dirty build from a dirty worktree (escape hatch)
    python kit/ops/pack.py --dogfood     install the PUBLISHED release into this repo (see below)

Why this exists as Python and not `zip`:
  * Git Bash ships no `zip` binary, and PowerShell's Compress-Archive cannot store
    unix permissions at all.
  * Three kit files are mode 100755 (ops/polaris, ops/install.sh,
    ops/hooks/ownership-guard.sh). An archive that loses the exec bit delivers a
    kit that is dead on arrival. zipfile can set it; nothing else available here can.

WHAT SHIPS is decided by one fact: this file lives in kit/, and every path comes from
`git ls-files -s` run with cwd=kit/ — which lists ONLY what is under kit/, already relative
to it. So kit/ops/polaris packs as polaris-v5/ops/polaris, and the repo's OTHER top-level
directories are excluded structurally rather than by a blacklist somebody has to remember to
extend. That matters here more than in most repos, because this one SELF-HOSTS POLARIS: the
root ops/ is a live board (tasks, MAP, SPRINT, CONVENTIONS, telemetry) and shipping it would
hand every user our board — and, because a target carrying CONVENTIONS.md IS a live board by
definition, would lock INIT out of their repo. ls-files gives the authoritative mode in the
same shot, and excludes .git/ and the ignored zip for free. Bytes are normalised to LF,
because bash cannot execute a CRLF script and Windows checkouts with autocrlf=true would
otherwise poison the archive.

Kit-repo tool only: ops/install.sh's copy list is explicit, so this never ships to a target.
"""
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

# Windows encodes piped stdout with the SYSTEM LOCALE (cp1252 on most machines), not UTF-8, so a
# plain print("✅ …") dies with UnicodeEncodeError. It only works on boxes with UTF-8 mode enabled —
# which is why this survived local testing and died the moment CI ran it. Force UTF-8.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):    # pre-3.7, or already-wrapped stream
        pass

KIT = Path(__file__).resolve().parent.parent     # <repo>/kit — the product's source tree
REPO = KIT.parent                                # <repo>    — which self-hosts POLARIS at ops/
PREFIX = "polaris-v5"                            # top-level folder inside the zip
OUT = REPO / f"{PREFIX}.zip"                     # gitignored; never inside kit/, or it would pack itself
VERSION_FILE = KIT / "ops" / "VERSION"
EXEC_MODE = 0o100755                             # S_IFREG | rwxr-xr-x
DATA_MODE = 0o100644                             # S_IFREG | rw-r--r--


def git(*args):
    return subprocess.run(
        ["git", "-C", str(KIT), *args],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def read_field(text, key):
    """First `<key>: value` line wins. Comments (#) are ignored.

    Values may contain colons (every URL in ops/VERSION does), so partition on the FIRST one only.
    """
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#") or ":" not in line:
            continue
        name, _, val = line.partition(":")
        if name.strip() == key:
            return val.split(" #")[0].strip()      # " #" — a bare # is legal inside a URL fragment
    return None


def read_version(text):
    return read_field(text, "version")


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

        # archive/ is where files go when a change retires them — kept in git so nothing is ever
        # lost (see archive/README.md), but it must NEVER ship into somebody else's project.
        if path.startswith("archive/"):
            continue

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
            "In Claude Code, in your project, just say:         install POLARIS\n"
            "By hand: drop this file in your project and run:   python polaris-v5.zip\n"
            "  ...which also arms this machine, so every install after it is offline + prompt-free.\n"
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


def zip_version(path):
    """The `version:` inside a packed kit. None if it isn't one."""
    try:
        with zipfile.ZipFile(path) as z:
            return read_version(z.read(f"{PREFIX}/ops/VERSION").decode("utf-8", "replace"))
    except (OSError, KeyError, zipfile.BadZipFile):
        return None


def dogfood():
    """Install the PUBLISHED release into this repo, exactly as a stranger would.

    This repo self-hosts POLARIS: kit/ is the product, and the root ops/ is a real installation
    that runs our own board. Refreshing that installation is not a chore — it is the acceptance
    test for a release, and the only one taken through the path a user actually walks. We fetch
    the artifact from releases/latest (not our own working tree, and not the branch tarball,
    either of which could be ahead of what the world can download), install it, and prove the
    board still works. A release that cannot run our board is not a release.

    It lands on install.sh's LIVE-BOARD path, so board/, CONVENTIONS.md, MAP.md, SPRINT.md and
    RULES.tsv are untouched; only kit code and the managed CLAUDE.md block are refreshed.
    Nothing is committed — you read the diff, like any other change.
    """
    if git("status", "--porcelain"):
        sys.exit("⛔ worktree is dirty — commit or stash first, so the refresh lands as a reviewable diff.")

    text = VERSION_FILE.read_text(encoding="utf-8")
    want, url = read_version(text), read_field(text, "zip")
    if not url:
        sys.exit("no `zip:` line in kit/ops/VERSION — that is the published-release URL")

    tmp = Path(tempfile.mkdtemp(prefix="polaris-dogfood-"))
    try:
        print(f"   fetching {url}")
        archive = tmp / f"{PREFIX}.zip"
        try:
            with urllib.request.urlopen(url, timeout=60) as r, open(archive, "wb") as fh:
                shutil.copyfileobj(r, fh)
        except OSError as exc:
            sys.exit(f"⛔ download failed — {exc}\n"
                     "   Is the release published yet? CI attaches the zip when you push the tag.")

        # Validate before we let it near the repo. A truncated download is still a file, and
        # `curl -f`-style status checks do not catch that.
        got = zip_version(archive)
        if not got:
            sys.exit(f"⛔ what came back from {url} is not a POLARIS kit — repo untouched.")
        if got != want:
            sys.exit(
                f"⛔ kit/ops/VERSION says {want}, but releases/latest still serves {got} — repo untouched.\n"
                f"   A fresh tag takes a minute for CI to build and publish. Dogfooding the OLD artifact\n"
                f"   would install the wrong version and then commit it as if it were {want} — only the daily\n"
                f"   'one version, everywhere' job would catch it, later and confusingly. Wait for CI to\n"
                f"   publish {want}, then re-run."
            )

        print(f"   installing {got} into {REPO}")
        rc = subprocess.run([sys.executable, str(archive), str(REPO)]).returncode
        if rc != 0:
            sys.exit("⛔ install failed — see above. The repo was not left half-installed.")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("   proving the board still works:  ops/polaris doctor --selftest")
    sys.path.insert(0, str(KIT / "ops"))
    from bootstrap import find_bash                    # the Windows-safe resolver, not PATH's `bash`
    bash = find_bash()
    if not bash:
        sys.exit("⛔ no working bash — cannot run the selftest. Install Git for Windows (ships Git Bash).")
    if subprocess.run([bash, "ops/polaris", "doctor", "--selftest"], cwd=str(REPO)).returncode != 0:
        sys.exit(f"⛔ {got} installs, but FAILS its own selftest here. Do not ship it — this is\n"
                 "   exactly the bug --dogfood exists to catch. Undo with: git checkout -- .")

    print(f"\n✅ POLARIS {got} installed from the published release, and it runs our board.")
    changed = git("status", "--porcelain")
    if changed:
        print("   review, then commit the refreshed instance:\n")
        for line in changed.splitlines():
            print(f"   {line}")
    else:
        print("   no diff — this repo was already running the published release.")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--bump":
        bump(args[1] if len(args) > 1 else "")
    elif args and args[0] == "--allow-dirty":
        build(allow_dirty=True)
    elif args and args[0] == "--dogfood":
        dogfood()
    elif args:
        sys.exit(__doc__)
    else:
        build(allow_dirty=False)
