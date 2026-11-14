#!/usr/bin/env python3
"""Add one LC_LOAD_DYLIB to both slices of this universal Mach-O."""

import os
import struct
import sys
from pathlib import Path


def u32be(data, offset):
    return struct.unpack_from(">I", data, offset)[0]


def u32le(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def patch_slice(data, slice_offset, dylib_name):
    if u32le(data, slice_offset) != 0xFEEDFACF:
        raise ValueError("Expected 64-bit little-endian Mach-O slice")

    ncmds = u32le(data, slice_offset + 16)
    sizeofcmds = u32le(data, slice_offset + 20)
    cursor = slice_offset + 32
    first_section_offset = None

    for _ in range(ncmds):
        cmd = u32le(data, cursor)
        cmdsize = u32le(data, cursor + 4)
        if cmdsize < 8:
            raise ValueError("Malformed load command")
        if cmd in (0xC, 0x18 | 0x80000000, 0x1F | 0x80000000):
            name_offset = u32le(data, cursor + 8)
            existing = data[cursor + name_offset:cursor + cmdsize].split(b"\0", 1)[0]
            if existing == dylib_name:
                raise ValueError("Dylib load command already exists")
        if cmd == 0x19:  # LC_SEGMENT_64
            section_count = u32le(data, cursor + 64)
            for index in range(section_count):
                section = cursor + 72 + index * 80
                offset = u32le(data, section + 48)
                if offset:
                    first_section_offset = min(first_section_offset or offset, offset)
        cursor += cmdsize

    command_end = slice_offset + 32 + sizeofcmds
    if cursor != command_end or first_section_offset is None:
        raise ValueError("Unexpected load-command layout")

    cmdsize = (24 + len(dylib_name) + 1 + 7) & ~7
    if 32 + sizeofcmds + cmdsize > first_section_offset:
        raise ValueError("No free Mach-O header space")
    if any(data[command_end:command_end + cmdsize]):
        raise ValueError("Mach-O header padding is not empty")

    command = bytearray(cmdsize)
    struct.pack_into("<6I", command, 0, 0xC, cmdsize, 24, 0, 0, 0)
    command[24:24 + len(dylib_name)] = dylib_name
    data[command_end:command_end + cmdsize] = command
    struct.pack_into("<I", data, slice_offset + 16, ncmds + 1)
    struct.pack_into("<I", data, slice_offset + 20, sizeofcmds + cmdsize)


def main():
    source, target, dylib = map(Path, sys.argv[1:4])
    data = bytearray(source.read_bytes())
    if u32be(data, 0) != 0xCAFEBABE:
        raise ValueError("Expected 32-bit fat Mach-O header")
    count = u32be(data, 4)
    if count != 2:
        raise ValueError("Expected exactly two architecture slices")
    for index in range(count):
        arch = 8 + index * 20
        slice_offset = u32be(data, arch + 8)
        patch_slice(data, slice_offset, os.fsencode(str(dylib)))
    target.write_bytes(data)
    os.chmod(target, source.stat().st_mode)


if __name__ == "__main__":
    main()
