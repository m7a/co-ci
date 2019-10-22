#!/bin/sh -e
# Ma_Sys.ma CI 1.0, Copyright (c) 2019 Ma_Sys.ma.
# For further info send an e-mail to Ma_Sys.ma@web.de.
#
# Simple script to allow re-generation of keys which are supplied as part
# of the repository. Normally, there should not be issues wrt. re-using
# the existing keys because they allow logins only to local Docker containers
# not exposing the ssh server to external connections. Still, it would seem to
# be good practice to use different keys everywhere and thus this script is
# provided.
ssh-keygen -N "" -t ed25519 -f dot_ssh_server/id_ed25519_i386
mv -f dot_ssh_server/id_ed25519_i386.pub dot_ssh_i386/authorized_keys
chmod 600 dot_ssh_server/id_ed25519_i386 dot_ssh_i386/authorized_keys
