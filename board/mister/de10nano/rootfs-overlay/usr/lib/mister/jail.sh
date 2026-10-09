# shellcheck shell=sh disable=SC2034 # JAIL_ERR and the JAIL_* paths are read by the caller
# Sourced by init scripts that run a daemon in minijail. The contract and the
# design: docs/minijail.md "Jailing a daemon".
#
# The caller sets, then calls jail_init:
#   JAIL_NAME       /etc/minijail/$JAIL_NAME.conf, /run/$JAIL_NAME, /sys/fs/cgroup/$JAIL_NAME
#   JAIL_EXEC       the daemon binary
#   JAIL_PIDS_MAX   ceiling on the cgroup's processes plus threads
#   JAIL_PROBE      a path in the jail its uid could write but Landlock must refuse
# and optionally:
#   JAIL_CONF       another config file (default /etc/minijail/$JAIL_NAME.conf)
#   JAIL_COMM       the process name too, when JAIL_EXEC is shared (BusyBox applets)
#   JAIL_ARGS_MATCH arguments its command line must contain, when one binary runs per
#                   instance (wpa_supplicant's "-i wlan0")
#   JAIL_SECCOMP_RULES  "syscall: rule" lines that replace the generated ones
#   JAIL_STOP_WAIT  seconds SIGTERM gets (default 10)
#   JAIL_STOP_KILL  1 to SIGKILL after JAIL_STOP_WAIT (default: never)
#   JAIL_LOG_TAG    pipe the daemon's stdout/stderr to syslog under this tag
#   JAIL_OOM_SCORE_ADJ

MINIJAIL=/usr/bin/minijail0

# Syscalls that return EPERM in every jail; every other one minijail0 knows is allowed.
JAIL_SECCOMP_DENY="io_uring_setup io_uring_enter io_uring_register perf_event_open bpf
userfaultfd keyctl add_key request_key ptrace process_vm_readv process_vm_writev
process_madvise kcmp pidfd_getfd mount umount2 pivot_root chroot mount_setattr
move_mount open_tree open_tree_attr fsopen fsconfig fsmount fspick unshare setns
swapon swapoff reboot kexec_load kexec_file_load init_module finit_module
delete_module acct quotactl quotactl_fd syslog settimeofday clock_settime
clock_settime64 adjtimex clock_adjtime clock_adjtime64 sethostname setdomainname
personality vhangup name_to_handle_at open_by_handle_at fanotify_init memfd_create
execveat"

# Derives the paths and reads uid, gid and capabilities from the config file.
jail_init() {
	: "${JAIL_CONF:=/etc/minijail/$JAIL_NAME.conf}"
	JAIL_RUN_DIR="/run/$JAIL_NAME"
	JAIL_ROOT="$JAIL_RUN_DIR/root"
	JAIL_PIDFILE="$JAIL_RUN_DIR/jail.pid"
	JAIL_POLICY="$JAIL_RUN_DIR/seccomp.policy"
	JAIL_CGROUP="/sys/fs/cgroup/$JAIL_NAME"
	JAIL_UID=$(sed -n 's/^u[[:space:]]*=[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p' "$JAIL_CONF" 2>/dev/null)
	JAIL_GID=$(sed -n 's/^g[[:space:]]*=[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p' "$JAIL_CONF" 2>/dev/null)
	JAIL_CAPS=$(sed -n 's/^c[[:space:]]*=[[:space:]]*\(0x[0-9a-fA-F]*\)[[:space:]]*$/\1/p' "$JAIL_CONF" 2>/dev/null)
	: "${JAIL_STOP_WAIT:=10}"
	# Mount points must be traversable by the jail's uid; a login shell's umask is 077.
	umask 022
}

# Serialises this script's verbs; fd 9 is closed again for the daemon.
jail_lock() {
	exec 9>"/run/$JAIL_NAME.lock" && flock -w 60 9
}

# Runs minijail0 with the config file, the common options, then "$@" (options -- command).
# Syslog takes the daemon's own timestamps, so the jail gets the host's zone.
jail_exec() {
	if [ -f /media/fat/linux/timezone ] && [ ! -L /media/fat/linux/timezone ]; then
		set -- -b /media/fat/linux/timezone,/etc/localtime "$@"
	fi
	# --config must come first.
	"$MINIJAIL" --config "$JAIL_CONF" -T static -n --ambient -P "$JAIL_ROOT" -S "$JAIL_POLICY" \
		-R RLIMIT_CORE,0,0 "$@"
}

# A fresh tmpfs root with the merged-usr links; minijail adds the other mount points.
jail_prepare_root() {
	mkdir -p "$JAIL_RUN_DIR" && chown -h 0:0 "$JAIL_RUN_DIR" && chmod 0700 "$JAIL_RUN_DIR" &&
		mkdir -p "$JAIL_ROOT" || return 1
	if mountpoint -q "$JAIL_ROOT"; then umount "$JAIL_ROOT" || return 1; fi
	mount -t tmpfs -o mode=0755,size=256k,nosuid,nodev,noexec tmpfs "$JAIL_ROOT" || return 1
	for l in bin lib sbin; do ln -s "usr/$l" "$JAIL_ROOT/$l" || return 1; done
}

# Writes the policy from minijail0's own syscall table: allow all, deny the
# deny list, and JAIL_SECCOMP_RULES in place of the line for their syscall.
jail_write_policy() {
	"$MINIJAIL" -H 2>/dev/null | DENY="$JAIL_SECCOMP_DENY" RULES="$JAIL_SECCOMP_RULES" awk '
		BEGIN {
			n = split(ENVIRON["DENY"], d); for (i = 1; i <= n; i++) D[d[i]] = 1
			n = split(ENVIRON["RULES"], r, "\n")
			for (i = 1; i <= n; i++) if (r[i] ~ /:/) { s = r[i]; sub(/:.*/, "", s); gsub(/[ \t]/, "", s); R[s] = r[i] }
		}
		$1 ~ /^[A-Za-z0-9_]+$/ && $2 ~ /^\[[0-9]+\]$/ {
			if ($1 in R) { print R[$1]; used[$1] = 1 }
			else print $1 (($1 in D) ? ": return 1" : ": 1")
			c++
		}
		END { for (s in R) if (!(s in used)) exit 1; exit c < 300 }' >"$JAIL_POLICY"
}

# The daemon's own cgroup2 group, with a ceiling on processes plus threads.
jail_prepare_cgroup() {
	c=/sys/fs/cgroup
	grep -qw pids "$c/cgroup.controllers" 2>/dev/null || return 1
	grep -qw pids "$c/cgroup.subtree_control" || echo +pids >"$c/cgroup.subtree_control" || return 1
	mkdir -p "$JAIL_CGROUP" && echo "$JAIL_PIDS_MAX" >"$JAIL_CGROUP/pids.max"
}

# Succeeds only if the jail ran and the write to JAIL_PROBE was refused.
jail_check_landlock() {
	# shellcheck disable=SC2016 # $1 expands in the jailed sh
	jail_exec -- /bin/sh -c '! printf "" >"$1"' sh "$JAIL_PROBE" 2>/dev/null
}

# minijail0 and a config file with numeric ids; on failure JAIL_ERR says why.
jail_ready() {
	if [ ! -x "$MINIJAIL" ] || [ ! -f "$JAIL_CONF" ]; then
		JAIL_ERR="$MINIJAIL or $JAIL_CONF missing"
	elif [ -z "$JAIL_UID" ] || [ -z "$JAIL_GID" ] || [ -z "$JAIL_CAPS" ]; then
		JAIL_ERR="$JAIL_CONF has no numeric u, g and c"
	else
		return 0
	fi
	return 1
}

# Root, policy, cgroup and the Landlock probe, after the caller's jail_prepare_root
# additions. On failure JAIL_ERR says why.
jail_prepare() {
	jail_ready || return 1
	# /run is per boot and minijail0 only changes with the image, so once per boot is enough.
	if [ ! -s "$JAIL_POLICY" ] && ! jail_write_policy; then
		rm -f "$JAIL_POLICY"
		JAIL_ERR="could not build the seccomp policy from $MINIJAIL -H"
	elif ! jail_prepare_cgroup; then
		JAIL_ERR="no cgroup2 pids controller at /sys/fs/cgroup"
	elif ! jail_check_landlock; then
		JAIL_ERR="Landlock is not enforced, or the jail cannot be built"
	else
		return 0
	fi
	return 1
}

# The start time from /proc/<pid>/stat (field 22), so a recycled pid is never taken for ours.
jail_starttime() {
	sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f20
}

# True if pid $1 runs JAIL_EXEC (named JAIL_COMM and given JAIL_ARGS_MATCH, when set).
jail_is_ours() {
	[ "$(readlink "/proc/$1/exe" 2>/dev/null)" = "$JAIL_EXEC" ] || return 1
	[ -z "$JAIL_COMM" ] || [ "$(cat "/proc/$1/comm" 2>/dev/null)" = "$JAIL_COMM" ] || return 1
	[ -z "$JAIL_ARGS_MATCH" ] ||
		printf ' %s ' "$({ tr '\0' ' ' <"/proc/$1/cmdline"; } 2>/dev/null)" | grep -qF -- " $JAIL_ARGS_MATCH "
}

# Sets JAIL_PID to the jailed daemon's host pid when the pidfile still names it.
jail_running() {
	JAIL_PID=""
	[ -f "$JAIL_PIDFILE" ] && read -r p s <"$JAIL_PIDFILE" || return 1
	[ -n "$p" ] && [ -n "$s" ] && [ "$(jail_starttime "$p")" = "$s" ] || return 1
	jail_is_ours "$p" || return 1
	JAIL_PID=$p
}

# True if any process is the daemon (pidof also matches a script of the same name).
jail_any_daemon() {
	for d in /proc/[0-9]*; do
		jail_is_ours "${d#/proc/}" && return 0
	done
	return 1
}

# Reads the jail's claims back from the kernel: all four uids and gids, no
# supplementary group but its own, no_new_privs, a seccomp filter, the cgroup, CapEff.
jail_check() {
	s="/proc/$1/status"
	u="[[:space:]]+${JAIL_UID}[[:space:]]+${JAIL_UID}[[:space:]]+${JAIL_UID}[[:space:]]+${JAIL_UID}[[:space:]]*$"
	g="[[:space:]]+${JAIL_GID}[[:space:]]+${JAIL_GID}[[:space:]]+${JAIL_GID}[[:space:]]+${JAIL_GID}[[:space:]]*$"
	grep -Eq "^Uid:$u" "$s" && grep -Eq "^Gid:$g" "$s" &&
		grep -Eq "^Groups:[[:space:]]*(${JAIL_GID}[[:space:]]*)?$" "$s" &&
		grep -q '^NoNewPrivs:[[:space:]]*1$' "$s" &&
		grep -q '^Seccomp:[[:space:]]*2$' "$s" &&
		grep -qx "0::/$JAIL_NAME" "/proc/$1/cgroup" &&
		grep -q "^CapEff:[[:space:]]*$(printf '%016x' "$JAIL_CAPS")$" "$s"
}

# Starts `"$0" run "$@"` in a session of its own, waits for the daemon and checks it.
# On failure JAIL_ERR says why and nothing of it is left running.
jail_launch() {
	rm -f "$JAIL_PIDFILE.new"
	setsid "$0" run "$@" </dev/null >/dev/null 2>&1 9>&- &
	leader=$!
	i=0
	pid=""
	while [ "$i" -lt 50 ]; do
		[ -s "$JAIL_PIDFILE.new" ] && read -r pid <"$JAIL_PIDFILE.new"
		[ -n "$pid" ] && jail_is_ours "$pid" && break
		pid=""
		sleep 0.2
		i=$((i + 1))
	done
	if [ -z "$pid" ]; then
		# A late start must not leave an unmanaged daemon behind.
		kill -TERM "-$leader" 2>/dev/null
		[ -s "$JAIL_PIDFILE.new" ] && read -r pid <"$JAIL_PIDFILE.new" && kill -KILL "$pid" 2>/dev/null
		rm -f "$JAIL_PIDFILE.new"
		JAIL_ERR="jailed daemon did not start; see syslog"
		return 1
	fi
	rm -f "$JAIL_PIDFILE.new"
	echo "$pid $(jail_starttime "$pid")" >"$JAIL_PIDFILE"
	if ! jail_check "$pid"; then
		k=$JAIL_STOP_KILL
		JAIL_STOP_KILL=1
		jail_stop
		JAIL_STOP_KILL=$k
		JAIL_ERR="jail self-check: uid/gid, groups, NoNewPrivs, seccomp, cgroup or CapEff not as configured"
		return 1
	fi
}

# Starts "$@" as root with no jail, recorded in the pidfile so jail_running and
# jail_stop manage it the same way. For daemons whose loss costs more than their jail.
jail_launch_unjailed() {
	rm -f "$JAIL_PIDFILE" "$JAIL_PIDFILE.new"
	mkdir -p "$JAIL_RUN_DIR" && chmod 0700 "$JAIL_RUN_DIR" || return 1
	exe=$1
	shift
	start-stop-daemon -S -q -b -m -p "$JAIL_PIDFILE.new" -x "$exe" -- "$@" 9>&- || return 1
	read -r pid <"$JAIL_PIDFILE.new" && rm -f "$JAIL_PIDFILE.new" || return 1
	echo "$pid $(jail_starttime "$pid")" >"$JAIL_PIDFILE"
	jail_running
}

# SIGTERM, then up to JAIL_STOP_WAIT seconds; SIGCONT throughout, so a frozen
# daemon can act on it. Fails if the daemon is still running at the end.
jail_stop() {
	if ! jail_running; then
		rm -f "$JAIL_PIDFILE"
		return 0
	fi
	kill -CONT "$JAIL_PID" 2>/dev/null
	kill -TERM "$JAIL_PID"
	i=0
	while jail_running && [ "$i" -lt $((JAIL_STOP_WAIT * 5)) ]; do
		sleep 0.2
		kill -CONT "$JAIL_PID" 2>/dev/null
		i=$((i + 1))
	done
	if jail_running && [ "${JAIL_STOP_KILL:-0}" = 1 ]; then
		kill -KILL "$JAIL_PID"
		i=0
		while jail_running && [ "$i" -lt 25 ]; do
			sleep 0.2
			i=$((i + 1))
		done
	fi
	jail_running && return 1
	rm -f "$JAIL_PIDFILE"
}

# Closes every fd above 2 that would survive exec, so none of the caller's reaches the daemon.
jail_close_fds() {
	for f in /proc/$$/fdinfo/*; do
		n=${f##*/}
		[ "$n" -gt 2 ] 2>/dev/null || continue
		fl=$(sed -n 's/^flags:[[:space:]]*//p' "$f" 2>/dev/null)
		[ -n "$fl" ] && [ $((0$fl & 02000000)) -eq 0 ] && eval "exec $n>&-"
	done
}

# The `run` verb: from jail_launch, in its own session. "$@" is minijail options -- command.
jail_run() {
	echo $$ >"$JAIL_CGROUP/cgroup.procs" || exit 1
	jail_close_fds
	[ -n "$JAIL_OOM_SCORE_ADJ" ] && echo "$JAIL_OOM_SCORE_ADJ" >/proc/self/oom_score_adj
	if [ -n "$JAIL_LOG_TAG" ]; then
		jail_exec -i -f "$JAIL_PIDFILE.new" "$@" 2>&1 | logger -t "$JAIL_LOG_TAG"
	else
		jail_exec -i -f "$JAIL_PIDFILE.new" "$@"
	fi
}
