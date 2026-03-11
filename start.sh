#!/bin/bash
set -e

echo "============================================"
echo "  Starting Ubuntu VNC + Pelican Environment"
echo "============================================"

# ── Fix DBus ─────────────────────────────────────────────────────────────────
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# ── PostgreSQL init (first run only) ─────────────────────────────────────────
if [ ! -f /var/lib/postgresql/16/main/PG_VERSION ]; then
    echo "[INIT] Setting up PostgreSQL..."
    su - postgres -c "/usr/lib/postgresql/16/bin/initdb -D /var/lib/postgresql/16/main" 2>/dev/null || true
fi

# ── Generate SSL cert for noVNC ───────────────────────────────────────────────
if [ ! -f /root/self.pem ]; then
    openssl req -new -subj "/C=US/CN=localhost" -x509 -days 365 -nodes \
        -out /root/self.pem -keyout /root/self.pem 2>/dev/null
fi

# ── VNC xstartup ─────────────────────────────────────────────────────────────
mkdir -p /root/.vnc
cat > /root/.vnc/xstartup <<'VNCEOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
startxfce4
VNCEOF
chmod +x /root/.vnc/xstartup
touch /root/.Xauthority

# ── Start all services via supervisor ────────────────────────────────────────
echo "[START] Launching all services..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
