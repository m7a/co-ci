# Ma_Sys.ma CI 2.0.0, Copyright (c) 2019, 2020, 2023 Ma_Sys.ma.
# For further info send an e-mail to Ma_Sys.ma@web.de.
#
# This file defines a container for building MDVL packages. It is prepared to
# run Ma_Sys.ma CI tasks. It provides a user "masysmaci" with ID 1000 and
# has common Ma_Sys.ma build dependencies installed.

# docker build -t masysmaci:v2 .
# docker build -t i386/masysmaci:v2  --build-arg=MDVL_CI_ARCH_PREFIX=i386/  .
# docker build -t armhf/masysmaci:v2 --build-arg=MDVL_CI_ARCH_PREFIX=armhf/ .

ARG     MDVL_CI_ARCH_PREFIX=
ARG     MDVL_CI_DEBIAN_VERSION=bookworm
FROM    debian:$MDVL_CI_DEBIAN_VERSION AS qemustatic
ARG     MDVL_CI_DEBIAN_VERSION=bookworm
ARG     MA_DEBIAN_MIRROR=http://ftp.it.debian.org/debian
SHELL   ["/bin/sh", "-ec"]
RUN     :; \
	printf "%s\n%s\n%s %s\n" \
		"deb $MA_DEBIAN_MIRROR $MDVL_CI_DEBIAN_VERSION main" \
		"deb $MA_DEBIAN_MIRROR $MDVL_CI_DEBIAN_VERSION-updates main" \
		"deb http://security.debian.org/" \
				"$MDVL_CI_DEBIAN_VERSION-security main" \
		> /etc/apt/sources.list; \
	apt-get update; \
	apt-get -y full-upgrade; \
	apt-get -y install qemu-user-static; \
	:

ARG     MDVL_CI_ARCH_PREFIX=
ARG     MDVL_CI_DEBIAN_VERSION=bookworm
FROM    ${MDVL_CI_ARCH_PREFIX}debian:$MDVL_CI_DEBIAN_VERSION
ARG     MDVL_CI_DEBIAN_VERSION=bookworm
LABEL   maintainer "Linux-Fan, Ma_Sys.ma <Ma_Sys.ma@web.de>"
LABEL   name masysmaci
ARG     MA_DEBIAN_MIRROR=http://ftp.it.debian.org/debian
SHELL   ["/bin/sh", "-ec"]
COPY    --from=qemustatic /usr/bin/qemu-arm-static /usr/bin/qemu-arm-static
COPY    metapackages/*.deb /opt/metapackages/
# Here, we are using apt instead of apt-get specifically for the modern
# possibility of installing .deb files without having to fix their dependencies
# afterwards.
RUN     :; \
	set -x; \
	printf "%s\n%s\n%s %s\n" \
		"deb $MA_DEBIAN_MIRROR $MDVL_CI_DEBIAN_VERSION main" \
		"deb $MA_DEBIAN_MIRROR $MDVL_CI_DEBIAN_VERSION-updates main" \
		"deb http://security.debian.org/" \
				"$MDVL_CI_DEBIAN_VERSION-security main" \
		> /etc/apt/sources.list; \
	useradd -u 1000 -m masysmaci; \
	apt-get update; \
	apt-get -y full-upgrade; \
	apt-get -y install sudo; \
	apt -y install /opt/metapackages/*.deb; \
	printf "%s\n" "deb file:///data/programs/repo squeeze main" \
						>> /etc/apt/sources.list; \
	:
COPY    51-masysma-apt /etc/sudoers.d/
RUN     chmod 600 /etc/sudoers.d/51-masysma-apt
USER    masysmaci
CMD     ["/bin/bash"]
