FROM gitea.weakptr.site/weakptr/peaceiris/hugo:latest-full AS BUILD
RUN mkdir -p /src
COPY . /src
WORKDIR /src
RUN hugo --config weakptr.site.yaml --minify -b https://weakptr.site/

FROM nginx:mainline
COPY --from=BUILD /src/public /usr/share/nginx/html/

