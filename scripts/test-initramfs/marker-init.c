/*
 * scripts/test-initramfs/marker-init.c
 *
 * TASKS.md P1.12 (A7). Lifted from work/p1.10-qemu/marker-init.c, P1.10's own
 * throwaway verification harness (docs/decisions/0002-initramfs.md §8), and
 * extended with the non-ASCII-filename check P1.12 adds.
 *
 * This is the /sbin/init baked into the tiny ext4 image that the REAL
 * initramfs /init loop-mounts and switch_root's into (see
 * board/mister/de10nano/initramfs-overlay/init). It runs as PID 1 in the
 * switched root and asserts, from *inside* the booted system, every property
 * /init is supposed to have established, then powers the machine off so QEMU
 * exits with a deterministic status.
 *
 * scripts/test-initramfs.sh compiles this source TWICE:
 *   marker-init           - the six ADR-0002 §8 invariants (every fixture)
 *   marker-init-nonascii  - the same six PLUS check_nonascii() below, built
 *                           with -DCHECK_NONASCII, used only for the
 *                           "nonascii" fixture (a non-ASCII FAT32 long
 *                           filename must survive the vfat utf8=1 mount
 *                           path byte-for-byte -- ADR 0010).
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/reboot.h>
#include <linux/reboot.h>

static int fail;

static void expect(const char *what, int ok)
{
	printf("MARKER: %-42s %s\n", what, ok ? "PASS" : "FAIL");
	if (!ok)
		fail = 1;
}

/* Return 1 if any line of `path` contains all of the (NULL-terminated) needles. */
static int grep_all(const char *path, const char **needles)
{
	char line[1024];
	FILE *f = fopen(path, "r");
	if (!f)
		return 0;
	while (fgets(line, sizeof line, f)) {
		int i, ok = 1;
		for (i = 0; needles[i]; i++)
			if (!strstr(line, needles[i]))
				ok = 0;
		if (ok) {
			fclose(f);
			return 1;
		}
	}
	fclose(f);
	return 0;
}

/* Read the first byte of a sysfs file. */
static int first_byte(const char *path)
{
	char c = 0;
	FILE *f = fopen(path, "r");
	if (!f)
		return -1;
	if (fread(&c, 1, 1, f) != 1)
		c = -1;
	fclose(f);
	return c;
}

#ifdef CHECK_NONASCII
/*
 * scripts/test-initramfs.sh creates this exact file, with this exact name and
 * content, on the FAT32 data partition (at its root, alongside linux/) using
 * mtools `mcopy` -- entirely independent of the kernel or the initramfs /init.
 * Written as explicit \xHH escapes rather than a source-literal UTF-8 string
 * so the assertion below does not depend on THIS .c file's own encoding.
 *
 *   Pok\xc3\xa9mon_\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e_\xe2\x98\x85.txt
 *   = "Pokémon_日本語_★.txt"
 *     é      -> C3 A9                    (Latin-1 Supplement, 2-byte UTF-8)
 *     日本語 -> E6 97 A5 E6 9C AC E8 AA 9E (CJK Unified Ideographs, 3 bytes each)
 *     ★      -> E2 98 85                 (Miscellaneous Symbols, 3-byte UTF-8)
 *
 * If the vfat mount ever loses `utf8=1` (ADR 0010(b)) the on-disk UTF-16LE
 * long-name entry gets decoded through the wrong (or no) NLS table and
 * userland sees mojibake -- a DIFFERENT byte sequence than the one below, so
 * this exact open() fails with ENOENT even though a file is plainly there
 * (visible, under a mangled name, in a directory listing). That is precisely
 * the failure mode the task text describes for Main_MiSTer's recents/
 * favorites/MGL path lookups, reproduced here byte-for-byte instead of by eye.
 */
#define NONASCII_NAME    "Pok\xc3\xa9mon_\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e_\xe2\x98\x85.txt"
#define NONASCII_CONTENT "MARKER-NONASCII-OK"

static void check_nonascii(void)
{
	char path[256];
	char buf[128];
	int fd, n;

	snprintf(path, sizeof path, "/media/fat/%s", NONASCII_NAME);

	fd = open(path, O_RDONLY);
	expect("non-ASCII vfat filename opens by its exact UTF-8 bytes", fd >= 0);
	if (fd < 0)
		return;

	n = (int)read(fd, buf, sizeof buf - 1);
	close(fd);
	if (n < 0)
		n = 0;
	buf[n] = '\0';

	expect("non-ASCII file content round-trips byte-for-byte",
	       n == (int)strlen(NONASCII_CONTENT) &&
	       memcmp(buf, NONASCII_CONTENT, (size_t)n) == 0);
}
#endif

int main(void)
{
	const char *root_ro[]  = { " / ", "ext4", "ro,", NULL };
	const char *fat_mnt[]  = { " /media/fat ", "sync", "dirsync", "noatime", NULL };
	const char *fat_rw[]   = { " /media/fat ", "rw,", NULL };
	const char *devtmpfs[] = { " /dev ", "devtmpfs", NULL };
	const char *procfs[]   = { " /proc ", "proc", NULL };

	puts("");
	puts("MARKER: ===== /sbin/init reached: switch_root WORKED =====");

	/* This is the whole ballgame: the rootfs came from the loop-mounted image. */
	expect("rootfs is ext4 and mounted READ-ONLY",   grep_all("/proc/mounts", root_ro));

	/* A13: /media/fat exists at all (nothing in /etc mounts it) and is sync,dirsync. */
	expect("/media/fat present, sync+dirsync+noatime", grep_all("/proc/mounts", fat_mnt));

	/* A15 (indirect): the data partition is rw, which is what keeps the loop
	 * device writable -- busybox losetup falls back to O_RDONLY otherwise. */
	expect("/media/fat is READ-WRITE",              grep_all("/proc/mounts", fat_rw));

	/* A15 (direct): the loop DEVICE must not be read-only, or /etc/profile's
	 * `mount -o remount,rw /` fails on every login shell. */
	expect("loop device is WRITABLE (/sys/.../ro==0)", first_byte("/sys/block/loop0/ro") == '0');

	/* Moved from the initramfs; the rootfs image has no devtmpfs line in fstab. */
	expect("/dev is devtmpfs (moved from initramfs)", grep_all("/proc/mounts", devtmpfs));
	expect("/proc is mounted",                      grep_all("/proc/mounts", procfs));

#ifdef CHECK_NONASCII
	check_nonascii();
#endif

	printf("\nMARKER: RESULT=%s\n", fail ? "FAIL" : "PASS");
	fflush(NULL);
	sync();
	reboot(LINUX_REBOOT_CMD_POWER_OFF);
	for (;;)
		pause();
}
