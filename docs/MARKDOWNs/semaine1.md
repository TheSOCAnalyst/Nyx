# Semaine 1 — Déploiement du laboratoire et validation du pipeline de logs

**Période** : 18 avril – 8 mai 2026  
**Statut** : Terminée

---

## Ce qui a été fait

- Déploiement de la VM SOC via Vagrant (box `bento/ubuntu-24.04`, provider libvirt)
- Création manuelle des VMs target (Debian 12), OPNsense 26.1.2 et attacker (Kali 2026.1)
  via virt-manager — abandon de Vagrant pour ces trois VMs (voir S1-D1)
- Configuration et validation du réseau isolé libvirt (`10.0.1.0/24`)
- Configuration du pipeline syslog SSH : target → SOC, validation end-to-end
- Snapshot OPNsense post-configuration (virt-manager, mode externe)
- Validation de la connectivité inter-VMs
- Résolution erreur démarrage VM : réseaux libvirt passés en autostart (voir Obstacle 6)
- IP target fixée en statique `10.0.1.20` — double IP DHCP+static résolue (voir Obstacle 7)
- Déploiement Samba sur target (2 partages privés + 1 commun, 4 utilisateurs, SMB3 chiffré)
- Extension pipeline syslog : ajout facility `daemon.*` pour transmission logs Samba → SOC
- Validation pipeline SMB end-to-end : connexions réussies et échecs NTLMv2 visibles sur SOC

---

## Topologie finale opérationnelle

| Composant | OS | RAM | IP lab | IP management | Rôle |
|---|---|---|---|---|---|
| Firewall | OPNsense 26.1.2 | 1 Go | 10.0.1.1 | — | Routage, logs pare-feu |
| SOC | Ubuntu Server 24.04 | 6 Go | 10.0.1.10 | 192.168.121.188 | Collecte logs, moteur Python |
| Target | Debian 12.13 | 1 Go | 10.0.1.20 | 192.168.121.23 | Cible SSH + Samba, logs auth+daemon |
| Attacker | Kali Linux 2026.1 | 2 Go | 10.0.1.190 | — | Simulation scénarios |

Réseau lab : `10.0.1.0/24`, réseau libvirt `isolated` (NAT vers hôte pour mises à jour).  
Réseau management : `192.168.121.0/24`, réseau libvirt `vagrant-libvirt`.

Note version OPNsense : plan initial prévoyait 24.7, version installée 26.1.2 (dernière
disponible à la date d'installation). Fonctionnellement identique pour ce projet.

---

## Décisions de déploiement

Voir `decisions.md` — entrées S1-D1 à S1-D5.

---

## Obstacles rencontrés et solutions

### Obstacle 1 — Box Vagrant introuvable (`generic/ubuntu2404` 404)

**Symptôme** :
```
The box 'generic/ubuntu2404' could not be found or
could not be accessed in the remote catalog. Error: 404
```

**Cause** : La box `generic/ubuntu2404` n'existe pas sur Vagrant Cloud.
Les boxes Roboxes (`generic/*`) pour Ubuntu 24.04 ont migré vers `bento/*`.

**Solution** : Remplacement par `bento/ubuntu-24.04` dans le Vagrantfile.

---

### Obstacle 2 — Réseau isolé absent, permission refusée sur la création du bridge

**Symptôme** :
```
error: Failed to start network isolated
error: error creating bridge interface virbr1: Operation not permitted
```

**Cause** : `virsh` sans argument se connecte à `qemu:///session` (scope utilisateur).
La création de bridges réseau nécessite `qemu:///system` (scope root/système).

**Solution** :
```bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc
virsh --connect qemu:///system net-define /tmp/isolated-net.xml
virsh --connect qemu:///system net-start isolated
virsh --connect qemu:///system net-autostart isolated
```

---

### Obstacle 3 — NFS échoue au montage `/vagrant`

**Symptôme** :
```
mount.nfs: Connection refused for 192.168.121.1:/home/.../infrastructure on /vagrant
```

**Cause** : vagrant-libvirt utilise NFS pour `/vagrant`. `nfs-server` inactif sur Fedora.

**Solution** : Remplacement par rsync dans le Vagrantfile :
```ruby
config.vm.synced_folder ".", "/vagrant", type: "rsync",
  rsync__exclude: [".git/", ".vagrant/"]
```

---

### Obstacle 4 — Box `generic/debian12` télécharge `ppc64le` au lieu d'`amd64`

**Symptôme** :
```
Downloading: .../providers/libvirt/ppc64le/vagrant.box
```

**Cause** : Bug vagrant-libvirt 0.11.2 + Vagrant 2.3.4 sur Fedora x86_64.

**Décision finale** : Abandon de Vagrant pour target, OPNsense et Kali (voir S1-D1).

---

### Obstacle 5 — Pipeline syslog silencieux : logs reçus mais non écrits

Trois sous-problèmes en cascade — voir `decisions.md` S1-D2 pour le détail complet.

**Config finale validée** (`/etc/rsyslog.d/10-remote.conf` sur SOC) :
```
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip startswith '10.0.1.' then ?RemoteLogs
& stop
```

---

### Obstacle 6 — VM target ne démarre pas : réseau `vagrant-libvirt` inactif

**Symptôme** :
```
Error starting domain: Requested operation is not valid:
network 'vagrant-libvirt' is not active
```

**Cause** : Réseaux libvirt non marqués autostart — inactifs après reboot Fedora.

**Solution** :
```bash
virsh --connect qemu:///system net-start vagrant-libvirt
virsh --connect qemu:///system net-start isolated
virsh --connect qemu:///system net-autostart vagrant-libvirt
virsh --connect qemu:///system net-autostart isolated
```

---

### Obstacle 7 — Double IP sur target : DHCP et statique simultanés sur enp2s0

**Symptôme** :
```
inet 10.0.1.137/24  dynamic    (bail DHCP existant, non tué)
inet 10.0.1.20/24   secondary  (static ajoutée par-dessus)
```

**Cause** : `systemctl restart networking` ajoute la nouvelle IP sans couper dhclient.

**Solution** :
```bash
sudo pkill dhclient
sudo ip addr del 10.0.1.137/24 dev enp2s0
ip addr show enp2s0
# inet 10.0.1.20/24 scope global enp2s0 (valid_lft forever)
```

**Config `/etc/network/interfaces` finale** :
```
auto lo
iface lo inet loopback

auto enp1s0
iface enp1s0 inet dhcp

auto enp2s0
iface enp2s0 inet static
    address 10.0.1.20
    netmask 255.255.255.0
    gateway 10.0.1.254
```

---

### Obstacle 8 — Logs Samba non transmis au SOC malgré `logging = syslog`

**Symptôme** : `/var/log/syslog` sur target contient bien les messages smbd,
mais `grep smb /var/log/remote/debian.log` ne retourne rien sur le SOC.

**Cause** : Samba émet ses messages via la facility `daemon` (hardcodé dans le
source C de smbd via `openlog(LOG_DAEMON)`). Le fichier `50-forward.conf` ne
transmettait que `auth,authpriv.*` et `syslog.*` — `daemon.*` était absent.

`syslog.*` capture les messages internes de rsyslog lui-même, pas les démons système.
`daemon.*` est la facility pour tous les services système génériques (smbd, nmbd, etc.).

**Solution** :
```bash
sudo tee /etc/rsyslog.d/50-forward.conf <<'EOF'
auth,authpriv.*  @10.0.1.10:514
syslog.*         @10.0.1.10:514
daemon.*         @10.0.1.10:514
EOF
sudo systemctl restart rsyslog
```

**Validation** :
```bash
# Depuis hôte
smbclient //10.0.1.20/direction -U dir1%MotDePasseFaux -m SMB3 -c "ls"

# Depuis SOC
grep "NT_STATUS_WRONG_PASSWORD" /var/log/remote/debian.log | tail -3
```

**À retenir** : Quand un service ne transmet pas ses logs malgré `logging = syslog`,
identifier sa facility dans `/var/log/syslog` puis l'ajouter à `50-forward.conf`.
Pour un lab SOC, transmettre `auth,authpriv.*` + `daemon.*` + `kern.*` couvre
90% des événements de sécurité pertinents.

---

## Configuration finale — target

### Samba (`/etc/samba/smb.conf`)

```ini
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
```

### rsyslog (`/etc/rsyslog.d/50-forward.conf`)

```
auth,authpriv.*  @10.0.1.10:514
syslog.*         @10.0.1.10:514
daemon.*         @10.0.1.10:514
```

### Utilisateurs et partages

| Utilisateur | Groupe | Partages accessibles |
|---|---|---|
| dir1 | direction | direction, commun |
| dir2 | direction | direction, commun |
| tech1 | technique | technique, commun |
| tech2 | technique | technique, commun |

Mot de passe Samba : `Samba2026!` (lab uniquement).

---

## Configuration finale rsyslog — SOC

### `/etc/rsyslog.d/10-remote.conf`

```
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip startswith '10.0.1.' then ?RemoteLogs
& stop
```

---

## Configuration OPNsense

### Interfaces assignées

| Interface | Carte | Réseau libvirt | IP |
|---|---|---|---|
| LAN | vtnet0 (52:54:00:97:5e:ee) | isolated | 10.0.1.1/24 |
| WAN | vtnet1 (52:54:00:e4:7d:70) | default (NAT) | DHCP |

### Syslog vers SOC (à configurer semaine 2)

```
System → Settings → Logging / Targets
Destination : 10.0.1.10:514 (UDP)
Niveau : Notice et supérieur
```

---

## Pourquoi chrony sur toutes les VMs

Le moteur de corrélation mesure des fenêtres temporelles précises :
- S1 : fenêtre de 60 secondes pour les échecs SSH
- S2 : fenêtre de 30 secondes pour le scan réseau

Une dérive de 5 secondes sur 60 secondes = 8% d'erreur → faux négatifs.

---

## Validation GO/NO-GO semaine 1

### SOC (Ubuntu 24.04)

```bash
chronyc tracking | grep "System time"     # NTP synchronisé
ss -ulnp | grep 514                        # rsyslog écoute UDP 514
python3 --version                          # Python 3.12.x
docker info 2>/dev/null | head -3          # Docker opérationnel
ls /var/log/remote/                        # Répertoire présent
```

Résultat : **5/5 GO** ✓

### Target (Debian 12)

```bash
ip addr show enp2s0                        # 10.0.1.20/24 statique
chronyc tracking | grep "System time"     # NTP synchronisé
cat /etc/rsyslog.d/50-forward.conf         # 3 facilities configurées
sudo sshd -T | grep passwordauthentication # yes
sudo systemctl is-active smbd             # active
```

Résultat : **5/5 GO** ✓

### Pipeline syslog SSH end-to-end

```bash
# Depuis target
logger -p auth.warning -t TEST "ip-statique-validee-10.0.1.20"
# Depuis SOC
grep "ip-statique-validee" /var/log/remote/debian.log
# 2026-05-05T03:40:40+00:00 debian TEST: ip-statique-validee-10.0.1.20
```

Résultat : **GO** ✓

### Pipeline syslog Samba end-to-end

```bash
# Depuis hôte — échec d'auth SMB
smbclient //10.0.1.20/direction -U dir1%MotDePasseFaux -m SMB3 -c "ls"
# Depuis SOC
grep "NT_STATUS_WRONG_PASSWORD" /var/log/remote/debian.log | tail -3
# 2026-05-08T03:52:43+00:00 debian smbd[1327]: ...NT_STATUS_WRONG_PASSWORD...
```

Résultat : **GO** ✓

### Isolation des partages Samba

```bash
# dir1 accède à direction
smbclient //10.0.1.20/direction -U dir1%Samba2026! -m SMB3 -c "ls"  # OK
# tech1 bloqué sur direction
smbclient //10.0.1.20/direction -U tech1%Samba2026! -m SMB3 -c "ls" # NT_STATUS_ACCESS_DENIED
# tech1 accède à commun
smbclient //10.0.1.20/commun -U tech1%Samba2026! -m SMB3 -c "ls"    # OK
```

Résultat : **3/3 GO** ✓

### Réseaux libvirt autostart

```bash
virsh --connect qemu:///system net-list --all
# isolated        active  yes
# vagrant-libvirt active  yes
```

Résultat : **GO** ✓

---

## Points d'attention pour la semaine 2

1. **Configurer syslog OPNsense → SOC** via l'interface web.
   Requis pour S2 (scan réseau détecté côté firewall).

2. **Snapshot SOC** avant le début du développement moteur (semaine 4).

3. **chrony sur target** — vérifier la synchronisation NTP avant génération des logs
   d'évaluation (semaine 3).

---

## Décisions documentées

Voir `decisions.md` — entrées S1-D1 à S1-D5.