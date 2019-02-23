all: test
ID_OFFSET=10
UID=$(shell expr $$(id -u) - ${ID_OFFSET})
GID=$(shell expr $$(id -g) - ${ID_OFFSET})
JOBS=4

linux:
	docker build -f Dockerfile-linux -t aosp:linux .

user: linux
	cp ~/.gitconfig .
	docker build --build-arg userid=${UID} --build-arg groupid=${GID} --build-arg username=$$(id -un) -f Dockerfile-$@ -t aosp:$@ .
	rm .gitconfig

run: user
	docker run -it --rm aosp:$<

test: user
	docker run -it --rm \
	-v /home/${USER}/aosp:/home/${USER}/aosp:ro \
	aosp:$< build -c 'set -aux;cd ~;mkdir source;cd source;\
	git config --global color.ui false;\
	repo init -u ~/aosp/mirror/platform/manifest.git;\
	echo'

master: user
	-docker container kill aosp_$@;
	-docker container rm aosp_$@;
	docker run -it --name aosp_$@ \
	-v /home/${USER}/aosp:/home/${USER}/aosp:ro \
	aosp:$< build -c 'set -aux;cd ~;mkdir source;cd source;\
	git config --global color.ui false;\
	repo init -u ~/aosp/mirror/platform/manifest.git -b $@;\
	time repo sync -c --no-clone-bundle --no-tags -j${JOBS};\
	echo DONE'

