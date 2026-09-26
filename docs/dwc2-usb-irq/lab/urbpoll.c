/*
 * urbpoll - measure host-controller interrupt-IN polling cadence.
 *
 * Bypasses the HID (or other) driver by disconnect-and-claiming the
 * interface directly via usbfs, then keeps K interrupt URBs in flight
 * on one endpoint, reaping and immediately resubmitting each one, for
 * a fixed number of seconds. Reports completion rate, inter-completion
 * gap statistics, and how often the payload actually changed.
 *
 * Usage: urbpoll <bus> <dev> <iface> <ep_hex e.g. 81> <maxp> <K urbs> <seconds>
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/usbdevice_fs.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>

static const char *progname = "urbpoll";

static void usage(FILE *out)
{
	fprintf(out,
		"usage: %s <bus> <dev> <iface> <ep_hex e.g. 81> <maxp> <K urbs> <seconds>\n"
		"  bus, dev   decimal, as in /dev/bus/usb/BBB/DDD\n"
		"  iface      interface number to disconnect-claim\n"
		"  ep_hex     endpoint address, hex, e.g. 81 for EP1 IN\n"
		"  maxp       URB buffer length in bytes (endpoint wMaxPacketSize)\n"
		"  K urbs     number of interrupt URBs kept in flight\n"
		"  seconds    how long to poll before reporting and cleaning up\n",
		progname);
}

static volatile sig_atomic_t g_stop;

static void on_signal(int signo)
{
	(void)signo;
	g_stop = 1;
}

static double ts_diff_us(const struct timespec *a, const struct timespec *b)
{
	double sec = (double)(a->tv_sec - b->tv_sec);
	double nsec = (double)(a->tv_nsec - b->tv_nsec);
	return sec * 1e6 + nsec / 1e3;
}

struct status_count {
	int status;
	long count;
};

static struct status_count g_status_counts[64];
static size_t g_status_nkeys;

static void bump_status(int status)
{
	size_t i;

	for (i = 0; i < g_status_nkeys; i++) {
		if (g_status_counts[i].status == status) {
			g_status_counts[i].count++;
			return;
		}
	}
	if (g_status_nkeys < sizeof(g_status_counts) / sizeof(g_status_counts[0])) {
		g_status_counts[g_status_nkeys].status = status;
		g_status_counts[g_status_nkeys].count = 1;
		g_status_nkeys++;
	}
}

static int cmp_double(const void *pa, const void *pb)
{
	double a = *(const double *)pa;
	double b = *(const double *)pb;

	if (a < b)
		return -1;
	if (a > b)
		return 1;
	return 0;
}

static double percentile(double *sorted, size_t n, double frac)
{
	size_t idx;

	if (n == 0)
		return 0.0;
	idx = (size_t)(frac * (double)(n - 1) + 0.5);
	if (idx >= n)
		idx = n - 1;
	return sorted[idx];
}

/* Best-effort: disconnect the kernel driver from iface and claim it. */
static int disconnect_claim(int fd, int iface)
{
	struct usbdevfs_disconnect_claim dc;
	unsigned int ifno;

	memset(&dc, 0, sizeof(dc));
	dc.interface = (unsigned int)iface;
	dc.flags = 0; /* unconditionally disconnect whatever driver is bound, and claim */
	if (ioctl(fd, USBDEVFS_DISCONNECT_CLAIM, &dc) == 0)
		return 0;

	/* Fallback for kernels without USBDEVFS_DISCONNECT_CLAIM. */
	struct usbdevfs_ioctl ctl;

	memset(&ctl, 0, sizeof(ctl));
	ctl.ifno = iface;
	ctl.ioctl_code = (int)USBDEVFS_DISCONNECT;
	ctl.data = NULL;
	if (ioctl(fd, USBDEVFS_IOCTL, &ctl) < 0 && errno != ENODATA)
		fprintf(stderr, "%s: warning: USBDEVFS_DISCONNECT: %s\n", progname, strerror(errno));

	ifno = (unsigned int)iface;
	if (ioctl(fd, USBDEVFS_CLAIMINTERFACE, &ifno) < 0) {
		fprintf(stderr, "%s: USBDEVFS_CLAIMINTERFACE: %s\n", progname, strerror(errno));
		return -1;
	}
	return 0;
}

static void reconnect(int fd, int iface)
{
	struct usbdevfs_ioctl ctl;
	unsigned int ifno = (unsigned int)iface;

	if (ioctl(fd, USBDEVFS_RELEASEINTERFACE, &ifno) < 0)
		fprintf(stderr, "%s: warning: USBDEVFS_RELEASEINTERFACE: %s\n", progname, strerror(errno));

	memset(&ctl, 0, sizeof(ctl));
	ctl.ifno = iface;
	ctl.ioctl_code = (int)USBDEVFS_CONNECT;
	ctl.data = NULL;
	if (ioctl(fd, USBDEVFS_IOCTL, &ctl) < 0)
		fprintf(stderr, "%s: warning: USBDEVFS_CONNECT: %s\n", progname, strerror(errno));
}

int main(int argc, char **argv)
{
	if (argc != 8) {
		usage(stderr);
		return 1;
	}

	int bus = atoi(argv[1]);
	int dev = atoi(argv[2]);
	int iface = atoi(argv[3]);
	unsigned long ep = strtoul(argv[4], NULL, 16);
	int maxp = atoi(argv[5]);
	int K = atoi(argv[6]);
	double seconds = strtod(argv[7], NULL);

	if (maxp <= 0 || K <= 0 || seconds <= 0.0) {
		fprintf(stderr, "%s: maxp, K and seconds must be positive\n", progname);
		usage(stderr);
		return 1;
	}

	char path[64];
	snprintf(path, sizeof(path), "/dev/bus/usb/%03d/%03d", bus, dev);

	int fd = open(path, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "%s: open %s: %s\n", progname, path, strerror(errno));
		return 1;
	}

	if (disconnect_claim(fd, iface) < 0) {
		close(fd);
		return 1;
	}

	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	struct usbdevfs_urb *urbs = calloc((size_t)K, sizeof(*urbs));
	unsigned char **bufs = calloc((size_t)K, sizeof(*bufs));
	if (!urbs || !bufs) {
		fprintf(stderr, "%s: out of memory\n", progname);
		reconnect(fd, iface);
		close(fd);
		return 1;
	}

	int i;
	for (i = 0; i < K; i++) {
		bufs[i] = malloc((size_t)maxp);
		if (!bufs[i]) {
			fprintf(stderr, "%s: out of memory\n", progname);
			reconnect(fd, iface);
			close(fd);
			return 1;
		}
		memset(&urbs[i], 0, sizeof(urbs[i]));
		urbs[i].type = USBDEVFS_URB_TYPE_INTERRUPT;
		urbs[i].endpoint = (unsigned char)ep;
		urbs[i].buffer = bufs[i];
		urbs[i].buffer_length = maxp;
		if (ioctl(fd, USBDEVFS_SUBMITURB, &urbs[i]) < 0) {
			fprintf(stderr, "%s: USBDEVFS_SUBMITURB[%d]: %s\n", progname, i, strerror(errno));
			reconnect(fd, iface);
			close(fd);
			return 1;
		}
	}

	unsigned char *last_data = malloc((size_t)maxp);
	int last_len = -1;
	int have_last = 0;

	size_t gap_cap = 1024, gap_n = 0;
	double *gaps_us = malloc(gap_cap * sizeof(*gaps_us));
	struct timespec prev_completion;
	int have_prev = 0;

	long completions = 0;
	long changed = 0;
	uint64_t bytes = 0;

	struct timespec start, now;
	clock_gettime(CLOCK_MONOTONIC, &start);

	while (!g_stop) {
		clock_gettime(CLOCK_MONOTONIC, &now);
		if (ts_diff_us(&now, &start) >= seconds * 1e6)
			break;

		struct pollfd pfd = { .fd = fd, .events = POLLOUT, .revents = 0 };
		int pr = poll(&pfd, 1, 100);
		if (pr < 0) {
			if (errno == EINTR)
				continue;
			fprintf(stderr, "%s: poll: %s\n", progname, strerror(errno));
			break;
		}
		if (g_stop)
			break;
		if (pr == 0 || !(pfd.revents & POLLOUT))
			continue;

		for (;;) {
			struct usbdevfs_urb *reaped = NULL;
			if (ioctl(fd, USBDEVFS_REAPURBNDELAY, &reaped) < 0) {
				if (errno == EAGAIN)
					break;
				if (errno == EINTR)
					continue;
				fprintf(stderr, "%s: USBDEVFS_REAPURBNDELAY: %s\n", progname, strerror(errno));
				break;
			}

			clock_gettime(CLOCK_MONOTONIC, &now);
			completions++;
			bump_status(reaped->status);

			if (have_prev) {
				double gap = ts_diff_us(&now, &prev_completion);
				if (gap_n == gap_cap) {
					gap_cap *= 2;
					gaps_us = realloc(gaps_us, gap_cap * sizeof(*gaps_us));
				}
				gaps_us[gap_n++] = gap;
			}
			prev_completion = now;
			have_prev = 1;

			if (reaped->status == 0 && reaped->actual_length > 0) {
				bytes += (uint64_t)reaped->actual_length;

				int diff = 1;
				if (have_last && reaped->actual_length == last_len) {
					diff = memcmp(reaped->buffer, last_data, (size_t)last_len) != 0;
				}
				if (diff)
					changed++;

				memcpy(last_data, reaped->buffer, (size_t)reaped->actual_length);
				last_len = reaped->actual_length;
				have_last = 1;
			}

			if (ioctl(fd, USBDEVFS_SUBMITURB, reaped) < 0)
				fprintf(stderr, "%s: warning: resubmit: %s\n", progname, strerror(errno));
		}
	}

	clock_gettime(CLOCK_MONOTONIC, &now);
	double elapsed_s = ts_diff_us(&now, &start) / 1e6;

	/* Cleanup: discard every URB we submitted, then drain completions. */
	for (i = 0; i < K; i++)
		ioctl(fd, USBDEVFS_DISCARDURB, &urbs[i]);
	for (;;) {
		struct usbdevfs_urb *reaped = NULL;
		struct pollfd pfd = { .fd = fd, .events = POLLOUT, .revents = 0 };
		if (poll(&pfd, 1, 100) <= 0)
			break;
		if (!(pfd.revents & POLLOUT))
			break;
		if (ioctl(fd, USBDEVFS_REAPURBNDELAY, &reaped) < 0)
			break;
	}

	reconnect(fd, iface);
	close(fd);

	qsort(gaps_us, gap_n, sizeof(*gaps_us), cmp_double);
	double gmin = gap_n ? gaps_us[0] : 0.0;
	double gmax = gap_n ? gaps_us[gap_n - 1] : 0.0;
	double gsum = 0.0;
	size_t hist[6] = { 0, 0, 0, 0, 0, 0 };
	for (i = 0; i < (int)gap_n; i++) {
		double g = gaps_us[i];
		gsum += g;
		if (g < 750)
			hist[0]++;
		else if (g < 1250)
			hist[1]++;
		else if (g < 1750)
			hist[2]++;
		else if (g < 2500)
			hist[3]++;
		else if (g < 3500)
			hist[4]++;
		else
			hist[5]++;
	}
	double gmean = gap_n ? gsum / (double)gap_n : 0.0;

	printf("urbs=%d\n", K);
	printf("secs=%.3f\n", elapsed_s);
	printf("completions=%ld\n", completions);
	printf("rate=%.2f\n", elapsed_s > 0.0 ? (double)completions / elapsed_s : 0.0);
	for (i = 0; i < (int)g_status_nkeys; i++)
		printf("status_%d=%ld\n", g_status_counts[i].status, g_status_counts[i].count);
	printf("bytes=%" PRIu64 "\n", bytes);
	printf("changed=%ld\n", changed);
	printf("gap_n=%zu\n", gap_n);
	printf("gap_min_us=%.1f\n", gmin);
	printf("gap_p10_us=%.1f\n", percentile(gaps_us, gap_n, 0.10));
	printf("gap_p50_us=%.1f\n", percentile(gaps_us, gap_n, 0.50));
	printf("gap_p90_us=%.1f\n", percentile(gaps_us, gap_n, 0.90));
	printf("gap_max_us=%.1f\n", gmax);
	printf("gap_mean_us=%.1f\n", gmean);
	printf("hist_lt750=%zu\n", hist[0]);
	printf("hist_lt1250=%zu\n", hist[1]);
	printf("hist_lt1750=%zu\n", hist[2]);
	printf("hist_lt2500=%zu\n", hist[3]);
	printf("hist_lt3500=%zu\n", hist[4]);
	printf("hist_ge3500=%zu\n", hist[5]);

	free(gaps_us);
	free(last_data);
	for (i = 0; i < K; i++)
		free(bufs[i]);
	free(bufs);
	free(urbs);

	return 0;
}
