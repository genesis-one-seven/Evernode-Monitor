#!/bin/bash

# Controllo se è stato passato un comando
if [ $# -eq 0 ]; then
    echo "Errore: devi passare il comando tra virgolette come argomento."
    echo "Esempio: $0 \"sudo apt update && sudo apt upgrade -y\""
    exit 1
fi

COMMAND="$1"

echo "Comando da eseguire in tutte le VM attive:"
echo "    $COMMAND"
echo

# Ciclo su tutte le VM attive (KVM e LXC)
for vmid in $(qm list | awk 'NR>1 && $3=="running" {print $1}'); do
    name=$(qm config $vmid | grep ^name: | cut -d' ' -f2-)
    echo "=== VM KVM $vmid ($name) ==="
    qm guest exec $vmid -- bash -c "$COMMAND" 2>/dev/null || echo "Fallito (forse guest agent non installato o non attivo)"
    echo
done

for vmid in $(pct list | awk 'NR>1 && $3=="running" {print $1}'); do
    name=$(pct config $vmid | grep ^hostname: | cut -d' ' -f2-)
    echo "=== Container LXC $vmid ($name) ==="
    pct exec $vmid -- bash -c "$COMMAND"
    echo
done

echo "Esecuzione completata."