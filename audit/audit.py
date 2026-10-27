#!/usr/bin/env python3
"""Agora provenance audit — is any first-party source copied from GNUstep, from
Apple's swift-corelibs, or from Cocotron?

Two modes, because they answer different questions:

  code   fingerprints code tokens. Code can coincide legitimately: both Agora and
         GNUstep implement the same Apple API, so declarations and thin delegating
         bodies converge because the specification forces them. Treat a hit here
         as a candidate to inspect, not as a finding.

  prose  fingerprints comment text only. Comment prose is the least constrained
         thing in a source file, so a shared 12-word run is the strongest
         available evidence of copying. A clean prose result is the result that
         matters.

Both modes take a positive control (--control), which runs the same comparison
against libagora-core/libagora-dispatch: those are known verbatim extractions of
swift-corelibs, so the control MUST light up. If it does not, the tool is broken
and the clean result is meaningless.

Usage
  ./audit.py setup                     # clone the comparison trees, pinned
  ./audit.py code   [--control]        # code-token audit
  ./audit.py prose  [--control]        # comment-prose audit
  ./audit.py explain AGORA CORPUS      # longest shared token run between two files

Corpus revisions are pinned in CORPUS in this file; `setup` checks them out.
"""

import argparse
import hashlib
import os
import re
import subprocess
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
AGORA = os.path.dirname(HERE)
CORPUS_DIR = os.environ.get("AUDIT_CORPUS", os.path.join(HERE, "corpus"))

# Pinned comparison trees. A clean audit is only meaningful against stated
# revisions, so these are recorded rather than floating.
CORPUS = {
    "libs-base": ("https://github.com/gnustep/libs-base.git", "cb9b67d"),
    "libs-gui": ("https://github.com/gnustep/libs-gui.git", "cacd5cb"),
    "swift-corelibs-foundation": (
        "https://github.com/swiftlang/swift-corelibs-foundation.git", "28249ce"),
    "swift-corelibs-libdispatch": (
        "https://github.com/swiftlang/swift-corelibs-libdispatch.git", "ce1b4d3"),
    # The other independent Cocoa implementation, MIT, dormant since 2015. It is
    # here because a reimplementation this old is exactly the material a model
    # could have absorbed into a "new" file without anyone noticing.
    "cocotron": ("https://github.com/cjwl/cocotron.git", "9cda7d7"),
}

FIRST_PARTY = ["libagora-base", "libagora-app", "libagora-drawing", "libagora-text",
               "libagora-iconservices", "libagora-launchservices", "libagora-watch",
               "window-server", "workspace"]
CONTROL = ["libagora-core", "libagora-dispatch"]
SRC_EXT = (".c", ".h", ".m", ".mm", ".cc", ".cpp")
SKIP_DIRS = {".git", "build", "CMakeFiles", "__pycache__", "themes", "fonts", "art", "assets"}

TOKEN_RE = re.compile(r"""
    //[^\n]*
  | /\*.*?\*/
  | "(?:\\.|[^"\\])*"
  | '(?:\\.|[^'\\])*'
  | [A-Za-z_]\w*
  | \d[\w.]*
  | [^\sA-Za-z0-9_]
""", re.S | re.X)
COMMENT_RE = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)
WORD_RE = re.compile(r"[a-z][a-z0-9_]{2,}")

B = 1000003
MASK = (1 << 64) - 1


def comment_spans(src):
    """(start, end) of every comment, so the tokeniser can skip them."""
    return [(m.start(), m.end()) for m in COMMENT_RE.finditer(src)]


def tokens(path):
    """Code tokens with comments removed and string/char literal TEXT kept.

    Keeping the literal text matters: erasing it makes any comma-separated list
    of quoted strings look like any other, which produced a 369-token false
    positive during the first run of this audit.
    """
    try:
        src = open(path, encoding="utf-8").read()
    except UnicodeDecodeError:
        src = open(path, encoding="latin-1").read()
    except OSError:
        return []
    spans = comment_spans(src)
    out = []
    si = 0
    for m in TOKEN_RE.finditer(src):
        s = m.start()
        while si < len(spans) and spans[si][1] <= s:
            si += 1
        if si < len(spans) and spans[si][0] <= s < spans[si][1]:
            continue
        t = m.group(0)
        c = t[0]
        if c == '"':
            out.append('S' + t[1:-1])
        elif c == "'":
            out.append('C' + t[1:-1])
        else:
            out.append(t)
    return out


def comment_words(path):
    try:
        src = open(path, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        src = open(path, encoding="latin-1").read()
    words = []
    for m in COMMENT_RE.finditer(src):
        t = m.group(0)
        t = t[2:] if t.startswith("//") else t[2:-2]
        words.extend(WORD_RE.findall(t.lower()))
    return words


_TOKEN_HASHES = {}


def token_hash(t):
    """A process-independent 64-bit hash of one token.

    Not hash(): CPython randomises string hashing per process, so winnowing
    picked different minima on every run and two runs of the same corpus
    reported different collision counts (98 vs 104 files on the same trees).
    A recorded number has to be a number the next run reproduces.
    """
    h = _TOKEN_HASHES.get(t)
    if h is None:
        h = int.from_bytes(hashlib.blake2b(t.encode("utf-8", "surrogatepass"),
                                           digest_size=8).digest(), "big")
        _TOKEN_HASHES[t] = h
    return h


def shingles(toks, k):
    """Rolling 64-bit hashes over k-token shingles."""
    if len(toks) < k:
        return []
    ints = [token_hash(t) for t in toks]
    bk = pow(B, k - 1, 1 << 64)
    h = 0
    for i in range(k):
        h = (h * B + ints[i]) & MASK
    hs = [h]
    for i in range(k, len(ints)):
        h = (((h - ints[i - k] * bk) & MASK) * B + ints[i]) & MASK
        hs.append(h)
    return hs


def winnow(hs, w):
    """Keep the minimum of each window: a sparse set with no gap longer than w."""
    if len(hs) < w:
        return set(hs)
    out, last = set(), None
    for i in range(len(hs) - w + 1):
        win = hs[i:i + w]
        pos = i + win.index(min(win))
        if pos != last:
            out.add(hs[pos])
            last = pos
    return out


def tree_counts(rels):
    """Hits per corpus tree, so coverage of each upstream is visible, not implied."""
    c = Counter(rel.split(os.sep)[0] for rel in rels)
    return ", ".join(f"{t} {n}" for t, n in sorted(c.items(), key=lambda kv: -kv[1]))


def walk(root, repos):
    files = []
    for repo in repos:
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, repo)):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                if fn.endswith(SRC_EXT):
                    p = os.path.join(dirpath, fn)
                    files.append((os.path.relpath(p, root), p))
    return sorted(files)


def corpus_files():
    """Every corpus file, with a guard against a corpus that is not there.

    A missing tree used to be indistinguishable from a clean tree: os.walk
    yields nothing and the audit prints NO COLLISIONS. Now that five upstreams
    are pinned, that silence would be the easiest way to record a result that
    compared against nothing.
    """
    present = set(os.listdir(CORPUS_DIR))
    absent = [n for n in CORPUS if n not in present]
    if absent:
        sys.exit(f"corpus missing: {', '.join(absent)} — run `audit.py setup`")
    files = []
    for name in sorted(present):
        got = walk(CORPUS_DIR, [name])
        if not got:
            sys.exit(f"corpus tree {name} has no source files: bad checkout")
        print(f"  corpus {name:<32}{len(got):>5} files", flush=True)
        files.extend(got)
    return files


def audit_code(repos, k, w, label):
    print(f"\n=== {label} (code tokens, k={k}, w={w}) ===", flush=True)
    afiles = walk(AGORA, repos)
    cfiles = corpus_files()
    aset, index = {}, {}
    for i, (_rel, p) in enumerate(afiles):
        hs = winnow(shingles(tokens(p), k), w)
        aset[i] = hs
        for h in hs:
            index.setdefault(h, i)
    print(f"  Agora files {len(afiles)}, fingerprints {len(index)}", flush=True)
    hits = Counter()
    for rel, p in cfiles:
        for h in winnow(shingles(tokens(p), k), w):
            fid = index.get(h)
            if fid is not None:
                hits[(fid, rel)] += 1
    if not hits:
        print("  NO COLLISIONS")
        return []
    best = {}
    for (fid, c), n in hits.items():
        frac = n / max(1, len(aset[fid]))
        if frac > best.get(fid, (0, ""))[0]:
            best[fid] = (frac, c)
    kind = Counter("header" if afiles[f][0].endswith(".h") else "source" for f in best)
    print(f"  files with any collision : {len(best)} of {len(afiles)}  {dict(kind)}")
    trees = tree_counts(c for _f, c in hits)
    if trees:
        print("  collision pairs by corpus: " + trees)
    print(f"  {'agora file':<44}{'frac':>7}  corpus file")
    for fid, (frac, c) in sorted(best.items(), key=lambda kv: -kv[1][0])[:12]:
        print(f"  {afiles[fid][0]:<44}{frac*100:>6.1f}%  {c}")
    return list(best.items())


def audit_prose(repos, n, label):
    print(f"\n=== {label} (comment prose, {n}-word shingles) ===", flush=True)
    afiles = walk(AGORA, repos)
    cfiles = corpus_files()
    index = {}
    for i, (_rel, p) in enumerate(afiles):
        w = comment_words(p)
        for j in range(max(0, len(w) - n + 1)):
            index.setdefault(tuple(w[j:j + n]), i)
    print(f"  Agora files {len(afiles)}, prose shingles {len(index)}", flush=True)
    if not index:
        print("  NO COMMENT PROSE TO INDEX")
        return []
    hits = Counter()
    for rel, p in cfiles:
        w = comment_words(p)
        c = Counter()
        for j in range(max(0, len(w) - n + 1)):
            fid = index.get(tuple(w[j:j + n]))
            if fid is not None:
                c[fid] += 1
        for fid, m in c.items():
            hits[(fid, rel)] += m
    if not hits:
        print("  NO SHARED COMMENT PROSE")
        return []
    per = Counter(f for f, _ in hits)
    print(f"  Agora files sharing comment prose: {len(per)} of {len(afiles)}")
    trees = tree_counts(c for _f, c in hits)
    if trees:
        print("  shared runs by corpus    : " + trees)
    for (fid, c), m in sorted(hits.items(), key=lambda kv: -kv[1])[:10]:
        print(f"    {afiles[fid][0]:<46}{m:>5} shared  {c}")
    return list(hits)


def explain(agora_rel, corpus_rel, k):
    frompath = agora_rel if os.path.isabs(agora_rel) else os.path.join(AGORA, agora_rel)
    topath = corpus_rel if os.path.isabs(corpus_rel) else os.path.join(CORPUS_DIR, corpus_rel)
    a, b = tokens(frompath), tokens(topath)
    idx = {}
    for j in range(max(0, len(b) - k + 1)):
        idx.setdefault(tuple(b[j:j + k]), j)
    best = (0, 0, 0)
    for i in range(max(0, len(a) - k + 1)):
        j = idx.get(tuple(a[i:i + k]))
        if j is None:
            continue
        e = k
        while i + e < len(a) and j + e < len(b) and a[i + e] == b[j + e]:
            e += 1
        if e > best[0]:
            best = (e, i, j)
    n, i, j = best
    print(f"{os.path.basename(frompath)} vs {os.path.basename(topath)}: "
          f"{n} identical tokens" if n else "no shared run")
    if n:
        print("  agora :", " ".join(a[i:i + min(n, 24)]))
        print("  corpus:", " ".join(b[j:j + min(n, 24)]))


def setup():
    """Clone/check out every pinned tree, and refuse to report a pin it cannot reach.

    The old version ignored fetch and checkout failures, so an unreachable pin
    left the tree on whatever HEAD happened to be and the audit then produced a
    result labelled with a revision it never read.
    """
    os.makedirs(CORPUS_DIR, exist_ok=True)
    bad = []
    for name, (url, rev) in CORPUS.items():
        dst = os.path.join(CORPUS_DIR, name)
        if not os.path.isdir(os.path.join(dst, ".git")):
            subprocess.run(["git", "clone", "--quiet", url, dst], check=True)

        def have():
            return subprocess.run(["git", "-C", dst, "cat-file", "-e", rev + "^{commit}"],
                                  capture_output=True).returncode == 0

        if not have():
            print(f"  {name:<30}fetching {rev}", flush=True)
            subprocess.run(["git", "-C", dst, "fetch", "--quiet", "origin", rev],
                           check=False)
        if not have():
            print(f"  {name:<30}PIN MISSING: {rev}", flush=True)
            bad.append(name)
            continue

        subprocess.run(["git", "-C", dst, "checkout", "--quiet", "--detach", rev],
                       check=True)
        head = subprocess.run(["git", "-C", dst, "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", dst, "status", "--porcelain"],
                               capture_output=True, text=True).stdout.strip()
        print(f"  {name:<30}{head}{'  MODIFIED (not the pin)' if dirty else ''}")
    if bad:
        sys.exit(f"could not check out: {', '.join(bad)} — the audit would not have "
                 f"compared the pinned revision")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("setup")
    for name in ("code", "prose"):
        p = sub.add_parser(name)
        p.add_argument("--control", action="store_true")
        p.add_argument("--k", type=int, default=40)
        p.add_argument("--w", type=int, default=8)
        p.add_argument("--n", type=int, default=12)
    p = sub.add_parser("explain")
    p.add_argument("agora")
    p.add_argument("corpus")
    p.add_argument("--k", type=int, default=40)
    args = ap.parse_args()

    if args.cmd == "setup":
        return setup()
    if args.cmd == "explain":
        return explain(args.agora, args.corpus, args.k)
    if not os.path.isdir(CORPUS_DIR):
        sys.exit(f"no corpus at {CORPUS_DIR}: run `{os.path.basename(__file__)} setup` first")

    if args.control:
        if args.cmd == "code":
            audit_code(CONTROL, args.k, args.w, "POSITIVE CONTROL")
        else:
            audit_prose(CONTROL, args.n, "POSITIVE CONTROL")
        print()

    if args.cmd == "code":
        hit = audit_code(FIRST_PARTY, args.k, args.w, "AUDIT")
        print("\nCode collisions are candidates, not findings: inspect them with "
              "`explain`, and weigh the prose result, which is the probative one.")
    else:
        hit = audit_prose(FIRST_PARTY, args.n, "AUDIT")
        print("\nNo shared comment prose is the expected result. If this is not "
              "empty, triage each file per THIRD-PARTY.md.")


if __name__ == "__main__":
    main()
