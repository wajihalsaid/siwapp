
#-----------------------------------------
# Set Hostname
echo "Setting hostname to ${HOSTNAME}..."
sudo hostnamectl set-hostname "${HOSTNAME}"
#---------------------------------------------------------
# 1️⃣ Install HAProxy
#---------------------------------------------------------
echo "Installing HAProxy..."
sudo apt update -y
sudo apt install -y haproxy socat postgresql-client

sudo systemctl enable haproxy

#---------------------------------------------------------
# 2️⃣ Configure HAProxy (basic role-aware template)
#---------------------------------------------------------
sudo tee $HAPROXY_CFG >/dev/null <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 2000
    daemon
    stats socket ${ADMIN_SOCKET} mode 600 level admin

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend pg_front
    bind *:5432
    default_backend pg_back

backend pg_back
    mode tcp
    balance roundrobin
    server ${NODES[0]} ${IPS[0]}:${PG_PORT} check
    server ${NODES[1]} ${IPS[1]}:${PG_PORT} check
    server ${NODES[2]} ${IPS[2]}:${PG_PORT} check
EOF

sudo systemctl restart haproxy

#---------------------------------------------------------
# 3️⃣ Create Role-Aware Health Check Script
#---------------------------------------------------------
HEALTH_SCRIPT="/usr/local/bin/pg_role_check.sh"

sudo tee $HEALTH_SCRIPT >/dev/null <<EOF
#!/bin/bash

NODES=(${NODES[@]})
IPS=(${IPS[@]})
PORT=${PG_PORT}
USER="${PG_USER}"
PASS="${PG_PASS}"
ADMIN_SOCKET="${ADMIN_SOCKET}"

for i in "\${!NODES[@]}"; do
    NODE="\${NODES[\$i]}"
    IP="\${IPS[\$i]}"

    # Check if node is primary
    IS_PRIMARY=\$(PGPASSWORD=\$PASS psql -h \$IP -U \$USER -d postgres -tAc "SELECT NOT pg_is_in_recovery();")

    if [ "\$IS_PRIMARY" = "t" ]; then
        echo "Node \$NODE (\$IP) is PRIMARY → enable server"
        echo "enable server pg_back/\$NODE" | sudo socat stdio \$ADMIN_SOCKET
    else
        echo "Node \$NODE (\$IP) is REPLICA → disable server"
        echo "disable server pg_back/\$NODE" | sudo socat stdio \$ADMIN_SOCKET
    fi
done
EOF

sudo chmod +x $HEALTH_SCRIPT

#---------------------------------------------------------
# 4️⃣ Optional: Run Health Check Every 10 seconds via systemd Timer
#---------------------------------------------------------
sudo tee /etc/systemd/system/pg_role_check.service >/dev/null <<EOF
[Unit]
Description=PostgreSQL Role Health Check

[Service]
Type=oneshot
ExecStart=${HEALTH_SCRIPT}
EOF

sudo tee /etc/systemd/system/pg_role_check.timer >/dev/null <<EOF
[Unit]
Description=Run PostgreSQL Role Health Check every 10 seconds

[Timer]
OnBootSec=10
OnUnitActiveSec=10

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pg_role_check.timer

echo "✅ HAProxy role-aware setup completed!"
echo "Frontend port: 5432 → routes traffic to primary/replicas dynamically"
