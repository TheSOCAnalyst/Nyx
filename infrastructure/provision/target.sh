# infra/provision/target.sh
set -euo pipefail

source /vagrant/provision/common.sh

echo "[target] Installation SSH + rsyslog..."
apt-get install -y -qq openssh-server rsyslog

echo "[target] Configuration forwarding syslog vers SOC..."
cat > /etc/rsyslog.d/50-forward.conf <<'EOF'
auth,authpriv.* @10.0.1.10:514
EOF

systemctl restart rsyslog
systemctl enable ssh

echo "[target] Autorisation connexions SSH par mot de passe (pour les tests brute-force)..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

echo "[target] Done."