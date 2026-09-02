#!/bin/sh
# etc/wifi-hotplug.sh -- async ifup/ifdown dispatcher for
# etc/udev/rules.d/70-persistent-net.rules (T2). Read that file first; this
# script exists for one reason only: get ifup/ifdown OFF the udev worker
# process that runs this RUN+= command, so a slow bring-up never ties one up.
#
# usage: wifi-hotplug.sh {up|down} <ifname>
#   ifname is %k from the rule -- the kernel-assigned name (wlan0, wlan1,
#   ...), which on this image is also the PERMANENT name: see the rule
#   file's part (1) for why no udev rule (this one included) ever renames a
#   USB WiFi netdev on this board.
#
# Why detach (verified, see the rule file for citations): the pre-up loop in
# etc/network/interfaces can block for up to 20s per interface, plus the
# stanza's own `post_up sleep 2`. The load-bearing consequence is at BOOT,
# not on the 180s event timeout: package/eudev/S10udevd:43 runs
# `udevadm settle --timeout=30` (SETTLE_TIMEOUT at :22) right after the
# coldplug trigger, and settle blocks rcS until the udev event queue drains.
# A non-detached RUN+= would hold its event open for the entire bring-up, so
# every boot with WiFi hardware present would stall rcS for >20s and risk
# tripping settle's 30s timeout ("udevadm settle failed"). eudev's own 180s
# default event timeout (udevd.c:72) is well clear of that, so nothing would
# have been *killed* -- the cost is a stalled boot and an occupied worker,
# and worker occupancy stacks (a hub with more than one dongle fires one
# "add" event per interface).
#
# setsid + redirected std fds is what makes the detach actually stick:
#   - setsid (util-linux's, not BusyBox's -- board/mister/de10nano/
#     busybox.fragment carries "# CONFIG_SETSID is not set" specifically
#     because util-linux provides it; configs/fragments/de10nano-image.fragment's
#     BR2_PACKAGE_UTIL_LINUX_BINARIES comment lists setsid among the basic
#     set it installs, and it is confirmed present at output/target/usr/bin/
#     setsid, an ELF binary, not a BusyBox applet) starts ifup/ifdown in a
#     new session, detached from udev's.
#   - </dev/null >/dev/null 2>&1 is applied by the shell in the FORKED CHILD,
#     after fork and before exec -- not in this script's own process. That is
#     what matters: at this image's shipped udev log level the child would
#     otherwise inherit, and keep open, the pipe udev_event_spawn() reads.
#     Traced rather than assumed:
#       * output/build/eudev-3.2.14/src/shared/log.c:42 sets the default
#         log_max_level to LOG_INFO, and nothing lowers it here --
#         output/target/etc/udev/udev.conf:6 leaves `#udev_log="info"`
#         commented out (so libudev.c:173 never fires), S10udevd:23 passes
#         UDEVD_ARGS="" and this image ships no /etc/default/udevd for
#         S10udevd:26 to source over it (no output/target/etc/default at
#         all), so udevd gets no --debug and udevd.c:1173 never fires; this
#         board's cmdline carries no `udev.log-priority=` (udevd.c:1010, fed
#         by parse_proc_cmdline(); the effective cmdline is recorded at
#         docs/boot-chain.md:323).
#       * udev-event.c:726 creates outpipe `if (result != NULL ||
#         log_get_max_level() >= LOG_INFO)` and :733 creates errpipe on the
#         log-level test alone. udev_event_execute_run() passes result ==
#         NULL for RUN+= (:1087), but LOG_INFO >= LOG_INFO is true, so BOTH
#         pipes are created in this build.
#       * udev_event_spawn() (:709) then calls spawn_read() (:787).
#         spawn_read() (:450) loops on `while (fd_stdout >= 0 ||
#         fd_stderr >= 0)` (:494) and only drops an fd on EPOLLHUP -- i.e.
#         it waits for every writer to close. A grandchild holding a write end
#         would keep the udev worker blocked for the full bring-up even
#         though THIS script has already returned, defeating the whole point
#         of backgrounding.
#     (spawn_exec() at udev-event.c:409-448 dup2()s /dev/null over std fds
#     only for the ends that have no pipe, so it does not save us here.)
#   - the trailing `&` backgrounds the setsid/ifup command and this script
#     falls straight through to `exit 0` without waiting on it -- the
#     backgrounded process is reparented to init on this script's exit and
#     keeps running to completion.
#
# ifup/ifdown's own re-entrancy (double hotplug events, or racing
# S40network's boot-time `ifup -a`) is handled by ifupdown itself, via an
# exclusive POSIX record lock on its per-interface state file (fcntl
# F_SETLK/F_SETLKW, output/build/ifupdown-0.8.44/main.c:203-215 -- not
# flock(2); there is no flock() call anywhere in that tree) -- see the rule
# file's part (2). This script does not need to, and does not, do any
# locking of its own.

set -u

action="$1"
iface="$2"

case "$action" in
	up)   cmd="/sbin/ifup" ;;
	down) cmd="/sbin/ifdown" ;;
	*)    exit 1 ;;
esac

setsid "$cmd" "$iface" </dev/null >/dev/null 2>&1 &

exit 0
