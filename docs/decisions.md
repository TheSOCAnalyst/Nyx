# Journal des décisions architecturales et de scope

Règle de ce fichier : **pourquoi**, pas quoi. Ce qui est déjà dans `mini-soc-rapport.pdf`
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

## Semaine 1 — Déploiement du laboratoire (18–28 avril 2026)

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
   Contournement possible via `box_url` explicite, mais fragile à chaque mise à jour de box.

2. **Connexion libvirt : session vs system.**
   vagrant-libvirt utilise `qemu:///session` par défaut. Les opérations réseau
   (création de bridges) nécessitent `qemu:///system`. Sans `libvirt.uri = "qemu:///system"`
   explicite dans chaque bloc provider, les réseaux ne peuvent pas être créés.
   Ce paramètre n'est pas documenté clairement pour Fedora dans vagrant-libvirt 0.11.2.

3. **NFS échoue sur Fedora par défaut.**
   vagrant-libvirt utilise NFS pour `/vagrant`. `nfs-server` est inactif sur Fedora
   par défaut. Contournement : `type: "rsync"`, mais ajoute de la fragilité.

**Conséquence acceptée** : Perte de reproductibilité automatique pour 3 VMs sur 4.
Acceptable pour un projet solo de 10 semaines avec une topologie fixe :
les VMs ne seront pas recréées sauf incident majeur (snapshot disponible pour OPNsense).

**Ce que le Vagrantfile conserve** : Documentation de l'allocation RAM, des IPs cibles,
et des scripts de provisioning — valeur de référence pour une éventuelle reconstruction.

**Scripts de provisioning** : `soc.sh` et `target.sh` restent valides. Pour target,
les commandes ont été exécutées manuellement via SSH après installation Debian.

---

### S1-D2 — Config rsyslog : règle RemoteLogs dans `/etc/rsyslog.d/10-remote.conf`

**Décision** : La règle de réception des logs distants est placée dans
`/etc/rsyslog.d/10-remote.conf` (template + règle + stop dans le même fichier),
et non dans `rsyslog.conf`.

**Justification** — trois sous-problèmes résolus séquentiellement :

**Sous-problème A — Ordre de chargement** :
rsyslog charge `rsyslog.conf` puis inclut `rsyslog.d/*.conf` par ordre alphanumérique.
`50-default.conf` (règles système) était traité avant la règle `RemoteLogs` définie
dans `rsyslog.conf`. Les messages distants étaient consommés par `50-default.conf`
sans atteindre `RemoteLogs`. Solution : fichier `10-remote.conf` (chargé avant `50-default.conf`).

**Sous-problème B — Dépendance de template** :
Un template rsyslog doit être défini avant son premier usage dans l'ordre de chargement.
Mettre le template dans `rsyslog.conf` et la règle dans `10-remote.conf` crée une
référence avant définition. Solution : template et règle dans le même fichier.

**Sous-problème C — Permissions** :
`/var/log/remote/` créé par `soc.sh` avec `mkdir -p` (propriétaire `root:root`).
rsyslog tourne sous l'utilisateur `syslog` (groupe `adm`) — écriture refusée.
Solution : `chown -R syslog:adm /var/log/remote/`.

**Config finale** (`/etc/rsyslog.d/10-remote.conf`) :
```
$template RemoteLogs,"/var/log/remote/%HOSTNAME%.log"
if $fromhost-ip startswith '10.0.1.' then ?RemoteLogs
& stop
```

**Correction apportée à `soc.sh`** : Ajouter après `mkdir -p /var/log/remote/` :
```bash
chown syslog:adm /var/log/remote/
chmod 755 /var/log/remote/
```

**Références rsyslog** :
- Architecture et flux : https://www.rsyslog.com/doc/master/configuration/index.html
- Ordre de traitement des règles : https://www.rsyslog.com/doc/master/configuration/actions.html
- Templates dynamiques : https://www.rsyslog.com/doc/master/configuration/templates.html

---

### S1-D3 — RAM target maintenue à 1 Go malgré l'ajout de Samba

**Décision** : La VM target reste à 1 Go RAM. Aucune modification des specs.

**Justification** :
- La target est une cible passive : elle reçoit des attaques et génère des logs.
  Elle n'a pas de charge applicative significative.
- Samba au repos sur un lab solo (3-4 connexions max) consomme 30-60 Mo.
- Le swap observé (195 Mo) est lié au démarrage du système et à l'interface
  SPICE — pas à une saturation fonctionnelle.
- Augmenter la RAM allouerait des ressources que la target n'exploitera jamais.
  Le budget RAM global (6,5 Go phases 1-7) n'a pas de marge justifiant ce
  changement.

**Conséquence acceptée** : La VM peut rester en swap léger au repos.
Acceptable pour une cible de lab à topologie fixe.

---

### S1-D4 — Scénario S2 : vecteur d'exfiltration défini comme SMB

**Décision** : Le scénario S2 (reconnaissance + exfiltration) est redéfini avec
SMB comme vecteur d'exfiltration explicite. Samba est déployé sur la target Debian
(configuration simplifiée : 2 partages, 4 utilisateurs).

**Chaîne d'attaque S2** :

Kali → nmap scan réseau
→ CrackMapExec brute-force SMB sur target (10.0.1.20:445)
→ accès au partage Samba
→ smbclient get fichiers (exfiltration)

**Justification** :
- Cohérence avec le contexte PME togolaise : Samba est la solution de partage
  de fichiers de référence dans ce type d'environnement.
- Le projet SambaPME (KPODONOU & GNIGMA, INF 1527, 2025-2026) démontre
  exactement cette chaîne d'attaque sur une infrastructure identique — réutilisation
  directe des scénarios validés (Hydra, CrackMapExec, smbclient).
- S2 dispose ainsi de trois sources de logs distinctes pour la corrélation :
  OPNsense (scan), target auth/authpriv (échecs SMB), target syslog (accès
  partages).
- Le vecteur SSH/SCP écarté : trop proche de S1, ne génère pas de signal
  réseau exploitable par OPNsense.

**Impact pipeline syslog** : extension de `/etc/rsyslog.d/50-forward.conf`
sur target pour transmettre la facility `syslog` en plus de `auth,authpriv` :

auth,authpriv.*  @10.0.1.10:514
syslog.*         @10.0.1.10:514

**Décision permanente** : ajoutée au tableau des décisions figées (P-D1 étendue).

---

## Décisions permanentes (scope — toutes semaines)

Ces décisions sont figées pour la durée du projet.

| Réf. | Décision | Statut |
|------|----------|--------|
| P-D1 | 2 scénarios uniquement : S1 brute-force SSH, S2 scan+exfiltration | Figé |
| P-D2 | Réponse automatisée hors scope principal | Figé |
| P-D3 | Backend d'états : dict Python + persistence JSON (`StateStore`) — Redis écarté | Figé |
| P-D4 | Règles de corrélation externalisées en YAML (`engine/rules/`) | Figé |
| P-D5 | Dataset d'évaluation isolé semaine 3, jamais modifié ensuite | Figé |
| P-D6 | Benchmark : Wazuh uniquement (même catégorie fonctionnelle SIEM/corrélation) | Figé |
| P-D7 | Python 3.12 (min. 3.10), toutes dépendances pinnées dans `requirements.txt` | Figé |
