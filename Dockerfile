FROM gitea.weakptr.site/weakptr/peaceiris/hugo:latest-full AS BUILD
RUN mkdir -p /src
COPY . /src
WORKDIR /src
RUN cp weakptr.site.yaml config.yaml
RUN hugo --minify

FROM nginx:mainline
COPY --from=BUILD /src/public /usr/share/nginx/html/

