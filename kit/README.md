# GoW2 Recomp — macOS build kit

This kit builds a native macOS (Apple Silicon) version of **God of War II HD**
(PS3, NPUA80491) from **your own copy of the game**. It is the same idea as
[Dusk](https://github.com/zeldaret/tp) or the N64 recomp projects: the kit
ships no game data, only the tools and the recipe. Everything is recompiled on
your Mac from the files you provide.

## What you need

- A Mac with Apple Silicon (M1 or newer) running a recent macOS.
- Xcode Command Line Tools: `xcode-select --install`.
- [Homebrew](https://brew.sh), then `brew install cmake ninja python`.
  Python must be 3.11 or newer.
- Your game, **God of War II HD, NPUA80491 v01.00**:
  - the game folder (`PS3_GAME`, the one with `USRDIR/gow2.psarc`), from your
    disc or from RPCS3's `dev_hdd0/game/NPUA80491`;
  - the decrypted executable `EBOOT.ELF`. In RPCS3, open **Utilities > Decrypt
    PS3 Binaries** and pick `PS3_GAME/USRDIR/EBOOT.BIN`. Save the result as
    `EBOOT.ELF`.

## Build

```bash
cd gow2-recomp
./kit/setup.sh /path/to/EBOOT.ELF /path/to/PS3_GAME
```

The first run takes 5–15 minutes. `setup.sh` does the following:

1. Checks that the EBOOT is the supported release, using its SHA-256.
2. Extracts the movies and WADs the host video player needs from your
   `gow2.psarc` into `movie_cache/`.
3. Recompiles the PPU code: the pinned lifter, then the patch scripts, then
   `kit/ppu_lift_delta.patch`.
4. Recompiles the seven SPU programs.
5. Builds the engine and links `./g2play`.

Steps 3 and 4 are checked file by file against the hashes in `kit/`. If your
build does not match the one the project tests, the script stops and tells you
which file differs.

Running `setup.sh` again only redoes the steps whose output no longer matches.

## Play

```bash
./jogar_g2.sh
```

To use the native launcher instead, run `launcher/macos/build_app.sh` once and
then open **GoW2 Recomp.app**.

Controls: a DualShock 4, DualSense or Xbox controller works when plugged in.
The keyboard also works. Press Escape to release the mouse.

## Status

The game runs from boot to gameplay, at 33–60 fps on an M-series Mac. It is
still in development, and the known problems are listed in the main README.
This is not an emulator: the game code is translated ahead of time into native
arm64 code.

## Legal

The kit contains no part of the game. You need a legally obtained copy of
God of War II HD. The engine (`ps3recomp`) is MIT-licensed.
