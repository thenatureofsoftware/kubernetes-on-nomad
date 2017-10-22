
VERSION_FILE=script/version
VERSION=$(shell cat $(VERSION_FILE))

default: args docker push

args:
	@./argbash -o script/arguments.sh script/kon.m4
	@sed -i '' -e '/assign_positional_args$$/d' -e '/parse_commandline "\$$\@"$$/d' -e '/handle_passed_args_count$$/d' script/arguments.sh

docker: args
	docker build --no-cache -t thenatureofsoftware/kon:$(VERSION) -f Dockerfile .
	docker tag thenatureofsoftware/kon:$(VERSION) thenatureofsoftware/kon:latest

push: docker
	docker push thenatureofsoftware/kon:$(VERSION)
	docker push thenatureofsoftware/kon:latest
