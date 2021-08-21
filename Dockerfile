FROM klakegg/hugo:0.87.0-ext AS BUILD
COPY . /src
RUN hugo

FROM nginx:mainline-alpine
COPY --from=BUILD /src/public/ /usr/share/nginx/html/