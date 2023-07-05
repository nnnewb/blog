FROM peaceiris/hugo:latest-full AS BUILD
RUN mkdir -p /src
COPY . /src
WORKDIR /src
RUN cp config.tpl.yaml config.yaml
RUN hugo --minify -b https://weakptr.site/

FROM nginx:mainline
COPY --from=BUILD /src/public /usr/share/nginx/html/

