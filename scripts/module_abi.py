#!/usr/bin/env python3
"""Extract modversions ABI from stock modules and check it against a built kernel's Module.symvers."""

import argparse
import glob as globmod
import os
import random
import struct
import sys

MODULE_NAME_LEN = 56
SHN_ABS = 0xFFF1


class Elf:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as handle:
            self.data = handle.read()
        if self.data[:4] != b"\x7fELF" or self.data[4] != 2 or self.data[5] != 1:
            raise ValueError(f"{path}: not a little-endian ELF64 file")
        self.sections = self._read_sections()

    def _read_sections(self):
        shoff, = struct.unpack_from("<Q", self.data, 0x28)
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", self.data, 0x3A)
        raw = []
        for index in range(shnum):
            base = shoff + index * shentsize
            name_off, sh_type, _flags, addr, offset, size, link, _info, _align, entsize = struct.unpack_from(
                "<IIQQQQIIQQ", self.data, base
            )
            raw.append(
                {
                    "name_off": name_off,
                    "type": sh_type,
                    "addr": addr,
                    "offset": offset,
                    "size": size,
                    "link": link,
                    "entsize": entsize,
                }
            )
        strtab = raw[shstrndx]
        out = {}
        for entry in raw:
            start = strtab["offset"] + entry["name_off"]
            end = self.data.index(b"\x00", start)
            name = self.data[start:end].decode("ascii", "replace")
            entry["name"] = name
            out[name] = entry
        return out

    def imports(self):
        section = self.sections.get("__versions")
        if section is None:
            return []
        entsize = section["entsize"] or (8 + MODULE_NAME_LEN)
        out = []
        for index in range(section["size"] // entsize):
            base = section["offset"] + index * entsize
            crc, = struct.unpack_from("<I", self.data, base)
            name = self.data[base + 8:base + entsize].split(b"\x00", 1)[0].decode("ascii", "replace")
            if name:
                out.append((name, crc))
        return out

    def symbols(self):
        symtab = self.sections.get(".symtab")
        if symtab is None:
            raise ValueError(f"{self.path}: no .symtab")
        strtab = next(entry for entry in self.sections.values() if entry is not symtab and entry["type"] == 3 and entry["name"] == ".strtab")
        entsize = symtab["entsize"] or 24
        for index in range(symtab["size"] // entsize):
            base = symtab["offset"] + index * entsize
            name_off, info, _other, shndx, value, _size = struct.unpack_from("<IBBHQQ", self.data, base)
            start = strtab["offset"] + name_off
            name = self.data[start:self.data.index(b"\x00", start)].decode("ascii", "replace")
            yield name, value, shndx

    def exports(self):
        names = set()
        crcs = {}
        for name, value, shndx in self.symbols():
            if name.startswith("__ksymtab_") and name != "__ksymtab_strings":
                names.add(name[len("__ksymtab_"):])
            elif name.startswith("__crc_") and shndx == SHN_ABS:
                crcs[name[len("__crc_"):]] = value & 0xFFFFFFFF
        missing = sorted(names - set(crcs))
        if missing:
            raise ValueError(f"{self.path}: exported without __crc_ symbol: {missing[:5]}")
        return sorted((name, crcs[name]) for name in names)


def module_paths(paths):
    found = []
    for path in paths:
        if os.path.isdir(path):
            found.extend(sorted(globmod.glob(os.path.join(path, "**", "*.ko"), recursive=True)))
        else:
            found.extend(sorted(globmod.glob(path)))
    return found


def cmd_extract(args):
    rows = []
    exports = []
    for path in module_paths(args.modules):
        elf = Elf(path)
        module = os.path.basename(path)
        for symbol, crc in elf.imports():
            rows.append(f"{module}\t{symbol}\t{crc:08x}")
        for symbol, crc in elf.exports():
            exports.append(f"{symbol}\t{module}\t{crc:08x}")
    rows = sorted(set(rows))
    exports = sorted(set(exports))
    write_tsv(args.out_imports, "module\tsymbol\tcrc", rows)
    write_tsv(args.out_exports, "symbol\tmodule\tcrc", exports)
    print(f"extracted {len(rows)} imports and {len(exports)} exports from {len(module_paths(args.modules))} modules")
    return 0


def write_tsv(path, header, rows):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(header + "\n")
        for row in rows:
            handle.write(row + "\n")


def read_tsv(path):
    with open(path, encoding="utf-8") as handle:
        lines = [line.rstrip("\n") for line in handle if line.strip()]
    return lines[0].split("\t"), [line.split("\t") for line in lines[1:]]


def parse_symvers(path):
    table = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                raise ValueError(f"{path}: malformed Module.symvers line: {line!r}")
            crc_text, symbol, owner, export_type = parts[0], parts[1], parts[2], parts[3]
            namespace = parts[4] if len(parts) > 4 else ""
            table[symbol] = {
                "crc": int(crc_text, 16),
                "owner": owner,
                "export_type": export_type,
                "namespace": namespace,
            }
    return table


def compare(imports, module_exported, symvers):
    ok = 0
    skipped = 0
    mismatched = []
    missing = []
    gpl_only = []
    for module, symbol, crc in imports:
        if symbol in module_exported:
            skipped += 1
            continue
        entry = symvers.get(symbol)
        if entry is None:
            missing.append((module, symbol))
            continue
        if entry["crc"] != crc:
            mismatched.append((module, symbol, crc, entry["crc"]))
            continue
        if "GPL" in entry["export_type"]:
            gpl_only.append((module, symbol))
        ok += 1
    return ok, skipped, mismatched, missing, gpl_only


def load_inputs(args):
    _, import_rows = read_tsv(args.imports)
    imports = [(row[0], row[1], int(row[2], 16)) for row in import_rows]
    module_exported = set()
    for path in args.module_exports or []:
        _, export_rows = read_tsv(path)
        module_exported.update(row[0] for row in export_rows)
    return imports, module_exported


def report(result, limit=25):
    ok, skipped, mismatched, missing, gpl_only = result
    print(f"module imports checked against vmlinux exports: {ok}")
    print(f"module-to-module imports skipped (exporter binary unchanged): {skipped}")
    print(f"crc mismatches: {len(mismatched)}")
    print(f"symbols missing from vmlinux: {len(missing)}")
    print(f"symbols reachable only through a GPL-only export: {len(gpl_only)}")
    for module, symbol, want, got in mismatched[:limit]:
        print(f"  mismatch {symbol}: module wants {want:08x}, kernel exports {got:08x} ({module})")
    for module, symbol in missing[:limit]:
        print(f"  missing {symbol} ({module})")
    return not mismatched and not missing


def cmd_check(args):
    imports, module_exported = load_inputs(args)
    symvers = parse_symvers(args.symvers)
    result = compare(imports, module_exported, symvers)
    passed = report(result)
    if args.self_test:
        passed = self_test(imports, module_exported, symvers) and passed
    return 0 if passed else 1


def self_test(imports, module_exported, symvers):
    rng = random.Random(4389)
    candidates = sorted({row[1] for row in imports if row[1] not in module_exported and row[1] in symvers})
    if len(candidates) < 20:
        print("self-test FAILED: too few kernel symbols to perturb")
        return False
    shuffled = rng.sample(candidates, len(candidates))
    perturbed = set(shuffled[: len(shuffled) // 5])
    dropped = set(shuffled[len(shuffled) // 5: len(shuffled) // 5 + len(shuffled) // 10])
    hijacked = dict(symvers)
    for symbol in perturbed:
        entry = dict(hijacked[symbol])
        entry["crc"] ^= 0x5A5A5A5A
        hijacked[symbol] = entry
    for symbol in dropped:
        hijacked.pop(symbol, None)
    expected_mismatch = sum(1 for row in imports if row[1] in perturbed)
    expected_missing = sum(1 for row in imports if row[1] in dropped)
    result = compare(imports, module_exported, hijacked)
    got_mismatch, got_missing = len(result[2]), len(result[3])
    ok = got_mismatch == expected_mismatch and got_missing == expected_missing
    print(
        f"self-test: perturbed {len(perturbed)} symbols ({expected_mismatch} imports) and removed "
        f"{len(dropped)} symbols ({expected_missing} imports), checker reported {got_mismatch} mismatches "
        f"and {got_missing} missing -> {'PASS' if ok else 'FAIL'}"
    )
    return ok


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    extract = sub.add_parser("extract", help="read modversions ABI out of stock .ko files")
    extract.add_argument("--modules", nargs="+", required=True)
    extract.add_argument("--out-imports", required=True)
    extract.add_argument("--out-exports", required=True)
    extract.set_defaults(func=cmd_extract)
    check = sub.add_parser("check", help="compare stored module ABI against a built Module.symvers")
    check.add_argument("--imports", required=True)
    check.add_argument("--module-exports", nargs="*", default=[])
    check.add_argument("--symvers", required=True)
    check.add_argument("--self-test", action="store_true")
    check.set_defaults(func=cmd_check)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
