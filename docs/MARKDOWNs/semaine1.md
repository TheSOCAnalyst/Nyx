# Semaine 1 — Déploiement du laboratoire et validation du pipeline de logs

**Période** : 18 avril – 5 mai 2026  
**Statut** : Terminée

---

## Ce qui a été fait

- Déploiement de la VM SOC via Vagrant (box `bento/ubuntu-24.04`, provider libvirt)
- Création manuelle des VMs target (Debian 12), OPNsense 26.1.2 et attacker (Kali 2026.1)
  via virt-manager — abandon de Vagrant pour ces trois VMs (voir S1-D1)
- Configuration et validation du réseau isolé libvirt (`10.0.1.0/24`)
- Configuration du pipeline syslog : target → SOC, validation end-to-end
- Snapshot OPNsense post-configuration (virt-manager, mode externe)
- Validation de la connectivité inter-VMs
- Résolution erreur démarrage VM : réseaux libvirt `isolated` et `vagrant-libvirt` passés en autostart (voir Obstacle 6)
- IP target fixée en statique `10.0.1.20` — double IP DHCP+static résolue (voir Obstacle 7)
- Pipeline syslog re-validé sur la nouvelle IP statique

---

## Topologie finale opérationnelle

| Composant | OS | RAM | IP lab | IP management | Rôle |
|---|---|---|---|---|---|
| Firewall | OPNsense 26.1.2 | 1 Go | 10.0.1.1 | — | Routage, logs pare-feu |
| SOC | Ubuntu Server 24.04 | 6 Go | 10.0.1.10 | 192.168.121.188 | Collecte logs, moteur Python |
| Target | Debian 12.13 | 1 Go | 10.0.1.20 | 192.168.121.23 | Cible SSH, logs auth |
| Attacker | Kali Linux 2026.1 | 2 Go | 10.0.1.190 | — | Simulation scénarios |

Réseau lab : `10.0.1.0/24`, réseau libvirt `isolated` (NAT vers hôte pour mises à jour).  
Réseau management : `192.168.121.0/24`, réseau libvirt `vagrant-libvirt`.

Note version OPNsense : plan initial prévoyait 24.7, version installée 26.1.2 (dernière
disponible à la date d'installation). Fonctionnellement identique pour ce projet.

---

## Décisions de déploiement

Voir `decisions.md` — entrées S1-D1 et S1-D2.

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
Vérification préalable via l'API :
```bash
curl -s "https://vagrantcloud.com/api/v2/vagrant/bento/ubuntu-24.04" \
  | python3 -m json.tool | grep '"name"'
# Confirme la présence du provider libvirt amd64
```

---

### Obstacle 2 — Réseau isolé absent, permission refusée sur la création du bridge

**Symptôme** :
```
Network 10.0.1.10 is not available.
error: Failed to start network isolated
error: error creating bridge interface virbr1: Operation not permitted
```

**Cause** : `virsh` sans argument se connecte à `qemu:///session` (scope utilisateur).
La création de bridges réseau nécessite `qemu:///system` (scope root/système).

**Diagnostic** :
```bash
virsh uri
# Retournait qemu:///session au lieu de qemu:///system
```

**Solution** :
```bash
# Variable d'environnement permanente
export LIBVIRT_DEFAULT_URI="qemu:///system"
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc

# Création du réseau avec la bonne connexion
virsh --connect qemu:///system net-define /tmp/isolated-net.xml
virsh --connect qemu:///system net-start isolated
virsh --connect qemu:///system net-autostart isolated
```

**Contenu de `/tmp/isolated-net.xml`** :
```xml
<network>
  <name>isolated</name>
  <bridge name="virbr2"/>
  <forward mode='nat'/>
  <ip address="10.0.1.254" netmask="255.255.255.0">
    <dhcp>
      <range start="10.0.1.100" end="10.0.1.200"/>
    </dhcp>
  </ip>
</network>
```

Note : `forward mode='nat'` conservé (accès Internet temporaire pour mises à jour).
Gateway `10.0.1.254` libère `.1` pour OPNsense. Plage DHCP `100–200` évite les
collisions avec les IPs statiques prévues (`.10`, `.20`, `.50`).

**À retenir** : Sur Fedora avec KVM, toujours utiliser `qemu:///system`.

---

### Obstacle 3 — NFS échoue au montage `/vagrant`

**Symptôme** :
```
mount.nfs: Connection refused for 192.168.121.1:/home/.../infrastructure on /vagrant
```

**Cause** : vagrant-libvirt tente de monter le répertoire de travail via NFS par défaut.
Le daemon `nfs-server` n'est pas actif sur Fedora par défaut.

**Solution retenue** : Remplacement de NFS par rsync dans le Vagrantfile.
rsync est unidirectionnel (hôte → VM) ce qui est suffisant pour les scripts de provisioning.
```ruby
config.vm.synced_folder ".", "/vagrant", type: "rsync",
  rsync__exclude: [".git/", ".vagrant/"]
```

---

### Obstacle 4 — Box `generic/debian12` télécharge une image `ppc64le` au lieu d'`amd64`

**Symptôme** : La VM target démarre mais ne répond pas (mauvaise architecture).
Dans les logs :
```
Downloading: .../providers/libvirt/ppc64le/vagrant.box
```

**Cause** : Bug de sélection d'architecture dans vagrant-libvirt 0.11.2 + Vagrant 2.3.4.
Pour certaines boxes `generic/*`, vagrant-libvirt sélectionne `ppc64le` (PowerPC)
au lieu d'`amd64` sur les hôtes Fedora x86_64.

**Décision finale** : Ce bug, combiné aux obstacles 2 et 3, a conduit à l'abandon de
Vagrant pour target, OPNsense et Kali (voir S1-D1).

---

### Obstacle 5 — Pipeline syslog silencieux : logs reçus mais non écrits

Trois sous-problèmes distincts en cascade.

#### 5a — Ordre de chargement rsyslog (règle écrasée par 50-default.conf)

**Symptôme** : `tcpdump` confirme la réception des paquets UDP 514, mais
`/var/log/remote/` reste vide.

**Cause** : rsyslog charge les fichiers `/etc/rsyslog.d/*.conf` par ordre alphanumérique.
`50-default.conf` consommait les messages distants avant que la règle `RemoteLogs`
(définie dans `rsyslog.conf`) soit évaluée.

**Solution** : Template + règle dans `/etc/rsyslog.d/10-remote.conf` (chargé avant `50-default.conf`) :
```bash
sudo tee /etc/rsyslog.d/10-remote.conf <<'EOF'
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip startswith '10.0.1.' then ?RemoteLogs
& stop
EOF
```

Note : `$fromhost-ip startswith '10.0.1.'` filtre positivement sur le sous-réseau lab.

#### 5b — Template non trouvé (définition et usage dans des fichiers différents)

**Symptôme** :
```
rsyslogd: Could not find template 1 'RemoteLogs' - action disabled
```

**Cause** : Template dans `rsyslog.conf`, règle dans `10-remote.conf` — référence avant
définition dans l'ordre de chargement.

**Règle** : En rsyslog, template et règle qui l'utilise doivent être dans le même fichier.

#### 5c — Permission denied (répertoire appartenant à root, rsyslog tourne sous syslog)

**Symptôme** :
```
rsyslogd: file '/var/log/remote/debian.log': open error: Permission denied
```

**Cause** : `/var/log/remote/` créé par `soc.sh` avec `mkdir -p` (propriétaire `root:root`).
rsyslog tourne sous l'utilisateur `syslog` (groupe `adm`).

**Solution** :
```bash
sudo chown -R syslog:adm /var/log/remote/
sudo chmod 755 /var/log/remote/
```

**Correction apportée à `soc.sh`** : ajouter après `mkdir -p /var/log/remote/` :
```bash
chown syslog:adm /var/log/remote/
chmod 755 /var/log/remote/
```

---

### Obstacle 6 — VM target ne démarre pas : réseau `vagrant-libvirt` inactif

**Symptôme** :
```
Error starting domain: Requested operation is not valid:
network 'vagrant-libvirt' is not active
```

**Cause** : libvirt vérifie que tous les réseaux déclarés dans la config XML d'une VM
sont actifs avant de la démarrer. Au reboot de Fedora, les réseaux libvirt ne se
relancent pas automatiquement sauf s'ils sont marqués `autostart`.

**Solution** :
```bash
virsh --connect qemu:///system net-start vagrant-libvirt
virsh --connect qemu:///system net-start isolated
virsh --connect qemu:///system net-autostart vagrant-libvirt
virsh --connect qemu:///system net-autostart isolated
```

**Vérification** :
```bash
virsh --connect qemu:///system net-list --all
# Colonne Autostart : "yes" pour isolated et vagrant-libvirt
```

---

### Obstacle 7 — Double IP sur target : DHCP et statique simultanés sur enp2s0

**Symptôme** : Après ajout de la config statique dans `/etc/network/interfaces` et
`systemctl restart networking`, `ip addr show` affichait deux IPs sur `enp2s0` :
```
inet 10.0.1.137/24  dynamic    (bail DHCP existant, non tué)
inet 10.0.1.20/24   secondary  (static ajoutée par-dessus)
```

**Cause** : `systemctl restart networking` ajoute la nouvelle IP sans couper le bail
DHCP en cours. `dhclient` continuait de maintenir `.137` comme IP primaire.

**Solution** :
```bash
# Tuer dhclient (dhclient -r bloque indéfiniment sur ce réseau)
sudo pkill dhclient

# Supprimer l'IP DHCP résiduelle
sudo ip addr del 10.0.1.137/24 dev enp2s0

# Vérifier
ip addr show enp2s0
# inet 10.0.1.20/24 scope global enp2s0  (valid_lft forever, pas de "secondary")
```

**Config `/etc/network/interfaces` finale** :
```
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Management (vagrant-libvirt)
auto enp1s0
iface enp1s0 inet dhcp

# Lab isolé — IP statique définitive
auto enp2s0
iface enp2s0 inet static
    address 10.0.1.20
    netmask 255.255.255.0
    gateway 10.0.1.254
```

`enp1s0` déclarée explicitement en DHCP pour éviter toute ambiguïté au boot.
`enp1s0` (vagrant-libvirt) n'intervient pas dans le pipeline lab — SSH hôte → target
passe par `enp2s0` (`ssh target@10.0.1.20`).

**À retenir** : `ip addr del` modifie l'état courant du kernel uniquement — disparaît
au reboot. La persistance est dans `/etc/network/interfaces`. Un bail DHCP a deux
composantes indépendantes : le processus `dhclient` et l'IP assignée dans le kernel.
Tuer l'un ne supprime pas l'autre automatiquement.

---

## Configuration finale rsyslog

### Sur le SOC (`/etc/rsyslog.d/10-remote.conf`)

```
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip startswith '10.0.1.' then ?RemoteLogs
& stop
```

### Sur target (`/etc/rsyslog.d/50-forward.conf`)

```
auth,authpriv.* @10.0.1.10:514
```

Seuls `auth,authpriv` transmis : pertinents pour S1 (brute-force SSH), extension
possible pour S2 si nécessaire.

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

Une dérive de 5 secondes sur une fenêtre de 60 secondes = 8% d'erreur → faux négatifs.
`chrony` préféré à `ntpd` : convergence plus rapide après reboot, meilleure gestion
des horloges virtuelles KVM.

```bash
sudo apt-get install -y chrony
sudo systemctl enable --now chrony
chronyc tracking | grep "System time"
```

---

## Validation GO/NO-GO semaine 1

### SOC (Ubuntu 24.04)

```bash
ssh vagrant@192.168.121.188
chronyc tracking | grep "System time"     # NTP synchronisé
ss -ulnp | grep 514                        # rsyslog écoute UDP 514
python3 --version                          # Python 3.12.x
docker info 2>/dev/null | head -3          # Docker opérationnel
ls /var/log/remote/                        # Répertoire présent
```

Résultat : **5/5 GO** ✓

### Target (Debian 12)

```bash
ssh target@10.0.1.20
ip addr show enp2s0                        # 10.0.1.20/24 statique, valid_lft forever
chronyc tracking | grep "System time"     # NTP synchronisé
cat /etc/rsyslog.d/50-forward.conf         # auth,authpriv.* @10.0.1.10:514
sudo sshd -T | grep passwordauthentication # passwordauthentication yes
ping -c 2 10.0.1.10                        # SOC joignable
```

Résultat : **5/5 GO** ✓

### Pipeline syslog end-to-end

```bash
# Depuis target
logger -p auth.warning -t TEST "ip-statique-validee-10.0.1.20"

# Depuis SOC
grep "ip-statique-validee" /var/log/remote/debian.log
# 2026-05-05T03:40:40+00:00 debian TEST: ip-statique-validee-10.0.1.20
```

Résultat : **GO** ✓

### Connectivité inter-VMs (depuis Kali)

```
ping 10.0.1.10  (SOC)      → OK
ping 10.0.1.20  (target)   → OK
ping 10.0.1.1   (OPNsense) → OK
```

Résultat : **GO** ✓

### Réseaux libvirt autostart

```bash
virsh --connect qemu:///system net-list --all
# isolated       active  yes
# vagrant-libvirt active  yes
```

Résultat : **GO** ✓

---

## Points d'attention pour la semaine 2

1. **Configurer syslog OPNsense → SOC** via l'interface web.
   Vérifier la réception avec `tcpdump -i any udp port 514`.
   Requis pour le scénario S2 (scan réseau détecté côté firewall).

2. **Snapshot SOC** avant le début du développement moteur (semaine 4).

3. Au reboot : les réseaux libvirt démarrent automatiquement (autostart actif).
   Vérifier avec `virsh --connect qemu:///system net-list --all` si un problème survient.

---

## Décisions documentées

Voir `decisions.md` — entrées S1-D1 et S1-D2.
