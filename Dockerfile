FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Base system
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl wget sudo ca-certificates gnupg2 gnupg lsb-release \
    git unzip tar zip software-properties-common tzdata \
    apt-transport-https net-tools iproute2 iputils-ping dnsutils \
    openssl iptables vim nano htop procps psmisc lsof \
    python3 python3-pip netcat-traditional socat cron \
    build-essential xterm dbus-x11 \
    x11-utils x11-xserver-utils x11-apps && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# XFCE Desktop + VNC + noVNC
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    xfce4 xfce4-goodies xfce4-terminal \
    tigervnc-standalone-server tigervnc-common \
    novnc websockify \
    xubuntu-icon-theme fonts-dejavu fonts-liberation \
    dbus-x11 at-spi2-core && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Firefox
RUN add-apt-repository ppa:mozillateam/ppa -y && \
    printf 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' \
        > /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update -y && apt-get install -y firefox && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# MySQL
RUN apt-get update -y && apt-get install -y mysql-server mysql-client && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# PostgreSQL 16
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -y && apt-get install -y postgresql-16 postgresql-client-16 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# PHP 8.3
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

# Docker (for Wings)
RUN curl -fsSL https://get.docker.com | sh

# Docker daemon config (container-safe)
RUN mkdir -p /etc/docker && cat > /etc/docker/daemon.json <<'EOF'
{
  "dns": ["8.8.8.8", "1.1.1.1"],
  "iptables": false,
  "ip6tables": false,
  "ipv6": false,
  "userland-proxy": false,
  "storage-driver": "vfs",
  "bridge": "none"
}
EOF

# Fix iptables legacy
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# VNC xstartup
RUN mkdir -p /root/.vnc && touch /root/.Xauthority && \
    printf '#!/bin/bash\nexport XKL_XMODMAP_DISABLE=1\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nstartxfce4 &\n' \
    > /root/.vnc/xstartup && chmod +x /root/.vnc/xstartup

# Startup script — just Docker + VNC + noVNC, nothing else
RUN cat > /start.sh <<'EOF'
#!/bin/bash

# DBus
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# Start Docker
dockerd --config-file /etc/docker/daemon.json > /var/log/dockerd.log 2>&1 &
sleep 5

# SSL cert for noVNC
openssl req -new -subj "/C=US/CN=localhost" -x509 -days 365 -nodes \
    -out /root/self.pem -keyout /root/self.pem 2>/dev/null || true

# Clean stale VNC locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Start VNC
/usr/bin/Xtigervnc :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1280x800 \
    -depth 24 \
    -rfbport 5901 \
    -desktop "Ubuntu Desktop" \
    -AlwaysShared &
sleep 3

# Launch XFCE inside VNC
DISPLAY=:1 /root/.vnc/xstartup &

# Start noVNC on port 6080
websockify -D --web=/usr/share/novnc/ --cert=/root/self.pem 6080 localhost:5901

tail -f /dev/null
EOF
RUN chmod +x /start.sh

EXPOSE 5901 6080

CMD ["/start.sh"]
