#!/bin/sh

envsubst < /usr/share/nginx/html/config.js.tpl \
         > /usr/share/nginx/html/config.js

echo "Generated config.js with API_URL=${API_URL}"

exec nginx -g "daemon off;"