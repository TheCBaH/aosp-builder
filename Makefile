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
AOSP_VOLUME_DIR?=/data/docker
AOSP_IMAGE?=aosp
AOSP_PREFIX?=$(subst /,_,${AOSP_IMAGE})

linux:
	docker build -f Dockerfile-linux -t ${AOSP_IMAGE}:linux .

user: linux
	cp ~/.gitconfig .
	docker build --build-arg userid=${UID} --build-arg image=${AOSP_IMAGE} --build-arg groupid=${GID} --build-arg username=${USER} -f Dockerfile-$@ -t ${AOSP_IMAGE}:$@ .
	rm .gitconfig

mirror.master: user
	-docker volume create ${AOSP_PREFIX}_$(subst .,-,$@)
	docker run -i${TERMINAL} --rm --name ${AOSP_PREFIX}_$@ -v ${AOSP_PREFIX}_$(subst .,-,$@):${MIRROR} ${AOSP_IMAGE}:$< bash -euxc \
		"chown ${USER} ${MIRROR};exec chroot --userspec ${USER}:${GID} / /bin/bash -euxc \
		'export HOME=/home/${USER};id;cd ${MIRROR};repo init -u ${ORIGIN} -b $(subst .,,$(suffix $@)) \
		;time repo sync -c --network-only --no-clone-bundle --no-tags -j${SYNC_JOBS}'"
	touch done-$@

ccache: user
	-docker volume create ${AOSP_PREFIX}_$@
	docker run -i${TERMINAL} --rm --name ${AOSP_PREFIX}_$@ -v ${AOSP_PREFIX}_ccache:/ccache ${AOSP_IMAGE}:$< bash -exc \
		'chown ${USER}:${GID} /ccache ;env CCACHE_DIR=/ccache ccache -M104G'
	touch done-$@

ccache.stats: user
	docker run -i${TERMINAL} --rm --name $(subst .,-,$@) -v ${AOSP_PREFIX}_ccache:/ccache:ro ${AOSP_IMAGE}:$< bash -exc \
		'env CCACHE_DIR=/ccache ccache -s'

run: user
	docker run -i${TERMINAL} --rm ${AOSP_IMAGE}:$<


image.master: user
	-docker container kill ${AOSP_PREFIX}_$(subst .,-,$@)
	-docker container rm ${AOSP_PREFIX}_$(subst .,-,$@)
	docker run -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst .,-,$@) -v ${AOSP_PREFIX}_mirror-master:${MIRROR}:ro \
	${AOSP_IMAGE}:$< build -c 'set -eux;mkdir -p ${SOURCE};cd ${SOURCE};\
	repo init -u ${ORIGIN} --reference=${MIRROR} ;\
	time repo sync --network-only --current-branch --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	time repo sync --local-only --current-branch --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	echo DONE'
	time docker commit --change='CMD "build"' ${AOSP_PREFIX}_$(subst .,-,$@) ${AOSP_IMAGE}:$(subst .,,$(suffix $@))
	docker container rm ${AOSP_PREFIX}_$(subst .,-,$@)
	touch done-$@

master.update:
	-docker container kill ${AOSP_PREFIX}_$(subst .,-,$@)
	-docker container rm ${AOSP_PREFIX}_$(subst .,-,$@)
	docker run -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst .,-,$@) -v/home:/home_root ${AOSP_IMAGE}:$(basename $@) bash -i
	docker commit --change='CMD "build"' ${AOSP_PREFIX}_$(subst .,-,$@) ${AOSP_IMAGE}:$(basename $@)
	docker container rm ${AOSP_PREFIX}_$(subst .,-,$@)

run.%:
	docker run --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@)) \
	-v ${OUT_VOLUME}${SOURCE}/out -v ${AOSP_PREFIX}_ccache:/ccache -v ${AOSP_PREFIX}_mirror-master:${MIRROR}:ro \
	${AOSP_IMAGE}:$(subst +,-,$(subst .,,$(suffix $@))) build ${RUN_ARGS}

build.%:
	echo $(basename $@)
	docker run --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@)) \
	-v ${OUT_VOLUME}${SOURCE}/out -v ${AOSP_PREFIX}_ccache:/ccache \
	${AOSP_IMAGE}:$(subst +,-,$(subst .,,$(suffix $(basename $@)))) build ${BUILD_ARGS} -c 'cd ${SOURCE}; source build/envsetup.sh;lunch $(subst .,,$(suffix $@)) && time make -j${BUILD_JOBS}'

image.%:
	-docker container kill ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@))
	-docker container rm ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@))
	docker run -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@)) -v ${AOSP_PREFIX}_mirror-master:${MIRROR}:ro \
	${AOSP_IMAGE}:$(subst +,-,$(subst .,,$(suffix $<))) build -c 'set -eux;cd ${SOURCE};\
	repo init -u ${ORIGIN} --reference=${MIRROR} -b $(subst +,.,$(subst .,,$(suffix $@)));\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	find . -type l -name Android\* -not -readable -delete;repo sync -c --local-only -j${SYNC_JOBS};\
	echo DONE'
	time docker commit --change='CMD "build"' ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@)) ${AOSP_IMAGE}:$(subst +,-,$(subst .,,$(suffix $@)))
	docker container rm ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@))
	touch done-$

java.8.oreo-dev:
	docker build --build-arg branch=$(subst .,,$(suffix $@)) --build-arg image=${AOSP_IMAGE} --build-arg jdk=$(subst .,,$(suffix $(basename $@))) -f Dockerfile-jdk -t ${AOSP_IMAGE}:$(subst .,,$(suffix $@)) .

update.%:
	-docker container kill ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@))
	-docker container rm ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@))
	docker run -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@)) -v/home:/home_root ${AOSP_IMAGE}:$(subst +,-,$(subst .,,$(suffix $@))) bash -i
	docker commit --change='CMD "build"' ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@)) ${AOSP_IMAGE}:$(subst +,-,$(subst .,,$(suffix $@)))
	docker container rm ${AOSP_PREFIX}_$(subst +,-,$(subst .,-,$@))

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

test: user ccache mirror.master image.master build_master

volumes:
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=${AOSP_VOLUME_DIR}/${AOSP_PREFIX}_mirror-master ${AOSP_PREFIX}_mirror-master
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=${AOSP_VOLUME_DIR}/${AOSP_PREFIX}_ccache ${AOSP_PREFIX}_ccache
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=${AOSP_VOLUME_DIR}/${AOSP_PREFIX}_out  ${AOSP_PREFIX}_out
