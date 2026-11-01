#!/usr/bin/env python3
"""Pack and inspect Android boot images (header v3/v4) without external toolchains."""

import argparse
import hashlib
import json
import struct
import sys

MAGIC = b"ANDROID!"
ARGS_SIZE = 512
EXTRA_ARGS_SIZE = 1024
HEADER_V3_SIZE = 1580
HEADER_V4_SIZE = 1584


def round_up(value, align):
    return (value + align - 1) // align * align


def build_header(kernel_size, ramdisk_size, os_version, header_version, cmdline):
    if header_version not in (3, 4):
        raise SystemExit(f"unsupported header_version {header_version}")
    header_size = HEADER_V4_SIZE if header_version == 4 else HEADER_V3_SIZE
    cmdline_bytes = cmdline.encode()
    if len(cmdline_bytes) > ARGS_SIZE + EXTRA_ARGS_SIZE - 1:
        raise SystemExit("cmdline too long")
    out = bytearray()
    out += struct.pack("<8s", MAGIC)
    out += struct.pack("<I", kernel_size)
    out += struct.pack("<I", ramdisk_size)
    out += struct.pack("<I", os_version)
    out += struct.pack("<I", header_size)
    out += struct.pack("<4I", 0, 0, 0, 0)
    out += struct.pack("<I", header_version)
    out += cmdline_bytes.ljust(ARGS_SIZE + EXTRA_ARGS_SIZE, b"\x00")
    if header_version == 4:
        out += struct.pack("<I", 0)
    if len(out) != header_size:
        raise SystemExit(f"header size mismatch: built {len(out)}, expected {header_size}")
    return bytes(out)


def pack(kernel_path, ramdisk_path, output_path, pagesize, header_version, cmdline, os_version):
    kernel = read_or_empty(kernel_path)
    ramdisk = read_or_empty(ramdisk_path)
    header = build_header(len(kernel), len(ramdisk), os_version, header_version, cmdline)
    with open(output_path, "wb") as handle:
        handle.write(header.ljust(round_up(len(header), pagesize), b"\x00"))
        if kernel:
            handle.write(kernel.ljust(round_up(len(kernel), pagesize), b"\x00"))
        if ramdisk:
            handle.write(ramdisk.ljust(round_up(len(ramdisk), pagesize), b"\x00"))


def read_or_empty(path):
    if not path:
        return b""
    with open(path, "rb") as handle:
        return handle.read()


def info(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != MAGIC:
        raise SystemExit(f"{path}: bad boot magic")
    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from("<4I", data, 8)
    header_version, = struct.unpack_from("<I", data, 8 + 4 * 4 + 16)
    cmdline = data[8 + 4 * 4 + 16 + 4:8 + 4 * 4 + 16 + 4 + ARGS_SIZE + EXTRA_ARGS_SIZE]
    signature_size = 0
    if header_version >= 4:
        signature_size, = struct.unpack_from("<I", data, 8 + 4 * 4 + 16 + 4 + ARGS_SIZE + EXTRA_ARGS_SIZE)
    payload_offset = round_up(header_size, 4096)
    kernel = data[payload_offset:payload_offset + kernel_size]
    ramdisk = data[payload_offset + round_up(kernel_size, 4096):payload_offset + round_up(kernel_size, 4096) + ramdisk_size]
    return {
        "path": path,
        "size": len(data),
        "header_version": header_version,
        "header_size": header_size,
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "os_version": os_version,
        "cmdline": cmdline.split(b"\x00", 1)[0].decode("ascii", "replace"),
        "signature_size": signature_size,
        "kernel_sha256": hashlib.sha256(kernel).hexdigest() if kernel_size else None,
        "ramdisk_sha256": hashlib.sha256(ramdisk).hexdigest() if ramdisk_size else None,
    }


def main(argv):
    if not argv:
        raise SystemExit("usage: bootimg.py pack|info ...")
    command = argv[0]
    if command == "info":
        print(json.dumps([info(path) for path in argv[1:]], indent=2))
        return 0
    if command == "pack":
        parser = argparse.ArgumentParser()
        parser.add_argument("--kernel")
        parser.add_argument("--ramdisk")
        parser.add_argument("--output", required=True)
        parser.add_argument("--pagesize", type=int, default=4096)
        parser.add_argument("--header-version", type=int, default=4)
        parser.add_argument("--cmdline", default="")
        parser.add_argument("--os-version", type=lambda text: int(text, 0), default=0)
        args = parser.parse_args(argv[1:])
        pack(args.kernel, args.ramdisk, args.output, args.pagesize, args.header_version, args.cmdline, args.os_version)
        return 0
    raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
