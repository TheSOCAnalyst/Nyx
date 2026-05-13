# Deep-Dive 04 : Architecture Réseau et Choix Systèmes (Semaine 1)

Ce document récapitule les choix techniques critiques effectués lors de la première semaine pour garantir la stabilité et la visibilité du laboratoire Nyx.

---

## 1. Validation de la Pipeline de Logs (Permissions)
Au début de la phase finale, nous avons exécuté `ls -ld /var/log/remote/`. 

> [!IMPORTANT]
> Cette commande permet de vérifier que la correction **S1-D2** (permissions `syslog:adm`) a été appliquée sur la VM réelle.

- **Pourquoi c'est critique ?** Si le dossier appartient encore à `root:root`, le service `rsyslog` ne peut pas créer les fichiers de logs. Les logs arrivent bien sur le réseau, mais disparaissent "silencieusement" avant d'être écrits sur le disque.
- **Leçon apprise :** On vérifie toujours l'état réel de la VM (runtime), pas seulement le succès théorique du script de déploiement.

---

## 2. Stockage OPNsense : Pourquoi UFS et non ZFS ?
Bien que ZFS soit le système de fichiers moderne de référence pour FreeBSD, il n'est pas adapté à notre configuration actuelle pour deux raisons majeures :

| Contrainte | Explication |
| :--- | :--- |
| **Mémoire RAM** | ZFS recommande ~1 Go de RAM par To de stockage. OPNsense n'a que 1 Go au total. ZFS consommerait une part trop importante des ressources, au détriment du firewalling. |
| **Complexité** | Sur un disque unique de 8 Go sans RAID, ZFS n'apporte aucun avantage de redondance. Les snapshots sont déjà gérés au niveau de l'hyperviseur (KVM). |

**Décision :** Utilisation de **UFS** (Unix File System), léger, stable et parfaitement adapté aux ressources limitées.

---

## 3. Table de Partitionnement : Pourquoi MBR et non GPT ?
Le standard moderne est GPT, mais son utilisation a échoué lors de l'installation initiale.

- **Le problème :** La VM démarre en mode **BIOS Legacy** (via SeaBIOS). GPT nécessite une partition de boot spécifique (`bios-boot`) que l'installateur standard ne crée pas automatiquement dans ce contexte.
- **La solution :** Le format **MBR** (Master Boot Record) est nativement compatible avec le BIOS Legacy sans configuration additionnelle.
- **Note technique :** Si nous utilisions un firmware UEFI (OVMF), GPT aurait fonctionné sans problème.

---

## 4. Segmentation Réseau : Double Interfaces (NICs)
Chaque machine du lab possède deux interfaces réseau distinctes :

1. **Management (vagrant-libvirt) :** Utilisée pour l'administration SSH depuis la machine hôte.
2. **Isolated (Lab) :** Réseau `10.0.1.0/24` où circule le trafic de production et les logs SOC.

> [!TIP]
> Cette séparation est cruciale pour la fidélité des données. Si le management passait par le réseau Lab, nos propres connexions SSH pollueraient les logs et fausseraient l'analyse de sécurité.

---

## 5. Cas Particulier : La Gateway 10.0.1.254
Une erreur de configuration initiale a défini la passerelle de la Target sur `10.0.1.254`, alors qu'OPNsense est en `10.0.1.1`.

- **Impact actuel :** Nul pour la Semaine 1. Les machines communiquent en Layer 2 (via l'adresse MAC) car elles sont sur le même sous-réseau.
- **Impact futur :** Si la Target doit sortir sur Internet ou parler à un autre VLAN (via le firewall), elle échouera car elle ne trouvera pas `10.0.1.254`.
- **Action :** À corriger en `10.0.1.1` lors de la phase d'optimisation de la Semaine 2.
