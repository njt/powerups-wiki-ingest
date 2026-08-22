#!/usr/bin/env python3
"""Measure a BOUNDED union rule against every real conflict in the wiki's history.

Rule (the thing being evaluated):
  A conflicted topic/ file is auto-resolvable iff
    (1) the path exists in the merge base (never auto-resolve add/add), AND
    (2) every conflict hunk has an EMPTY base section (both sides only ADDED;
        neither revised or deleted a base line).
  Resolution = ours-block then theirs-block, with a blank line between them
  if neither side already supplies one.
Otherwise: leave it as today's loud failure.
"""
import argparse, subprocess, sys, tempfile, os


def die(msg, code=2):
    print(f"bounded-union-audit: {msg}", file=sys.stderr)
    sys.exit(code)


def resolve_wiki(arg):
    wiki = arg or os.environ.get("WIKI_PATH")
    if not wiki:
        die("WIKI_PATH is not set and --wiki was not given.\n"
            "  export WIKI_PATH=/path/to/wiki")
    wiki = os.path.expanduser(wiki)
    if not os.path.isdir(wiki):
        die(f"not a directory: {wiki}")
    if not os.path.exists(os.path.join(wiki, ".git")):
        die(f"not a git repository: {wiki} — this audit replays the wiki's own "
            "merge history, so it needs a real wiki with history")
    return wiki


_ap = argparse.ArgumentParser(prog="bounded-union-audit", description=__doc__,
                              formatter_class=argparse.RawDescriptionHelpFormatter)
_ap.add_argument("--wiki", help="wiki root (default: $WIKI_PATH)")
W = resolve_wiki(_ap.parse_args().wiki)

def git(*a, **kw):
    return subprocess.run(["git", "-C", W] + list(a), capture_output=True, **kw)

def blob(rev, path):
    r = git("show", f"{rev}:{path}")
    return None if r.returncode else r.stdout.decode("utf-8", "replace")

def classify(ours, base, theirs):
    """Return (eligible, resolved_text) using diff3-style conflict regions."""
    fs = []
    for txt in (ours, base, theirs):
        f = tempfile.NamedTemporaryFile("w", delete=False, suffix=".md")
        f.write(txt); f.close(); fs.append(f.name)
    r = subprocess.run(["git", "merge-file", "--diff3", "-p"] + fs, capture_output=True)
    out = r.stdout.decode("utf-8", "replace")
    for f in fs: os.unlink(f)
    if r.returncode == 0:
        return True, out           # merged cleanly, nothing to decide
    res, state, o, b, t = [], 0, [], [], []
    for line in out.splitlines(keepends=True):
        if line.startswith("<<<<<<<"): state, o, b, t = 1, [], [], []; continue
        if line.startswith("|||||||") and state == 1: state = 2; continue
        if line.startswith("=======") and state == 2: state = 3; continue
        if line.startswith(">>>>>>>") and state == 3:
            if [x for x in b if x.strip()]:
                return False, None            # a base line was revised/removed
            blk = list(o)
            if blk and blk[-1].strip() and t and t[0].strip():
                blk.append("\n")              # keep the two added blocks separate
            res.extend(blk + t); state = 0; continue
        (res if state == 0 else o if state == 1 else b if state == 2 else t).append(line)
    return True, "".join(res)

merges = git("log", "--merges", "--since=2026-08-05", "--format=%h").stdout.decode().split()
stats = {"auto-ok": 0, "auto-WRONG": 0, "kept-as-failure": 0}
for c in merges:
    p1 = git("rev-parse", f"{c}^1").stdout.decode().strip()
    p2r = git("rev-parse", f"{c}^2")
    if p2r.returncode: continue
    p2 = p2r.stdout.decode().strip()
    mb = git("merge-base", p1, p2).stdout.decode().strip()
    names = git("-c", "core.quotePath=false", "show", "--cc", "--name-only", "--format=", c).stdout.decode()
    for f in [n for n in names.splitlines() if n.startswith("topic/")]:
        ours, theirs, human = blob(p1, f), blob(p2, f), blob(c, f)
        base = blob(mb, f)
        if ours is None or theirs is None or human is None: continue
        # is it a real conflict at all?
        fs = []
        for txt in (ours, base or "", theirs):
            t = tempfile.NamedTemporaryFile("w", delete=False); t.write(txt); t.close(); fs.append(t.name)
        clean = subprocess.run(["git", "merge-file", "-p"] + fs, capture_output=True).returncode == 0
        for x in fs: os.unlink(x)
        if clean: continue
        if base is None:
            stats["kept-as-failure"] += 1
            print(f"KEPT-AS-FAILURE (add/add)   {c}  {f}"); continue
        elig, resolved = classify(ours, base, theirs)
        if not elig:
            stats["kept-as-failure"] += 1
            print(f"KEPT-AS-FAILURE (revision)  {c}  {f}")
        elif resolved == human:
            stats["auto-ok"] += 1
            print(f"AUTO == human resolution    {c}  {f}")
        else:
            stats["auto-WRONG"] += 1
            print(f"AUTO != human resolution    {c}  {f}")
            import difflib
            for l in list(difflib.unified_diff(resolved.splitlines(), human.splitlines(), "auto", "human", n=0))[:8]:
                print("      " + l[:150])
print("\n", stats)
