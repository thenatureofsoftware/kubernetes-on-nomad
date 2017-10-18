
VERSION_FILE=script/version
VERSION=$(shell cat $(VERSION_FILE))

default: docker push

docker:
	docker build --no-cache -t thenatureofsoftware/kon:$(VERSION) -f Dockerfile .
	docker tag thenatureofsoftware/kon:$(VERSION) thenatureofsoftware/kon:latest

push: docker
	docker push thenatureofsoftware/kon:$(VERSION)
	docker push thenatureofsoftware/kon:latest