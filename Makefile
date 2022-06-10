.PHONY: deploy build cert

REPO_ROOT:=$(shell pwd | realpath)


deploy: build
	docker-compose up -d

build:
	docker run \
		--rm \
		-v $(REPO_ROOT):/blog \
		-v $(REPO_ROOT)/public:/blog/public \
		-w /blog \
		klakegg/hugo:ext-alpine hugo -b https://weakptr.site/

cert:
	docker run \
		-it \
		--rm \
		--name certbot \
		-v "$(REPO_ROOT)/ssl/var/lib/letsencrypt:/var/lib/letsencrypt" \
		-v "$(REPO_ROOT)/ssl/etc/letsencrypt:/etc/letsencrypt" \
		-v "$(REPO_ROOT)/public:/public"
		-p "80:80" \
		-p "443:443" \
		certbot/certbot certonly --web-root=/public
