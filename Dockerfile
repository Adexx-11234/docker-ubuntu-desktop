FROM --platform=linux/amd64 ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# ── Base system + tools ──────────────────────────────────────────────────────
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl wget sudo ca-certificates gnupg2 git unzip tar \
    software-properties-common tzdata net-tools openssl \
    xterm dbus-x11 x11-utils x11-xserver-utils x11-apps \
    vim procps psmisc lsof python3 \
    iptables iproute2 netcat-openbsd \
    snapd cron

# ── Desktop (XFCE + VNC + noVNC) ────────────────────────────────────────────
RUN apt-get install -y --no-install-recommends \
    xfce4 xfce4-goodies \
    tigervnc-standalone-server \
    novnc websockify \
    xubuntu-icon-theme

# ── Firefox ──────────────────────────────────────────────────────────────────
RUN add-apt-repository ppa:mozillateam/ppa -y && \
    echo 'Package: *' > /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' \
        > /etc/apt/apt.conf.d/51unattended-upgrades-firefox && \
    apt-get update -y && apt-get install -y firefox

# ── PHP 8.3 + all Pelican required extensions ────────────────────────────────
RUN add-apt-repository ppa:ondrej/php -y && apt-get update -y && \
    apt-get install -y \
    php8.3 php8.3-cli php8.3-fpm \
    php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath \
    php8.3-xml php8.3-curl php8.3-zip php8.3-intl \
    php8.3-sqlite3 php8.3-common

# ── Nginx ────────────────────────────────────────────────────────────────────
RUN apt-get install -y nginx

# ── MySQL 8 ──────────────────────────────────────────────────────────────────
RUN apt-get install -y mysql-server mysql-client && \
    mkdir -p /var/run/mysqld && \
    chown mysql:mysql /var/run/mysqld

# ── SQLite3 ──────────────────────────────────────────────────────────────────
RUN apt-get install -y sqlite3 libsqlite3-dev

# ── Composer ─────────────────────────────────────────────────────────────────
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# ── Certbot (for SSL when you're ready) ──────────────────────────────────────
RUN snap install core 2>/dev/null || true && \
    snap refresh core 2>/dev/null || true && \
    snap install --classic certbot 2>/dev/null || true && \
    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true

# ── Docker (for Wings / Pelican game servers) ────────────────────────────────
RUN curl -fsSL https://get.docker.com | sh

# ── Docker daemon config (container-safe, no iptables crashes) ───────────────
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

# ── Fix iptables to legacy mode (avoids nftables conflicts) ──────────────────
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# ── VNC setup ────────────────────────────────────────────────────────────────
RUN touch /root/.Xauthority && \
    mkdir -p /root/.vnc && \
    printf '#!/bin/bash\nstartxfce4 &\n' > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup

EXPOSE 5901 6080 80 443 3306

CMD bash -c "\
    dockerd --config-file /etc/docker/daemon.json > /var/log/dockerd.log 2>&1 & \
    sleep 5 && \
    service mysql start && \
    service php8.3-fpm start && \
    service nginx start && \
    vncserver -localhost no -SecurityTypes None -geometry 1280x800 --I-KNOW-THIS-IS-INSECURE && \
    openssl req -new -subj '/C=US' -x509 -days 365 -nodes \
        -out /root/self.pem -keyout /root/self.pem 2>/dev/null && \
    websockify -D --web=/usr/share/novnc/ --cert=/root/self.pem 6080 localhost:5901 && \
    tail -f /dev/null"
