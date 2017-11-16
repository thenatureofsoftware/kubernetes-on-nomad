
VERSION_FILE := script/version
VERSION := $(shell cat $(VERSION_FILE))
WORKDIR := .build
UNAME := $(shell uname)
MT_VERSION := v0.7.0

default: args docker push

args:
	@./argbash -o script/arguments.sh script/kon.m4
	@sed -i '' -e '/assign_positional_args$$/d' -e '/parse_commandline "\$$\@"$$/d' -e '/handle_passed_args_count$$/d' script/arguments.sh

docker: args
	docker run --rm --privileged multiarch/qemu-user-static:register --reset
	docker build --no-cache -t thenatureofsoftware/kon-amd64:$(VERSION) -f Dockerfile.amd64 .
	docker build --no-cache -t thenatureofsoftware/kon-arm:$(VERSION) -f Dockerfile.arm .
	docker build --no-cache -t thenatureofsoftware/kon-arm64:$(VERSION) -f Dockerfile.arm64 .
	docker tag thenatureofsoftware/kon-amd64:$(VERSION) thenatureofsoftware/kon-amd64:latest
	docker tag thenatureofsoftware/kon-arm:$(VERSION) thenatureofsoftware/kon-arm:latest
	docker tag thenatureofsoftware/kon-arm64:$(VERSION) thenatureofsoftware/kon-arm64:latest

push: docker manifest-tool
	docker push thenatureofsoftware/kon-arm:$(VERSION)
	docker push thenatureofsoftware/kon-arm64:$(VERSION)
	docker push thenatureofsoftware/kon-amd64:$(VERSION)
	@$(WORKDIR)/manifest-tool --username $(DOCKER_USER) --password $(DOCKER_PASS) push from-spec $(WORKDIR)/manifest.yml

manifest-tool: manifest-tool-url
ifeq ("$(wildcard $(WORKDIR)/manifest-tool)","")
	@mkdir -p $(WORKDIR)
	@wget -q -O $(WORKDIR)/manifest-tool $(MT_URL)
	@chmod +x $(WORKDIR)/manifest-tool
endif
	@cat manifest.yml | sed -e 's/VERSION/$(VERSION)/g' > $(WORKDIR)/manifest.yml

manifest-tool-url:
ifeq ($(UNAME), Darwin)
	@echo "downloading manifest-tool for OSX ..."
MT_URL="https://github.com/estesp/manifest-tool/releases/download/$(MT_VERSION)/manifest-tool-darwin-amd64"
else
	@echo "downloading manifest-tool for Linux ..."
MT_URL="https://github.com/estesp/manifest-tool/releases/download/$(MT_VERSION)/manifest-tool-linux-amd64"
endif

