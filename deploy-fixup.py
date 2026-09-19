#!/usr/bin/env python3

# fix homebrew path issues

import os
import re
import subprocess
import sys

HOMEBREW = re.compile(
    r"^/opt/homebrew/(?:opt/[^/]+/)?lib/"
    r"(?P<loc>Q[^/]+\.framework/\S+|lib\S+\.dylib)$"
)
EXEC_PREFIX = "@executable_path/../Frameworks/"
RPATH_PREFIX = "@rpath/"
LOADER_PREFIX = "@loader_path/"


def macho_files(root):
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(dirpath, name)
            # Framework bundles symlink X.framework/X -> Versions/Current/X.
            # install_name_tool would follow that and rewrite the real binary
            # with paths relative to the symlink's directory, corrupting it.
            if os.path.islink(path):
                continue
            yield path


def locator(ref, file_dir, frameworks):
    """Map a reference to its locator under Contents/Frameworks, or None."""
    if ref.startswith(EXEC_PREFIX):
        return ref[len(EXEC_PREFIX):]
    if ref.startswith(RPATH_PREFIX):
        cand = ref[len(RPATH_PREFIX):]
        if "/" not in cand:
            return None  # bare dylib rpath -- can't be sure it lives in Frameworks
        return cand
    m = HOMEBREW.match(ref)
    if m:
        return m.group("loc")
    if ref.startswith(LOADER_PREFIX):
        # @loader_path refs may point just outside this framework's versioned
        # directory (e.g. "Versions/A/../libicu" which does not exist while
        # "Frameworks/libicu" does). Heal those rather than assume they're right.
        relpart = ref[len(LOADER_PREFIX):]
        cand = os.path.realpath(os.path.join(file_dir, relpart))
        if os.path.exists(cand):
            return None  # resolves fine -- not our problem
        m = re.search(r"([^/]+\.framework/.*)$", relpart)
        tail = m.group(1) if m else os.path.basename(relpart)
        if os.path.exists(os.path.join(frameworks, tail)):
            return tail
        return None
    return None


def main():
    args = sys.argv[1:]
    main_only = "--main-only" in args
    args = [a for a in args if a != "--main-only"]
    if len(args) != 2:
        sys.exit("usage: deploy-fixup.py /path/to/App.app /path/to/main-executable [--main-only]")
    bundle, main_exe = args
    frameworks = os.path.join(bundle, "Contents", "Frameworks")
    if not os.path.isdir(frameworks):
        sys.exit(f"no Contents/Frameworks in {bundle}")

    main_exe = os.path.realpath(main_exe)
    files = [main_exe] if main_only else list(macho_files(os.path.join(bundle, "Contents")))
    dirty = 0

    for f in files:
        out = subprocess.run(
            ["otool", "-L", f], capture_output=True, text=True, check=False
        ).stdout
        refs = out.splitlines()[1:]
        if not refs:
            continue

        dir_of_f = os.path.dirname(f)
        changes = []
        for line in refs:
            parts = line.split()
            if not parts:
                continue
            old = parts[0]
            loc = locator(old, dir_of_f, frameworks)
            if not loc:
                continue
            target = os.path.join(frameworks, loc)
            if not os.path.exists(target):
                print(f"  skip (not bundled): {old}", file=sys.stderr)
                continue
            new = "@loader_path/" + os.path.relpath(target, dir_of_f)
            if new != old:
                changes.append((old, new))

        if not changes:
            continue
        dirty += 1
        for old, new in changes:
            subprocess.run(
                ["install_name_tool", "-change", old, new, f],
                check=True, stdout=subprocess.DEVNULL,
            )
        print(f"fixed {os.path.relpath(f, bundle)} ({len(changes)} refs)")

    print(f"\nRewrote {dirty} of {len(files)} Mach-O files under the bundle.")


if __name__ == "__main__":
    main()