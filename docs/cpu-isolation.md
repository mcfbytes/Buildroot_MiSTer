# Keeping Linux work off CPU1

`Scripts/cpu_isolation.sh` launches `/usr/sbin/mister-cpu-isolation`. It keeps every Linux
program except the MiSTer main program off CPU1, either live or through the kernel command
line. Sources below are Main_MiSTer at 6cda9cc and Linux 6.18.55.

## Why CPU1

Main_MiSTer pins itself to CPU1 at startup (`main.cpp:44-48`, `sched_setaffinity` to CPU 1)
and busy-polls there. Its offload thread is pinned to CPU0 (`offload.cpp:83`). Everything
else may run on either CPU, so the scheduler sometimes puts a Linux task (an update, `7za`,
Samba, SSH, transmission) on CPU1. The busy main loop then shares CPU1 with that task in
time slices of a few milliseconds.

Keeping that work on CPU0 gives the main loop CPU1 to itself. Linux work then has one CPU
instead of two. Nothing has been measured yet: the expected gain is fewer main-loop gaps
while something runs in the background, not lower input latency in general.

## The live switch (default)

`mister-cpu-isolation on` moves every user-space thread whose CPU list is `0-1` to CPU0 with
`taskset`. It skips:

- kernel threads (`PF_KTHREAD`);
- every thread of the MiSTer process, which manages its own CPUs;
- threads someone pinned to CPU1 alone.

It also sets `/sys/devices/virtual/workqueue/cpumask` to CPU0 for unbound kernel work. New
programs inherit CPU0 from init and from the daemons that start them. Programs Main starts
itself inherit Main's CPU1 mask, exactly as without this switch.

`off` gives both CPUs back to every non-MiSTer user thread on CPU0 alone, and sets the
workqueue mask back to both. That includes a thread that was on CPU0 alone for its own reasons;
Main's script terminal (`menu.cpp:3432`) is the one known case, and widening it is harmless.

The switch lasts until the next reboot. "Every boot" writes `/media/fat/linux/cpu_isolation`,
and `/etc/init.d/S03cpu-isolation` runs `mister-cpu-isolation boot`, which switches on only
when that file exists. S03 runs before the daemons start, so they inherit CPU0 from init.

## The kernel command line (advanced)

`cmdline-on` adds `isolcpus=domain,managed_irq,1 irqaffinity=0` to the last `v=` line of
`/media/fat/linux/u-boot.txt` (or adds `v=loglevel=4 ...`, restating U-Boot's built-in `v=`).
`cmdline-off` removes exactly those two tokens. The edit:

- touches only `v=` lines and refuses to save if any other line would change
  ([rollback.md](user/rollback.md) explains why `u-boot.txt` is that fragile);
- keeps CRLF line endings and adds a missing final newline;
- copies the old file to `u-boot.txt.before-cpu-isolation` first;
- warns when a custom `mmcboot=` does not pass `$v`.

What each part does on the DE10-Nano:

| Token | Effect here |
|---|---|
| `isolcpus=domain,…,1` | Init starts on the housekeeping CPU (`kernel/sched/core.c:8604`), so every task inherits CPU0. CPU1 gets no scheduler domain, so nothing is load-balanced onto it. Unbound workqueues are restricted to CPU0 (`kernel/workqueue.c:7835`) |
| `managed_irq` | No effect: only multi-queue devices (PCI MSI) have managed interrupts, and this board has none |
| `irqaffinity=0` | No visible effect: the GIC already delivers each SPI to the first online CPU of its mask (`drivers/irqchip/irq-gic.c:804`), and IRQ threads follow that effective CPU (`kernel/irq/manage.c:1038`). The masks in `/proc/irq/*/smp_affinity` read `1` instead of `3` |

Main still works: a task in the top cpuset may pin itself to an isolated CPU, because
`cpuset_cpus_allowed()` removes only cgroup-v2 partition CPUs, not boot-isolated ones
(`kernel/cgroup/cpuset.c:4242-4267`). So `main.cpp`'s `sched_setaffinity(CPU1)` succeeds.

One difference from the live switch: when scripts run in the OSD rather than on the
framebuffer terminal, and during Bluetooth pairing, Main widens itself to CPUs 0-1 and
`popen`s the script (`menu.cpp:7497-7509`). The child is forked on CPU1, and with no
scheduler domain there nothing moves it to CPU0, so it shares CPU1 with Main until it exits.
The live switch keeps CPU1's domain, so the load balancer still moves such a child.

The two can be combined; the live switch is then redundant. `uninstall.sh` leaves the
command-line tokens in place, and stock's kernel honours them too; run `cmdline-off` first
to drop them.
