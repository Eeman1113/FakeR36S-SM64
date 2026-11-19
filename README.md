# FakeR36S-SM64: native Super Mario 64 on a fake R36S

Super Mario 64 running natively (no emulator) on the fake R36S / GA36-MB handheld (Allwinner A23, 32-bit ARM, Mali-400, 512 MB) under [FakeR36S-OS](https://github.com/Eeman1113/FakeR36S-OS). It is HarbourMasters' [Ghostship](https://github.com/HarbourMasters/Ghostship) 3.0.0, the PC port built on the SM64 decompilation, cross-compiled for armhf with an OpenGL ES 2 renderer for the Mali-400 (Ghostship's own renderer needs OpenGL 3 or OpenGL ES 3).

It is the sibling of [FakeR36S-Ocarina](https://github.com/Eeman1113/FakeR36S-Ocarina) (Ocarina of Time and Majora's Mask) and is built the same way: GitHub Actions builds the game in a Debian cross toolchain, with the patches in `patches/`, and packs it as a port that shows up in EmulationStation under **Ports**.

**No game files are included.** You need your own Super Mario 64 ROM, the N64 USA or Japan version. The game builds its assets from it on the first start, on the console.

## Install on FakeR36S-OS

1. Download `FakeR36S-SM64-*.zip` from [Releases](https://github.com/Eeman1113/FakeR36S-SM64/releases) (or the latest build under Actions: open the newest green run of **Build** and download the `FakeR36S-SM64` artifact, then unzip it once to get the zip inside).
2. Unzip it into the root of the card's **HOME** partition. It adds `ports/sm64/`, its menu entry (`.local/share/applications/sm64.puppy`) and its icon.
3. Copy your ROM to the root of HOME. Any name works (`Super Mario 64 (USA).z64` is fine), as a `.z64`, `.n64` or `.v64` file or a zip of one. The port folder (`ports/sm64/`) and `roms/n64/` are searched too.
4. On the handheld, open **Ports**, then **Super Mario 64**. The first start finds your ROM by the name in its header, starts the game with it, and the game extracts its assets into `HOME/.config/sm64/sm64.o2r` (a progress window, a minute or two), then the game starts. From then on it starts straight away and the ROM is no longer needed.

Saves, settings, save states and the extracted assets live in `HOME/.config/sm64`, outside the port: a newer zip unzipped over the old one keeps them. The game's log is `HOME/logs/sm64.log`.

If the ROM is a version Ghostship does not take (it takes the US and Japan N64 versions, SHA-1 `9bef1128717f958171a4afac3ed78ee2bb4e86ce` and `8a20a5c83d6ceb0f0506cfc9fa20d8f438cafe51`), a screen says so instead.

## Buttons

| Buttons | What it does |
|---|---|
| Select + Start | Quit the game (back to EmulationStation); the autosave state is written first |
| Select + B | Show / hide the frame rate (stats window) |
| Select + R1 | Save state to the current slot |
| Select + L1 | Load the current slot |
| Select + Right / Left | Next / previous slot (0 to 5) |
| Select + X | Go back to the autosave (refreshed every 5 seconds of gameplay). The first Select+X after a restart resumes where your last session ended |

The game ignores its own buttons while Select is held, so the combos don't make Mario jump or move the camera.

## Building

Everything is built in GitHub Actions (`.github/workflows/build.yml`) on every push to `main`; a tag like `v0.1.0` publishes the zip as that release, with `RELEASE.md` as its notes. Locally, on a PC with Docker:

```sh
GL_JOBS=4 ./build.sh game   # the armhf binary, out/sm64/Ghostship
./build.sh port             # ghostship.o2r, the port's own archive (fonts, the GLES2 shaders, textures)
./build.sh shaders          # every GLES2 shader variant compiled and linked by glslang as GLSL ES 1.00
./build.sh libs             # the libraries FakeR36S-OS lacks, into out/sm64/libs
./build.sh fakers36s        # out/FakeR36S-SM64-<version>.zip
./build.sh check            # no ARMv8-only instruction in what ships, and the NEEDED list
```

No ROM is used anywhere in the build.

## Layout

| | |
|---|---|
| `build.sh`, `Dockerfile` | the build, in the `fakers36s-sm64` image (Debian trixie, `arm-linux-gnueabihf`, `-march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard`, static libzip, `-no-pie`) |
| `patches/lus` | libultraship: the OpenGL ES 2 renderer (with its own GLSL ES 1.00 shader), 32-bit texture pointers, asset memory tracking for save states |
| `patches/ghostship` | Ghostship: scripting can be turned off, the ROM given on the command line is extracted without prompts (any byte order), audio that keeps its tempo when frames run late, the handheld hotkeys and save states |
| `app/` | `common.sh` and `sm64.sh` (find the ROM, start the game with it the first time), `run.sh` (the menu entry's command), `sm64.puppy`, first settings and the icon (`tools/icon.py`) |
| `native/setup.c` | the first start's screen when there is no ROM to take (SDL2, Pixelify Sans, from FakeR36S-Ocarina) |
| `cmake/ghostship-deps.cmake` | tinyxml2 and spdlog, built static |
| `tools/shadercheck` | renders the GLES2 shader template for thousands of combiner setups, for glslang |

## Credits

- **[HarbourMasters](https://github.com/HarbourMasters)** for [Ghostship](https://github.com/HarbourMasters/Ghostship) (MIT), [libultraship](https://github.com/Kenix3/libultraship) (Kenix3 and contributors, MIT) and [Torch](https://github.com/HarbourMasters/Torch) (Lywx and contributors, MIT), which extracts the assets from your ROM.
- **The SM64 decompilation team** ([n64decomp](https://github.com/n64decomp/sm64)) for the decompilation everything starts from.
- **alvesmaicon** for the OpenGL ES 2 / Mali-400 work in [glOSports-harbourmasters](https://github.com/alvesmaicon/glOSports-harbourmasters), which came here through FakeR36S-Ocarina and was rebased onto Ghostship's newer libultraship.
- The authors of libzip, tinyxml2, spdlog, prism and Pixelify Sans (SIL Open Font License).
- **CodeZombie and contributors** for [goodluckOS](https://github.com/CodeZombie/goodluckOS), the base of FakeR36S-OS.

Super Mario 64 is Nintendo's. Use your own legally obtained ROM.

The scripts and patches in this repository are MIT licensed ([LICENSE](LICENSE)); the patches change the projects above and follow their terms. The zip's `licenses` folder has the licenses of what it carries.
