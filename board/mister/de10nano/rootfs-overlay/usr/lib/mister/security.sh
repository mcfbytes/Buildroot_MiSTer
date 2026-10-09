# shellcheck shell=sh
# /usr/lib/mister/security.sh -- read the card's security state (ADR 0031).
# Sourced by init scripts and mister-security; security.conf itself is parsed, never sourced.

MISTER_SECURITY_CONF="${MISTER_SECURITY_CONF:-/media/fat/linux/security.conf}"

# Every key with its allowed values; the FIRST value is the stock default.
MISTER_SECURITY_KEYS="ssh_password:yes,no ssh_forwarding:stock,limited ftp:stock,off"

# security_values KEY -- the allowed values, space-separated, default first.
security_values() {
	for _sv in $MISTER_SECURITY_KEYS; do
		[ "${_sv%%:*}" = "$1" ] || continue
		echo "${_sv#*:}" | tr ',' ' '
		return 0
	done
	return 1
}

# security_get KEY -- the card's value for KEY; the stock default when the
# file or the key is absent, or the value is not allowed (with a warning).
security_get() {
	_sg_allowed="$(security_values "$1")" || return 2
	_sg_def="${_sg_allowed%% *}"
	_sg_v=""
	if [ -r "$MISTER_SECURITY_CONF" ]; then
		_sg_v="$(tr -d '\r' <"$MISTER_SECURITY_CONF" | sed -n \
			"s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^#[:space:]]*\)[[:space:]]*\(#.*\)\{0,1\}\$/\1/p" |
			tail -n 1 | tr '[:upper:]' '[:lower:]')"
	fi
	[ -n "$_sg_v" ] || { echo "$_sg_def"; return 0; }
	for _sg_a in $_sg_allowed; do
		[ "$_sg_v" = "$_sg_a" ] && { echo "$_sg_v"; return 0; }
	done
	echo "WARNING: $MISTER_SECURITY_CONF: '$1=$_sg_v' is not one of: $_sg_allowed; using $_sg_def" >&2
	echo "$_sg_def"
}
