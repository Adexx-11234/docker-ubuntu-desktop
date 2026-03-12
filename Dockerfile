FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# ============================================================================
# STEP 1 — Base system packages + tools
# ============================================================================
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl wget sudo ca-certificates gnupg2 gnupg lsb-release \
    git unzip tar zip zstd \
    software-properties-common tzdata apt-transport-https \
    net-tools iproute2 iputils-ping dnsutils \
    openssl iptables iptables-persistent \
    vim nano htop tmux screen \
    procps psmisc lsof \
    python3 python3-pip \
    netcat-openbsd socat \
    cron supervisor \
    build-essential \
    xterm dbus-x11 x11-utils x11-xserver-utils x11-apps \
    snapd && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 2 — Desktop environment (XFCE + VNC + noVNC)
# ============================================================================
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    xfce4 xfce4-goodies xfce4-terminal \
    tigervnc-standalone-server tigervnc-common \
    novnc websockify \
    xubuntu-icon-theme \
    fonts-dejavu fonts-liberation \
    dbus-x11 at-spi2-core && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 3 — Firefox
# ============================================================================
RUN add-apt-repository ppa:mozillateam/ppa -y && \
    echo 'Package: *' > /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' \
        > /etc/apt/apt.conf.d/51unattended-upgrades-firefox && \
    apt-get update -y && apt-get install -y firefox && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 4 — PHP 8.3 + all extensions Pelican needs
# ============================================================================
RUN add-apt-repository ppa:ondrej/php -y && \
    apt-get update -y && \
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

# Fix php-fpm to run as root (prevents exit status 78 in containers)
RUN sed -i 's/^user = www-data/user = root/' /etc/php/8.3/fpm/pool.d/www.conf && \
    sed -i 's/^group = www-data/group = root/' /etc/php/8.3/fpm/pool.d/www.conf && \
    mkdir -p /run/php

# ============================================================================
# STEP 5 — Nginx
# ============================================================================
RUN apt-get update -y && apt-get install -y nginx && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 6 — MySQL 8
# ============================================================================
RUN apt-get update -y && apt-get install -y mysql-server mysql-client && \
    mkdir -p /var/run/mysqld && \
    chown mysql:mysql /var/run/mysqld && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 7 — PostgreSQL 16
# ============================================================================
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
    https://apt.postgresql.org/pub/repos/apt jammy-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -y && apt-get install -y postgresql-16 postgresql-client-16 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 8 — SQLite3
# ============================================================================
RUN apt-get update -y && apt-get install -y sqlite3 libsqlite3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 9 — Redis
# ============================================================================
RUN apt-get update -y && apt-get install -y redis-server && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 10 — Composer
# ============================================================================
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# ============================================================================
# STEP 11 — Node.js 20
# ============================================================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 12 — Docker
# ============================================================================
RUN curl -fsSL https://get.docker.com | sh

# ============================================================================
# STEP 13 — Docker daemon config (container-safe, no iptables crashes)
# ============================================================================
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

# ============================================================================
# STEP 14 — Fix iptables legacy mode
# ============================================================================
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# ============================================================================
# STEP 15 — Certbot
# ============================================================================
RUN pip3 install --upgrade pip && \
    pip3 install certbot certbot-nginx 2>/dev/null || true

# ============================================================================
# STEP 16 — VNC xstartup (launches XFCE inside the display)
# ============================================================================
RUN mkdir -p /root/.vnc && \
    touch /root/.Xauthority && \
    cat > /root/.vnc/xstartup <<'EOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
startxfce4 &
EOF
RUN chmod +x /root/.vnc/xstartup

# ============================================================================
# STEP 17 — supervisord.conf
# ============================================================================
RUN mkdir -p /var/log/supervisor && cat > /etc/supervisor/conf.d/supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
user=root

[program:dockerd]
command=dockerd --config-file /etc/docker/daemon.json
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/dockerd.log
stderr_logfile=/var/log/supervisor/dockerd.log
priority=1
startsecs=3

[program:mysql]
command=/usr/bin/mysqld_safe
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/mysql.log
stderr_logfile=/var/log/supervisor/mysql.log
priority=10
startsecs=5

[program:postgresql]
command=/usr/lib/postgresql/16/bin/postgres -D /var/lib/postgresql/16/main -c config_file=/etc/postgresql/16/main/postgresql.conf
user=postgres
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/postgresql.log
stderr_logfile=/var/log/supervisor/postgresql.log
priority=10
startsecs=5

[program:redis]
command=/usr/bin/redis-server /etc/redis/redis.conf --daemonize no
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/redis.log
stderr_logfile=/var/log/supervisor/redis.log
priority=10
startsecs=2

[program:php-fpm]
command=/usr/sbin/php-fpm8.3 -F -R
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/php-fpm.log
stderr_logfile=/var/log/supervisor/php-fpm.log
priority=20
startsecs=3
environment=HOME="/root",USER="root"

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx.log
priority=30
startsecs=2

[program:vnc]
command=/usr/local/bin/start-vnc.sh
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/vnc.log
stderr_logfile=/var/log/supervisor/vnc.log
priority=40
startsecs=5
environment=HOME="/root",USER="root",DISPLAY=":1"

[program:novnc]
command=/usr/bin/websockify --web=/usr/share/novnc/ --cert=/root/self.pem 6080 localhost:5901
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/novnc.log
stderr_logfile=/var/log/supervisor/novnc.log
priority=50
startsecs=3
EOF

# ============================================================================
# STEP 18 — VNC start script
# KEY FIX: Use Xtigervnc directly + run xstartup manually in background
# This avoids the vncserver wrapper -fg issue that caused exit 255
# ============================================================================
RUN cat > /usr/local/bin/start-vnc.sh <<'EOF'
#!/bin/bash
export HOME=/root
export USER=root
export DISPLAY=:1

# Clean stale locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Start Xtigervnc (X server only, foreground)
/usr/bin/Xtigervnc :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1280x800 \
    -depth 24 \
    -rfbport 5901 \
    -desktop "Ubuntu Desktop" \
    -AlwaysShared &

VNC_PID=$!

# Wait for X server to be ready
sleep 3

# Now launch XFCE inside the display
export DISPLAY=:1
/root/.vnc/xstartup &

# Keep script alive by waiting on VNC process
wait $VNC_PID
EOF
RUN chmod +x /usr/local/bin/start-vnc.sh

# ============================================================================
# STEP 19 — Main startup script
# ============================================================================
RUN cat > /start.sh <<'EOF'
#!/bin/bash
set -e
echo "============================================"
echo "  Starting Ubuntu VNC + Pelican Environment"
echo "============================================"

# DBus
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# PostgreSQL first-run init
if [ ! -f /var/lib/postgresql/16/main/PG_VERSION ]; then
    echo "[INIT] Initialising PostgreSQL..."
    su - postgres -c "/usr/lib/postgresql/16/bin/initdb -D /var/lib/postgresql/16/main" 2>/dev/null || true
fi

# SSL cert for noVNC
if [ ! -f /root/self.pem ]; then
    openssl req -new -subj "/C=US/CN=localhost" -x509 -days 365 -nodes \
        -out /root/self.pem -keyout /root/self.pem 2>/dev/null
fi

# Clean stale VNC locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

echo "[START] Launching all services..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
EOF
RUN chmod +x /start.sh

# ── Ports ─────────────────────────────────────────────────────────────────────
# 5901 = VNC | 6080 = noVNC browser | 80/443 = Nginx | 3306 = MySQL
# 5432 = PostgreSQL | 6379 = Redis | 8080 = Pelican Wings
EXPOSE 5901 6080 80 443 3306 5432 6379 8080

CMD ["/start.sh"]
