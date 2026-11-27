# XiriBSD website

Static scaffolding for `https://xiribsd.org`, hosted by Apache on
`kimcarsons`. Serve only `public/`; it needs no build tools, JavaScript,
database or third-party assets. The Downloads section deliberately has no
release files or download links. XiriBSD ISOs will be added later.

The project description and platform summary come from Xiri's
[README](https://github.com/salvogendut/xiri/blob/99c2e90715eae938c6f4d858853e33e875cdaf72/README.md)
and [architecture guide](https://github.com/salvogendut/xiri/blob/99c2e90715eae938c6f4d858853e33e875cdaf72/docs/ARCHITECTURE.md),
reviewed on 2026-11-27. The page distinguishes emulation results from
physical-hardware qualification and future distribution releases.
`public/assets/xiri-logo.png` is an unchanged copy of `../xiri/xiri-logo.png`.
The CSS takes its teal casing, charcoal recesses, warm gray controls and
beveled borders from the SGI Octane's industrial design. The layout remains
responsive and uses local system fonts. No workstation photographs are
bundled; the visual reference is the
[Octane front view](https://bukosek.si/hardware/collection/sgi-octane.html).

## Preview

From the repository root:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory website/public
```

Open `http://127.0.0.1:8080/`. The page also works when opened directly from
`public/index.html` because its asset references are relative.

## Install on kimcarsons

The server uses a Red Hat-style installation: `/usr/sbin/httpd`,
`/usr/sbin/apachectl`, `/etc/httpd/conf.d`, and `/usr/local/bin/certbot`.
The commands below assume its service is managed by systemd as `httpd`.
The provided configuration is for an initial HTTP virtual host and
preserves the server's existing logging policy. It does not replace an
existing HTTPS configuration.

First inspect the loaded virtual hosts from your workstation:

```sh
ssh kimcarsons '/usr/sbin/apachectl -S'
```

If `xiribsd.org` already appears, inspect that configuration and update its
document root instead of installing a duplicate. Keep any existing TLS
configuration. The following installation block is for a new virtual host.

From this checkout, create the document root and upload the public files:

```sh
ssh kimcarsons 'install -d -m 0755 /var/www/xiribsd.org/public'
rsync -rt --chmod=D755,F644 website/public/ kimcarsons:/var/www/xiribsd.org/public/
scp website/apache/xiribsd.org.conf kimcarsons:/tmp/xiribsd.org.conf
```

No `--delete` is used: future release downloads must survive a page update.
Do not upload repository metadata, deployment configuration or documentation
into the document root. The SSH profile selects the user and port.

From the same checkout, install and enable the virtual host. Apache loads
files in `conf.d` directly; there is no separate site-enable command.

```sh
ssh kimcarsons 'sh -s' <<'REMOTE'
set -eu
site_conf=/etc/httpd/conf.d/xiribsd.org.conf
test ! -e "$site_conf"
test ! -L "$site_conf"
/usr/sbin/apachectl configtest
if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF /var/www/xiribsd.org
fi
install -m 0644 /tmp/xiribsd.org.conf "$site_conf"
if command -v restorecon >/dev/null 2>&1; then
    restorecon "$site_conf"
fi
if ! /usr/sbin/apachectl configtest; then
    rm -f "$site_conf"
    exit 1
fi
if ! systemctl reload httpd; then
    rm -f "$site_conf"
    /usr/sbin/apachectl configtest
    systemctl reload httpd
    exit 1
fi
REMOTE
```

The block stops if the target configuration already exists or Apache's
existing configuration is invalid. It applies the standard SELinux file
contexts when `restorecon` is installed. A failed syntax check removes only
the newly added configuration; a failed reload also attempts to reload the
previous configuration. It leaves the uploaded public files in place.

## DNS and HTTPS

DNS is managed separately by the site owner. Check the public A and AAAA
records against the addresses serving `kimcarsons`; any published IPv6
address must reach the same virtual host. The scaffold only claims
`xiribsd.org`. Add `www` only if its DNS and certificate are configured too.

Check the HTTP host locally on the server before relying on public DNS:

```sh
ssh kimcarsons
curl --fail -H 'Host: xiribsd.org' http://127.0.0.1/
curl --fail -I -H 'Host: xiribsd.org' http://127.0.0.1/assets/xiri-logo.png
```

Check `http://xiribsd.org/` from outside the server as well. Once the public
domain reaches this host on port 80, use the installed Certbot on the server.
Confirm its Apache plugin is present before requesting the certificate:

```sh
/usr/local/bin/certbot plugins
/usr/local/bin/certbot --apache --redirect -d xiribsd.org
/usr/sbin/apachectl configtest
# Use the certificate name printed by Certbot if it differs from xiribsd.org.
/usr/local/bin/certbot renew --cert-name xiribsd.org --dry-run
curl --fail -I https://xiribsd.org/
curl --fail -I https://xiribsd.org/assets/xiri-logo.png
```

Use the existing ACME account and renewal schedule, or configure those
explicitly when bootstrapping the server. Certbot's Apache plugin obtains
and installs the certificate; `--redirect` configures the HTTP-to-HTTPS
redirect. Keep its resulting TLS configuration for later content updates.
[Certbot documentation](https://eff-certbot.readthedocs.io/en/stable/using.html#apache).

## Later updates

Publish content updates with the same `rsync` command; no Apache reload is
needed for static content. Update the Downloads section only when actual
release files and checksums are available. Large ISO/CHD files belong in
release storage on the server, not in this source repository. Directory
listing is disabled; publish explicit download links when ready.
