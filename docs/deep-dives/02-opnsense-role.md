# Deep-Dive 02 : Le Rôle d'OPNsense - La Source de Vérité Réseau

Ce document explique pourquoi un Firewall comme OPNsense est indispensable dans une architecture SOC.

## 1. L'Analogie : Le Douanier et le Réceptionniste

Pour comprendre la différence entre les logs de la Target et ceux d'OPNsense, imagine un **Hôtel de Luxe** (ton infrastructure) :

*   **La Target (Le Réceptionniste)** : Il note dans son registre qui a réservé une chambre, qui a la clé, et qui est entré légitimement. Si un client monte dans sa chambre, le réceptionniste le sait. Mais si quelqu'un essaie de forcer une fenêtre au rez-de-chaussée ou rôde sur le parking, le réceptionniste ne voit rien depuis son bureau.
*   **OPNsense (Le Gardien au portail + Caméras)** : Il est à l'entrée du domaine. Il voit chaque voiture qui arrive, même celles qui font demi-tour. Il voit si quelqu'un essaie de tester toutes les poignées de porte de l'hôtel (Scan de ports). Il enregistre la plaque d'immatriculation de tout le monde, même de ceux qui ne parlent jamais au réceptionniste.

**Moralité** : Si un criminel corrompt le réceptionniste pour qu'il efface les registres, les caméras du gardien (OPNsense) ont toujours l'enregistrement de son arrivée.

## 2. Rôles Techniques dans le SIEM

### A. Visibilité sur la "Reconnaissance"
Un attaquant ne frappe jamais au hasard. Il utilise `nmap` pour scanner les ports.
- La Target ne logue pas les connexions rejetées sur des ports fermés.
- **OPNsense logue chaque paquet "DROPPED"**. C'est le premier signal d'alerte dans un SIEM.

### B. Détection de l'Exfiltration (Egress Filtering)
Une fois qu'un pirate a volé des données, il doit les faire sortir.
- Si le pirate utilise un protocole caché (ex: DNS tunneling), la Target peut ne rien voir d'anormal.
- **OPNsense voit un volume de données inhabituel** sortir vers une IP inconnue. C'est la "Vérité Réseau".

## 3. Perspective Professionnelle : La Défense en Profondeur

En entreprise, on appelle cela le **"Segregation of Duties"** (Séparation des tâches) appliqué à la donnée :
1.  **Host-based Logs** (Target) : Disent **QUOI** (ex: l'utilisateur 'admin' a ouvert ce fichier).
2.  **Network-based Logs** (OPNsense) : Disent **COMMENT** (ex: la donnée a été envoyée vers la Russie via le port 443).

**Sans corrélation entre les deux, un SIEM est aveugle d'un œil.**

## 4. Test de compréhension
Si un attaquant utilise un exploit "Zero-Day" (inconnu) qui ne laisse aucune trace dans les fichiers `/var/log/` de la Target, comment OPNsense peut-il quand même nous aider à détecter qu'il y a un problème ?
