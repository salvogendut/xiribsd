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

The Screenshots section shows the supplied Indy R4400 emulation captures,
from startup to the IRIX desktop. Its four PNGs in `public/assets/screenshots/`
are unchanged copies of the screenshots taken on 2026-11-27 at 07:55:47,
07:55:58, 07:56:27, and 07:57:54, in that order. The gallery uses two columns on larger screens and one on phones, and
links each image to its full-size original.

## Preview

From the repository root:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory website/public
```

Open `http://127.0.0.1:8080/`. The page also works when opened directly from
`public/index.html` because its asset references are relative.

## Install on kimcarsons

The site was deployed on 2026-11-27 to Rocky Linux 9.9. It uses its own
`/etc/httpd/conf.d/xiribsd.org.conf` and `/var/www/xiribsd.org/public`;
existing virtual hosts and the default host remain unchanged. HTTPS is
normally public; HTTP is opened only temporarily for certificate validation.

Deployment validation confirmed that the public HTTPS page matches the
repository, the existing Apache configurations are unchanged, and the
scheduled Snap Certbot installation can complete a simulated renewal.
The renewal hooks opened and closed HTTP successfully; both runtime and
permanent firewall checks showed HTTP disabled afterward.

The server uses a Red Hat-style installation: `/usr/sbin/httpd`,
`/usr/sbin/apachectl`, `/etc/httpd/conf.d`, and `/usr/local/bin/certbot`.
Its service is managed by systemd as `httpd`. The bootstrap instructions
below are for a new installation. For the deployed site, use **Later
updates** instead. `apache/xiribsd.org.conf` is the initial HTTP template;
`apache/xiribsd.org-https.conf` replaces it once the certificate exists.
Enable only one, under the production filename `xiribsd.org.conf`.

First inspect the loaded virtual hosts from your workstation:

```sh
ssh kimcarsons '/usr/sbin/httpd -S'
```

If `xiribsd.org` already appears, inspect that configuration and update its
document root instead of installing a duplicate. Keep any existing TLS
configuration. The following installation block is for a new virtual host.

From this checkout, create the document root and upload the public files:

```sh
ssh kimcarsons 'install -d -m 0755 /var/www/xiribsd.org/public'
rsync -rt --chown=root:root --chmod=D755,F644 website/public/ kimcarsons:/var/www/xiribsd.org/public/
scp website/apache/xiribsd.org.conf kimcarsons:/tmp/xiribsd.org.conf
```

No `--delete` is used: future release downloads must survive a page update.
Do not upload repository metadata, deployment configuration or documentation
into the document root. The SSH profile selects the user and port.
The files are owned by `root:root`, with directories `0755` and files
`0644`. Apache runs as `apache` and can read the content without being
able to modify it. SELinux labels are `httpd_sys_content_t`; apply them
with `restorecon`, preserving the host's existing SELinux mode.

From the same checkout, install and enable the virtual host. Apache loads
files in `conf.d` directly; there is no separate site-enable command.

```sh
ssh kimcarsons 'sh -s' <<'REMOTE'
set -eu
site_conf=/etc/httpd/conf.d/xiribsd.org.conf
test ! -e "$site_conf"
test ! -L "$site_conf"
/usr/sbin/httpd -t
if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF /var/www/xiribsd.org
fi
install -m 0644 /tmp/xiribsd.org.conf "$site_conf"
if command -v restorecon >/dev/null 2>&1; then
    restorecon "$site_conf"
fi
if ! /usr/sbin/httpd -t; then
    rm -f "$site_conf"
    exit 1
fi
if ! systemctl reload httpd; then
    rm -f "$site_conf"
    /usr/sbin/httpd -t
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

Use Certbot's webroot authenticator and a separate certificate named
`xiribsd.org`. This avoids having the Apache plugin rewrite existing
virtual hosts. Use the server's existing ACME account and renewal timer.
The shared TLS options at `/etc/letsencrypt/options-ssl-apache.conf` already
exist on this host; the HTTPS template includes them without modifying them.

Upload the HTTPS template and renewal helpers from the checkout:

```sh
scp website/apache/xiribsd.org-https.conf kimcarsons:/tmp/
scp website/scripts/certbot-http-open.sh website/scripts/certbot-http-close.sh kimcarsons:/tmp/
```

On the server, install the root-owned helpers:

```sh
install -o root -g root -m 0755 /tmp/certbot-http-open.sh /usr/local/sbin/xiribsd-certbot-http-open
install -o root -g root -m 0755 /tmp/certbot-http-close.sh /usr/local/sbin/xiribsd-certbot-http-close
restorecon /usr/local/sbin/xiribsd-certbot-http-open /usr/local/sbin/xiribsd-certbot-http-close

/usr/local/bin/certbot certonly --webroot \
  --webroot-path /var/www/xiribsd.org/public \
  --cert-name xiribsd.org -d xiribsd.org --non-interactive \
  --pre-hook /usr/local/sbin/xiribsd-certbot-http-open \
  --post-hook /usr/local/sbin/xiribsd-certbot-http-close \
  --deploy-hook '/usr/sbin/httpd -t && /usr/bin/systemctl reload httpd'
```

The pre-hook opens the `http` service in firewalld's `public` zone with
`--timeout=600`. The post-hook closes it once renewal finishes, including
after a failed attempt. A marker in `/run` records whether the hook opened
the port. Pre-existing HTTP access is preserved. No permanent firewall
rule is added, and the timeout closes the port if Certbot is interrupted.
These hooks are specific to the `xiribsd.org` certificate.

After certificate issuance, replace only XiriBSD's configuration on the server:

```sh
(
set -eu
site_conf=/etc/httpd/conf.d/xiribsd.org.conf
site_backup=$(mktemp /var/tmp/xiribsd-http.XXXXXX)
cp -p "$site_conf" "$site_backup"
install -o root -g root -m 0644 /tmp/xiribsd.org-https.conf "$site_conf"
restorecon "$site_conf"
if /usr/sbin/httpd -t && systemctl reload httpd; then
    rm -f "$site_backup"
else
    install -o root -g root -m 0644 "$site_backup" "$site_conf"
    restorecon "$site_conf"
    /usr/sbin/httpd -t
    systemctl reload httpd
    exit 1
fi
)
```

The HTTP host serves ACME challenges directly and redirects other requests
to HTTPS while port 80 is open. Outside renewal windows, use the explicit
`https://xiribsd.org/` URL: the firewall blocks HTTP, including redirects.

Validate content and renewal:

```sh
curl --fail -I https://xiribsd.org/
curl --fail -I https://xiribsd.org/assets/xiri-logo.png
/usr/bin/snap run certbot renew --cert-name xiribsd.org --dry-run \
  --run-deploy-hooks --no-random-sleep-on-renew
firewall-cmd --zone=public --query-service=http
firewall-cmd --permanent --zone=public --query-service=http
```

The manual test skips Certbot's random scheduling delay; regular scheduled
renewals retain it. With HTTP initially closed, both final firewall checks should print `no`
(exit status 1). This uses the same Snap installation as the existing
`snap.certbot.renew.timer`, which handles scheduling. The local
`/usr/local/bin/certbot` points to `/opt/certbot/bin/certbot`; both installations
read `/etc/letsencrypt`. Do not add a duplicate cron job. The deploy hook checks Apache's syntax
and reloads it after a successful certificate renewal.

For an already-issued certificate, save hook settings with a staging test:

```sh
/usr/local/bin/certbot reconfigure --cert-name xiribsd.org \
  --pre-hook /usr/local/sbin/xiribsd-certbot-http-open \
  --post-hook /usr/local/sbin/xiribsd-certbot-http-close \
  --deploy-hook '/usr/sbin/httpd -t && /usr/bin/systemctl reload httpd' \
  --non-interactive
```

See the [Certbot renewal documentation](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates).

## Later updates

Publish content updates from the checkout:

```sh
rsync -rt --chown=root:root --chmod=D755,F644 website/public/ kimcarsons:/var/www/xiribsd.org/public/
ssh kimcarsons 'restorecon -RF /var/www/xiribsd.org'
```

No Apache reload is needed for static content. Keep the production HTTPS
configuration and renewal hooks in place. Update the Downloads section only
when actual release files and checksums are available. Large ISO/CHD files belong in
release storage on the server, not in this source repository. Directory
listing is disabled; publish explicit download links when ready.
