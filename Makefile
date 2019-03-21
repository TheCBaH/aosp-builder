all: test
ID_OFFSET:=$(shell id -u docker 2</dev/null || echo 0)
UID:=$(shell id -u)
GID:=$(shell id -g)
KVM_GID:=$(shell (getent group kvm || echo x:x:0) | awk -F: '{print $$3}')
USER:=$(shell id -un)
TERMINAL:=$(shell test -t 0 && echo t)
CPU_CORES?=$(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
SYNC_JOBS?=$(shell [ ${CPU_CORES} -ge 4 ] && echo 4 || echo ${CPU_CORES})
BUILD_JOBS?=${CPU_CORES}
MIRROR=/home/${USER}/aosp/mirror
SOURCE=/home/${USER}/source
MIRROR_MANIFEST=${MIRROR}/platform/manifest
ORIGIN=https://android.googlesource.com/platform/manifest
AOSP_VOLUME_DIR?=/data/aosp
AOSP_IMAGE?=aosp
AOSP_PREFIX?=$(subst /,_,${AOSP_IMAGE})
RUN_ARGS?=${BUILD_ARGS}
CCACHE_CONFIG=--max-size=104G --set-config=compression=true
OUT_VOLUME?=${AOSP_PREFIX}_out:

linux:
	docker build --build-arg HTTP_PROXY=${http_proxy} -f Dockerfile-linux -t ${AOSP_IMAGE}:linux .

user: linux
	cp ~/.gitconfig .
	docker build --build-arg id_offset=${ID_OFFSET} --build-arg kvm_gid=${KVM_GID}  --build-arg userid=${UID} --build-arg image=${AOSP_IMAGE} --build-arg groupid=${GID} --build-arg username=${USER} -f Dockerfile-$@ -t ${AOSP_IMAGE}:$@ .
	rm .gitconfig

ccache: user
	-docker volume create ${AOSP_PREFIX}_$@
	docker run ${DOCKER_RUN_ARGS} -i${TERMINAL} --rm --name ${AOSP_PREFIX}_$@ -v ${AOSP_PREFIX}_ccache:/ccache ${AOSP_IMAGE}:$< bash -exc \
		'chown ${USER}:${GID} /ccache ;/root/entrypoint.sh run env CCACHE_DIR=/ccache ccache --cleanup  ${CCACHE_CONFIG}'
	touch done-$@

ccache.stats: user
	docker run ${DOCKER_RUN_ARGS} -i${TERMINAL} --rm --name $(subst .,-,$@) -v ${AOSP_PREFIX}_ccache:/ccache:ro ${AOSP_IMAGE}:$< bash -exc \
		'/root/entrypoint.sh run env CCACHE_DIR=/ccache ccache --show-stats'

ccache.clear: user
	docker run ${DOCKER_RUN_ARGS} -i${TERMINAL} --rm --name $(subst .,-,$@) -v ${AOSP_PREFIX}_ccache:/ccache ${AOSP_IMAGE}:$< bash -exc \
		'/root/entrypoint.sh run env CCACHE_DIR=/ccache ccache --clear'

ccache.config: user
	docker run ${DOCKER_RUN_ARGS} -i${TERMINAL} --rm --name $(subst .,-,$@) -v ${AOSP_PREFIX}_ccache:/ccache ${AOSP_IMAGE}:$< bash -exc \
		'env CCACHE_DIR=/ccache ccache ${CCACHE_CONFIG} --print-config'

run: user
	docker run ${DOCKER_RUN_ARGS} -i${TERMINAL} --rm ${AOSP_IMAGE}:$<




java.8.oreo-dev:
	docker build --build-arg branch=$(subst .,,$(suffix $@)) --build-arg image=${AOSP_IMAGE} --build-arg jdk=$(subst .,,$(suffix $(basename $@))) -f Dockerfile-jdk -t ${AOSP_IMAGE}:$(subst .,,$(suffix $@)) .



clean:
	rm done-*

test: user ccache


master.source.root: user
	docker run ${DOCKER_RUN_ARGS} --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst .,-,$@) -v ${AOSP_PREFIX}_master.mirror:${MIRROR}:ro \
	-v ${AOSP_PREFIX}_$@:${SOURCE} ${AOSP_IMAGE}:user  build -c 'set -eux;cd ${SOURCE};\
	repo init -u ${ORIGIN} --reference=${MIRROR} ;mkdir -p out;\
	time repo sync --network-only --current-branch --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	time repo sync --local-only --current-branch --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	echo DONE'

%.source:
	docker run ${DOCKER_RUN_ARGS} --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst .,-,$@) -v ${AOSP_PREFIX}_master.mirror:${MIRROR}:ro \
	-v ${AOSP_PREFIX}_$@:${SOURCE} ${AOSP_IMAGE}:user  build -c 'set -eux;cd ${SOURCE};\
	repo init -u ${ORIGIN} -b $(basename $@);\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	find . -type l -name Android\* -not -readable -delete;repo sync -c --local-only -j${SYNC_JOBS};\
	echo DONE'
	touch done-$@

%.source.root:
	docker run ${DOCKER_RUN_ARGS} --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst .,-,$@) -v ${AOSP_PREFIX}_master.mirror:${MIRROR}:ro \
	-v ${AOSP_PREFIX}_$@:${SOURCE} ${AOSP_IMAGE}:user  build -c 'set -eux;cd ${SOURCE};\
	repo init -u ${ORIGIN} -b $(basename $(basename $@));\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	find . -type l -name Android\* -not -readable -delete;repo sync -c --local-only -j${SYNC_JOBS};\
	echo DONE'
	touch done-$@

%.sync:
	docker run ${DOCKER_RUN_ARGS} --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst .,-,$@) -v ${AOSP_PREFIX}_mirror-master:${MIRROR}:ro \
	-v ${AOSP_PREFIX}_$(basename $@).source:${SOURCE} ${AOSP_IMAGE}:user  build -c 'set -eux;cd ${SOURCE};\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	echo DONE'

%.build:
	docker run ${DOCKER_RUN_ARGS} --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst +,.,$(subst .,-,$@)) \
	-v ${OUT_VOLUME}${SOURCE}/out -v ${AOSP_PREFIX}_ccache:/ccache -v ${AOSP_PREFIX}_$(basename $(basename $@)).source:${SOURCE}:ro \
	${AOSP_IMAGE}:user build ${BUILD_ARGS} -c 'cd ${SOURCE}; source build/envsetup.sh;lunch $(subst .,,$(suffix $(basename $@))) && time nice make -j${BUILD_JOBS} ${BUILD_TARGET}'

%.run:
	docker run ${DOCKER_RUN_ARGS} --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst +,.,$(subst .,-,$@)) \
	-v ${OUT_VOLUME}${SOURCE}/out -v ${AOSP_PREFIX}_ccache:/ccache -v ${AOSP_PREFIX}_mirror-master:${MIRROR}:ro \
	-v ${AOSP_PREFIX}_$(basename $(basename $@)).source:${SOURCE} \
	${AOSP_IMAGE}:user build ${RUN_ARGS}

%.emulator:
	docker run ${DOCKER_RUN_ARGS} --device /dev/kvm -v /tmp/.X11-unix:/tmp/.X11-unix --rm -i${TERMINAL} --name ${AOSP_PREFIX}_$(subst +,.,$(subst .,-,$@)) \
	-v ${OUT_VOLUME}${SOURCE}/out -v ${AOSP_PREFIX}_$(basename $(basename $@)).source:${SOURCE}:ro \
	${AOSP_IMAGE}:user build -c \
	'source build/envsetup.sh;lunch $(subst .,,$(suffix $(basename $@))) && env DISPLAY=${DISPLAY} emulator -verbose -no-snapshot -show-kernel -noaudio ${EMULATOR_ARGS}'


%.mirror:user
	-docker volume create ${AOSP_PREFIX}_$(subst .,-,$@)
	docker run ${DOCKER_RUN_ARGS} -i${TERMINAL} --rm --name ${AOSP_PREFIX}_$@ -v ${AOSP_PREFIX}_$@:${MIRROR} ${AOSP_IMAGE}:$< run bash -euxc \
		"cd ${MIRROR};repo init -u ${ORIGIN} -b $(basename  $@); \
		time repo sync -c --network-only --no-clone-bundle --no-tags -j${SYNC_JOBS}"
	touch done-$@

%.mirror-root:user
	-docker volume create ${AOSP_PREFIX}_$(subst .,-,$@)
	docker run ${DOCKER_RUN_ARGS} -i${TERMINAL} --rm --name ${AOSP_PREFIX}_$@ -v ${AOSP_PREFIX}_$(basename $@).mirror.root:${MIRROR} ${AOSP_IMAGE}:$< run bash -euxc \
	"cd ${MIRROR};repo init -u ${ORIGIN} -b $(basename  $@); \
	time repo sync -c --network-only --no-clone-bundle --no-tags -j${SYNC_JOBS}"
	touch done-$@

master:
pie-release:
pie-dev:
oreo-dev:
android-9.0.0_r32:

pie-dev.source-volume: master
pie-release.source-volume: pie-dev master
oreo-dev.source-volume: pie-dev master
android-9.0.0_r32.source-volume: pie-release pie-dev master
android-9.0.0_r33.source-volume: android-9.0.0_r32 pie-release pie-dev master

pie-dev.source-root-volume: master
pie-release.source-root-volume: pie-dev master
android-9.0.0_r32.source-root-volume: pie-release pie-dev master
android-9.0.0_r33.source-root-volume: android-9.0.0_r32 pie-release pie-dev master
oreo-dev.source-root-volume: pie-dev master

pie-dev.mirror-root-volume: master
oreo-dev.mirror-root-volume: master

pie-dev.mirror-volume: master
oreo-dev.mirror-volume: master

space=$() $()
coma=,

master.source-root-volume:
	-docker volume rm ${AOSP_PREFIX}_$(basename $@).source.root
	mkdir -p ${AOSP_VOLUME_DIR}/source.root/$(basename $@)
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=${AOSP_VOLUME_DIR}/source.root/$(basename $@) ${AOSP_PREFIX}_$(basename $@).source.root


%.source-root-volume:
	-docker volume rm ${AOSP_PREFIX}_$(basename $@).source.root
	mkdir -p ${AOSP_VOLUME_DIR}/source.root/$(basename $@) ${AOSP_VOLUME_DIR}/source.root/$(basename $@).work
	docker volume create --driver local --opt type=overlay \
	  --opt o='lowerdir=$(subst ${space},:,$(foreach p,$?,${AOSP_VOLUME_DIR}/source.root/${p})),upperdir=${AOSP_VOLUME_DIR}/source.root/$(basename $@),workdir=${AOSP_VOLUME_DIR}/source.root/$(basename $@).work' --opt device=overlay ${AOSP_PREFIX}_$(basename $@).source.root


%.source-volume:
	-docker volume rm ${AOSP_PREFIX}_$(basename $@).source
	mkdir -p ${AOSP_VOLUME_DIR}/source/$(basename $@) ${AOSP_VOLUME_DIR}/source/$(basename $@).work
	docker volume create --driver local --opt type=overlay \
	--opt o='lowerdir=${AOSP_VOLUME_DIR}/source.root/$(basename $@)$(subst ${space},,$(foreach p,$?,:${AOSP_VOLUME_DIR}/source.root/${p})),upperdir=${AOSP_VOLUME_DIR}/source/$(basename $@),workdir=${AOSP_VOLUME_DIR}/source/$(basename $@).work' --opt device=overlay ${AOSP_PREFIX}_$(basename $@).source

master.mirror-root-volume:
	-docker volume rm ${AOSP_PREFIX}_$(basename $@).mirror.root
	mkdir -p ${AOSP_VOLUME_DIR}/mirror.root/$(basename $@)
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=${AOSP_VOLUME_DIR}/mirror.root/$(basename $@) ${AOSP_PREFIX}_$(basename $@).mirror.root

%.mirror-root-volume:
	-docker volume rm ${AOSP_PREFIX}_$(basename $@).mirror.root
	mkdir -p ${AOSP_VOLUME_DIR}/mirror.root/$(basename $@) ${AOSP_VOLUME_DIR}/mirror.root/$(basename $@).work
	docker volume create --driver local --opt type=overlay \
	  --opt o='lowerdir=$(subst ${space},:,$(foreach p,$?,${AOSP_VOLUME_DIR}/mirror.root/${p})),upperdir=${AOSP_VOLUME_DIR}/mirror.root/$(basename $@),workdir=${AOSP_VOLUME_DIR}/mirror.root/$(basename $@).work' --opt device=overlay ${AOSP_PREFIX}_$(basename $@).mirror.root

%.mirror-volume:
	-docker volume rm ${AOSP_PREFIX}_$(basename $@).mirror
	mkdir -p ${AOSP_VOLUME_DIR}/mirror/$(basename $@) ${AOSP_VOLUME_DIR}/mirror/$(basename $@).work
	docker volume create --driver local --opt type=overlay \
	--opt o='lowerdir=${AOSP_VOLUME_DIR}/mirror.root/$(basename $@)$(subst ${space},,$(foreach p,$?,:${AOSP_VOLUME_DIR}/mirror.root/${p})),upperdir=${AOSP_VOLUME_DIR}/mirror/$(basename $@),workdir=${AOSP_VOLUME_DIR}/mirror/$(basename $@).work' --opt device=overlay ${AOSP_PREFIX}_$(basename $@).mirror

volumes:
	mkdir -p ${AOSP_VOLUME_DIR}/${AOSP_PREFIX}_ccache ${AOSP_VOLUME_DIR}/${AOSP_PREFIX}_out
	-docker volume rm ${AOSP_PREFIX}_ccache ${AOSP_PREFIX}_out
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=${AOSP_VOLUME_DIR}/${AOSP_PREFIX}_ccache ${AOSP_PREFIX}_ccache
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=${AOSP_VOLUME_DIR}/${AOSP_PREFIX}_out  ${AOSP_PREFIX}_out

