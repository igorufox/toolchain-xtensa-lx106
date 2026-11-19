GCC 14.2 for the ESP8266 (lx106, call0 ABI): libgcc, newlib / newlib-nano 4.3 and libstdc++ built from Espressif's sources of the esp-14.2.0_20260121 release (gcc, binutils, newlib, the xtensa_esp8266 overlay of crosstool-NG). The compiler is Espressif's toolchain-xtensa-esp-elf 14.2 with xtensa_esp8266.so; this package is the PlatformIO toolchain-xtensa slot of the espressif8266 platform. Tags: `<gcc version>-espurna.<N>`.

- `sources.txt` — the source repositories and tags
- `build-lx106.sh` — the build (binutils, gcc, newlib, newlib-nano, libstdc++)
- `package.sh` — the PlatformIO package (`package.json`)
- `.github/workflows/build.yml` — GitHub Actions: an artifact on every run; a push to main releases the version of `package.json` (tag `14.2.0+espurna.1` → `14.2.0-espurna.1`) when it is not released yet; the build itself runs only when `sources.txt`, `build-lx106.sh`, `package.sh` or `package.json` changed (otherwise the package of an earlier green run is taken)
