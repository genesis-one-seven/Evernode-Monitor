#!/bin/bash

VMID=120
OLD_IP="192.168.100.100"
NEW_IP="192.168.100.120"
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