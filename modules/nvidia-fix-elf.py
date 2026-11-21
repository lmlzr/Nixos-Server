# Repariert NVIDIA-Programme, die patchelf beim Anpassen an Nix-Pfade kaputt gemacht hat
# (siehe nvidia.nix): patchelf legt ein neues beschreibbares LOAD-Segment vor das erste,
# das in derselben Speicherseite endet, in der ein nur lesbares Segment beginnt. glibc 2.44
# mappt die Seite dann nur lesbar und stuerzt beim Schreiben (.dynamic/DT_DEBUG) mit SIGSEGV
# in ld-linux ab, noch bevor das Programm startet. Fix: das nur lesbare Segment, das eine Seite
# mit einem beschreibbaren teilt, ebenfalls beschreibbar markieren.
import struct
import sys

PAGE = 0x1000
PT_LOAD, PF_W = 1, 2


def fix(path):
    with open(path, "rb") as f:
        d = bytearray(f.read())
    if d[:4] != b"\x7fELF" or d[4] != 2:  # nur 64-Bit-ELF
        return
    phoff, = struct.unpack_from("<Q", d, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", d, 0x36)
    loads = []
    for i in range(phnum):
        o = phoff + i * phentsize
        ptype, flags = struct.unpack_from("<II", d, o)
        vaddr, = struct.unpack_from("<Q", d, o + 16)
        memsz, = struct.unpack_from("<Q", d, o + 40)
        if ptype == PT_LOAD:
            loads.append((o, flags, vaddr, memsz))
    changed = False
    for o, flags, vaddr, memsz in loads:
        if flags & PF_W:
            continue
        first_page = vaddr & ~(PAGE - 1)
        for _, wflags, wvaddr, wmemsz in loads:
            if wflags & PF_W and wvaddr < vaddr and wvaddr + wmemsz > first_page:
                struct.pack_into("<I", d, o + 4, flags | PF_W)
                print(f"{path}: LOAD {vaddr:#x} teilt Seite mit beschreibbarem Segment, +W")
                changed = True
                break
    if changed:
        with open(path, "wb") as f:
            f.write(d)


for p in sys.argv[1:]:
    fix(p)
