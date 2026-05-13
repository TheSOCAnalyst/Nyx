# Journal des décisions architecturales et de scope

Règle de ce fichier : **pourquoi**, pas quoi. Ce qui est déjà dans `ProjetFinal.pdf`
n'est pas répété ici. Chaque entrée documente un choix qui n'allait pas de soi, un pivot,
ou une contrainte explicite.

---

## Semaine 0 — Choix fondateurs (11 avril 2026)

### S0-D1 — Pare-feu : OPNsense à la place d'Alpine Linux

**Décision** : VM OPNsense 24.7 (1 Go RAM) à la place d'Alpine Linux (512 Mo).

**Justification** :
- OPNsense dispose d'une interface web pour configurer l'export syslog vers le collecteur
  sans écriture manuelle de scripts — gain de temps significatif en semaine 1.
- Correspond davantage aux appliances réelles déployées dans les PME de la région.
- Le surcoût RAM (500 Mo) est absorbé par le budget global.

**Conséquence** : IaC partiel (voir S0-D3).

---

### S0-D2 — Regroupement moteur Python + Wazuh sur une seule VM SOC

**Décision** : Une seule VM SOC Ubuntu Server 24.04 (6 Go RAM, IP 10.0.1.10)
héberge à la fois le moteur Python (phases 1–7) et la stack Wazuh (phases 8–10).
Les deux ne tournent **jamais simultanément**.

**Justification** :
- Simplifie le routage des logs : une seule IP de destination pour toutes les sources.
- Les mesures de performance restent comparables : les ressources disponibles sont
  identiques pour les deux systèmes puisqu'ils n'occupent pas la machine en même temps.
- Évite une 5ème VM qui ferait dépasser le budget RAM sur les phases 8–10.

**Protocole d'isolation** :
- Phases 1–7 : stack Wazuh non démarrée.
- Phases 8–10 : arrêt du processus moteur Python avant démarrage de Wazuh.

---

### S0-D3 — IaC partiel assumé (Vagrant sans OPNsense)

**Décision** : Les VMs SOC, Cible Debian et Kali sont provisionnées via Vagrant.
OPNsense est installé manuellement une première fois, puis sauvegardé via snapshot KVM
(`virsh snapshot-create-as`).

**Justification** :
- Aucune image Vagrant officielle pour OPNsense n'existe.
- Écrire un provisioner custom dépasse le périmètre du projet et n'apporte rien
  aux objectifs de détection.
- Le snapshot KVM remplace l'automatisation pour ce composant unique.

**Documentation associée** : `docs/opnsense-setup.md` (procédure manuelle pas à pas).

---

### S0-D4 — Réseau interne 10.0.1.0/24, NAT libvirt pour les mises à jour

**Décision** : Sous-réseau interne `10.0.1.0/24` via réseau isolé libvirt.
Pour les mises à jour système, chaque VM accède temporairement à Internet
via le réseau NAT libvirt par défaut, désactivé après `apt upgrade`.

**Justification** :
- Isolation totale du lab vis-à-vis du réseau domestique/universitaire pendant les tests.
- Le réseau NAT libvirt est la méthode standard pour les labs KVM : propre,
  reproductible, sans exposition permanente.
- Le sous-réseau `192.168.100.0/24` mentionné dans le rapport initial était une
  ébauche — `10.0.1.0/24` est retenu définitivement.

---

### S0-D5 — VM Debian complète pour la cible SSH (pas un conteneur)

**Décision** : La cible SSH est une VM Debian 12 (1 Go RAM) et non un conteneur Docker.

**Justification** :
- Une PME togolaise typique utilise un serveur physique ou VPS sous Linux complet.
- Les logs `/var/log/auth.log` générés par une VM Debian sont strictement identiques
  à ceux d'un système réel. Un conteneur Docker produit des logs structurellement
  différents (pas de PAM complet, pas de systemd).
- La fidélité des logs est critique pour la validité du benchmark.

---

### S0-D6 — Wazuh déployé via Docker Compose avec limites mémoire explicites

**Décision** : Stack Wazuh (Manager + Indexer + Dashboard) via `docker-compose`
officiel Wazuh, avec contraintes mémoire imposées dans `docker-compose.yml` :
Indexer ≤ 3 Go, Manager ≤ 1 Go, Dashboard ≤ 512 Mo.

**Justification** :
- Reproductibilité : `docker-compose up -d` reconstruit toute la stack.
- Les quotas mémoire garantissent que Wazuh reste dans l'enveloppe de 6 Go de la VM SOC.
- Permet de mesurer la consommation réelle via `docker stats` et d'ajuster si nécessaire.

---

### S0-D7 — OS hôte : Fedora 41 + KVM/QEMU à la place de Xubuntu + VirtualBox

**Décision** : Réinstallation de l'hôte sous Fedora Workstation 41.
Hyperviseur remplacé : VirtualBox → KVM/QEMU + libvirt + virt-manager.
Vagrant conservé avec le plugin `vagrant-libvirt`.

**Justification** :
- Xubuntu corrompu irrécupérable après OOM killer (13 avril 2026).
- VirtualBox repose sur des modules kernel tiers (DKMS) — sur Fedora 41
  avec kernel 6.x récent, le cycle de recompilation casse à chaque update.
  C'est la cause racine du crash initial.
- KVM est intégré au kernel Linux depuis 2007 : pas de module tiers,
  pas de recompilation, stabilité garantie quelle que soit la version kernel.
- `vagrant-libvirt` remplace le provider `virtualbox` dans le Vagrantfile.

**Impact sur le projet** :
- Vagrantfile : provider `virtualbox` → `libvirt`, boxes `ubuntu/noble64` →
  `bento/ubuntu-24.04`, `debian/bookworm64` → `generic/debian12`.
- Scripts de provisioning `soc.sh`, `target.sh` : inchangés.
- OS hôte non composant du pipeline SOC : benchmark non affecté.

**Date du pivot** : 13 avril 2026.

---

## Semaine 1 — Déploiement du laboratoire (18 avril – 11 mai 2026)

### S1-D1 — Abandon de Vagrant pour target, OPNsense et Kali : création manuelle via virt-manager

**Décision** : Les VMs target (Debian 12), OPNsense et attacker (Kali) sont créées
manuellement via virt-manager. Vagrant est conservé uniquement pour la VM SOC
(déjà opérationnelle). Le Vagrantfile reste dans le dépôt comme documentation de
l'intent IaC initial.

**Justification** — trois bugs cumulatifs vagrant-libvirt qui rendent l'automatisation
non rentable pour ce projet solo :

1. **Box `generic/debian12` : sélection d'architecture incorrecte.**
   vagrant-libvirt 0.11.2 + Vagrant 2.3.4 télécharge systématiquement la variante
   `ppc64le` au lieu d'`amd64` pour les boxes `generic/*` sur Fedora x86_64.

2. **Connexion libvirt : session vs system.**
   vagrant-libvirt utilise `qemu:///session` par défaut. Les opérations réseau
   nécessitent `qemu:///system`. Sans `libvirt.uri = "qemu:///system"` explicite,
   les réseaux ne peuvent pas être créés.

3. **NFS échoue sur Fedora par défaut.**
   vagrant-libvirt utilise NFS pour `/vagrant`. `nfs-server` inactif sur Fedora.
   Contournement : `type: "rsync"`, mais ajoute de la fragilité.

**Conséquence acceptée** : Perte de reproductibilité automatique pour 3 VMs sur 4.
Acceptable pour un projet solo de 10 semaines avec une topologie fixe.

**Ce que le Vagrantfile conserve** : Documentation de l'allocation RAM, des IPs cibles,
et des scripts de provisioning — valeur de référence pour une éventuelle reconstruction.

---

### S1-D2 — Config rsyslog : règle RemoteLogs dans `/etc/rsyslog.d/10-remote.conf`

**Décision** : La règle de réception des logs distants est placée dans
`/etc/rsyslog.d/10-remote.conf` (template + règle + stop dans le même fichier),
et non dans `rsyslog.conf`.

**Justification** — trois sous-problèmes résolus séquentiellement :

**Sous-problème A — Ordre de chargement** :
rsyslog charge `rsyslog.conf` puis inclut `rsyslog.d/*.conf` par ordre alphanumérique.
`50-default.conf` consommait les messages distants avant `RemoteLogs`.
Solution : fichier `10-remote.conf` (chargé avant `50-default.conf`).

**Sous-problème B — Dépendance de template** :
Un template rsyslog doit être défini avant son premier usage dans l'ordre de chargement.
Solution : template et règle dans le même fichier.

**Sous-problème C — Permissions** :
`/var/log/remote/` créé par `soc.sh` avec propriétaire `root:root`.
rsyslog tourne sous `syslog:adm` — écriture refusée.
Solution : `chown syslog:adm /var/log/remote/` + `chmod 755 /var/log/remote/`.

**Config finale** (`/etc/rsyslog.d/10-remote.conf`) :
```
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip startswith '10.0.1.' then ?RemoteLogs
& stop
```

---

### S1-D3 — RAM target maintenue à 1 Go malgré l'ajout de Samba

**Décision** : La VM target reste à 1 Go RAM. Aucune modification des specs.

**Justification** :
- Samba au repos sur un lab solo (3-4 connexions max) consomme 30-60 Mo.
- Le swap observé (195 Mo) est lié au démarrage et à l'interface SPICE —
  pas à une saturation fonctionnelle.

**Conséquence acceptée** : La VM peut rester en swap léger au repos.

---

### S1-D4 — Scénario S2 : vecteur d'exfiltration défini comme SMB

**Décision** : Le scénario S2 (reconnaissance + exfiltration) est redéfini avec
SMB comme vecteur d'exfiltration explicite. Samba est déployé sur la target Debian
(configuration simplifiée : 2 partages privés + 1 commun, 4 utilisateurs).

**Chaîne d'attaque S2** :
```
Kali → nmap scan réseau
     → CrackMapExec brute-force SMB sur target (10.0.1.20:445)
     → accès au partage Samba
     → smbclient get fichiers (exfiltration)
```

**Justification** :
- Cohérence avec le contexte PME togolaise : Samba est la solution de partage
  de fichiers de référence dans ce type d'environnement.
- S2 dispose de trois sources de logs distinctes pour la corrélation :
  OPNsense (scan), target auth/authpriv (échecs SMB), target daemon (accès partages).

**Impact pipeline syslog** : extension de `50-forward.conf` avec `daemon.*`.

---

### S1-D5 — Facility syslog Samba : `daemon.*` requis, `syslog.*` insuffisant

**Décision** : La transmission des logs Samba vers le SOC nécessite la facility
`daemon.*` dans `50-forward.conf`. La facility `syslog.*` ne suffit pas.

**Justification** :
Samba (`smbd`) émet ses messages via `openlog(LOG_DAEMON)` — hardcodé dans le
source C. `syslog.*` capture les messages internes de rsyslog lui-même, pas les
démons système.

**Config `50-forward.conf` finale** :
```
auth,authpriv.*  @10.0.1.10:514   # SSH, PAM, sudo
syslog.*         @10.0.1.10:514   # Messages internes rsyslog
daemon.*         @10.0.1.10:514   # Samba (smbd, nmbd) et autres démons
```

**Règle générale** : `auth,authpriv.*` + `daemon.*` + `kern.*` couvre 90% des
événements de sécurité pertinents pour un lab SOC.

---

### S1-D6 — IP Kali fixée en statique 10.0.1.50 sur eth1

**Décision** : L'interface `eth1` de la VM Kali est configurée en statique
à `10.0.1.50/24` (réseau `isolated`). L'interface `eth0` reste en DHCP sur
le réseau management (`vagrant-libvirt`, 192.168.121.0/24).

**Justification** :
- L'IP initiale après installation était `10.0.1.190` (bail DHCP du réseau isolated).
- L'adresse `10.0.1.50` est l'IP cible définie dès S0 pour la machine attaquante.
- Une IP statique évite que l'adresse source des attaques change entre sessions,
  ce qui invaliderait les règles de corrélation basées sur l'IP.
- P-D8 référence `10.0.1.50` comme IP Kali — la correction aligne la réalité
  sur la documentation.

**Config `/etc/network/interfaces` sur Kali** :
```
auto eth1
iface eth1 inet static
    address 10.0.1.50
    netmask 255.255.255.0
```

**Validation** :
```
eth1: inet 10.0.1.50/24 scope global eth1 (valid_lft forever)
```

---

### S1-D7 — OPNsense : réinstallation depuis ISO DVD sur disque qcow2 dédié

**Décision** : La VM OPNsense est recréée from scratch avec un disque qcow2
de 8 Go dédié, à partir de l'ISO DVD `OPNsense-26.1.6-dvd-amd64.iso`.
La version passe de 26.1.2 (plan initial) à 26.1.6 (dernière disponible).
Partition scheme : **MBR** (DOS Partitions).

**Justification** — séquence d'échecs ayant conduit à cette décision :

1. **Image VGA live sans disque dédié** : la VM originale pointait sur
   `OPNsense-26.1.2-vga-amd64.post-install-base` comme seul disque, avec
   backing store sur l'`.img` original. OPNsense tournait en live media —
   toute configuration disparaissait au reboot.

2. **Ajout de disque à chaud non fonctionnel** : l'attachement d'un qcow2
   de 8 Go via `virsh attach-disk` pendant que la VM tournait provoquait
   `Partition destroy failed` dans l'installateur VGA — le kernel FreeBSD
   ne voit pas proprement un disque attaché à chaud pour le partitionnement.

3. **Image VGA incompatible avec l'installation** : même après redémarrage
   avec le disque attaché via XML, l'installateur VGA refusait de partitionner
   (`Partition destroy failed` persistant). Cause probable : l'image VGA est
   conçue pour être copiée, pas pour servir d'installateur avec disque cible séparé.

4. **ISO DVD + MBR = solution propre** : l'ISO DVD contient le bsdinstall
   standard FreeBSD. Avec un disque qcow2 vierge comme seul disque cible,
   l'installation s'est déroulée sans erreur. GPT avait été tenté d'abord et
   échoué (incompatibilité SeaBIOS/BIOS legacy) — MBR fonctionne correctement.

**Procédure de recréation** :
```bash
# Suppression ancienne VM
virsh --connect qemu:///system snapshot-delete Firewall --snapshotname post-install-base
sudo rm /var/lib/libvirt/images/opnsense.qcow2
virsh --connect qemu:///system undefine Firewall --remove-all-storage

# Création disque vierge
qemu-img create -f qcow2 /var/lib/libvirt/images/opnsense.qcow2 8G

# Création VM dans virt-manager :
# ISO : OPNsense-26.1.6-dvd-amd64.iso (CDROM)
# Disque : opnsense.qcow2 8 Go (VirtIO)
# RAM : 1024 Mo, CPU : 1
# NIC1 (vtnet0) : isolated → LAN
# NIC2 (vtnet1) : default (NAT) → WAN
# Partition scheme : MBR

# Post-install : déconnecter l'ISO, booter sur disque
# Console option 2 : LAN → 10.0.1.1/24
```

**Nom VM dans libvirt** : `Opnsense` (majuscule O, sans tiret).

**Conséquence** : le snapshot `post-install-base` mentionné en S0-D3 n'existe
plus — remplacé par le snapshot `post-semaine1` créé après configuration complète.

---

## Décisions permanentes (scope — toutes semaines)

Ces décisions sont figées pour la durée du projet.

| Réf. | Décision | Statut |
|------|----------|--------|
| P-D1 | 2 scénarios uniquement : S1 brute-force SSH, S2 scan+exfiltration SMB | Figé |
| P-D2 | Réponse automatisée hors scope principal | Figé |
| P-D3 | Backend d'états : dict Python + persistence JSON (`StateStore`) — Redis écarté | Figé |
| P-D4 | Règles de corrélation externalisées en YAML (`engine/rules/`) | Figé |
| P-D5 | Dataset d'évaluation isolé semaine 3, jamais modifié ensuite | Figé |
| P-D6 | Benchmark : Wazuh uniquement (même catégorie fonctionnelle SIEM/corrélation) | Figé |
| P-D7 | Python 3.12 (min. 3.10), toutes dépendances pinnées dans `requirements.txt` | Figé |

### P-D8 — Limite topologie : trafic Est-Ouest non filtré par OPNsense

**Constat** : Kali (10.0.1.50) et target (10.0.1.20) sont sur le même
segment L2 (bridge virbr2). Le trafic inter-VMs ne traverse pas OPNsense.

**Impact par scénario** :
- S1 (brute-force SSH) : aucun impact. Détection HIDS via logs auth de target.
- S2 (scan + exfiltration) : impact partiel. OPNsense ne voit pas le trafic
  SMB entre Kali et target. Il voit les paquets nmap adressés à 10.0.1.1
  (lui-même) pendant le scan — suffisant pour un log de reconnaissance.

**Décision** : topologie maintenue. Documentée comme limite de lab dans le rapport.

**Pour une version future** : placer Kali sur un segment séparé (10.0.2.0/24)
avec routage via OPNsense pour une visibilité complète du trafic Est-Ouest.

**Constat** : -- soc.sh place RemoteLogs dans rsyslog.conf au lieu de 10-remote.conf — écart documenté en S1-D2, script à aligner si reconstruction nécessaire.--
