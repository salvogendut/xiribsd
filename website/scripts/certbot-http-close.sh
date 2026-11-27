#!/bin/sh
# Install as /usr/local/sbin/xiribsd-certbot-http-close, owned by root.
set -eu

marker=/run/xiribsd-certbot-http-opened
if [ ! -f "$marker" ]; then
    exit 0
fi

if /usr/bin/firewall-cmd --zone=public --query-service=http >/dev/null; then
    /usr/bin/firewall-cmd --zone=public --remove-service=http
fi
rm -f "$marker"
