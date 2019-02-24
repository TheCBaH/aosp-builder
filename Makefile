all: test
ID_OFFSET=10
UID:=$(shell expr $$(id -u) - ${ID_OFFSET})
GID:=$(shell expr $$(id -g) - ${ID_OFFSET})
USER:=$(shell id -un)
SYNC_JOBS?=4
BUILD_JOBS?=$(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
MIRROR=/home/${USER}/aosp/mirror/
SOURCE=/home/${USER}/source
INIT_MANIFEST=${MIRROR}/platform/manifest.git
ORIGIN=https://android.googlesource.com/platform/manifest

linux:
	docker build -f Dockerfile-linux -t aosp:linux .

user: linux
	cp ~/.gitconfig .
	docker build --build-arg userid=${UID} --build-arg groupid=${GID} --build-arg username=${USER} -f Dockerfile-$@ -t aosp:$@ .
	rm .gitconfig

mirror.master: user
	-docker volume create aosp_$(subst .,-,$@) 
	docker run -it --rm --name aosp_$@ -v aosp_$(subst .,-,$@):${MIRROR} aosp:$< bash -euxc \
		"chown ${USER} ${MIRROR};exec chroot --userspec ${USER}:${GID} / /bin/bash -euxc \
		'export HOME=/home/${USER};id;cd ${MIRROR};[ -d .repo ] || repo init -u ${ORIGIN} --mirror \
		;time repo sync -j${SYNC_JOBS}'"

ccache: user
	-docker volume create aosp_$@
	docker run -it --rm --name aosp_$@ -v aosp_ccache:/ccache aosp:$< bash -exc \
		'chown ${USER}:${GID} /ccache ;env CCACHE_DIR=/ccache ccache -M512G'

ccache.stats: user
	docker run -it --rm --name $(subst .,-,$@) -v aosp_ccache:/ccache:ro aosp:$< bash -exc \
		'env CCACHE_DIR=/ccache ccache -s'

run: user
	docker run -it --rm aosp:$<

test: user
	docker run -it --rm \
	-v /home/${USER}/aosp:/home/${USER}/aosp:ro \
	aosp:$< build -c 'set -aux;cd ~;mkdir source;cd source;\
	git config --global color.ui false;\
	repo init -u ${MIRROR};\
	echo'

master: user
	-docker container kill aosp_$@;
	-docker container rm aosp_$@;
	docker run -it --name aosp_$@ -v  aosp_mirror-master:${MIRROR}:ro \
	aosp:$< build -c 'set -aux;cd ~;mkdir -p ${SOURCE};cd ${SOURCE};\
	git config --global color.ui false;\
	repo init -u ${INIT_MANIFEST} --reference=${MIRROR} -b $@;\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	echo DONE'
	docker commit --change='CMD "build"' apsp_$@  aosp:$@
	docker container rm aosp_$@;

master.update:
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -it --name aosp_$(subst .,-,$@) -v/home:/home_root aosp:$(basename $@) bash -i
	docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(basename $@)
	docker container rm aosp_$(subst .,-,$@)

run.master:
	docker run --rm -it --name aosp_$(subst .,-,$@) --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
	aosp:$(subst .,,$(suffix $@)) bash -i

build.master:
	docker run --rm -it --name aosp_$(subst .,-,$@) \
   	-v ${SOURCE}/out -v aosp_ccache:/ccache \
	aosp:$(subst .,,$(suffix $@)) build -c 'cd ${SOURCE}; source build/envsetup.sh;lunch aosp_arm64-eng && time make -j${BUILD_JOBS}'
