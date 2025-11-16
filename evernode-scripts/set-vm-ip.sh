#!/bin/bash

# ==================================================================
# Script: set-vm-ip.sh
# Descrizione: Imposta IP statico su VM Ubuntu 24.04 (no cloud-init)
#              tramite qm guest exec
# Uso: ./set-vm-ip.sh <VMID> <IP/CIDR> [GATEWAY] [DNS1] [DNS2]
# Esempio: ./set-vm-ip.sh 120 192.168.100.120/24 192.168.100.1 8.8.8.8 1.1.1.1
# ==================================================================

set -euo pipefail

# --- Parametri ---
VMID="$1"
NEW_IP_CIDR="$2"
GATEWAY="${3:-192.168.100.1}"
DNS1="${4:-8.8.8.8}"
DNS2="${5:-1.1.1.1}"

echo  "$VMID $NEW_IP_CIDR $GATEWAY $DNS1 $DNS2"

# --- Validazione ---
if [ $# -lt 2 ]; then
    echo "Errore: parametri insufficienti"
    echo "Uso: $0 <VMID> <IP/CIDR> [gateway] [dns1] [dns2]"
    exit 1
fi

if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    echo "Errore: VMID deve essere un numero"
    exit 1
fi

if ! qm status "$VMID" | grep -q "running"; then
    echo "Errore: La VM $VMID non è in esecuzione!"
    echo "Avviala prima con: qm start $VMID"
    exit 1
fi

# --- Controllo agente QEMU (obbligatorio!) ---
echo "Controllo presenza qemu-guest-agent nella VM..."
if ! qm guest exec "$VMID" -- which qemu-ga &>/dev/null; then
    echo "Attenzione: qemu-guest-agent NON installato nella VM!"
    echo "Installalo nella VM con:"
    echo "   sudo apt update && sudo apt install -y qemu-guest-agent"
    echo "   sudo systemctl enable --now qemu-guest-agent"
    exit 1
fi

# --- Configurazione Netplan ---
echo "Configurazione Netplan per IP $NEW_IP_CIDR..."

NETPLAN_CONFIG=$(cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:  # Cambia se la tua interfaccia è diversa (es. eth0, enp1s0)
      dhcp4: no
      addresses:
        - $NEW_IP_CIDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - $DNS1
          - $DNS2
EOF
)

# Scrivi il file Netplan nella VM
qm guest exec "$VMID" -- bash -c "cat > /etc/netplan/99-static-ip.yaml" <<< "$NETPLAN_CONFIG"

# Applica la configurazione
echo "Applicazione della configurazione di rete..."
qm guest exec "$VMID" -- netplan apply

# Verifica IP
echo "Verifica indirizzo IP..."
sleep 3
qm guest exec "$VMID" -- ip addr show dev ens18 | grep "inet "

echo "IP impostato con successo su $NEW_IP_CIDR"
echo "   VM ID: $VMID"
echo "   Interfaccia: ens18 (modifica lo script se diversa)"
echo "   Gateway: $GATEWAY"
echo "   DNS: $DNS1, $DNS2"
