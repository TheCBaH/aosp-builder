all: test
ID_OFFSET=10
UID:=$(shell expr $$(id -u) - ${ID_OFFSET})
GID:=$(shell expr $$(id -g) - ${ID_OFFSET})
USER:=$(shell id -un)
TERMINAL:=$(shell test -t 0 && echo t)
SYNC_JOBS?=4
BUILD_JOBS?=$(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
MIRROR=/home/${USER}/aosp/mirror
SOURCE=/home/${USER}/source
MIRROR_MANIFEST=${MIRROR}/platform/manifest
ORIGIN=https://android.googlesource.com/platform/manifest

linux:
	docker build -f Dockerfile-linux -t aosp:linux .

user: linux
	cp ~/.gitconfig .
	docker build --build-arg userid=${UID} --build-arg groupid=${GID} --build-arg username=${USER} -f Dockerfile-$@ -t aosp:$@ .
	rm .gitconfig

mirror.master: user
	-docker volume create aosp_$(subst .,-,$@)
	docker run -i${TERMINAL} --rm --name aosp_$@ -v aosp_$(subst .,-,$@):${MIRROR} aosp:$< bash -euxc \
		"chown ${USER} ${MIRROR};exec chroot --userspec ${USER}:${GID} / /bin/bash -euxc \
		'export HOME=/home/${USER};id;cd ${MIRROR};repo init -u ${ORIGIN} -b $(subst .,,$(suffix $@)) \
		;time repo sync -c --network-only --no-clone-bundle --no-tags -j${SYNC_JOBS}'"
	touch done-$@

ccache: user
	-docker volume create aosp_$@
	docker run -i${TERMINAL} --rm --name aosp_$@ -v aosp_ccache:/ccache aosp:$< bash -exc \
		'chown ${USER}:${GID} /ccache ;env CCACHE_DIR=/ccache ccache -M104G'
	touch done-$@

ccache.stats: user
	docker run -i${TERMINAL} --rm --name $(subst .,-,$@) -v aosp_ccache:/ccache:ro aosp:$< bash -exc \
		'env CCACHE_DIR=/ccache ccache -s'

run: user
	docker run -i${TERMINAL} --rm aosp:$<

test: user
	docker run -i${TERMINAL} --rm \
	-v /home/${USER}/aosp:/home/${USER}/aosp:ro \
	aosp:$< build -c 'set -eux;cd ~;mkdir source;cd source;\
	git config --global color.ui false;\
	repo init -u ${MIRROR};\
	echo'

image.master: user
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -i${TERMINAL} --name aosp_$(subst .,-,$@) -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$< build -c 'set -eux;mkdir -p ${SOURCE};cd ${SOURCE};\
	repo init -u ${ORIGIN} --reference=${MIRROR} ;\
	time repo sync --network-only --current-branch --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	time repo sync --local-only --current-branch --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	echo DONE'
	time docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(subst .,,$(suffix $@))
	docker container rm aosp_$(subst .,-,$@)
	touch done-$@

master.update:
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -i${TERMINAL} --name aosp_$(subst .,-,$@) -v/home:/home_root aosp:$(basename $@) bash -i
	docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(basename $@)
	docker container rm aosp_$(subst .,-,$@)

run.%:
	docker run --rm -i${TERMINAL} --name aosp_$(subst +,-,$(subst .,-,$@)) \
	-v ${OUT_VOLUME}${SOURCE}/out -v aosp_ccache:/ccache -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$(subst +,-,$(subst .,,$(suffix $@))) build ${RUN_ARGS}

build.%:
	echo $(basename $@)
	docker run --rm -i${TERMINAL} --name aosp_$(subst +,-,$(subst .,-,$@)) \
	-v ${OUT_VOLUME}${SOURCE}/out -v aosp_ccache:/ccache \
	aosp:$(subst +,-,$(subst .,,$(suffix $(basename $@)))) build ${BUILD_ARGS} -c 'cd ${SOURCE}; source build/envsetup.sh;lunch $(subst .,,$(suffix $@)) && time make -j${BUILD_JOBS}'

image.%:
	-docker container kill aosp_$(subst +,-,$(subst .,-,$@))
	-docker container rm aosp_$(subst +,-,$(subst .,-,$@))
	docker run -i${TERMINAL} --name aosp_$(subst +,-,$(subst .,-,$@)) -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$(subst +,-,$(subst .,,$(suffix $<))) build -c 'set -eux;cd ${SOURCE};\
	repo init -u ${ORIGIN} --reference=${MIRROR} -b $(subst +,.,$(subst .,,$(suffix $@)));\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	find . -type l -name Android\* -not -readable -delete;repo sync -c --local-only -j${SYNC_JOBS};\
	echo DONE'
	time docker commit --change='CMD "build"' aosp_$(subst +,-,$(subst .,-,$@)) aosp:$(subst +,-,$(subst .,,$(suffix $@)))
	docker container rm aosp_$(subst +,-,$(subst .,-,$@))
	touch done-$

java.8.oreo-dev:
	docker build --build-arg branch=$(subst .,,$(suffix $@)) --build-arg jdk=$(subst .,,$(suffix $(basename $@))) -f Dockerfile-jdk -t aosp:$(subst .,,$(suffix $@)) .

update.%:
	-docker container kill aosp_$(subst +,-,$(subst .,-,$@))
	-docker container rm aosp_$(subst +,-,$(subst .,-,$@))
	docker run -i${TERMINAL} --name aosp_$(subst +,-,$(subst .,-,$@)) -v/home:/home_root aosp:$(subst +,-,$(subst .,,$(suffix $@))) bash -i
	docker commit --change='CMD "build"' aosp_$(subst +,-,$(subst .,-,$@)) aosp:$(subst +,-,$(subst .,,$(suffix $@)))
	docker container rm aosp_$(subst +,-,$(subst .,-,$@))

image.pie-release: done-image.master
image.oreo-dev: done-image.pie-release
image.oreo-cts-dev: done-image.oreo-dev
image.android-8+1+0_r53: done-image.oreo-dev
image.android-9+0+0_r33: done-image.pie-release

build_master: build.master.aosp_arm64  build.master.aosp_arm

build_pie-release: build.pie-release.aosp_x86 build.pie-release.aosp_arm64  build.pie-release.aosp_arm

build_oreo-dev: build.oreo-dev.aosp_x86 build.oreo-dev.aosp_arm64 build.oreo-dev.aosp_arm

build_android-8+1+0_r53: build.android-8+1+0_r53.aosp_arm

build_android-9+0+0_r33: build.android-9+0+0_r33.aosp_x86


clean:
	rm done-*

volumes:
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=/data/docker/aosp_mirror-master aosp_mirror-master
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=/data/docker/aosp_ccache aosp_ccache
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=/data/docker/aosp_out  aosp_out
