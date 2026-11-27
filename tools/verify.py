#!/usr/bin/env python3
"""Verify exported scripts against manifest.tsv (byte length + FNV-1a 32-bit, as computed in Studio).
Usage: python3 tools/verify.py [idx ...]   (no args = all used scripts)"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def fnv1a(b):
    h = 2166136261
    for x in b:
        h ^= x; h = (h * 16777619) & 0xFFFFFFFF
    return "%08x" % h
want = set(int(a) for a in sys.argv[1:])
ok = bad = 0
for line in open(os.path.join(ROOT, "manifest.tsv"), encoding="utf-8").read().splitlines()[1:]:
    cols = line.split("\t")
    idx, n, h, path = cols[:4]
    if len(cols) > 4 and cols[4] != "used": continue  # unused/duplicate files were deleted; row kept as a record
    if want and int(idx) not in want: continue
    p = os.path.join(ROOT, path)
    if not os.path.exists(p):
        print(f"MISSING {idx} {path}"); bad += 1; continue
    data = open(p, "rb").read()
    if len(data) == int(n) and fnv1a(data) == h: ok += 1
    else:
        print(f"MISMATCH {idx} {path}: got {len(data)}B {fnv1a(data)}, want {n}B {h}"); bad += 1
print(f"OK {ok}  BAD {bad}")
sys.exit(1 if bad else 0)
