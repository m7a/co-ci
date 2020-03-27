#!/bin/sh -e

subroot="$(cd "$(dirname "$0")" && pwd)"

mkdir "$subroot/keytmp"
cat > "$subroot/keytmp/genkeybatch.txt" <<EOF
%no-protection
Key-Type: default
Subkey-Type: default
Name-Real: Linux-Fan/Test
Expire-Date: 0
EOF

chown 1000:1000 -R keytmp
docker run --rm -v "$subroot/keytmp:/media/keytmp" -i -u 1000 masysmaci \
							/bin/bash -ex <<EOF
cd /media/keytmp
gpg --batch --gen-key genkeybatch.txt
gpg --armor --export Linux-Fan/Test > /home/masysmaci/.gnupg/pubkey
cp -R /home/masysmaci/.gnupg dot_gnupg
EOF

if [ -d "$subroot/dot_gnupg_sample" ]; then
	rm -r "$subroot/dot_gnupg_sample"
fi

mkdir "$subroot/dot_gnupg_sample"
dot_gnupg="$subroot/keytmp/dot_gnupg"
cp -R "$dot_gnupg"/*.d "$dot_gnupg/pubring.kbx" "$dot_gnupg/trustdb.gpg" \
				"$dot_gnupg/pubkey" "$subroot/dot_gnupg_sample"
rm -R "$subroot/keytmp"

chown 1000:1000 -R "$subroot/dot_gnupg_sample"
