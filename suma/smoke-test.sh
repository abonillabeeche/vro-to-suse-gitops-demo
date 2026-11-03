#!/bin/sh
# WordPress smoke test, run on the VM by the wordpress-maintenance action chain.
# Calls the site with its configured Host header (WordPress redirects other host names to siteurl).
set -e
wp="php -d memory_limit=512M /usr/local/bin/wp --allow-root --path=/srv/www/wordpress"
host=$($wp option get siteurl); host=${host#http://}
echo "http: $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $host" http://localhost/)"
echo "site: $($wp option get blogname)"
echo "cache: $(valkey-cli ping)"
echo "package: $(rpm -q valkey)"
