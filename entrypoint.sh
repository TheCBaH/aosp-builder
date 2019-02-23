#!/bin/sh
set -exu
echo "$@"
if [ $# -ge 1 ]; then
    if [ $1 = build ]; then
        shift;
        ccache=y
        clean=y

        while true; do
            if [ $# -eq 0 ]; then
                break;
            fi
            case $1 in
            --ccache)
                ccache=$2;
                shift
                ;;
            --clean)
                clean=$2;
                shift
                ;;
            *)
                break
                ;;
           esac
           shift
        done

        username=$(cat /root/username)
        HOME=/home/$username
        export HOME
        USER=$username
        export USER
        source=/home/$USER/source
        if [ _$clean = _1 -o _$clean = _y ]; then
            if [ -d $source/out ]; then
                chown $username $source/out
                rm -rf $source/out/*
            fi
        fi
        if [ _$ccache = _1 -o _$ccache = _y ]; then
            if [ -d /ccache ]; then
                CCACHE_DIR=/ccache
                USE_CCACHE=1
                CCACHE_EXEC=$(which ccache)
                export CCACHE_DIR
                export USE_CCACHE
                export CCACHE_EXEC
            fi
        fi
        exec chroot --userspec=$username:$(cat /root/username) / /bin/bash "$@"
    fi
fi
exec "$@"
