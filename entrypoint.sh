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
        source=/home/$USER/source
        cp /root/.gitconfig /home/$username/
        chown $username /home/$username/.gitconfig
        [ -d $source/out ] && chown $username $source/out
        if [ -d /ccache ]; then 
            CCACHE_DIR=/ccache
            USE_CCACHE=1
            CCACHE_EXEC=$(which ccache)
            export CCACHE_DIR
            export USE_CCACHE
            export CCACHE_EXEC
        fi
        exec chroot --userspec=$username:$(cat /root/username) / /bin/bash -i "$@"
    fi
fi
exec "$@"
