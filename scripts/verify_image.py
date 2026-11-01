#!/usr/bin/env python3
"""Fail when an image breaks its partition, header or content expectations."""

import argparse
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bootimg


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--max-size", type=int)
    parser.add_argument("--header-version", type=int)
    parser.add_argument("--contains", action="append", default=[])
    parser.add_argument("--min-ramdisk-size", type=int, default=0)
    args = parser.parse_args(argv)

    data = open(args.image, "rb").read()
    meta = bootimg.info(args.image)
    failures = []
    if args.max_size and len(data) > args.max_size:
        failures.append(f"size {len(data)} exceeds {args.max_size}")
    if args.header_version is not None and meta["header_version"] != args.header_version:
        failures.append(f"header version {meta['header_version']} != {args.header_version}")
    if meta["ramdisk_size"] < args.min_ramdisk_size:
        failures.append(f"ramdisk {meta['ramdisk_size']} smaller than {args.min_ramdisk_size}")
    for marker in args.contains:
        if marker.encode() not in data:
            failures.append(f"missing marker {marker!r}")
    summary = dict(meta)
    summary["sha256"] = hashlib.sha256(data).hexdigest()
    print(json.dumps(summary, indent=2))
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print("image checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
