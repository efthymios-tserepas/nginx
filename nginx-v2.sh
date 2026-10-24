if [[ -z "$version" ]]; then
  if [[ -z "$channel" ]]; then
    if [[ "$assume_yes" == true || ! -t 0 ]]; then
      channel=stable
    else
      printf 'Select nginx: 1) stable  2) mainline [1]: '
      read -r choice
      case "$choice" in 1|'') channel=stable ;; 2) channel=mainline ;; *) die 'Cancelled.' ;; esac
    fi
  fi
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
    https://nginx.org/en/download.html --output "$workdir/download.html"
  # Official nginx versions use an even minor for stable and odd for mainline.
  # Read version references across the entire upstream download page, rather than
  # assuming that the release heading and the tarball URL occupy separate lines.
  # This also tolerates upstream HTML whitespace/layout changes.
  version=$(
    grep -Eo 'nginx-[0-9]+\.[0-9]+\.[0-9]+' "$workdir/download.html" |
      sed 's/^nginx-//' |
      awk -F. -v channel="$channel" '
        NF == 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
          if ((channel == "stable" && $2 % 2 == 0) ||
              (channel == "mainline" && $2 % 2 == 1)) print
        }' |
      sort -Vu | tail -n 1
  ) || die 'Could not parse the official nginx download page; use --version X.Y.Z.'
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'No matching upstream release found; use --version X.Y.Z.'
  say "Resolved latest $channel release: nginx $version"
fi
say "Building nginx $version from nginx.org (not apt nginx)."

# Install just the necessary build dependencies; never upgrade the entire OS.
if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential libpcre2-dev libssl-dev zlib1g-dev ca-certificates curl tar gzip
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y gcc make pcre2-devel openssl-devel zlib-devel ca-certificates curl tar gzip
elif command -v yum >/dev/null 2>&1; then
  yum install -y gcc make pcre2-devel openssl-devel zlib-devel ca-certificates curl tar gzip
else
  die 'Only apt-get, dnf, and yum systems are supported.'
fi
for tool in cc make curl tar; do command -v "$tool" >/dev/null || die "Required command missing: $tool"; done

# Do not displace a different web server on a new installation.
if [[ "$prior_install" == false ]] && command -v ss >/dev/null 2>&1; then
  if ss -H -ltn | awk '$4 ~ /:80$/ { found=1 } END { exit !found }'; then
    die 'Port 80 already has a listener. Free it before installing nginx.'
  fi
fi

archive="$workdir/nginx-$version.tar.gz"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
  "https://nginx.org/download/nginx-$version.tar.gz" --output "$archive"
# Source is only extracted into our private temporary build directory.
tar -tzf "$archive" >/dev/null || die 'Invalid nginx source archive.'
tar -xzf "$archive" -C "$workdir"
cd "$workdir/nginx-$version" || die 'Source directory missing from archive.'

./configure \
  --prefix=/usr/local/nginx \
  --sbin-path="$BIN" \
  --conf-path="$CONFIG" \
  --pid-path=/run/nginx.pid \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --with-pcre --with-pcre-jit \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_gzip_static_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_sub_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module

jobs=${NGINX_BUILD_JOBS:-2}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die 'NGINX_BUILD_JOBS must be a positive integer.'
make -j "$jobs"

# Save the old working binary/config/unit before touching an installed v2 service.
if [[ "$prior_install" == true ]]; then
  install -d -m 0700 /var/backups/nginx-installer-v2
  backupdir=$(mktemp -d /var/backups/nginx-installer-v2/backup.XXXXXXXX)
  cp -a "$BIN" "$backupdir/nginx"
  cp -a "$CONFIG" "$backupdir/nginx.conf"
  cp -a "$UNIT" "$backupdir/nginx.service"
  say "Previous version backed up under $backupdir"
  install_started=true
  if [[ "$prior_running" == true ]]; then systemctl stop nginx; fi
else
  install_started=true
fi
install -d -m 0755 /var/log/nginx /etc/nginx
make install
"$BIN" -t

# Own service (not a distribution package). Stable paths and reload/quit commands.
cat > "$UNIT" <<'SERVICE'
# Managed by nginx-installer-v2
[Unit]
Description=nginx HTTP and reverse proxy (built from official source)
Documentation=https://nginx.org/en/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/local/sbin/nginx -t -q
ExecStart=/usr/local/sbin/nginx
ExecReload=/usr/local/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT $MAINPID
Restart=on-failure
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now nginx
systemctl is-active --quiet nginx || die 'Service did not start.'
say "SUCCESS: nginx $version is active and enabled."
"$BIN" -v
say "LAN test: http://$(hostname -I | awk '{print $1}')"
