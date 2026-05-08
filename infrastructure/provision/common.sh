# infra/provision/common.sh
set -euo pipefail

echo "[common] Mise à jour système..."
apt-get update -qq
apt-get upgrade -y -qq

echo "[common] Installation outils de base..."
apt-get install -y -qq \
  curl wget vim git \
  net-tools tcpdump \
  chrony

echo "[common] Configuration NTP (chrony)..."
systemctl enable chrony
systemctl start chrony

echo "[common] Désactivation swap agressif..."
echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p

echo "[common] Done."