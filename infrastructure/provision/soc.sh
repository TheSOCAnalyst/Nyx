# infra/provision/soc.sh
set -euo pipefail

source /vagrant/provision/common.sh

echo "[soc] Installation rsyslog + Python 3.12 + Docker..."
apt-get install -y -qq \
  rsyslog \
  python3 python3-pip python3-venv \
  docker.io docker-compose-v2

echo "[soc] Configuration rsyslog — écoute UDP 514..."
cat >> /etc/rsyslog.conf <<'EOF'

# Réception logs distants
module(load="imudp")
input(type="imudp" port="514")
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip != '127.0.0.1' then ?RemoteLogs
& stop
EOF

mkdir -p /var/log/remote
systemctl restart rsyslog

echo "[soc] Ajout utilisateur vagrant au groupe docker..."
usermod -aG docker vagrant

echo "[soc] Environnement Python du moteur..."
cd /home/vagrant
python3 -m venv .venv
.venv/bin/pip install --quiet \
  "pyyaml>=6.0" \
  "watchdog>=4.0" \
  "jsonschema>=4.0" \
  "pytest>=8.0"

echo "[soc] Done."