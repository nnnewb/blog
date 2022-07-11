.PHONY: deploy prepare build cert

REPO_ROOT:=$(realpath $(shell pwd))

deploy: build
	docker-compose up -d

prepare:
	cp config.tpl.yaml config.yaml
	docker run \
		--rm \
		-v $(REPO_ROOT)/config.yaml:/config.yaml \
		-u $(shell id -u) \
		-w / \
		mikefarah/yq -i '.params.comments.enabled = false | .params.comments.provider = ~' config.yaml

build: prepare
	docker run \
		--rm \
		-v $(REPO_ROOT):/blog \
		-v $(REPO_ROOT)/public:/blog/public \
		-u $(shell id -u) \
		-w /blog \
		klakegg/hugo:ext-alpine -b https://weakptr.site/

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
		-u $(shell id -u) \
		--rm \
		--name certbot \
		-v "$(REPO_ROOT)/ssl/var/lib/letsencrypt:/var/lib/letsencrypt" \
		-v "$(REPO_ROOT)/ssl/etc/letsencrypt:/etc/letsencrypt" \
		-v "$(REPO_ROOT)/public:/public"
		-p "80:80" \
		-p "443:443" \
		certbot/certbot certonly --web-root=/public
