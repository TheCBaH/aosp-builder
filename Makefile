all: test

linux:
	cp ~/.gitconfig .
	docker build --build-arg userid=$$(id -u) --build-arg groupid=$$(id -g) --build-arg username=$$(id -un) -f Dockerfile-linux -t aosp:linux .
	rm .gitconfig


test: linux


