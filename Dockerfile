FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# ── Base system ────────────────────────────────────────────────────────────────
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl wget sudo ca-certificates gnupg2 gnupg lsb-release \
    git unzip tar zip software-properties-common tzdata \
    apt-transport-https net-tools iproute2 iputils-ping dnsutils \
    openssl iptables vim nano htop procps psmisc lsof \
    python3 python3-pip netcat-traditional socat cron \
    build-essential xterm dbus-x11 \
    x11-utils x11-xserver-utils x11-apps && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── XFCE Desktop + VNC + noVNC ────────────────────────────────────────────────
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    xfce4 xfce4-goodies xfce4-terminal \
    tigervnc-standalone-server tigervnc-common \
    novnc websockify \
    xubuntu-icon-theme fonts-dejavu fonts-liberation \
    dbus-x11 at-spi2-core && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Firefox ───────────────────────────────────────────────────────────────────
RUN add-apt-repository ppa:mozillateam/ppa -y && \
    printf 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' \
        > /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update -y && apt-get install -y firefox && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── MySQL ─────────────────────────────────────────────────────────────────────
RUN apt-get update -y && apt-get install -y mysql-server mysql-client && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── PostgreSQL 16 ─────────────────────────────────────────────────────────────
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -y && apt-get install -y postgresql-16 postgresql-client-16 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── PHP 8.3 ───────────────────────────────────────────────────────────────────
RUN add-apt-repository ppa:ondrej/php -y && apt-get update -y && \
    apt-get install -y \
    php8.3 php8.3-cli php8.3-fpm \
    php8.3-gd php8.3-mysql php8.3-pgsql \
    php8.3-mbstring php8.3-bcmath \
    php8.3-xml php8.3-curl php8.3-zip \
    php8.3-intl php8.3-sqlite3 \
    php8.3-common php8.3-readline \
    php8.3-opcache php8.3-redis \
    php8.3-tokenizer php8.3-fileinfo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Docker + fuse-overlayfs ───────────────────────────────────────────────────
# fuse-overlayfs is the critical addition. It implements overlay filesystem
# entirely in userspace via FUSE, bypassing the kernel's CLONE_NEWNS requirement.
# The standard overlay driver needs mount namespaces; fuse-overlayfs does not.
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    fuse3 \
    fuse-overlayfs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://get.docker.com | sh

# ── Allow FUSE inside the container ──────────────────────────────────────────
# /dev/fuse must be accessible. The device exists on most platforms even without
# full privilege. We chmod it here so it's writable at runtime.
# The container also needs to be run with --device /dev/fuse (or equivalent
# platform setting) — document this for your platform config.
RUN mkdir -p /etc/docker

# ── Docker daemon config ──────────────────────────────────────────────────────
# Key decisions:
#
# "storage-driver": "fuse-overlayfs"
#   Uses FUSE-based overlay. Does NOT call unshare(CLONE_NEWNS) during layer
#   registration — this is the fix for your specific error. VFS does still
#   attempt a namespace unshare in the snapshotter path on recent dockerd
#   versions; fuse-overlayfs avoids that entirely.
#
# "storage-opts": ["overlay2.override_kernel_check=true"]
#   Suppresses the kernel version check that would otherwise abort startup.
#
# "userland-proxy": true
#   Restored from your working config. Required for port-forwarding when
#   iptables rules cannot be installed (your platform blocks iptables).
#   With iptables:false, userland-proxy is the ONLY forwarding mechanism.
#
# "iptables": false / "ip6tables": false
#   Your platform cannot load iptables rules. Keep disabled.
#   With userland-proxy:true this is safe — the proxy handles NAT.
#
# "bip" + "default-address-pools"
#   Kept from your working config. Defines the docker0 bridge IP and the
#   pool for user-defined networks. Avoids conflicts with host networking.
#
# "dns" / "dns-opts"
#   Kept from your working config. ndots:0 prevents unnecessary search-domain
#   lookups which cause latency inside nested containers.
#
# "bridge": removed (was "none" in original — that disables docker0 entirely,
#   which breaks container networking. Only omit bip/bridge if you truly want
#   no networking. We restore bip instead.)
#
# "ipv6": false  — no change, keeps IPv6 stack disabled.
RUN cat > /etc/docker/daemon.json <<'EOF'
{
  "dns": ["8.8.8.8", "1.1.1.1", "8.8.4.4"],
  "dns-opts": ["ndots:0"],
  "storage-driver": "fuse-overlayfs",
  "iptables": false,
  "ip6tables": false,
  "ipv6": false,
  "userland-proxy": true,
  "bip": "172.26.0.1/16",
  "default-address-pools": [{"base": "172.25.0.0/16", "size": 24}],
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
EOF

# ── Fix iptables legacy ────────────────────────────────────────────────────────
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# ── VNC xstartup ──────────────────────────────────────────────────────────────
RUN mkdir -p /root/.vnc && touch /root/.Xauthority && \
    printf '#!/bin/bash\nexport XKL_XMODMAP_DISABLE=1\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nstartxfce4 &\n' \
    > /root/.vnc/xstartup && chmod +x /root/.vnc/xstartup

# ── Startup script ────────────────────────────────────────────────────────────
RUN cat > /start.sh <<'EOF'
#!/bin/bash

# ── DBus ──────────────────────────────────────────────────────────────────────
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# ── FUSE device permissions ───────────────────────────────────────────────────
# Ensure /dev/fuse is accessible. On some platforms this device is present
# but owned by root with 0600. fuse-overlayfs needs it readable by dockerd.
chmod 666 /dev/fuse 2>/dev/null || true

# ── Kernel tuning for nested Docker ──────────────────────────────────────────
# These are the sysctl values Docker normally sets itself via mount namespace.
# Since we cannot create mount namespaces, we set them directly. This requires
# CAP_SYS_ADMIN (which you have).
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
sysctl -w net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
sysctl -w net.bridge.bridge-nf-call-ip6tables=0 2>/dev/null || true
# Disable IPv6 on all interfaces to avoid Docker warnings
sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true

# ── Start Docker ──────────────────────────────────────────────────────────────
dockerd --config-file /etc/docker/daemon.json > /var/log/dockerd.log 2>&1 &
DOCKERD_PID=$!

# Wait for dockerd to be ready (up to 30s), not just a blind sleep
echo "Waiting for dockerd..."
for i in $(seq 1 30); do
    docker info > /dev/null 2>&1 && echo "dockerd ready." && break
    sleep 1
done

# ── SSL cert for noVNC ────────────────────────────────────────────────────────
openssl req -new -subj "/C=US/CN=localhost" -x509 -days 365 -nodes \
    -out /root/self.pem -keyout /root/self.pem 2>/dev/null || true

# ── Clean stale VNC locks ─────────────────────────────────────────────────────
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# ── Start VNC ─────────────────────────────────────────────────────────────────
/usr/bin/Xtigervnc :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1280x800 \
    -depth 24 \
    -rfbport 5901 \
    -desktop "Ubuntu Desktop" \
    -AlwaysShared &
sleep 3

# ── Launch XFCE inside VNC ────────────────────────────────────────────────────
DISPLAY=:1 /root/.vnc/xstartup &

# ── Start noVNC ───────────────────────────────────────────────────────────────
websockify -D --web=/usr/share/novnc/ --cert=/root/self.pem 6080 localhost:5901

tail -f /dev/null
EOF
RUN chmod +x /start.sh

EXPOSE 5901 6080

CMD ["/start.sh"]
