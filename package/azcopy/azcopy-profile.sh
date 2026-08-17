# azcopy defaults for a MiSTer -- see docs/azcopy.md.
#
# Sourced by /etc/profile's `for i in /etc/profile.d/*.sh` loop. THAT MEANS
# LOGIN SHELLS ONLY: a serial/HDMI console login, an interactive `ssh mister`,
# and anything started from one of those. It does NOT cover
# `ssh mister azcopy ...` (a non-login, non-interactive shell reads no profile)
# or a process started by init. There is no pam_env in /etc/pam.d/sshd and no
# /etc/environment on this image to close that gap with, and adding either
# would mean editing the authentication stack to fix an environment-variable
# default -- not a trade worth making. If you drive azcopy from a remote
# non-interactive command or a startup script, set these three yourself; the
# values below are the whole content of this file and are meant to be copied.
#
# Every assignment uses ${VAR:=...}, so anything you export beforehand wins.
# Nothing here is a policy the image enforces; they are defaults for a box the
# upstream defaults were never written for.
#
# This file lives at package/azcopy/azcopy-profile.sh and is installed here by
# azcopy.mk, NOT shipped from board/mister/de10nano/rootfs-overlay/. The overlay
# has no view of BR2_PACKAGE_AZCOPY, so an overlay copy would land in every
# image -- including the default one, which does not build azcopy at all.
#
# THAT MATTERS MOST IF YOU ARE RUNNING A DOWNLOADED BINARY. The default image
# does not enable this package (see configs/mister_de10nano_defconfig), so the
# usual way to have azcopy on a MiSTer is to drop the released binary onto
# /media/fat yourself -- in which case this file is NOT present and none of the
# defaults below apply. Set them yourself; that is what the copy-paste note
# above is for, and docs/azcopy.md repeats them for exactly this case.

# WHERE THE JOB PLAN AND LOG FILES GO.
#
# AzCopy defaults both to $HOME/.azcopy, i.e. /root/.azcopy, which is on the
# ROOTFS -- and the rootfs on this image is reflashed wholesale by a Linux
# update, so anything there is temporary by construction (the same reasoning
# that puts ssh host keys, wpa_supplicant.conf and samba.sh on the FAT
# partition instead). Two things go wrong if they stay there:
#
#   1. `azcopy jobs resume <id>` stops working across an image update, which
#      is exactly when a half-finished multi-gigabyte upload most needs it.
#      Job plan files are the resume state; without them the job is gone.
#   2. linux.img is a FIXED 512 MiB ext4 filesystem with no growth path. Plan
#      files are sized by the transfer (one record per file, and a `sync` of a
#      full games directory is a lot of records) and logs are verbose by
#      default. Filling the rootfs on a running MiSTer is its own class of bad
#      day.
#
# /media/fat/linux is where this image already keeps per-device persistent
# state, so azcopy's goes in a subdirectory of it. AzCopy creates both paths
# itself on first run (common/init.go InitializeFolders -> os.MkdirAll), so
# there is nothing to pre-create here and no init script to add.
: "${AZCOPY_JOB_PLAN_LOCATION:=/media/fat/linux/azcopy/plans}"
: "${AZCOPY_LOG_LOCATION:=/media/fat/linux/azcopy/logs}"

# HOW MUCH RAM AZCOPY MAY BUFFER.
#
# 0.125 GiB = 128 MiB. This one is not a tidiness preference -- the upstream
# default will not fit on this board.
#
# AzCopy sizes its buffer cache in jobsAdmin/JobsAdmin.go:getMaxRamForChunks()
# as 0.5 GiB per logical CPU, capped at 16 GiB -- or at 1 GiB when
# `strconv.IntSize == 32`, which is true for this ARMv7 build. The DE10-Nano
# has 2 cores, so 2 x 0.5 = 1.0 GiB, and the 32-bit cap does not bite. The
# board boots with `mem=511M` (U-Boot reserves the rest for the FPGA side), so
# the default limit is roughly TWICE the machine's entire RAM. It is a limit
# and not a preallocation, so nothing fails at startup -- azcopy simply keeps
# allocating on a big transfer until the kernel OOM-kills something, and on
# this board the fattest process around is usually MiSTer itself.
#
# 128 MiB is chosen to be comfortably above the block size, not tuned for
# throughput. AzCopy errors out if a single block is larger than the whole
# limit and warns below 4 blocks in flight (common.MinParallelChunkCountThreshold),
# so with the 8 MiB default block size this leaves 16 blocks of headroom.
# Raise it if you have measured that you need to and know what else is running.
: "${AZCOPY_BUFFER_GB:=0.125}"

export AZCOPY_JOB_PLAN_LOCATION AZCOPY_LOG_LOCATION AZCOPY_BUFFER_GB

# DELIBERATELY NOT SET HERE:
#
#   AZCOPY_CONCURRENCY_VALUE  AzCopy fixes this at 32 connections for machines
#                             with <= 4 CPUs (ste/concurrency.go getMainPoolSize).
#                             That is more than a 100 Mbit link needs, but the
#                             memory it costs is already bounded by the buffer
#                             cap above, and picking a number without measuring
#                             on the board would be guessing at a performance
#                             trade-off. Set it yourself if a transfer misbehaves.
#   AZCOPY_AUTO_LOGIN_TYPE    Credentials are the operator's business, not the
#                             image's. See docs/azcopy.md for the options.
