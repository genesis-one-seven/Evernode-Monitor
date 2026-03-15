
#!/bin/bash

# ==================================================================
# Script: create-vm-from-template.sh
# Descrizione: Clona full il template 348 (Ubuntu 24 Server) 
#              e crea una VM con ID e nome derivato
# Uso: ./create-vm-from-template.sh <VMID>
# Esempio: ./create-vm-from-template.sh 120
# ==================================================================

set -euo pipefail

# --- Configurazione fissa ---
TEMPLATE_ID=349
POOL=""  # Lascia vuoto se non usi storage pool, altrimenti es. "local-lvm"

# --- Controllo parametri ---
if [ $# -ne 1 ]; then
    echo "Errore: devi specificare l'ID della nuova VM"
    echo "Uso: $0 <VMID>"
    exit 1
fi

NEW_ID="$1"
NAME_SUFFIX="$((NEW_ID - 100))"
VM_NAME="andromeda-${NAME_SUFFIX}"

# --- Controlli preliminari ---
if ! qm status "$TEMPLATE_ID" &>/dev/null; then
    echo "Errore: Template con ID $TEMPLATE_ID non trovato!"
    exit 1
fi

if qm status "$NEW_ID" &>/dev/null; then
    echo "Errore: VM con ID $NEW_ID esiste già!"
    exit 1
fi

# --- Esecuzione clone FULL ---
echo "Clonazione full del template $TEMPLATE_ID -> VM $NEW_ID ($VM_NAME)..."

qm clone "$TEMPLATE_ID" "$NEW_ID" \
    --name "$VM_NAME" \
    --full 1 \
    ${POOL:+--storage "$POOL"}

# --- Opzionale: avvio immediato (commenta se non vuoi) ---
echo "Avvio della VM $NEW_ID..."
qm start "$NEW_ID"

sleep 10s

echo "VM creata con successo!"
echo "   ID: $NEW_ID"
echo "   Nome: $VM_NAME"
echo "   Basata sul template: $TEMPLATE_ID"

# --- Parametri ---
VMID="$NEW_ID"
NEW_IP_CIDR="192.168.100.$NEW_ID"
# GATEWAY="${3:-192.168.100.1}"
# DNS1="${4:-8.8.8.8}"
# DNS2="${5:-1.1.1.1}"

echo "Start with IP change"

echo "   ID: $VMID"
echo "   NewIP: $NEW_IP_CIDR"
# echo "   GATEWAY: $GATEWAY"
# echo "   DNS1: $DNS1"
# echo "   DNS2: $DNS2"

VMID="$NEW_ID"
OLD_IP="192.168.100.100"
NEW_IP="$NEW_IP_CIDR"
FILE="/etc/netplan/50-cloud-init.yaml"

echo "Avvio aggiornamento IP nella VM $VMID..."

# 1. Sostituzione IP nel file netplan
qm guest exec $VMID -- bash -c "
    if [ -f '$FILE' ]; then
        sudo sed -i 's/$OLD_IP/$NEW_IP/g' '$FILE' && \
        echo 'IP sostituito in $FILE: $OLD_IP -> $NEW_IP'
    else
        echo 'Errore: file $FILE non trovato nella VM'
        exit 1
    fi
"

if [ $? -ne 0 ]; then
    echo "Errore durante la modifica del file"
    exit 1
fi

# 2. Applicazione netplan try con accettazione automatica (invio ENTER)
echo "Applico netplan try e accetto automaticamente..."
qm guest exec $VMID -- bash -c "echo | sudo netplan try"

if [ $? -eq 0 ]; then
    echo "Configurazione netplan applicata con successo!"
else
    echo "Errore durante l'applicazione di netplan try"
    exit 1
fi

# 3. Modifica dell'host name
echo "Applico sudo hostnamectl set-hostname andromeda-$NAME_SUFFIX"
qm guest exec $VMID -- bash -c "sudo hostnamectl set-hostname andromeda-$NAME_SUFFIX"

if [ $? -eq 0 ]; then
    echo "Hostname modificato con successo!"
else
    echo "Errore durante l'applicazione del nuovo hostname"
    exit 1
fi

FILE="/etc/hosts"

echo "Avvio aggiornamento host file"

# 1. Sostituzione IP nel file netplan
qm guest exec $VMID -- bash -c "
    if [ -f '$FILE' ]; then
        sudo sed -i 's/template-48/andromeda-$NAME_SUFFIX\n127.0.0.1 andromeda-$NAME_SUFFIX.genesis-one-seven-1.online/g' '$FILE' && \
        echo 'host file modificato correttamente'
    else
        echo 'Errore: file $FILE non trovato nella VM'
        exit 1
    fi
"
