#!/bin/sh
# Builds a Quartus Prime Pro container image from Altera's installer files, laid out like
# Altera's own alterafpga/quartus-pro images. Usage and checksums: docs/de25-base-image.md §4.
#   quartus-image.sh <dir with the .run and .qdz files> [tag]
set -eu
src=$(cd -- "${1:?usage: $0 <installer dir> [tag]}" && pwd)
ver=26.3.0.114
tag=${2:-de25/quartus-pro:${ver}-agilex5}
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

(cd "$src" && sha1sum -c "$here/quartus-$ver.sha1")
run="QuartusProSetup-$ver-linux.run"
[ -x "$src/$run" ] || chmod +x "$src/$run" 2>/dev/null ||
	{ echo "${0##*/}: $src/$run is not executable" >&2; exit 2; }

# Everything but Quartus, its device database, Agilex 5 and the files Agilex 5 needs.
off=quartusiq,quartus_help,eda_simlib,eda_cdclib,agilex27,agilex3,agilex7,arria10,cyclone10gx
off=$off,easicn5x,stratix10,quartus_update,riscfree,questa_km_fse,questa_km_fe,questa_fse,questa_fe
off=$off,export_controlled,dsp_builder

name=quartus-image-$$
docker run -d --name "$name" -v "$src:/inst:ro" ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517 sh -c "
	set -e
	export DEBIAN_FRONTEND=noninteractive
	apt-get update && apt-get -y install --no-install-recommends libglib2.0-0t64 libxext6 \
		libfontconfig1 locales ca-certificates
	apt-get clean && rm -rf /var/lib/apt/lists/*
	localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
	/inst/$run --mode unattended --unattendedmodeui none --accept_eula 1 \
		--installdir /opt/altera --disable-components $off
	rm -rf /opt/altera/uninstall /opt/altera/logs /tmp/*
	test -x /opt/altera/quartus/bin/quartus_sh" >/dev/null
echo "${0##*/}: installing in container $name (docker logs -f $name)"
rc=$(docker wait "$name")
if [ "$rc" != 0 ]; then
	docker logs --tail 40 "$name" >&2; docker rm "$name" >/dev/null
	echo "${0##*/}: install failed ($rc)" >&2; exit 1
fi
docker commit \
	--change 'ENV PATH=/opt/altera/quartus/bin:/opt/altera/niosv/bin:/opt/altera/qsys/bin:/opt/altera/syscon/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
	--change 'ENV LANG=en_US.utf8' --change 'ENV QUARTUS_ROOTDIR=/opt/altera/quartus' \
	--change 'CMD ["/bin/bash"]' "$name" "$tag" >/dev/null
docker rm "$name" >/dev/null
echo "${0##*/}: built $tag"
