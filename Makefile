.PHONY: deploy prepare build cert

REPO_ROOT:=$(realpath $(shell pwd))
VERSION:=$(shell git rev-parse HEAD)

deploy: build
	docker-compose up -d

build:
	docker run \
		--rm \
		-v $(REPO_ROOT):/blog \
		-v $(REPO_ROOT)/public:/blog/public \
		-u $(shell id -u) \
		-w /blog \
		klakegg/hugo:ext-alpine -b https://weakptr.site/

image:
	docker build . -t gitea.weakptr.site/weakptr/blog:${VERSION}

serve:
	docker run \
		--rm \
		-v $(REPO_ROOT):/blog \
		-v $(REPO_ROOT)/public:/blog/public \
		-p 1313:1313 \
		-w /blog \
		klakegg/hugo:ext-alpine serve

cert:
	docker run \
		-it \
		-u $(shell id -u):$(shell id -g) \
		--rm \
		--name certbot \
		-v "$(REPO_ROOT)/ssl/:/ssl" \
		-v "$(REPO_ROOT)/public:/public" \
		certbot/certbot certonly \
			--webroot \
			--webroot-path=/public \
			--config-dir=/ssl \
			--logs-dir=/tmp \
			--work-dir=/tmp \
			--agree-tos \
			--email 'weak_ptr@outlook.com' \
			-n -d weakptr.site

