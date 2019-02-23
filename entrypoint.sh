#!/bin/sh
set -exu
echo "$@"
if [ $# -ge 1 ]; then
    if [ $1 = build ]; then
        shift;
        username=$(cat /root/username)
        HOME=/home/$username
        export HOME
        USER=$username
        export USER
        mv /root/.gitconfig /home/$username/
        chown $username /home/$username/.gitconfig
        exec chroot --userspec=$username:$(cat /root/username) / /bin/bash -i "$@"
    fi
fi
exec "$@"
