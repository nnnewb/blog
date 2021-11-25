FROM klakegg/hugo:ext-alpine as BUILD
ADD . /blog
WORKDIR /blog
RUN sed -i 's/enabled: true # --DISABLE-ON-DOCKER--/enabled: false/' config.yaml
RUN hugo -b https://weakptr.site/

FROM nginx:mainline
COPY --from=BUILD /blog/public /usr/share/nginx/html
