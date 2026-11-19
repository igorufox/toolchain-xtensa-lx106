#!/bin/bash
# The PlatformIO package toolchain-xtensa from the install directory of build-lx106.sh: only the target libraries and
# headers of xtensa-lx106-elf (no host programs - the compiler is toolchain-xtensa-esp-elf 14.2), package.json at the
# root of the zip.
#
#   bash package.sh <install dir> <output dir> <zip name>
set -e
PREFIX=$1
DIST=$2
NAME=$3
TARGET=xtensa-lx106-elf
GCC_LIB=lib/gcc/$TARGET/14.2.0
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$DIST"
DIST=$(cd "$DIST" && pwd)
PKG=$DIST/pkg
rm -rf "$PKG" && mkdir -p "$PKG/$GCC_LIB" "$PKG/$TARGET"

# libgcc, libgcov, crt*.o and the compiler's own headers
cp "$PREFIX/$GCC_LIB/"*.a "$PREFIX/$GCC_LIB/"*.o "$PKG/$GCC_LIB/"
cp -r "$PREFIX/$GCC_LIB/include" "$PREFIX/$GCC_LIB/include-fixed" "$PKG/$GCC_LIB/"
# newlib, newlib-nano, libstdc++, libsupc++ with their headers (c++/14.2.0)
cp -r "$PREFIX/$TARGET/include" "$PREFIX/$TARGET/lib" "$PKG/$TARGET/"
rm -f "$PKG/$TARGET/lib/"*.la "$PKG/$TARGET/lib/"*-gdb.py
cp "$HERE/package.json" "$PKG/"

for lib in libc libc_nano libm libm_nano libstdc++ libsupc++; do
    [ -s "$PKG/$TARGET/lib/$lib.a" ] || { echo "package.sh: $lib.a missing"; exit 1; }
done
[ -s "$PKG/$GCC_LIB/libgcc.a" ] || { echo "package.sh: libgcc.a missing"; exit 1; }

# the archive by Python (zip -q left no file on the runner, 19.11): package.json at its root
python3 - "$PKG" "$DIST/$NAME" <<'EOF'
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
count = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for top, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(top, name)
            z.write(path, os.path.relpath(path, root))
            count += 1
print(f"{out}: {count} files, {os.path.getsize(out)} bytes")
EOF
du -sh "$PKG"
