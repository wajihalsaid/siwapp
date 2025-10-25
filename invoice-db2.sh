

# Set Hostname
echo "Setting hostname to ${HOSTNAME}..."
sudo hostnamectl set-hostname "${HOSTNAME}"

# Update system packages
echo "Updating system..."
sudo apt update -y

# Install PostgreSQL
echo "Installing PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

# Find PostgreSQL version to specify data directory path
PG_DIR=$(find /etc/postgresql -maxdepth 1 -type d | grep -E '[0-9]+$')
PG_VER=$(basename "$PG_DIR")
DATA_DIR="/var/lib/postgresql/${PG_VER}/main"

# Stop PostgreSQL
echo "Stopping PostgreSQL..."
sudo systemctl stop postgresql

# Delete Old Data
echo "Cleaning old data directory..."
sudo rm -rf ${DATA_DIR}/*

# Clone Primary Node Data
echo "Cloning data from primary..."
sudo -u postgres PGPASSWORD="${REPL_PASS}" pg_basebackup -h ${PRIMARY_IP} -D ${DATA_DIR} -U ${REPL_USER} -Fp -Xs -P -R

# Update Standby Node Config
echo "Updating standby configuration..."
sudo tee ${DATA_DIR}/postgresql.auto.conf >/dev/null <<EOF
primary_conninfo = 'host=${PRIMARY_IP} user=${REPL_USER} password=${REPL_PASS}'
primary_slot_name = 'replica2_slot'
EOF

# Allow external connections
echo "Configuring PostgreSQL to allow remote connections..."
sudo sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
sudo bash -c "echo 'host all all 0.0.0.0/0 md5' >> /etc/postgresql/*/main/pg_hba.conf"

# Enable and start PostgreSQL
sudo systemctl enable --now postgresql

echo "✅ PostgreSQL setup completed successfully!"
