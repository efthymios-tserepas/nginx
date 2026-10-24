#!/usr/bin/env bash
# nginx-installer v2.0.0
# Build nginx from official sources on Ubuntu/Debian or RHEL-family Linux.
# Ubuntu 26.04 support: PCRE2, compiler toolchain, and safe systemd integration.
set -Eeuo pipefail

readonly BIN=/usr/local/sbin/nginx
readonly UNIT=/etc/systemd/system/nginx.service
readonly CONFIG=/etc/nginx/nginx.conf
readonly MARKER='Managed by nginx-installer-v2'
channel=''
version=''
assume_yes=false
allow_upgrade=false
workdir=''
backupdir=''
install_started=false
prior_install=false
prior_running=false

say() { printf '[nginx-v2] %s\n' "$*"; }
die() { printf '[nginx-v2] ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'HELP'
Usage: sudo bash nginx-v2.sh [OPTIONS]
  --channel stable|mainline   Release channel (prompts by default on a terminal)
  --version X.Y.Z            Build an explicit nginx version instead
  --yes                      Non-interactive: use stable unless a channel is given
  --upgrade                  Allow upgrading an installation managed by this v2 script
  --help                     Show help
Environment: NGINX_BUILD_JOBS=2 (default, suitable for small Raspberry Pis)
This script compiles upstream nginx; it does NOT install the distro nginx package.
No automatic reboot or firewall changes are performed.
HELP
}

cleanup() {
  local rc=$?
  trap - EXIT
  if (( rc != 0 )) && [[ "$install_started" == true ]]; then
    say 'Installation failed; attempting to restore the previous installation.' >&2
    if [[ "$prior_install" == true ]]; then
      [[ ! -f "$backupdir/nginx" ]] || cp -a "$backupdir/nginx" "$BIN" || true
      [[ ! -f "$backupdir/nginx.conf" ]] || cp -a "$backupdir/nginx.conf" "$CONFIG" || true
      [[ ! -f "$backupdir/nginx.service" ]] || cp -a "$backupdir/nginx.service" "$UNIT" || true
      systemctl daemon-reload || true
      if [[ "$prior_running" == true ]]; then systemctl start nginx || true; fi
    else
      rm -f "$UNIT" "$BIN" "$CONFIG"
      systemctl daemon-reload || true
    fi
  fi
  [[ -z "$workdir" ]] || rm -rf -- "$workdir"
  if (( rc != 0 )); then say "Exited with code $rc. No reboot was requested." >&2; fi
  exit "$rc"
}
trap cleanup EXIT

while (( $# )); do
  case "$1" in
    --channel) (( $# >= 2 )) || die '--channel requires a value'; channel=$2; shift 2 ;;
    --version) (( $# >= 2 )) || die '--version requires a value'; version=$2; shift 2 ;;
    --yes|-y) assume_yes=true; shift ;;
    --upgrade) allow_upgrade=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
[[ $(id -u) == 0 ]] || die 'Run with sudo.'
command -v systemctl >/dev/null || die 'Requires systemd.'
[[ -z "$channel" || "$channel" == stable || "$channel" == mainline ]] || die 'Choose stable or mainline.'
[[ -z "$version" || "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Invalid version; expected X.Y.Z.'

# Never overwrite an nginx package or a pre-existing service not installed by v2.
if [[ -f "$UNIT" ]] && ! grep -Fq "$MARKER" "$UNIT"; then
  die "Existing nginx unit at $UNIT is not managed by v2. Not overwriting it."
fi
if [[ -f /lib/systemd/system/nginx.service || -f /usr/lib/systemd/system/nginx.service ]]; then
  die 'A distribution nginx systemd unit already exists. Refusing to overwrite it.'
fi
if command -v nginx >/dev/null 2>&1; then
  existing_bin=$(command -v nginx)
  [[ $(readlink -f "$existing_bin") == "$BIN" ]] || die "Existing nginx binary ($existing_bin) is not managed by this installer."
fi
if [[ -e "$BIN" || -e "$UNIT" ]]; then
  [[ -f "$UNIT" && -x "$BIN" ]] || die 'Partial nginx installation exists. Inspect it before proceeding.'
  [[ "$allow_upgrade" == true ]] || die 'v2 already installed. Run again with --upgrade to replace its binary.'
  prior_install=true
  if systemctl is-active --quiet nginx; then prior_running=true; fi
elif [[ -e "$CONFIG" ]]; then
  die "Existing configuration $CONFIG found without a v2 installation. Not overwriting it."
fi

# Fetch official release metadata (requires TLS). Never scrape arbitrary versions.
workdir=$(mktemp -d /tmp/nginx-build-v2.XXXXXXXX)
chmod 700 "$workdir"
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
  version=$(awk -v label="${channel^} version" '
    index($0,label) { found=1; next }
    found && match($0,/nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz/) {
      result=substr($0,RSTART,RLENGTH); sub(/^nginx-/,"",result); sub(/\.tar\.gz$/,"",result);
      print result; exit
    }
  ' "$workdir/download.html")
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Could not identify upstream release; use --version X.Y.Z.'
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
say 'No automatic reboot performed. Firewall rules were not modified.'
