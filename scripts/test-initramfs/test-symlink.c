/* QEMU guest driver for the exfat symlink patch (0031, ADR 0019).
 * Usage: test-symlink <mountpoint> create|verify|fixture
 *   create  — make target + links, assert everything hot-cache
 *   verify  — after umount/remount: assert everything cold-cache, then unlink
 *   fixture — readlink a hand-crafted Samsung-style link made on the host
 * Prints PASS:<tag> / FAIL:<tag> lines; exits nonzero on first failure.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/statvfs.h>

static char base[4096];

static void die(const char *tag) { printf("FAIL:%s errno=%d (%s)\n", tag, errno, strerror(errno)); exit(1); }
static void pass(const char *tag) { printf("PASS:%s\n", tag); }

static void path(char *out, const char *rel) { snprintf(out, 4096, "%s/%s", base, rel); }

static void check_readlink(const char *rel, const char *want, const char *tag)
{
	char p[4096], buf[4096];
	ssize_t n;
	path(p, rel);
	n = readlink(p, buf, sizeof(buf) - 1);
	if (n < 0) die(tag);
	buf[n] = 0;
	if (strcmp(buf, want)) { printf("FAIL:%s got '%s' want '%s'\n", tag, buf, want); exit(1); }
	pass(tag);
}

static void check_islnk(const char *rel, const char *tag)
{
	char p[4096]; struct stat st;
	path(p, rel);
	if (lstat(p, &st) < 0) die(tag);
	if (!S_ISLNK(st.st_mode)) { printf("FAIL:%s mode=%o not a symlink\n", tag, st.st_mode); exit(1); }
	pass(tag);
}

static void check_follow(const char *rel, const char *want, const char *tag)
{
	char p[4096], buf[256];
	int fd; ssize_t n;
	path(p, rel);
	fd = open(p, O_RDONLY);           /* follows the link */
	if (fd < 0) die(tag);
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n < 0) die(tag);
	buf[n] = 0;
	if (strcmp(buf, want)) { printf("FAIL:%s got '%s'\n", tag, buf); exit(1); }
	pass(tag);
}

static void check_dtype(const char *dirrel, const char *name, unsigned char want, const char *tag)
{
	char p[4096]; DIR *d; struct dirent *e; int found = 0;
	path(p, dirrel);
	d = opendir(p);
	if (!d) die(tag);
	while ((e = readdir(d)))
		if (!strcmp(e->d_name, name)) { found = 1; break; }
	if (!found) { printf("FAIL:%s '%s' missing from readdir\n", tag, name); closedir(d); exit(1); }
	if (e->d_type != want) { printf("FAIL:%s d_type=%d want %d\n", tag, e->d_type, want); closedir(d); exit(1); }
	closedir(d);
	pass(tag);
}

int main(int argc, char **argv)
{
	char p[4096], p2[4096];
	int fd;

	if (argc != 3) { fprintf(stderr, "usage: %s <mnt> create|verify|fixture\n", argv[0]); return 2; }
	snprintf(base, sizeof(base), "%s", argv[1]);

	if (!strcmp(argv[2], "create")) {
		path(p, "_Arcade");    if (mkdir(p, 0777) && errno != EEXIST) die("mkdir-arcade");
		path(p, "_Organized"); if (mkdir(p, 0777) && errno != EEXIST) die("mkdir-organized");

		path(p, "_Arcade/Galaga.mra");
		fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0666);
		if (fd < 0 || write(fd, "MRA-CONTENT", 11) != 11) die("write-target");
		close(fd);

		path(p, "_Organized/Galaga.mra");
		if (symlink("../_Arcade/Galaga.mra", p)) die("symlink-rel");
		pass("symlink-rel");
		path(p, "abslink");
		snprintf(p2, sizeof(p2), "%s/_Arcade/Galaga.mra", base);
		if (symlink(p2, p)) die("symlink-abs");
		pass("symlink-abs");
		path(p, "dangle");
		if (symlink("no/such/file", p)) die("symlink-dangle");
		pass("symlink-dangle");

		check_readlink("_Organized/Galaga.mra", "../_Arcade/Galaga.mra", "hot-readlink-rel");
		check_islnk("_Organized/Galaga.mra", "hot-lstat-islnk");
		check_follow("_Organized/Galaga.mra", "MRA-CONTENT", "hot-follow-rel");
		check_follow("abslink", "MRA-CONTENT", "hot-follow-abs");
		check_dtype("_Organized", "Galaga.mra", DT_LNK, "hot-readdir-dtype");

		/* EEXIST semantics */
		path(p, "dangle");
		if (!symlink("x", p) || errno != EEXIST) die("symlink-eexist");
		pass("symlink-eexist");

		/* same-mount create+delete: the freshly created (never
		 * remounted) inode must free its target cluster on eviction —
		 * regression test for the __exfat_truncate() type-guard leak
		 * (ei->type must be TYPE_FILE, not a symlink-only type). The
		 * leak is visible as free space not returning after unlink. */
		{
			struct statvfs before, after;
			if (statvfs(base, &before)) die("churn-statvfs1");
			path(p, "churn");
			if (symlink("some/target/path", p)) die("churn-create");
			if (unlink(p)) die("churn-unlink");
			pass("churn-create-unlink");
			if (statvfs(base, &after)) die("churn-statvfs2");
			if (after.f_bfree != before.f_bfree) {
				printf("FAIL:churn-cluster-leak bfree %lu -> %lu\n",
				       (unsigned long)before.f_bfree,
				       (unsigned long)after.f_bfree);
				exit(1);
			}
			pass("churn-cluster-leak");
		}
		return 0;
	}

	if (!strcmp(argv[2], "verify")) {
		check_readlink("_Organized/Galaga.mra", "../_Arcade/Galaga.mra", "cold-readlink-rel");
		check_islnk("_Organized/Galaga.mra", "cold-lstat-islnk");
		check_follow("_Organized/Galaga.mra", "MRA-CONTENT", "cold-follow-rel");
		check_follow("abslink", "MRA-CONTENT", "cold-follow-abs");
		check_dtype("_Organized", "Galaga.mra", DT_LNK, "cold-readdir-dtype");
		check_readlink("dangle", "no/such/file", "cold-readlink-dangle");
		path(p, "dangle");
		if (open(p, O_RDONLY) >= 0 || errno != ENOENT) die("dangle-enoent");
		pass("dangle-enoent");
		if (unlink(p)) die("unlink-link");
		pass("unlink-link");
		path(p, "_Arcade/Galaga.mra");
		if (access(p, R_OK)) die("target-survives-unlink");
		pass("target-survives-unlink");
		return 0;
	}

	if (!strcmp(argv[2], "fixture")) {
		check_islnk("samsung_link", "samsung-lstat-islnk");
		check_readlink("samsung_link", "_Arcade/Galaga.mra", "samsung-readlink");
		check_follow("samsung_link", "MRA-CONTENT", "samsung-follow");
		return 0;
	}

	return 2;
}
