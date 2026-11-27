#!/bin/sh
# Install as /usr/local/sbin/xiribsd-certbot-http-open, owned by root.
# Used only by the xiribsd.org Certbot renewal configuration.
set -eu

marker=/run/xiribsd-certbot-http-opened
umask 077
rm -f "$marker"

# Preserve a port already opened by an administrator or another workflow.
if /usr/bin/firewall-cmd --zone=public --query-service=http >/dev/null; then
    exit 0
fi

# firewalld closes the port after ten minutes even if Certbot is interrupted.
/usr/bin/firewall-cmd --zone=public --add-service=http --timeout=600
: > "$marker"
