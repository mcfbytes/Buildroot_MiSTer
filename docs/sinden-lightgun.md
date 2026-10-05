# Sinden Lightgun: runtime, hotplug, and what the image does not ship

The [Sinden Lightgun](https://www.sindenlightgun.com/) is a camera light gun
that works on LCDs. It has no aim sensor of its own. Its barrel camera streams
video to the host, and a host-side driver from Sinden Technology finds the
screen in that video by looking for a white border. The driver then sends the
aim point back to the gun over a USB serial port, and the gun reports it as a
mouse or joystick.

This image supplies everything the driver needs except the driver itself.

## 1. What a gun looks like to the board

One USB device (VID `16c0` or `16d0`, PID `0f01`/`0f02`/`0f38`/`0f39`) with
three functions:

| Interface | Kernel driver | Node | Used by |
|---|---|---|---|
| UVC camera | `uvcvideo` (module) | `/dev/video0` (+ a metadata node) | the driver reads frames |
| CDC ACM serial | `cdc_acm` (built in) | `/dev/ttyACM0` | the driver writes the aim point |
| HID keyboard + mouse + joystick | `hid-generic` | `/dev/input/event*` | Main_MiSTer |

Main_MiSTer already recognises all four PIDs (`input.cpp`, "Sinden Lightgun")
and puts the joystick in light-gun mode with a 0..65535 calibration. Until the
driver is running, the gun reports buttons only, never an aim position.

## 2. Kernel

Stock and our image both had `MEDIA_SUPPORT` off, so a gun's camera had no
driver. That is why MrLightgun's MiSTer package replaces `zImage_dtb` with its
own 5.15.1 kernel. **Never run that installer on this image**: it would swap
our 6.18 kernel for one whose module tree is not on the rootfs.

Both `board/mister/de10nano/linux.config` and the common fragment now set:

```
MEDIA_SUPPORT=m, MEDIA_SUPPORT_FILTER=y, MEDIA_CAMERA_SUPPORT=y,
MEDIA_USB_SUPPORT=y, USB_VIDEO_CLASS=m
MEDIA_SUBDRV_AUTOSELECT is not set        (else: I2C mux core + sensor framework)
USB_VIDEO_CLASS_INPUT_EVDEV is not set    (else: an extra input device with the gun's VID:PID)
```

`olddefconfig` resolves this to the same 20-symbol delta on 6.18.55 (DE10),
7.2.9 (RT, which inherits the DE10 config) and the DE25's arm64 7.2 config.
The only built-in addition is `DMA_SHARED_BUFFER` (and the `NET_DEVMEM`
def_bool it unlocks). Everything else is modules (`videodev`, `videobuf2-*`,
`uvc`, `uvcvideo`), loaded by udev's modalias handling when a camera appears.
Any UVC webcam works as a side effect.

## 3. Userspace: which Sinden build, and why

| Candidate | Verdict |
|---|---|
| Official zip, `ARMversion/Pi/Lightgun/Application` | **Used.** Sinden's own armhf build: `LightgunMono.exe` (CIL) + `libCameraInterface.so` + `libSdlInterface.so`. Same `joystick` / `lowresource` / `mediumresource` / `sdl` arguments as the MiSTer build. |
| [MrLightgun/MiSTerSindenDriver](https://github.com/MrLightgun/MiSTerSindenDriver) | Not used. An `mkbundle`d binary of unclear provenance with bundled cairo/krb5. Its installer also replaces the kernel (§2). |
| Official zip, Pi5 / PC builds | aarch64 / x86-64, not this board. |

**Licence.** Sinden's `License.txt` says the software "may only be distributed
by Sinden Technology Ltd". So the image ships none of it. The user downloads it
from sindenlightgun.com onto their own card through `Scripts/sinden_lightgun.sh`,
and our release never carries a Sinden byte. The licence lands next to the
driver as `/media/fat/linux/sinden/License.txt`.

**Replacing the two `.so` files was considered and rejected.** They are
Sinden's own wrappers (31 + 10 exported functions), not third-party libraries,
so Buildroot has no package for them. A compatible rewrite would need their
argument and buffer semantics, which means decompiling, and the licence
forbids that. Everything *they* link against comes from Buildroot instead.

## 4. What the image adds

`BR2_PACKAGE_SINDEN_LIGHTGUN` (DE10 defconfig only: it installs the armhf Pi
build; Sinden's Pi5 aarch64 build could serve the DE25 later) selects:

| Package | Why | Target cost |
|---|---|---|
| `mono` 6.12 | runs `LightgunMono.exe` | ~20 MB after the trim below |
| `sdl` 1.2.15 (fbcon) | `libSdlInterface.so` calls plain SDL 1.2 (`SDL_SetVideoMode`, `SDL_LoadBMP_RW`, ...) | 320 KB |
| `sdl_image` 1.2 | a `NEEDED` entry of both `.so` files, never called | 24 KB |
| `libjpeg62` (new, this repo) | `libCameraInterface.so` decodes MJPEG with `jpeg_*@LIBJPEG_6.2` | 520 KB |

**libjpeg.so.62** is the libjpeg-6b ABI, which libjpeg-turbo keeps by default.
Debian and Raspberry Pi OS ship it as `libjpeg62-turbo`. Buildroot always
builds jpeg-turbo with `WITH_JPEG8=ON` (`libjpeg.so.8`, used by imlib2 and
Main_MiSTer), so `package/libjpeg62` builds the same tarball a second time with
the 6.2 ABI. It installs only the shared object, with no headers and no `.pc`,
so nothing in the build can link it by accident. It verifies against
Buildroot's own `jpeg-turbo.hash` and so moves with every Buildroot bump. The
two libraries' symbols are versioned (`LIBJPEG_6.2` vs `LIBJPEG_8.0`), so both
can load in one process. A `.so.62 -> .so.8` symlink would *not* work, because
`jpeg_decompress_struct` changed layout in v7.

**The mono trim.** Buildroot's mono rsyncs the host's whole `lib/mono` to the
target: every profile, reference assembly and tool, 200 MB. A
`TARGET_FINALIZE` hook keeps only:

- `mono-sgen` (`mono` symlink), `libmono-native.so` (`System.Native`) and
  `libMonoPosixHelper.so` (`SerialPort`);
- the reference closure of `LightgunMono.exe`: `mscorlib System System.Core
  System.Configuration System.Xml System.Security System.Numerics
  Mono.Security`;
- `/etc/mono/config` and `/etc/mono/4.5/machine.config`.

The closure must stay **in `gac/`**. Mono resolves strong-named framework
references only through the GAC; `4.5/` holds `mscorlib.dll` plus symlinks.
Flattening the symlinks into real files and deleting `gac/` fails at startup
with `Could not load file or assembly 'System, Version=4.0.0.0'`. That was
found by running the app, and is why the run test below matters. If a future
Sinden release references another assembly, add it to
`SINDEN_LIGHTGUN_MONO_ASSEMBLIES`.

## 5. Runtime

- **Install:** `Scripts/sinden_lightgun.sh` runs
  `/usr/sbin/mister-sinden-lightgun install`. That downloads V2.08b,
  checks its pinned sha256 and unpacks the Pi `Application` files to
  `/media/fat/linux/sinden/`. `LightgunMono.exe.config` is written once, with
  `CameraRes` set to `320,240` (Sinden's own advice for weak hosts), and is
  never overwritten, so it keeps the user's settings. `args` holds the driver
  arguments, default `joystick mediumresource`.
- **Hotplug:** `/etc/udev/rules.d/61-sinden-lightgun.rules` calls
  `mister-sinden-lightgun hotplug` when a gun's camera appears and on any v4l
  removal. That detaches at once (udev waits on `RUN`'s stdio) and, 2 s
  later, *reconciles*. The driver runs while at least one gun is present, and
  restarts when the gun count changes, because it enumerates guns only at
  startup. One instance handles two guns. Guns present at boot are covered by
  the coldplug `add` events; `/media/fat` is mounted by the initramfs before
  udev starts.
- **CPU0:** the driver runs under `taskset -c 0`. Main_MiSTer pins itself to
  CPU1 (`main.cpp:42-48`, [abi-contract](abi-contract.md)), and the driver must
  not compete with it.
- **Logs:** `/var/log/sinden-lightgun.log`. `mister-sinden-lightgun status`
  shows the install, gun count, PID and affinity.

The driver shells out to `sh -c "udevadm info ... | grep ..."` and `ls` to find
guns. All of those are on the image.

## 6. What is verified, and what is not

Verified on the build host (qemu-arm, `unshare -r chroot` into `rootfs.tar`):

- `mister-sinden-lightgun install` downloads, verifies and unpacks with BusyBox
  `unzip`/`sha256sum`.
- `mono LightgunMono.exe joystick mediumresource` on the **trimmed** mono
  starts and reaches `Number of Sinden Lightguns Found 0` (its gun search ran).
- A probe assembly on the same runtime reads `CameraRes` through
  `ConfigurationManager`, resolves `libCameraInterface.so` and
  `libSdlInterface.so` via P/Invoke (`Marshal.Prelink`), and opens a
  `SerialPort` through `libMonoPosixHelper`.
- `ld.so --list` resolves every `NEEDED` of both `.so` files to Buildroot
  libraries.

**Not verified:** anything with a real gun. That includes the hotplug rule
firing, `uvcvideo` streaming the gun's MJPEG, whether `mediumresource` keeps up
on the Cortex-A9, and aim accuracy. No one on the project owns a gun.

## 7. The border is a separate problem

The driver needs a white border on screen. Cores do not draw one. Today that
means MrLightgun's `*-Sinden.rbf` core forks. A generic fix would wire the
scaler's unused `o_border` colour input (`sys/ascal.vhd`) to a register Main can
set, and combine it with Main's existing `vscale_border` INI option. Because
`sys/` is compiled into every core, that is an upstream Template_MiSTer +
Main_MiSTer change that would spread as cores resync `sys/`. It is not in this
repo.
