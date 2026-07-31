#!/bin/bash

# =============================================
# Script: deploy-ubuntu-vm.sh
# Descrizione: Clona template Ubuntu 24.04, configura hostname e IP
# Uso: ./deploy-ubuntu-vm.sh <numero> <vmid>
# Esempio: ./deploy-ubuntu-vm.sh 2 102
# =============================================

set -e  # Esce in caso di errore

# --- Parametri ---
NUM=$1          # es: 2 → andromeda-2
VMID=$2         # es: 102 → VM ID 102
TEMPLATE_ID=348 # ID del template

# --- Validazione input ---
if [[ -z "$NUM" || -z "$VMID" ]]; then
    echo "Errore: Devi passare due parametri: <numero> <vmid>"
    echo "Esempio: $0 2 102"
    exit 1
fi

HOSTNAME="andromeda-$NUM"
IP="192.168.100.$VMID"
DOMAIN="genesis-one-seven-1.online"
FULL_HOSTNAME="$HOSTNAME.$DOMAIN"
HOSTS_LINE="127.0.0.1 $FULL_HOSTNAME"

# --- Controllo se VM esiste già ---
if qm status "$VMID" &>/dev/null; then
    echo "Errore: VM con ID $VMID esiste già!"
    exit 1
fi

# --- 1. Clonazione del template ---
echo "Clonazione del template $TEMPLATE_ID in VM $VMID..."
qm clone "$TEMPLATE_ID" "$VMID" --name "$HOSTNAME" --full 1

# --- Avvio temporaneo per configurare cloud-init (se usi cloud-init) ---
# Se il template è configurato con cloud-init (consigliato), usiamo qm set
echo "Configurazione cloud-init per hostname e rete..."

qm set "$VMID" --ipconfig0 "ip=$IP/24,gw=192.168.100.1"
qm set "$VMID" --sshkey ~/.ssh/id_rsa.pub  # opzionale: aggiungi la tua chiave SSH
qm set "$VMID" --ciuser admin                    # opzionale
qm set "$VMID" --cipassword $(openssl passwd -6 'password_temporanea')  # opzionale

# --- 2. & 3. Configurazione hostname e IP via cloud-init user-data ---
cat > /tmp/user-data.$$ <<EOF
#cloud-config
hostname: $HOSTNAME
fqdn: $FULL_HOSTNAME

network:
  version: 2
  ethernets:
    ens18:  # cambia con il nome della tua interfaccia (verifica nel template)
      dhcp4: no
      addresses:
        - $IP/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]

write_files:
  - path: /etc/hosts
    permissions: '0644'
    content: |
      127.0.0.1   localhost
      $HOSTS_LINE

      # The following lines are desirable for IPv6 capable hosts
      ::1     localhost ip6-localhost ip6-loopback
      ff02::1 ip6-allnodes
      ff02::2 ip6-allrouters

runcmd:
  - hostnamectl set-hostname $HOSTNAME
  - echo "$FULL_HOSTNAME" > /etc/hostname
  - sed -i '/^127\.0\.0\.1.*$/d' /etc/hosts
  - echo "$HOSTS_LINE" >> /etc/hosts
  - systemctl restart systemd-networkd || true
EOF

# Imposta user-data e avvia
qm cloudinit update "$VMID" --user /tmp/user-data.$$
rm /tmp/user-data.$$

# --- Avvio VM ---
echo "Avvio della VM $VMID ($HOSTNAME)..."
qm start "$VMID"

echo "VM $VMID creata con successo!"
echo "   Hostname: $FULL_HOSTNAME"
echo "   IP: $IP"
echo "   Attendi 30-60 secondi per il completamento della configurazione cloud-init."
