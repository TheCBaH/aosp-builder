all: test
ID_OFFSET=10
UID:=$(shell expr $$(id -u) - ${ID_OFFSET})
GID:=$(shell expr $$(id -g) - ${ID_OFFSET})
USER:=$(shell id -un)
JOBS=4
MIRROR=/home/${USER}/aosp/mirror/
INIT_MANIFEST=${MIRROR}/platform/manifest.git
ORIGIN=https://android.googlesource.com/mirror/manifest

linux:
	docker build -f Dockerfile-linux -t aosp:linux .

user: linux
	cp ~/.gitconfig .
	docker build --build-arg userid=${UID} --build-arg groupid=${GID} --build-arg username=${USER} -f Dockerfile-$@ -t aosp:$@ .
	rm .gitconfig

mirror: user
	-docker volume create aosp_mirror
	docker run -it --rm --name aosp_mirror -v aosp_mirror:${MIRROR} --entrypoint "/bin/bash" aosp:$< -c \
		"chown ${USER} ${MIRROR};exec chroot --userspec ${USER}:${GID} / /bin/bash -euxc \
		'export HOME=/home/${USER};id;cd ${MIRROR};repo init -u ${ORIGIN} --mirror;time repo sync -j${JOBS}'"

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
	docker run -it --name aosp_$@ \
	-v /home/${USER}/aosp:/home/${USER}/aosp:ro \
	aosp:$< build -c 'set -aux;cd ~;mkdir source;cd source;\
	git config --global color.ui false;\
	repo init -u ${INIT_MANIFEST} --reference=${MIRROR} -b $@;\
	time repo sync -c --no-clone-bundle --no-tags -j${JOBS};\
	echo DONE'
