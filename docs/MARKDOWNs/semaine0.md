# Semaine 0 — Choix techniques et initialisation du laboratoire

**Période** : 11 avril 2026  
**Statut** : Terminée

---

## Ce qui a été fait

- Choix définitif de la stack technique (OS, réseau, allocation RAM)
- Identification et documentation des écarts par rapport au plan initial (`mini-soc-rapport.pdf`)
- Pivot hyperviseur : VirtualBox → KVM/QEMU suite à crash OOM kernel (voir S0-D7)
- Définition du workflow de développement (VS Code Remote-SSH depuis l'hôte)
- Préparation de la structure Git du projet

---

## Topologie réseau retenue

| Composant | OS | RAM | IP | Rôle |
|---|---|---|---|---|
| Firewall | OPNsense 24.7 | 1 Go | 10.0.1.1 | Routage, segmentation, logs pare-feu |
| Serveur SOC | Ubuntu Server 24.04 | 6 Go | 10.0.1.10 | Collecte logs, moteur Python, Wazuh (phases 8–10) |
| Cible SSH | Debian 12 | 1 Go | 10.0.1.20 | Serveur SSH + fichiers (cible des attaques) |
| Machine attaquante | Kali Linux | 2 Go | 10.0.1.50 | Simulation scénarios |
| **Hôte physique** | **Fedora 41** | — | — | **Dev, VS Code, Wireshark, virt-manager** |

Réseau : `10.0.1.0/24`, réseau isolé libvirt, isolé Internet.  
Mises à jour : réseau NAT libvirt par défaut, désactivé après `apt upgrade`.

---

## Budget RAM par phase

| Composant | Phases 1–7 | Phases 8–10 |
|---|---|---|
| OPNsense | 1 Go | 1 Go |
| SOC — OS + services | 1 Go | 1 Go |
| SOC — Moteur Python | 1,5 Go | 0 (arrêté) |
| SOC — Wazuh (Docker) | 0 (arrêté) | ≤ 4,5 Go |
| Cible Debian | 1 Go | 1 Go |
| Kali | 2 Go | 2 Go |
| **Total VMs** | **6,5 Go** | **9,5 Go** |
| Hôte Fedora 41 (OS + VS Code + Wireshark) | ~3 Go | ~3 Go |
| **Total général** | **~9,5 Go** | **~12,5 Go** |
| **Marge (sur 16 Go)** | **~6,5 Go** | **~3,5 Go** |

---

## Configuration des flux de logs

### OPNsense → SOC
```
System → Settings → Logging / Targets
Destination : 10.0.1.10:514 (UDP)
Niveau : Notice et supérieur
```

### Cible Debian → SOC
```bash
# /etc/rsyslog.d/50-forward.conf
auth,authpriv.* @10.0.1.10:514

systemctl restart rsyslog
```

Seul `auth,authpriv` est transmis — évite de saturer le collecteur avec des logs
non pertinents (cron, kernel, debug). Extension possible si scénario 2 le requiert.

### Réception sur le SOC
```bash
# /etc/rsyslog.conf — ajout
module(load="imudp")
input(type="imudp" port="514")
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip != '127.0.0.1' then ?RemoteLogs
& stop
```

---

## Workflow de développement

```
Hôte Fedora 41
├── VS Code + extension Remote-SSH
├── Git (clone local, sync GitLab privé)
└── Wireshark (capture réseau libvirt)
        │
        │ tunnel SSH
        ▼
VM SOC (10.0.1.10)
├── code source synchronisé via VS Code Remote
├── moteur Python en exécution
└── rsyslog en écoute UDP 514
```

L'hôte n'exécute aucun service de sécurité. Toutes les mesures de performance
(RAM, CPU, latence) sont prises sur la VM SOC uniquement.

---

## IaC — périmètre Vagrant

Vagrant automatise : SOC, Cible Debian, Kali.  
OPNsense : installation manuelle une seule fois, état sauvegardé via snapshot KVM
(`virsh snapshot-create-as`).  
Voir `docs/opnsense-setup.md` pour la procédure détaillée.

Provider : `vagrant-libvirt` (KVM/QEMU) — VirtualBox écarté (voir S0-D7).  
Boxes retenues (compatibles libvirt) :

| VM | Box |
|---|---|
| SOC | `generic/ubuntu2404` |
| Cible | `generic/debian12` |
| Attaquant | `kalilinux/rolling` |

Note : les boxes `generic/*` sont maintenues par Roboxes et ont une meilleure
compatibilité libvirt que les boxes officielles Ubuntu/Debian.

---

## Points d'attention pour la semaine 1

- Prendre un **snapshot KVM de l'état initial d'OPNsense** après configuration de base :
  `virsh snapshot-create-as --domain opnsense --name "post-install-base"`
- Configurer **chrony** sur toutes les VMs avant tout test
  (synchronisation NTP obligatoire pour la mesure de latence).
- Ajouter `vm.swappiness=10` dans `/etc/sysctl.conf` sur la VM SOC.
- Vérifier la réception des paquets syslog sur le port 514 depuis l'hôte :
  `sudo tcpdump -i virbr1 udp port 514`

---

## Décisions documentées

Voir `docs/decisions.md` — entrées S0-D1 à S0-D7.