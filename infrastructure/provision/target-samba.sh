#!/bin/bash
# infra/provision/target-samba.sh
# Déploie Samba sur la VM target Debian 12 pour le scénario S2.
# Exécuter directement sur la VM target via SSH :
#   ssh target@10.0.1.20
#   sudo bash target-samba.sh
#
# Prérequis : target.sh déjà exécuté (SSH, rsyslog, chrony en place)
# Décision : S1-D4 (vecteur exfiltration SMB), S1-D3 (RAM 1 Go maintenue)

set -euo pipefail

echo "[samba] Installation Samba..."
apt-get update -qq
apt-get install -y -qq samba

echo "[samba] Création des groupes Linux..."
groupadd -f direction
groupadd -f technique

echo "[samba] Création des utilisateurs..."
for user in dir1 dir2; do
    id "$user" >/dev/null 2>&1 || useradd -m -G direction -s /bin/bash "$user"
    echo "$user:Samba2026!" | chpasswd
    (echo "Samba2026!"; echo "Samba2026!") | smbpasswd -a "$user" >/dev/null 2>&1
    smbpasswd -e "$user" >/dev/null 2>&1
done

for user in tech1 tech2; do
    id "$user" >/dev/null 2>&1 || useradd -m -G technique -s /bin/bash "$user"
    echo "$user:Samba2026!" | chpasswd
    (echo "Samba2026!"; echo "Samba2026!") | smbpasswd -a "$user" >/dev/null 2>&1
    smbpasswd -e "$user" >/dev/null 2>&1
done

echo "[samba] Création des partages..."
mkdir -p /srv/samba/direction
mkdir -p /srv/samba/technique
mkdir -p /srv/samba/commun

chown root:direction /srv/samba/direction
chmod 2770 /srv/samba/direction

chown root:technique /srv/samba/technique
chmod 2770 /srv/samba/technique

chown root:users /srv/samba/commun
chmod 2777 /srv/samba/commun

echo "[samba] Écriture de smb.conf..."
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak 2>/dev/null || true

cat > /etc/samba/smb.conf <<'EOF'
[global]
   workgroup = WORKGROUP
   server string = TargetPME
   security = user
   map to guest = never
   restrict anonymous = 2
   min protocol = SMB2
   max protocol = SMB3
   smb encrypt = required
   logging = syslog
   syslog = 2
   syslog only = yes
   log file = /var/log/samba/log.%m
   max log size = 500

[direction]
   path = /srv/samba/direction
   valid users = @direction
   read only = no
   create mask = 0660
   directory mask = 2770

[technique]
   path = /srv/samba/technique
   valid users = @technique
   read only = no
   create mask = 0660
   directory mask = 2770

[commun]
   path = /srv/samba/commun
   valid users = @direction @technique
   read only = no
   create mask = 0664
   directory mask = 2777
EOF

echo "[samba] Extension pipeline rsyslog (daemon.*)..."
cat > /etc/rsyslog.d/50-forward.conf <<'EOF'
auth,authpriv.*  @10.0.1.10:514
syslog.*         @10.0.1.10:514
daemon.*         @10.0.1.10:514
EOF

systemctl restart rsyslog
systemctl enable --now smbd nmbd

echo "[samba] Validation..."
testparm -s 2>/dev/null | grep -E "^\[|encrypt|protocol|syslog" || true
systemctl is-active smbd && echo "[samba] smbd : actif" || echo "[samba] ERREUR : smbd inactif"
systemctl is-active nmbd && echo "[samba] nmbd : actif" || echo "[samba] ERREUR : nmbd inactif"

echo "[samba] Done."
echo ""
echo "Utilisateurs créés : dir1, dir2 (groupe direction) | tech1, tech2 (groupe technique)"
echo "Mot de passe Samba : Samba2026!"
echo "Partages : /direction /technique /commun"
echo ""
echo "Vérification depuis l'hôte :"
echo "  smbclient //10.0.1.20/direction -U dir1%Samba2026! -m SMB3 -c 'ls'"
