
# Set Hostname
echo "Setting hostname to ${HOSTNAME}..."
sudo hostnamectl set-hostname "${HOSTNAME}"

# ===============================
# Update & Install Dependencies
# ===============================
sudo apt update
sudo apt install -y wget gnupg git erlang elixir libpq-dev postgresql-client nginx openssl

# ===============================
# Install Google Chrome
# ===============================
wget -qO - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list'
sudo apt update
sudo apt install -y google-chrome-stable

# ===============================
# Create App User & Directory
# ===============================
sudo adduser --disabled-login --gecos 'Siwapp App' "$APP_USER"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ===============================
# Clone Siwapp Repo
# ===============================
sudo -u "$APP_USER" -H bash -c "git clone 'https://github.com/siwapp/siwapp.git' '$APP_DIR'"

# ===============================
# Configure PDF Options
# ===============================
sudo sed -i '/^config :siwapp, *$/{
    N
    s/env: :prod$/env: :prod,/
    a\
  pdf_opts: [\
    no_sandbox: true,\
    discard_stderr: true,\
    chrome_executable: \"/usr/bin/google-chrome\"\
  ]
}' "$APP_DIR/config/prod.exs"

# ===============================
# Install & Compile App
# ===============================
sudo -u "$APP_USER" -H bash -c "
export MIX_ENV=$MIX_ENV
export RELEASE_NODE=$RELEASE_NODE
export DATABASE_URL=ecto://$APP_USER:$DB_PASSWORD@$DB_HOST/siwapp_prod
export PHX_HOST=$PHX_HOST
export PORT=$PORT
cd $APP_DIR
mix local.hex --force
mix local.rebar --force
MIX_ENV=$MIX_ENV mix deps.get
MIX_ENV=$MIX_ENV mix deps.compile
MIX_ENV=$MIX_ENV mix assets.deploy
MIX_ENV=$MIX_ENV mix phx.digest
MIX_ENV=$MIX_ENV mix compile
"

# ===============================
# Generate SECRET_KEY_BASE
# ===============================
sudo -u "$APP_USER" -H bash -c "export DATABASE_URL=ecto://$APP_USER:$DB_PASSWORD@$DB_HOST/siwapp_prod && cd $APP_DIR && MIX_ENV=$MIX_ENV mix phx.gen.secret" > /tmp/siwapp_secret
SECRET_KEY_BASE=$(cat /tmp/siwapp_secret)

# ===============================
# Setup Database & Release
# ===============================
sudo -u "$APP_USER" -H bash -c "
export MIX_ENV=$MIX_ENV
export RELEASE_NODE=$RELEASE_NODE
export DATABASE_URL=ecto://$APP_USER:$DB_PASSWORD@$DB_HOST/siwapp_prod
export SECRET_KEY_BASE=$SECRET_KEY_BASE
export PHX_HOST=$PHX_HOST
export PORT=$PORT
cd $APP_DIR
MIX_ENV=$MIX_ENV mix ecto.create
MIX_ENV=$MIX_ENV mix ecto.migrate
MIX_ENV=$MIX_ENV mix release
"

# ===============================
# Change Favicon
# ===============================
sudo -u "$APP_USER" -H bash -c "
wget -q --no-cache -O $APP_DIR/priv/static/favicon.ico https://raw.githubusercontent.com/wajihalsaid/siwapp/refs/heads/main/favicon.ico
wget -q --no-cache -O $APP_DIR/_build/prod/rel/siwapp/lib/phoenix-*/priv/static/favicon.ico https://raw.githubusercontent.com/wajihalsaid/siwapp/refs/heads/main/favicon.ico
wget -q --no-cache -O $APP_DIR/_build/prod/rel/siwapp/lib/siwapp-*/priv/static/favicon.ico https://raw.githubusercontent.com/wajihalsaid/siwapp/refs/heads/main/favicon.ico
wget -q --no-cache -O $APP_DIR/deps/phoenix/priv/static/favicon.ico https://raw.githubusercontent.com/wajihalsaid/siwapp/refs/heads/main/favicon.ico
"

# ===============================
# Create Demo Data
# ===============================
sudo -u "$APP_USER" -H bash -c "
export SECRET_KEY_BASE=$SECRET_KEY_BASE
export DATABASE_URL=ecto://$APP_USER:$DB_PASSWORD@$DB_HOST/siwapp_prod
cd $APP_DIR
MIX_ENV=$MIX_ENV mix siwapp.demo force
"

# ===============================
# Environment File
# ===============================
sudo tee /etc/default/siwapp > /dev/null <<EOF
MIX_ENV=$MIX_ENV
RELEASE_NODE=$RELEASE_NODE
DATABASE_URL=ecto://$APP_USER:$DB_PASSWORD@$DB_HOST/siwapp_prod
SECRET_KEY_BASE=$SECRET_KEY_BASE
PHX_HOST=$PHX_HOST
PORT=$PORT
EOF

# ===============================
# Systemd Service
# ===============================
sudo tee /etc/systemd/system/siwapp.service >/dev/null <<'EOF'
[Unit]
Description=Siwapp Phoenix app (release)
After=network.target

[Service]
User=siwapp
Group=siwapp
EnvironmentFile=/etc/default/siwapp
WorkingDirectory=/var/www/siwapp
ExecStart=/var/www/siwapp/_build/prod/rel/siwapp/bin/siwapp start
ExecStop=/var/www/siwapp/_build/prod/rel/siwapp/bin/siwapp stop
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now siwapp

# ===============================
# SSL Self-Signed Certificate
# ===============================
sudo tee /tmp/siwapp_openssl.cnf > /dev/null <<EOF
[req]
distinguished_name=req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = SanFrancisco
O = Siwapp
OU = Dev
CN = $SSL_CN

[v3_req]
subjectAltName = DNS:$SSL_CN,DNS:$SSL_IP
EOF

sudo mkdir -p "$SSL_DIR"
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$SSL_DIR/siwapp.key" \
  -out "$SSL_DIR/siwapp.crt" \
  -config /tmp/siwapp_openssl.cnf \
  -extensions v3_req

# ===============================
# Server ID
# ===============================
sudo mkdir -p /var/www/siwapp/assets/custom
sudo tee /var/www/siwapp/assets/custom/backend_id.js > /dev/null <<EOF
document.addEventListener("DOMContentLoaded", function () {
  const host = "${HOSTNAME}";
  const srv = document.cookie
    .split('; ')
    .find(row => row.startsWith('SRV_ID='))
    ?.split('=')[1];
  const label = host || srv;

  if (label) {
    const div = document.createElement("div");
    div.textContent = label;
    div.style.position = "fixed";
    div.style.top = "60px";        // moved down a bit
    div.style.right = "10px";
    div.style.background = "rgba(0,0,0,0.6)";
    div.style.color = "#fff";
    div.style.padding = "4px 8px";  // smaller padding
    div.style.borderRadius = "4px";
    div.style.fontSize = "10px";    // smaller font
    div.style.zIndex = "99999";
    div.style.fontFamily = "Arial, sans-serif";
    document.body.appendChild(div);
  }
});
EOF

# ===============================
# Nginx Reverse Proxy
# ===============================
sudo tee /etc/nginx/sites-available/siwapp.conf > /dev/null <<EOF
server {
    listen ${HTTP_PORT};
    listen [::]:${HTTP_PORT};
    server_name _;

    client_max_body_size 50M;

    location / {
        sub_filter '</body>' '<script src="/assets/custom/backend_id.js"></script></body>';
        sub_filter_once on;
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;

        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 300s;
    }

    location /assets/ {
        alias /var/www/siwapp/priv/static/assets/;
        gzip_static on;
        expires max;
        add_header Cache-Control "public";
    }
    location /assets/custom/ {
        alias /var/www/siwapp/assets/custom/;
    }
}

server {
    listen ${HTTPS_PORT} ssl http2;
    listen [::]:${HTTPS_PORT} ssl http2;
    server_name _;

    ssl_certificate ${SSL_DIR}/siwapp.crt;
    ssl_certificate_key ${SSL_DIR}/siwapp.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 10m;

    client_max_body_size 50M;
    keepalive_timeout 65;

    location / {   
        sub_filter '</body>' '<script src="/assets/custom/backend_id.js"></script></body>';
        sub_filter_once on;
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;

        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 300s;
    }

    location /assets/ {
        alias /var/www/siwapp/priv/static/assets/;
        gzip_static on;
        expires max;
        add_header Cache-Control "public";
    }
    location /assets/custom/ {
        alias /var/www/siwapp/assets/custom/;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/siwapp.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

echo "NGINX configured on ports $HTTP_PORT (HTTP) and $HTTPS_PORT (HTTPS)"

echo "Siwapp installation completed successfully!"
