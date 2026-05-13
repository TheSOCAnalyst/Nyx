# Semaine 1 — Déploiement du laboratoire et validation du pipeline de logs

**Période** : 18 avril – 11 mai 2026  
**Statut** : Terminée

---

## Ce qui a été fait

- Déploiement de la VM SOC via Vagrant (box `bento/ubuntu-24.04`, provider libvirt)
- Création manuelle des VMs target (Debian 12), OPNsense et attacker (Kali 2026.1)
  via virt-manager — abandon de Vagrant pour ces trois VMs (voir S1-D1)
- Configuration et validation du réseau isolé libvirt (`10.0.1.0/24`)
- Configuration du pipeline syslog SSH : target → SOC, validation end-to-end
- IP target fixée en statique `10.0.1.20` — double IP DHCP+static résolue (voir Obstacle 7)
- Déploiement Samba sur target (2 partages privés + 1 commun, 4 utilisateurs, SMB3 chiffré)
- Extension pipeline syslog : ajout facility `daemon.*` pour transmission logs Samba → SOC
- Validation pipeline SMB end-to-end : connexions réussies et échecs NTLMv2 visibles sur SOC
- Validation chrony sur target et Kali
- Validation outils Kali (nmap, hydra, crackmapexec, smbclient)
- IP Kali fixée en statique `10.0.1.50` sur `eth1` (voir S1-D6)
- Installation propre OPNsense 26.1.6 sur disque qcow2 dédié (voir Obstacles 9–14 et S1-D7)
- Configuration LAN OPNsense : `10.0.1.1/24`, WAN DHCP (NAT libvirt)
- Configuration syslog OPNsense → SOC : UDP, 10.0.1.10:514, toutes facilities/niveaux
- Validation pipeline syslog OPNsense → SOC : filterlog visible sur SOC
- Snapshots `post-semaine1` sur les 4 VMs

---

## Topologie finale opérationnelle

| Composant | OS | RAM | IP lab | IP management | Rôle |
|---|---|---|---|---|---|
| Firewall | OPNsense 26.1.6 | 1 Go | 10.0.1.1 | — | Routage, logs pare-feu |
| SOC | Ubuntu Server 24.04 | 6 Go | 10.0.1.10 | 192.168.121.188 | Collecte logs, moteur Python |
| Target | Debian 12.13 | 1 Go | 10.0.1.20 | 192.168.121.23 | Cible SSH + Samba, logs auth+daemon |
| Attacker | Kali Linux 2026.1 | 2 Go | 10.0.1.50 | 192.168.121.69 | Simulation scénarios |

Réseau lab : `10.0.1.0/24`, réseau libvirt `isolated`.  
Réseau management : `192.168.121.0/24`, réseau libvirt `vagrant-libvirt`.  
Noms de domaine libvirt : `infrastructure_soc`, `debian12`, `Kali`, `Opnsense`.

Note version OPNsense : plan initial prévoyait 24.7, version installée 26.1.6 (dernière
disponible à la date de réinstallation). Fonctionnellement identique pour ce projet.

---

## Décisions de déploiement

Voir `decisions.md` — entrées S1-D1 à S1-D7.

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

**Solution** :
```bash
sudo tee /etc/rsyslog.d/50-forward.conf <<'EOF'
auth,authpriv.*  @10.0.1.10:514
syslog.*         @10.0.1.10:514
daemon.*         @10.0.1.10:514
EOF
sudo systemctl restart rsyslog
```

---

### Obstacle 9 — OPNsense tourne en live media : configuration non persistée

**Symptôme** : Bannière au login web :
```
You are currently running in live media mode.
A reboot will reset the configuration.
```
Toute configuration IP ou syslog disparaît au reboot.

**Cause** : La VM OPNsense avait été créée en pointant directement sur le fichier
`.img` comme disque source (avec backing store). Il n'y avait pas de disque virtuel
dédié — OPNsense tournait en read-only depuis l'image live, les écritures étaient
perdues à chaque arrêt.

**Diagnostic** :
```bash
virsh --connect qemu:///system domblklist Firewall
# Target   Source
# vda      /home/gael/Downloads/OPNsense-26.1.2-vga-amd64.post-install-base
```

**Solution** : installation propre sur disque dédié (voir Obstacles 10–14).

---

### Obstacle 10 — Installateur VGA refuse le disque : taille minimale non satisfaite

**Symptôme** :
```
The minimum size 4GB was not met
```

**Cause** : Le seul disque visible (`vtbd0`) était l'image live de 2 Go — pas un
disque d'installation cible. L'installateur VGA cherche un disque cible distinct.

**Tentative** : ajout d'un disque qcow2 de 8 Go via `attach-disk` à chaud.
L'installateur voyait bien `vtbd1` (8 Go), mais échouait avec `Partition destroy failed`
car le disque avait été attaché pendant que la VM tournait (kernel FreeBSD ne le
voit pas proprement pour le partitionnement).

**Décision** : abandonner l'image VGA live, utiliser l'ISO DVD standard (voir S1-D7).

---

### Obstacle 11 — Suppression VM bloquée : snapshot existant + volume non managé

**Symptôme** :
```
error: Requested operation is not valid: cannot delete inactive domain
with 1 snapshots
error: Storage volume 'vdb' is not managed by libvirt. Remove it manually.
```

**Solution** :
```bash
# Supprimer le snapshot bloquant
virsh --connect qemu:///system snapshot-delete Firewall --snapshotname post-install-base

# Supprimer le disque ajouté manuellement
sudo rm /var/lib/libvirt/images/opnsense.qcow2

# Undefine — le volume vda (.img) est supprimé automatiquement
virsh --connect qemu:///system undefine Firewall --remove-all-storage
```

Le message d'erreur résiduel sur `vdb` est sans conséquence (fichier déjà supprimé).

---

### Obstacle 12 — ISO DVD décompressée introuvable : `.img.bz2` uniquement disponible

**Symptôme** : Seul `/home/gael/Downloads/OPNsense-26.1.2-vga-amd64.img.bz2` restait.
L'image `.img` avait été supprimée par `undefine --remove-all-storage`.

**Solution** : Téléchargement et décompression de l'ISO DVD :
```bash
# (téléchargement préalable)
bunzip2 -k OPNsense-26.1.6-dvd-amd64.iso.bz2
# Résultat : OPNsense-26.1.6-dvd-amd64.iso (~900 Mo)
```

Note : version 26.1.6 au lieu de 26.1.2 — plus récente, fonctionnellement identique.

---

### Obstacle 13 — VM ne boote pas après installation : `No bootable device`

**Symptôme** :
```
Boot failed: Could not read from CDROM (code 0003)
No bootable device.
```

**Cause** : L'ISO DVD était encore référencée comme CDROM dans la config VM.
La VM essayait de booter sur le CDROM (déconnecté après installation) avant le disque.

**Solution** : Dans virt-manager → Boot Options :
- `VirtIO Disk 1` en premier dans l'ordre de boot
- `SATA CDROM 1` : déconnecter le media (vider la source)

---

### Obstacle 14 — Partition scheme : `Partition destroy failed` avec GPT sur disque vierge

**Symptôme** : L'installateur DVD (FreeBSD bsdinstall) échouait lors du partitionnement
avec GPT sur le disque `vtbd0`.

**Cause probable** : Schéma GPT incompatible avec le mode BIOS legacy (SeaBIOS)
de la VM KVM. La VM démarrait en mode BIOS, pas UEFI.

**Solution** : Sélectionner **MBR** (DOS Partitions) au lieu de GPT dans
l'écran "Partition Scheme". MBR est compatible SeaBIOS sans configuration UEFI.

**Résultat** : Installation complète, reboot sur disque, LAN `10.0.1.1/24` persisté. ✓

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

### rsyslog target (`/etc/rsyslog.d/50-forward.conf`)

```
auth,authpriv.*  @10.0.1.10:514   # SSH, PAM, sudo
syslog.*         @10.0.1.10:514   # Messages internes rsyslog
daemon.*         @10.0.1.10:514   # Samba (smbd, nmbd) et autres démons
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

## Configuration finale — SOC

### `/etc/rsyslog.d/10-remote.conf`

```
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip startswith '10.0.1.' then ?RemoteLogs
& stop
```

### Permissions `/var/log/remote/`

```bash
chown syslog:adm /var/log/remote/
chmod 755 /var/log/remote/
```

---

## Configuration finale — OPNsense

### Interfaces

| Interface | Carte | Réseau libvirt | IP |
|---|---|---|---|
| LAN | vtnet0 | isolated | 10.0.1.1/24 |
| WAN | vtnet1 | default (NAT) | DHCP (192.168.122.x) |

### Syslog remote (System → Settings → Logging → Remote)

| Champ | Valeur |
|---|---|
| Enabled | ✓ |
| Transport | UDP(4) |
| Hostname | 10.0.1.10 |
| Port | 514 |
| Levels | debug, info, notice, warn, error, critical, alert, emergency |
| Facilities | toutes (Nothing selected = all) |
| Applications | toutes (Nothing selected = all) |

Note : tous les niveaux sélectionnés pour le lab — filtrage des niveaux
non pertinents (debug, info) délégué au moteur Python.

Format des logs firewall reçus sur SOC (`filterlog`) :
```
2026-05-11T22:17:16+00:00 OPNsense.internal filterlog[56373]:
76,,,uuid,vtnet1,match,pass,out,4,0xb8,,64,29973,0,none,17,udp,76,
192.168.122.114,176.97.192.150,123,123,56
```

---

## Validation GO/NO-GO — état final semaine 1

### SOC (Ubuntu 24.04)

```bash
chronyc tracking | grep "System time"     # NTP synchronisé
ss -ulnp | grep 514                        # rsyslog écoute UDP 514
python3 --version                          # Python 3.12.x
docker info 2>/dev/null | head -3          # Docker opérationnel
ls -ld /var/log/remote/                    # drwxr-xr-x syslog adm
```

Résultat : **5/5 GO** ✓

### Target (Debian 12)

```bash
ip addr show enp2s0                        # 10.0.1.20/24 statique
chronyc tracking | grep "System time"     # 0.000000006 seconds slow ✓
cat /etc/rsyslog.d/50-forward.conf         # 3 facilities configurées
sudo sshd -T | grep passwordauthentication # yes
sudo systemctl is-active smbd             # active
```

Résultat : **5/5 GO** ✓

### Kali (2026.1)

```bash
ip addr show eth1                          # 10.0.1.50/24 statique ✓
chronyc tracking | grep "System time"     # 0.000081799 seconds fast ✓
which nmap hydra crackmapexec smbclient   # /usr/bin/* tous présents ✓
nmap --version                            # 7.99 ✓
```

Résultat : **4/4 GO** ✓

### OPNsense (26.1.6)

```
Console : LAN (vtnet0) -> v4: 10.0.1.1/24   ✓ (persisté après reboot)
Web GUI  : https://10.0.1.1 accessible        ✓
Syslog remote configuré vers 10.0.1.10:514   ✓
```

Résultat : **3/3 GO** ✓

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
# Depuis hôte
smbclient //10.0.1.20/direction -U dir1%MotDePasseFaux -m SMB3 -c "ls"
# Depuis SOC
grep "NT_STATUS_WRONG_PASSWORD" /var/log/remote/debian.log | tail -3
# 2026-05-08T03:52:43+00:00 debian smbd[1327]: ...NT_STATUS_WRONG_PASSWORD...
```

Résultat : **GO** ✓

### Pipeline syslog OPNsense end-to-end

```bash
# Depuis SOC
tail -f /var/log/remote/OPNsense.internal.log
# 2026-05-11T22:17:16+00:00 OPNsense.internal filterlog[56373]: ...
```

Résultat : **GO** ✓

### Snapshots

```bash
virsh --connect qemu:///system snapshot-list --domain infrastructure_soc
virsh --connect qemu:///system snapshot-list --domain debian12
virsh --connect qemu:///system snapshot-list --domain Kali
virsh --connect qemu:///system snapshot-list --domain Opnsense
# post-semaine1 présent sur les 4 VMs
```

Résultat : **4/4 GO** ✓

---

## Pourquoi chrony sur toutes les VMs

Le moteur de corrélation mesure des fenêtres temporelles précises :
- S1 : fenêtre de 60 secondes pour les échecs SSH
- S2 : fenêtre de 30 secondes pour le scan réseau

Une dérive de 5 secondes sur 60 secondes = 8% d'erreur → faux négatifs.

OPNsense synchronise via ntpd intégré (service non exposé via `rc.d` standard —
vérification indirecte : paquets UDP port 123 visibles dans filterlog).

---

## Décisions documentées

Voir `decisions.md` — entrées S1-D1 à S1-D7.
