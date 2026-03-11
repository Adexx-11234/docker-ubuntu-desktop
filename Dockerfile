FROM --platform=linux/amd64 ubuntu:22.04
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
# STEP 4 — PHP 8.3 + all extensions Pelican Panel needs
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
# STEP 9 — Redis (for Pelican queue/cache)
# ============================================================================
RUN apt-get update -y && apt-get install -y redis-server && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 10 — Composer
# ============================================================================
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer && \
    composer --version

# ============================================================================
# STEP 11 — Node.js 20 + npm (needed by some Pelican assets)
# ============================================================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# STEP 12 — Docker (for Wings / Pelican game servers)
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
# STEP 14 — Fix iptables to legacy mode (avoids nftables conflicts)
# ============================================================================
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# ============================================================================
# STEP 15 — Certbot (for SSL when ready)
# ============================================================================
RUN python3 -m pip install --upgrade pip && \
    pip3 install certbot certbot-nginx 2>/dev/null || true

# ============================================================================
# STEP 16 — VNC + XFCE setup
# ============================================================================
RUN touch /root/.Xauthority && \
    mkdir -p /root/.vnc && \
    printf '#!/bin/bash\nexport XKL_XMODMAP_DISABLE=1\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nstartxfce4\n' \
        > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup

# ============================================================================
# STEP 17 — Supervisor config (keeps all services alive automatically)
# ============================================================================
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ============================================================================
# STEP 18 — Startup script
# ============================================================================
COPY start.sh /start.sh
RUN chmod +x /start.sh

# ── Ports ────────────────────────────────────────────────────────────────────
# 5901  = VNC direct
# 6080  = noVNC (browser desktop access)
# 80    = Nginx / Pelican Panel HTTP
# 443   = Nginx / Pelican Panel HTTPS
# 3306  = MySQL
# 5432  = PostgreSQL
# 6379  = Redis
# 8080  = Pelican Wings
EXPOSE 5901 6080 80 443 3306 5432 6379 8080

CMD ["/start.sh"]
