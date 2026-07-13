#!/usr/bin/env python3
"""Drag-and-run entry point. pack.py copies this to the ZIP ROOT as __main__.py, which
makes polaris-v5.zip a Python zipapp — so the whole install is one command, no unzip:

    cd your-project
    python polaris-v5.zip                 # installs into the git repo you're standing in
    python polaris-v5.zip <target-repo>   # or name one (git init'd if greenfield)
    python polaris-v5.zip --claude-skill  # teach Claude Code to do all this for you, everywhere

Self-extracts to a temp dir, restores the exec bits the archive carries, and hands off to
the same ops/install.sh that a manual unzip would run. Nothing is left behind but the install.

Why the target is resolved HERE and not by install.sh: install.sh's zero-arg mode looks for the
git repo enclosing *the kit*, which — once we've extracted to a temp dir — is not your project.
So resolve from the CWD and always pass it explicitly. The safety rule still holds: we `git init`
only a directory you named, never one you merely happened to be standing in.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

# Windows encodes piped stdout with the SYSTEM LOCALE (cp1252 on most machines), not UTF-8, so a
# plain print("✅ …") dies with UnicodeEncodeError. Without this, `python polaris-v5.zip` — the
# whole point of the kit — crashed on any Windows box that doesn't have UTF-8 mode enabled.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):    # pre-3.7, or already-wrapped stream
        pass

PREFIX = "polaris-v5/"


def die(msg):
    sys.exit(f"⛔ {msg}")


def find_bash():
    """The one that actually runs — not the one PATH hands you.

    On Windows, `bash` on PATH is usually C:\\Windows\\System32\\bash.exe: that is WSL's
    launcher, and with no distro installed it dies instantly. Python is a native Windows
    process, so shutil.which() walks straight into it. Derive Git Bash from git's own
    install root instead, and PROVE each candidate runs before trusting it — the same
    "make it execute something" probe the kit uses to unmask the Windows Store python stub.
    """
    cands = []
    if os.name == "nt":
        git = shutil.which("git")
        if git:
            # git.exe lives at <root>\cmd\, <root>\bin\ or <root>\mingw64\bin\
            here = os.path.dirname(os.path.abspath(git))
            for root in (os.path.dirname(here), os.path.dirname(os.path.dirname(here))):
                cands += [os.path.join(root, "bin", "bash.exe"),
                          os.path.join(root, "usr", "bin", "bash.exe")]
        for pf in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
            if pf:
                cands.append(os.path.join(pf, "Git", "bin", "bash.exe"))
    cands.append(shutil.which("bash"))      # last on Windows: may well be WSL
    if os.name != "nt":
        cands.append("/bin/bash")

    seen = set()
    for cand in cands:
        if not cand or cand in seen or not os.path.isfile(cand):
            continue
        seen.add(cand)
        try:
            probe = subprocess.run([cand, "-c", "printf polaris_ok"],
                                   capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            continue
        if probe.returncode == 0 and b"polaris_ok" in probe.stdout:
            return cand
    return None


def git_toplevel(path):
    try:
        out = subprocess.run(
            ["git", "-C", path, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return out or None
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def install_claude_skill(archive):
    """Teach Claude Code, on this machine, how to install POLARIS into ANY repo.

    The project skill (.claude/skills/polaris/) only exists once POLARIS is installed, so it
    cannot help you install it. This one is USER-level (~/.claude/skills/) and is therefore
    opt-in via a flag: it writes outside the project, so it must never be implicit.

    After this, in any repo, "install POLARIS" is all you have to say — Claude will fetch the
    latest release itself if the zip isn't already sitting there.
    """
    src = f"{PREFIX}.claude/skills/polaris-install/SKILL.md"
    dest_dir = os.path.join(os.path.expanduser("~"), ".claude", "skills", "polaris-install")
    with zipfile.ZipFile(archive) as z:
        try:
            body = z.read(src)
        except KeyError:
            die("this archive carries no polaris-install skill — rebuild it with ops/pack.py")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, "SKILL.md")
    with open(dest, "wb") as fh:
        fh.write(body)
    print(f"✅ Claude skill installed: {dest}")
    print("   In any repo from now on, just say:  \"install POLARIS\"")
    print("   Claude fetches the latest release itself — you don't even need the zip.")


def main():
    archive = sys.path[0]          # running as a zipapp, sys.path[0] IS the archive
    if not os.path.isfile(archive) or not zipfile.is_zipfile(archive):
        die("run me as:  python polaris-v5.zip [target-repo]")

    if len(sys.argv) > 1 and sys.argv[1] == "--claude-skill":
        install_claude_skill(archive)
        return

    if not shutil.which("git"):
        die("git not found on PATH — POLARIS is built on git worktrees and branches")
    bash = find_bash()
    if not bash:
        die("no working bash found — on Windows, install Git for Windows (it ships Git Bash).\n"
            "   Note: System32\\bash.exe is WSL, not a shell POLARIS can use.")

    named = len(sys.argv) > 1
    if named:
        target = os.path.abspath(sys.argv[1])
        if not os.path.isdir(target):
            die(f"no such directory: {target}")
    else:
        target = git_toplevel(os.getcwd())
        if not target:
            die("not inside a git repo — cd into your project first, "
                "or name one:  python polaris-v5.zip <target-repo>")

    tmp = tempfile.mkdtemp(prefix="polaris-kit-")
    try:
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                if not info.filename.startswith(PREFIX):
                    continue          # skip __main__.py itself
                dest = z.extract(info, tmp)
                mode = (info.external_attr >> 16) & 0o777
                if mode and not info.is_dir():
                    os.chmod(dest, mode)   # the exec bits the archive preserved

        install = os.path.join(tmp, "polaris-v5", "ops", "install.sh")
        if not os.path.isfile(install):
            die("archive is malformed — no ops/install.sh inside")

        # Forward slashes: bash reads `C:\Users\x` as escape sequences, but takes `C:/Users/x`.
        posix = lambda p: p.replace("\\", "/")
        rc = subprocess.run([bash, posix(install), posix(target)]).returncode
        if rc != 0:
            die("install failed — see the error above; your repo was not left half-installed")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    print("   Next: start a NEW session in this project (CLAUDE.md and the hook are read at")
    print("   session start), then say:  \"You are INIT.\"")


if __name__ == "__main__":
    main()
