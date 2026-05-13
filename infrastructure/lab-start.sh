#!/bin/bash
# infrastructure/lab-start.sh
# Lance les 4 VMs du lab et ouvre les sessions SSH SOC et target
# A lancer comme ceci
# chmod +x infrastructure/lab-start.sh
# sudo ./infrastructure/lab-start.sh

VIRSH="virsh --connect qemu:///system"

echo "[lab] Démarrage des VMs..."
$VIRSH start infrastructure_soc 2>/dev/null || echo "[lab] SOC déjà démarrée"
$VIRSH start debian12          2>/dev/null || echo "[lab] target déjà démarrée"
$VIRSH start Kali              2>/dev/null || echo "[lab] Kali déjà démarrée"
$VIRSH start Opnsense          2>/dev/null || echo "[lab] OPNsense déjà démarrée"

echo "[lab] Attente 20s que les VMs bootent..."
sleep 20

echo "[lab] Ouverture SSH..."

# IP par défaut des VMs
IP_SOC="192.168.121.188"
IP_TARGET="192.168.121.23"
IP_KALI="192.168.121.69"
IP_OPNSENSE="192.168.121.205"

# Adapter le terminal à ce que tu utilises : kitty, gnome-terminal, xterm...

xterm -title "SOC"    -e ssh vagrant@${IP_SOC} &

xterm -title "target" -e ssh vagrant@${IP_TARGET} &

xterm -title "Kali"   -e ssh kali@${IP_KALI} &

xterm -title "OPNsense" -e ssh root@${IP_OPNSENSE} &

echo "[lab] Lab démarré."