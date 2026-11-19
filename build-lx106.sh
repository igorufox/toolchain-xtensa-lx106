#!/bin/bash
# GCC 14.2 for the ESP8266 (lx106, call0 ABI) from Espressif's sources of the esp-14.2.0_20260121 release (sources.txt):
# binutils, gcc and newlib with the xtensa_esp8266 overlay of crosstool-NG. What matters are the target libraries
# (libgcc, newlib and newlib-nano, libstdc++) for lx106 - the compiler of toolchain-xtensa-esp-elf 14.2
# (xtensa_esp8266.so) links against them. GitHub Actions runs it (.github/workflows/build.yml); by hand on Linux:
#
#   SRC_ROOT=<sources> WORK=<build dir> bash build-lx106.sh
set -e
# SRC_ROOT: where lx106-binutils / lx106-gcc / lx106-newlib / lx106-crosstool-ng are (sources.txt); WORK: the build
# and install directories
SRC_ROOT=${SRC_ROOT:-$PWD/src}
WORK=${WORK:-$PWD/work}
SRC_BINUTILS=$SRC_ROOT/lx106-binutils
SRC_GCC=$SRC_ROOT/lx106-gcc
SRC_NEWLIB=$SRC_ROOT/lx106-newlib
OVERLAY=$SRC_ROOT/lx106-crosstool-ng/overlays/xtensa_esp8266
OUT=$WORK/_build
PREFIX=${PREFIX:-$WORK/_install}
TARGET=xtensa-lx106-elf
JOBS=${JOBS:-$(nproc)}
export MAKEINFO=true

mkdir -p "$OUT" "$PREFIX"
export PATH="$PREFIX/bin:$PATH"

step() { echo "=== $(date +%H:%M:%S) $*"; }

step "overlay xtensa_esp8266 onto the sources"
cp -r "$OVERLAY/binutils/." "$SRC_BINUTILS/"
cp -r "$OVERLAY/gcc/." "$SRC_GCC/"
cp -r "$OVERLAY/newlib/." "$SRC_NEWLIB/"

if [ ! -e "$SRC_GCC/gmp" ]; then
    step "gcc prerequisites (gmp, mpfr, mpc, isl into the gcc tree)"
    (cd "$SRC_GCC" && ./contrib/download_prerequisites)
fi

if [ ! -x "$PREFIX/bin/$TARGET-as" ]; then
    step "binutils"
    mkdir -p "$OUT/binutils" && cd "$OUT/binutils"
    "$SRC_BINUTILS/configure" --target=$TARGET --prefix="$PREFIX" --disable-nls --disable-werror \
        --disable-gdb --disable-gdbserver --disable-sim --disable-libdecnumber --disable-readline
    make -j$JOBS MAKEINFO=true || exit 1
    make install MAKEINFO=true || exit 1
fi

GCC_COMMON="--target=$TARGET --prefix=$PREFIX --disable-nls --disable-shared --disable-threads --disable-libssp \
    --disable-libgomp --disable-libquadmath --disable-libstdcxx-verbose --with-newlib --enable-cxx-flags=-ffunction-sections \
    --enable-target-optspace --with-gnu-as --with-gnu-ld --disable-__cxa_atexit"

if [ ! -x "$PREFIX/bin/$TARGET-gcc" ]; then
    step "gcc stage 1 (C only, no libc)"
    mkdir -p "$OUT/gcc1" && cd "$OUT/gcc1"
    "$SRC_GCC/configure" $GCC_COMMON --enable-languages=c --without-headers
    make -j$JOBS MAKEINFO=true all-gcc all-target-libgcc || exit 1
    make MAKEINFO=true install-gcc install-target-libgcc || exit 1
fi

# the options of Espressif's own newlib build (samples/xtensa-esp-elf/crosstool.config of crosstool-NG
# esp-14.2.0_20260121), one for one: the newlib headers of toolchain-xtensa-esp-elf 14.2 then describe these libraries
NEWLIB_MAIN="--target=$TARGET --prefix=$PREFIX --enable-newlib-iconv --enable-newlib-reent-binary-compat     --enable-newlib-nano-malloc --enable-newlib-retargetable-locking --enable-newlib-global-atexit     --disable-newlib-supplied-syscalls --enable-newlib-reent-small --enable-newlib-io-c99-formats     --enable-newlib-io-long-long --enable-newlib-io-float --enable-newlib-io-pos-args --disable-newlib-wide-orient"
NEWLIB_NANO="--target=$TARGET --with-newlib --enable-multilib --disable-newlib-io-c99-formats     --disable-newlib-supplied-syscalls --enable-newlib-nano-formatted-io --enable-newlib-reent-small     --enable-target-optspace --enable-newlib-nano-malloc --enable-newlib-retargetable-locking     --disable-newlib_wide_orient --enable-newlib-iconv --enable-newlib-reent-binary-compat"
# every target library with -mlongcalls (Espressif's CT_TARGET_CFLAGS): libstdc++ takes CXXFLAGS_FOR_TARGET, without it
# its call0 to memset / strcmp (IRAM, ROM) did not reach (19.11 "dangerous relocation: call0: call target out of range")
export CFLAGS_FOR_TARGET="-mlongcalls -ffunction-sections -fdata-sections -O2 -g"
export CXXFLAGS_FOR_TARGET="-mlongcalls -ffunction-sections -fdata-sections -O2 -g"

# only newlib itself: libgloss (libnosys stubs) is not used, the SDK has its own syscalls
if [ ! -e "$PREFIX/$TARGET/lib/libc_nano.a" ]; then
    step "newlib nano"
    rm -rf "$OUT/newlib-nano" && mkdir -p "$OUT/newlib-nano" && cd "$OUT/newlib-nano"
    "$SRC_NEWLIB/configure" $NEWLIB_NANO --prefix="$OUT/nano-install"
    make -j$JOBS MAKEINFO=true all-target-newlib || exit 1
    make MAKEINFO=true install-target-newlib || exit 1
    for lib in libc libg libm; do
        cp "$OUT/nano-install/$TARGET/lib/$lib.a" "$OUT/$lib"_nano.a
    done

    step "newlib"
    rm -rf "$OUT/newlib" && mkdir -p "$OUT/newlib" && cd "$OUT/newlib"
    "$SRC_NEWLIB/configure" $NEWLIB_MAIN
    make -j$JOBS MAKEINFO=true all-target-newlib || exit 1
    make MAKEINFO=true install-target-newlib || exit 1
    for lib in libc libg libm; do
        cp "$OUT/$lib"_nano.a "$PREFIX/$TARGET/lib/"
    done
fi

if [ ! -e "$PREFIX/$TARGET/lib/libstdc++.a" ]; then
    step "gcc (C, C++, libgcc, libstdc++)"
    rm -rf "$OUT/gcc2" && mkdir -p "$OUT/gcc2" && cd "$OUT/gcc2"
    "$SRC_GCC/configure" $GCC_COMMON --enable-languages=c,c++ --with-headers="$PREFIX/$TARGET/include"
    make -j$JOBS MAKEINFO=true || exit 1
    make install MAKEINFO=true || exit 1
fi

step "done"
"$PREFIX/bin/$TARGET-gcc" --version | head -1
ls -la "$PREFIX/$TARGET/lib/"lib{c,c_nano,m,stdc++,supc++}.a "$PREFIX/lib/gcc/$TARGET/14.2.0/libgcc.a"
