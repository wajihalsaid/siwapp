
# Set Hostname
echo "Setting hostname to ${HOSTNAME}..."
sudo hostnamectl set-hostname "${HOSTNAME}"

# Update system packages
echo "Updating system..."
sudo apt update -y

# Install PostgreSQL
echo "Installing PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

# Enable and start PostgreSQL
sudo systemctl enable --now postgresql

# Create database role and database
echo "Creating PostgreSQL role and database..."
sudo -u postgres psql -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';"
sudo -u postgres psql -c "CREATE ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD '${REPL_PASS}';"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER} ENCODING 'UTF8';"
sudo -u postgres psql -c "SELECT * FROM pg_create_physical_replication_slot('replica2_slot');"
sudo -u postgres psql -c "SELECT * FROM pg_create_physical_replication_slot('replica3_slot');"


# Allow external connections
echo "Configuring PostgreSQL to allow remote connections..."
sudo sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
sudo bash -c "echo 'host all all 0.0.0.0/0 md5' >> /etc/postgresql/*/main/pg_hba.conf"

# Configure Replication
sudo tee -a /etc/postgresql/*/main/postgresql.conf >/dev/null <<EOF
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
EOF
sudo bash -c "echo 'host replication all 0.0.0.0/0 md5' >> /etc/postgresql/*/main/pg_hba.conf"

# Restart PostgreSQL
echo "Restarting PostgreSQL service..."
sudo systemctl restart postgresql

echo "✅ PostgreSQL setup completed successfully!"
