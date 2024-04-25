#!/bin/sh -eu
# Ma_Sys.ma CI v2 main script (c) 2023 Ma_Sys.ma <info@masysma.net>

: "${MDVL_CI_PHOENIX_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
export MDVL_CI_PHOENIX_ROOT

logf="$MDVL_CI_PHOENIX_ROOT/x-co-ci-logs/civ2_$(date +%s)_$(dpkg \
				--print-architecture)_$(cat /etc/hostname).txt"
cd "$(dirname "$0")"
while sleep 30; do
	{ ant runci || echo ANTRC=$?; } 2>&1 | ts "[%s] " | tee -a "$logf"
done
