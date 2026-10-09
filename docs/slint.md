# Slint and the Noto fonts

Four packages, none of which upstream Buildroot 2026.08 carries (checked against
`work/buildroot/package/`: the only font packages there are dejavu, font-awesome,
ghostscript-fonts, googlefontdirectory and similar; nothing named slint, noto or corrosion):

| Package | What it installs |
|---|---|
| `package/slint` (`BR2_PACKAGE_SLINT`) | `libslint_cpp.so` on the target; headers + `lib/cmake/Slint` in staging; `host/bin/slint-compiler` |
| `package/font-noto-sans` (`BR2_PACKAGE_FONT_NOTO_SANS`) | Noto Sans TTFs in `/usr/share/fonts/noto-sans` |
| `package/font-noto-sans-jp` (`BR2_PACKAGE_FONT_NOTO_SANS_JP`) | Noto Sans JP OTFs in `/usr/share/fonts/noto-sans-jp` |
| `package/corrosion` (host only, no Kconfig symbol) | the Corrosion CMake modules slint's build needs |

The `mister-userspace` profile selects `BR2_PACKAGE_SLINT` and `BR2_PACKAGE_FONT_NOTO_SANS`, so every image that
selects the profile ships them (`docs/buildroot-config.md` §5.5, §5.6). `font-noto-sans-jp` is not selected.

All four are tracked by Renovate (label `gui-pin`), and their hashes are refreshed on the
bump branch: corrosion by hash-sync case 1, slint by case 9, both Noto fonts by case 10
(`docs/renovate.md`). An image build builds slint and font-noto-sans, so a green bump PR
proves they build; it still proves nothing about rendering, so test as described in
[Building and testing a bump](#building-and-testing-a-bump) before merging one. font-noto-sans-jp
is still built by no image.

## Slint: what is built

Only the **C++ API**. A Rust program that uses Slint needs no package, because cargo
vendors the `slint` crate into that program's own build. The C++ library is what a C++
program such as Main_MiSTer would link.

| Choice | Setting | Why |
|---|---|---|
| Library | shared, `BUILD_SHARED_LIBS=ON` | one `libslint_cpp.so` in the image for every program that links it |
| Backend | **none by default**; LinuxKMS optional (`BR2_PACKAGE_SLINT_LINUXKMS`) | the intended caller supplies its own `slint::platform::Platform` and renders into its own buffer. `winit` and Qt are off: the image has no X11 or Wayland |
| Renderer | software only (FemtoVG, Skia off) | the DE10-Nano has no GPU |
| Input | libinput + xkbcommon, only with LinuxKMS (`BR2_PACKAGE_SLINT_LINUXKMS_LIBINPUT`) | without it LinuxKMS draws but receives no input |
| Interpreter, live preview | off (`BR2_PACKAGE_SLINT_INTERPRETER` for the first) | `.slint` files are compiled to C++ at build time; the interpreter adds several MB |
| Experimental, gettext, accessibility, system tray, testing | off | not needed, and accessibility and the tray need D-Bus or a desktop |
| Rust codegen | `-Ctarget-cpu=cortex-a9 -Ctarget-feature=+neon` | derived from `BR2_GCC_TARGET_CPU` and `BR2_ARM_CPU_HAS_NEON`, so rustc tunes for the same CPU GCC does; Buildroot's cargo environment sets neither |

### Carried patches

| Patch | What it does |
|---|---|
| `0001-api-cpp-dlopen-libfontconfig-instead-of-linking-it` | enables fontique's `fontconfig-dlopen` for the C++ library, so `libslint_cpp.so` does not need `libfontconfig.so.1` to load. Setting `RUST_FONTCONFIG_DLOPEN=on` alone breaks the build (E0432) |
| `0002-api-cpp-add-an-ARGB8888-software-renderer-target` | adds `slint_software_renderer_render_argb8888()`: render straight into a `u32` 0xAARRGGBB buffer (the framebuffer's scanout format) with `Rgb8Pixel`'s blend arithmetic. Stock C++ renders only RGB888 or RGB565 and needs a swizzle pass |
| `0003-api-cpp-let-the-caller-drive-the-animation-clock` | adds `slint_hdosd_set_scene_time(ms)`: advance animations and timers to a caller-owned clock. In a std build `Platform::duration_since_start()` is compiled out, so animations otherwise follow the wall clock |

None has been submitted upstream. Both new entry points are C symbols with no C++
wrapper, so a caller declares them itself. The ARGB8888 entry point takes the
`SoftwareRenderer`'s opaque handle, so a caller reaching it from C++ depends on that
class's layout. On a slint bump, re-check all three patches against
`api/cpp/platform.rs` and `api/cpp/Cargo.toml` (`Cargo.lock` too: 0001 adds `fontique` to
`slint-cpp`'s dependency list, and the build runs `--locked`).

### Fonts

fontconfig is optional at run time, which matters because the DE10 image does not ship it:

- **Without fontconfig**, a program sees no system fonts. Text in a family imported in
  `.slint` renders, but fonts imported in `.slint` never become fallbacks. Glyphs missing
  from that family (◀ ▶ are not in Noto Sans) and implicit CJK render blank unless
  `SLINT_FONT_PATH` names a fallback font, e.g.
  `SLINT_FONT_PATH=/usr/share/fonts/noto-sans-jp/NotoSansJP-Regular.otf`.
- **With fontconfig present but configuring no fonts**, fontique panics. Enable
  fontconfig only together with at least one font package.
- A consumer can compile its fonts into its own binary
  (`set_property(TARGET app PROPERTY SLINT_EMBED_RESOURCES embed-files)`), which costs
  their size again in the binary (4.5 MB for Noto Sans JP Regular) but needs no font files
  on the card at all.

`font-noto-sans` is the intended UI face. `font-noto-sans-jp` adds Japanese (kana and
kanji) and is also the natural `SLINT_FONT_PATH` fallback.

### Build mechanics

- The package is a `cmake-package` whose source is vendored like a `cargo-package`
  (`SLINT_DOWNLOAD_POST_PROCESS = cargo`). The hashed file is therefore
  `slint-<ver>-cargo6.tar.gz`, about 180 MB with every crate in the workspace's
  `Cargo.lock`, not GitHub's 11 MB archive. On a Renovate bump, hash-sync case 9
  (`scripts/hash-sync-cargo.sh`) rebuilds that file and refreshes the hash and the four
  licence lines. By hand, use the recipe in `package/itsalive/itsalive.hash`: bump the
  version, run `make slint-source`, and paste the value from the error message. Never add
  slint to `renovate-hash-sync.yml`'s `HASH_SYNC_PACKAGES`, because the generic loop would
  hash the wrong file.
- Slint's CMake fetches Corrosion with `FetchContent` (a `git clone` at configure time)
  unless `find_package(Corrosion)` succeeds. Corrosion is therefore vendored as its own
  package: `host-corrosion` is an ordinary hash-checked download (so `make source` fetches
  it with everything else, and an offline build works from `dl/`) installed into
  `$(HOST_DIR)`, and `-DCorrosion_DIR` points at it. `-DFETCHCONTENT_FULLY_DISCONNECTED=ON`
  makes any remaining fetch attempt fail instead of going to the network.
- Corrosion runs cargo at configure time (`cargo metadata`) and during the build, so
  Buildroot's `PKG_CARGO_ENV` (profile, linker, `CARGO_HOME`), `CARGO_NET_OFFLINE=true`
  and the rustflags above go on both `SLINT_CONF_ENV` and `SLINT_MAKE_ENV`. The rustflags
  variable replaces `PKG_CARGO_ENV`'s own ARM one, so it repeats that one's
  `--allow-multiple-definition`. `-DSLINT_LIBRARY_CARGO_FLAGS=--locked` makes Corrosion's
  `cargo build` honour `Cargo.lock`, as `cargo-package` does.
- Upstream's CMake would build `slint-compiler` for the host and install it into the
  target's `/usr/bin`. Instead, `host-slint` builds it with cargo (the same feature set
  upstream uses when cross-compiling) and `-DSLINT_COMPILER` points at it. The installed
  `SlintConfig.cmake` records that path, so a later Buildroot package can call
  `find_package(Slint)` and `slint_target_sources()` with no extra setup.

### Measured (2026-10-06, Buildroot 2026.08, rust-bin 1.97.1, glibc/GCC 15 armv7 toolchain)

- `host-slint`: about 40 s; `slint` (cargo via Corrosion): under a minute, both on a
  32-thread host.
- `libslint_cpp.so` with the default options: 16.9 MB as installed, **13.1 MB stripped**
  (`BR2_STRIP_strip` does this in the image). It needs only `libgcc_s`, `libm`, `libc` and
  `ld-linux-armhf`; libfontconfig is dlopened. ELF attributes: `Tag_CPU_name: 7-A`,
  `Tag_Advanced_SIMD_arch: NEONv1`. Weigh the size against `docs/size-budget.md` before
  enabling it.
- **End-to-end check.** A C++ program with its own `Platform` was cross-built with
  `find_package(Slint)` and `slint_target_sources()` against this package's staging
  tree. The program renders through the ARGB8888 entry point, drives time through the
  scene clock, and embeds its fonts. It was run on the target userland
  (`unshare -r chroot` with qemu-arm, libfontconfig hidden, `SLINT_FONT_PATH` set) at
  1080p and 720p, with and without CJK text. All four PNGs were **byte-identical** to the
  same program built earlier against a statically linked, separately configured Slint
  1.18.1 with the same patch.
- With `BR2_PACKAGE_SLINT_LINUXKMS` (an earlier configuration of this package), a minimal
  `slint::Window` program loads, and the backend probes DRM, then `/dev/fb0`..`fb9`.
- **Nothing has rendered on a board yet.** On a MiSTer, `/dev/fb0` exists only once the
  video path is up (Main_MiSTer or `itsalive up`), and nothing else may write to it at the
  same time.

## Building and testing a bump

CI builds slint and font-noto-sans as part of the image; nothing renders there. For a bump, build them by hand in a small
tree that reuses the toolchain of an existing DE10 build (`output/host`) as a
pre-installed external toolchain. This takes a few minutes and about 9 GB, not a full
image build.

```sh
mkdir -p /mnt/source/slint-test
cat > /mnt/source/slint-test/defconfig <<'EOF'
BR2_arm=y
BR2_cortex_a9=y
BR2_ARM_ENABLE_NEON=y
BR2_ARM_ENABLE_VFP=y
BR2_ARM_FPU_NEON=y
BR2_TOOLCHAIN_EXTERNAL=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y
BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y
BR2_TOOLCHAIN_EXTERNAL_PATH="/path/to/Buildroot_MiSTer/output/host"
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="arm-buildroot-linux-gnueabihf"
BR2_TOOLCHAIN_EXTERNAL_GCC_15=y
BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_18=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y
# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set
BR2_TOOLCHAIN_EXTERNAL_CXX=y
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
BR2_PACKAGE_SLINT=y
BR2_PACKAGE_FONT_NOTO_SANS=y
BR2_PACKAGE_FONT_NOTO_SANS_JP=y
# BR2_TARGET_ROOTFS_TAR is not set
EOF
make O=/mnt/source/slint-test/out BR2_DEFCONFIG=/mnt/source/slint-test/defconfig defconfig
make O=/mnt/source/slint-test/out slint font-noto-sans font-noto-sans-jp
```

The GCC and headers lines must match `output/.config` (`BR2_GCC_VERSION`,
`BR2_KERNEL_HEADERS_*`); after a Buildroot or toolchain bump, check them before blaming the
package. Then cross-build a minimal consumer against the staging tree:

```sh
# CMakeLists.txt: find_package(Slint REQUIRED); add_executable(hello main.cpp)
#                 slint_target_sources(hello hello.slint); target_link_libraries(hello PRIVATE Slint::Slint)
cmake -S app -B app/build \
  -DCMAKE_TOOLCHAIN_FILE=/mnt/source/slint-test/out/host/share/buildroot/toolchainfile.cmake
cmake --build app/build
```

Finally, run it on the ARM userland: copy the binary into `out/target/usr/bin/` and run
`unshare -r chroot out/target /usr/bin/<app>`. A program with its own `Platform` that
renders into a buffer can write a PNG, which can be compared byte-for-byte with the
previous version's output. With `BR2_PACKAGE_SLINT_LINUXKMS`, a plain `slint::Window`
program must reach the backend's probe (`Error using /dev/fb0 ...`). Anything earlier,
such as a missing library, is a packaging bug.

For a slint bump, rebase the three carried patches first (see above). Also re-check the
`SLINT_FEATURE_*` names that `slint.mk` passes against
`api/cpp/cmake/SlintFeatures.cmake` (CMake ignores an unknown `-D`, so a renamed feature
silently falls back to its default), and the `find_package(Rust <min>)` line in
`api/cpp/CMakeLists.txt` against Buildroot's rust-bin pin.

## Noto Sans and Noto Sans JP

The upstream release is `notofonts/latin-greek-cyrillic` `NotoSans-v2.015.zip` (OFL-1.1).
The package installs the **unhinted static TTFs**:

- By default, Regular, Italic, Bold and Bold Italic: 1.7 MB.
- With `BR2_PACKAGE_FONT_NOTO_SANS_ALL_WEIGHTS`, all 72 weight and width styles: 31 MB.

Unhinted fonts suit both FreeType and Slint's own rasteriser. The variable-font files in
the same zip would be smaller for the full family, but the static files are what every
consumer handles.

Noto Sans JP (`font-noto-sans-jp`) is the Japanese region subset of Noto Sans CJK, from
`notofonts/noto-cjk` release `Sans2.004`, asset `16_NotoSansJP.zip` (OFL-1.1). Its family
name is exactly `Noto Sans JP`, the one `art-src/gen.py` uses. The files are OpenType/CFF
(`.otf`), the only format that asset ships. FreeType renders CFF, and so does Slint's font
stack (skrifa).

- By default, Regular and Bold: 9 MB.
- With `BR2_PACKAGE_FONT_NOTO_SANS_JP_ALL_WEIGHTS`, all 7 weights (Thin to Black): 31 MB.

This is the expensive font: Regular alone is 4.5 MB, because it carries about 18,000
glyphs. Budget for it in `docs/size-budget.md` before enabling it.
