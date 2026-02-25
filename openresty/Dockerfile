FROM openresty/openresty:alpine

RUN apk update && apk add apache2-utils jq perl curl openssl sqlite && apk cache clean && \
    opm install ledgetech/lua-resty-http && opm install fffonion/lua-resty-acme && \
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out /usr/local/openresty/nginx/conf/account.key && \
    mkdir -p /usr/local/openresty/nginx/conf/ssl.d && \
    openssl req -newkey rsa:2048 -nodes -keyout /usr/local/openresty/nginx/conf/ssl.d/default.key -x509 -days 365 -out /usr/local/openresty/nginx/conf/ssl.d/default.pem -subj "/C=US/ST=New Sweden/L=Stockholm /O=.../OU=.../CN=.../emailAddress=..." && \
    chmod -R a+r /usr/local/openresty/nginx/conf/* && \
    apk del perl curl openssl
