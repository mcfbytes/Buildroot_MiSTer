# Slint and Noto Sans

Three packages, none of which upstream Buildroot 2026.08 carries (checked against
`work/buildroot/package/`: the only font packages there are dejavu, font-awesome,
ghostscript-fonts, googlefontdirectory and similar; nothing named slint, noto or corrosion):

| Package | What it installs |
|---|---|
| `package/slint` (`BR2_PACKAGE_SLINT`) | `libslint_cpp.so` on the target; headers + `lib/cmake/Slint` in staging; `host/bin/slint-compiler` |
| `package/font-noto-sans` (`BR2_PACKAGE_FONT_NOTO_SANS`) | Noto Sans TTFs in `/usr/share/fonts/noto-sans` |
| `package/corrosion` (host only, no Kconfig symbol) | the Corrosion CMake modules slint's build needs |

Neither image selects them yet. To use them, select both symbols from a profile or defconfig.

## Slint: what is built

Only the **C++ API**. A Rust program that uses Slint needs no package, because cargo
vendors the `slint` crate into that program's own build. The C++ library is what a C++
program such as Main_MiSTer would link.

| Choice | Setting | Why |
|---|---|---|
| Backend | LinuxKMS only (`winit`, Qt off) | no X11/Wayland on the image; LinuxKMS tries DRM dumb buffers, then the legacy framebuffer `/dev/fb0`..`fb9` |
| Renderer | software only (FemtoVG, Skia off) | the DE10-Nano has no GPU |
| Input | libinput + xkbcommon (`BR2_PACKAGE_SLINT_LIBINPUT`, default y) | without it the backend draws but receives no input |
| libseat | off | MiSTer userspace runs as root |
| Interpreter | off (`BR2_PACKAGE_SLINT_INTERPRETER`) | `.slint` files are compiled to C++ at build time; the interpreter adds several MB |
| Accessibility, system tray, testing | off | they need D-Bus/AT-SPI or a desktop, and the image has neither |

Slint finds fonts through fontconfig, so `fontconfig` is selected and at least one font
must be installed. `font-noto-sans` is the intended one.

### Build mechanics

- The package is a `cmake-package` whose source is vendored like a `cargo-package`
  (`SLINT_DOWNLOAD_POST_PROCESS = cargo`). The hashed file is therefore
  `slint-<ver>-cargo6.tar.gz`, about 180 MB with every crate in the workspace's
  `Cargo.lock`, not GitHub's 11 MB archive. Regenerate it the way
  `package/itsalive/itsalive.hash` describes: bump the version, run `make slint-source`,
  and paste the value from the error message. Never add slint to `renovate-hash-sync.yml`'s
  `HASH_SYNC_PACKAGES`, because the generic loop would hash the wrong file.
- Slint's CMake fetches Corrosion with `FetchContent` (a `git clone` at configure time)
  unless `find_package(Corrosion)` succeeds. `host-corrosion` installs it into
  `$(HOST_DIR)`, and `-DCorrosion_DIR` points at it, so the build stays offline.
- Corrosion runs cargo during the **build** step, so Buildroot's `PKG_CARGO_ENV` (profile,
  linker, the ARM `--allow-multiple-definition` rustflag) goes on `SLINT_MAKE_ENV` together
  with `CARGO_NET_OFFLINE=true`.
- Upstream's CMake would build `slint-compiler` for the host and install it into the
  target's `/usr/bin`. Instead, `host-slint` builds it with cargo (the same feature set
  upstream uses when cross-compiling) and `-DSLINT_COMPILER` points at it. The installed
  `SlintConfig.cmake` records that path, so a later Buildroot package can call
  `find_package(Slint)` and `slint_target_sources()` with no extra setup.

### Measured (2026-10-06, Buildroot 2026.08, rust-bin 1.97.1, glibc/GCC 15 armv7 toolchain)

- `host-slint`: 40 s; `slint` (cargo via Corrosion): 41 s, both on a 32-thread host.
- `libslint_cpp.so`: 17.6 MB as installed, **13.5 MB stripped** (`BR2_STRIP_strip` does
  this in the image). It links libxkbcommon, libudev, libinput, libfontconfig, libgcc_s and
  libc. Weigh it against `docs/size-budget.md` before enabling it.
- A minimal C++ consumer (`find_package(Slint)` + `slint_target_sources` + one `.slint`
  window) configured, compiled and linked against the staging tree using Buildroot's
  `toolchainfile.cmake`.
- Run on the target userland (`unshare -r chroot` with qemu-arm): the library loads, the
  component is created, and the LinuxKMS backend probes DRM, then `/dev/fb0`..`fb9`. It
  aborts only because the chroot has no framebuffer. **Rendering on a board is still
  owed.** On a MiSTer, `/dev/fb0` exists only after the video path is up (Main_MiSTer or
  `itsalive up`), and nothing else may write to it at the same time.

## Noto Sans

The upstream release is `notofonts/latin-greek-cyrillic` `NotoSans-v2.015.zip` (OFL-1.1).
The package installs the **unhinted static TTFs**:

- By default, Regular, Italic, Bold and Bold Italic: 1.7 MB.
- With `BR2_PACKAGE_FONT_NOTO_SANS_ALL_WEIGHTS`, all 72 weight and width styles: 31 MB.

Unhinted fonts suit both FreeType and Slint's own rasteriser. The variable-font files in
the same zip would be smaller for the full family, but the static files are what every
consumer handles.
