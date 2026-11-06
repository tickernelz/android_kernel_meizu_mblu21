#!/usr/bin/env python3
"""Fail when an image breaks its partition, header or content expectations."""

import argparse
import gzip
import hashlib
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bootimg


LZ4_LEGACY_MAGIC = 0x184C2102
CPIO_NEWC_MAGICS = (b"070701", b"070702")
CPIO_TRAILER = "TRAILER!!!"


def lz4_block(src, out):
    pos = 0
    end = len(src)
    while pos < end:
        token = src[pos]
        pos += 1
        literals = token >> 4
        if literals == 15:
            while True:
                byte = src[pos]
                pos += 1
                literals += byte
                if byte != 255:
                    break
        out += src[pos:pos + literals]
        pos += literals
        if pos >= end:
            break
        offset = src[pos] | src[pos + 1] << 8
        pos += 2
        if offset == 0 or offset > len(out):
            raise ValueError(f"lz4 match offset {offset} outside {len(out)} decoded bytes")
        length = token & 15
        if length == 15:
            while True:
                byte = src[pos]
                pos += 1
                length += byte
                if byte != 255:
                    break
        length += 4
        start = len(out) - offset
        if length <= offset:
            out += out[start:start + length]
        else:
            for index in range(length):
                out.append(out[start + index])


def lz4_legacy(data):
    out = bytearray()
    pos = 4
    while pos + 4 <= len(data):
        size, = struct.unpack_from("<I", data, pos)
        if size == LZ4_LEGACY_MAGIC:
            pos += 4
            continue
        if size == 0 or pos + 4 + size > len(data):
            break
        lz4_block(data[pos + 4:pos + 4 + size], out)
        pos += 4 + size
    return bytes(out)


def decompress_ramdisk(data):
    if data[:4] == struct.pack("<I", LZ4_LEGACY_MAGIC):
        return "lz4-legacy", lz4_legacy(data)
    if data[:2] == b"\x1f\x8b":
        return "gzip", gzip.decompress(data)
    if data[:6] in CPIO_NEWC_MAGICS:
        return "cpio", data
    raise ValueError(f"unknown ramdisk format, magic {data[:4].hex()}")


def cpio_entries(data):
    names = []
    pos = 0
    while pos + 110 <= len(data):
        if data[pos:pos + 6] not in CPIO_NEWC_MAGICS:
            raise ValueError(f"bad cpio header at {pos}")
        filesize = int(data[pos + 54:pos + 62], 16)
        namesize = int(data[pos + 94:pos + 102], 16)
        name = data[pos + 110:pos + 110 + namesize - 1].decode("utf-8", "replace")
        pos = bootimg.round_up(pos + 110 + namesize, 4)
        pos = bootimg.round_up(pos + filesize, 4)
        if name == CPIO_TRAILER:
            return names
        names.append(name)
    raise ValueError("cpio archive has no trailer")


def ramdisk_bytes(path, meta):
    with open(path, "rb") as handle:
        data = handle.read()
    offset = bootimg.round_up(meta["header_size"], 4096) + bootimg.round_up(meta["kernel_size"], 4096)
    return data[offset:offset + meta["ramdisk_size"]]


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--max-size", type=int)
    parser.add_argument("--header-version", type=int)
    parser.add_argument("--cpio-entry", action="append", default=[])
    parser.add_argument("--list-cpio", action="store_true")
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
    summary = dict(meta)
    if args.cpio_entry or args.list_cpio:
        try:
            summary["ramdisk_format"], cpio = decompress_ramdisk(ramdisk_bytes(args.image, meta))
            entries = cpio_entries(cpio)
        except (ValueError, OSError, EOFError, IndexError) as error:
            failures.append(f"ramdisk unreadable: {error}")
            entries = []
        summary["ramdisk_entries"] = len(entries)
        if args.list_cpio:
            summary["cpio"] = entries
        for entry in args.cpio_entry:
            if entry not in entries:
                failures.append(f"cpio entry {entry!r} missing from ramdisk")
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
