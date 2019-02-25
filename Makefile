all: test
ID_OFFSET=10
UID:=$(shell expr $$(id -u) - ${ID_OFFSET})
GID:=$(shell expr $$(id -g) - ${ID_OFFSET})
USER:=$(shell id -un)
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

mirror-new.master: user
	docker run -it --rm --name aosp_$@ -v aosp_mirror-master:${MIRROR}:ro -v aosp_$(subst .,-,$@):${MIRROR}.new aosp:$< bash -euxc \
		"echo mkdir ${MIRROR}.new;chown ${USER} ${MIRROR}.new;exec chroot --userspec ${USER}:${GID} / /bin/bash -euxc \
		'export HOME=/home/${USER};id;cd ${MIRROR}.new;[ -d .repo ] || repo init -u ${MIRROR_MANIFEST} -b $(subst .,,$(suffix $@)) --reference=${MIRROR} --dissociate \
		;time repo sync -c --network-only --no-clone-bundle --no-tags -j${SYNC_JOBS}'"


mirror.master: user
	-docker volume create aosp_$(subst .,-,$@) 
	docker run -it --rm --name aosp_$@ -v aosp_$(subst .,-,$@):${MIRROR} aosp:$< bash -euxc \
		"chown ${USER} ${MIRROR};exec chroot --userspec ${USER}:${GID} / /bin/bash -euxc \
		'export HOME=/home/${USER};id;cd ${MIRROR};[ -d .repo ] || repo init -u ${ORIGIN} --mirror \
		;time repo sync -j${SYNC_JOBS}'"

ccache: user
	-docker volume create aosp_$@
	docker run -it --rm --name aosp_$@ -v aosp_ccache:/ccache aosp:$< bash -exc \
		'chown ${USER}:${GID} /ccache ;env CCACHE_DIR=/ccache ccache -M1040'

ccache.stats: user
	docker run -it --rm --name $(subst .,-,$@) -v aosp_ccache:/ccache:ro aosp:$< bash -exc \
		'env CCACHE_DIR=/ccache ccache -s'

run: user
	docker run -it --rm aosp:$<

test: user
	docker run -it --rm \
	-v /home/${USER}/aosp:/home/${USER}/aosp:ro \
	aosp:$< build -c 'set -eux;cd ~;mkdir source;cd source;\
	git config --global color.ui false;\
	repo init -u ${MIRROR};\
	echo'

image.master: user
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -it --name aosp_$(subst .,-,$@) -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$< build -c 'set -eux;mkdir -p ${SOURCE};cd ${SOURCE};\
	git config --global color.ui false;\
	repo init -u ${MIRROR_MANIFEST} --reference=${MIRROR} ;\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	echo DONE'
	docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(subst .,,$(suffix $@))
	docker container rm aosp_$(subst .,-,$@)
	touch done-$@

master.update:
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -it --name aosp_$(subst .,-,$@) -v/home:/home_root aosp:$(basename $@) bash -i
	docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(basename $@)
	docker container rm aosp_$(subst .,-,$@)

run.master:
	docker run --rm -it --name aosp_$(subst .,-,$@) \
	-v ${SOURCE}/out -v aosp_ccache:/ccache -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$(subst .,,$(suffix $@)) build -c 'cd ${SOURCE}; exec bash -i'

build.master:
	docker run --rm -it --name aosp_$(subst .,-,$@) \
	-v ${OUT_VOLUME}${SOURCE}/out -v aosp_ccache:/ccache \
	aosp:$(subst .,,$(suffix $@)) build -c 'cd ${SOURCE}; source build/envsetup.sh;lunch aosp_arm64-eng && time make -j${BUILD_JOBS}'


image.pie-release:done-image.master
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -it --name aosp_$(subst .,-,$@) -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$(subst .,,$(suffix $<)) build -c 'set -eux;cd ${SOURCE};\
	git config --global color.ui false;\
	repo init -u ${ORIGIN} --reference=${MIRROR} -b $(subst .,,$(suffix $@));\
	time repo sync -c --force-sync --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	find . -type l -name Android\* -not -readable -delete;repo sync -c --local-only -j${SYNC_JOBS};\
	echo DONE'
	docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(subst .,,$(suffix $@))
	docker container rm aosp_$(subst .,-,$@)
	touch done-$@

image.oreo-dev: done-image.pie-release
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -it --name aosp_$(subst .,-,$@) -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$(subst .,,$(suffix $<)) build -c 'set -eux;cd ${SOURCE};\
	git config --global color.ui false;\
	repo init -u ${ORIGIN} --reference=${MIRROR} -b $(subst .,,$(suffix $@));\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	find . -type l -name Android\* -not -readable -delete;repo sync -c --local-only -j${SYNC_JOBS};\
	echo DONE'
	docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(subst .,,$(suffix $@))
	docker container rm aosp_$(subst .,-,$@)
	touch done-$@

build.pie-release:
	docker run --rm -it --name aosp_$(subst .,-,$@) \
	-v ${SOURCE}/out -v aosp_ccache:/ccache \
	aosp:$(subst .,,$(suffix $@)) build -c 'cd ${SOURCE}; source build/envsetup.sh;lunch aosp_arm64-eng && time make -j${BUILD_JOBS}'

run.%:done-image.%
	docker run --rm -it --name aosp_$(subst .,-,$@) \
	-v ${SOURCE}/out -v aosp_ccache:/ccache -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$(subst .,,$(suffix $@)) build -c 'cd ${SOURCE}; exec bash -i'

build.%:done-image.%
	docker run --rm -it --name aosp_$(subst .,-,$@) \
	-v ${SOURCE}/out -v aosp_ccache:/ccache \
	aosp:$(subst .,,$(suffix $@)) build -c 'cd ${SOURCE}; source build/envsetup.sh;lunch aosp_arm64-eng && time make -j${BUILD_JOBS}'

image.%:
	-docker container kill aosp_$(subst .,-,$@)
	-docker container rm aosp_$(subst .,-,$@)
	docker run -it --name aosp_$(subst .,-,$@) -v aosp_mirror-master:${MIRROR}:ro \
	aosp:$(subst .,,$(suffix $<)) build -c 'set -eux;cd ${SOURCE};\
	git config --global color.ui false;\
	repo init -u ${ORIGIN} --reference=${MIRROR} -b $(subst .,,$(suffix $@));\
	time repo sync -c --no-clone-bundle --no-tags -j${SYNC_JOBS};\
	find . -type l -name Android\* -not -readable -delete;repo sync -c --local-only -j${SYNC_JOBS};\
	echo DONE'
	docker commit --change='CMD "build"' aosp_$(subst .,-,$@) aosp:$(subst .,,$(suffix $@))
	docker container rm aosp_$(subst .,-,$@)
	touch done-$@

image.oreo-cts-dev: done-image.oreo-dev

clean:
	rm done-*

volumes:
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=/data/docker/aosp_mirror-master aosp_mirror-master  
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=/data/docker/aosp_ccache aosp_ccache
	docker volume create --driver local --opt type=bind --opt o=bind --opt device=/data/docker/aosp_out  aosp_out
