FROM klakegg/hugo:ext-alpine as BUILD
ADD . /blog
WORKDIR /blog
RUN hugo -b https://weakptr.site/

FROM nginx:mainline
COPY --from=BUILD /blog/public /usr/share/nginx/html
