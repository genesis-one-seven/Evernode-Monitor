#!/bin/bash
# =============================================
# Script per shutdown ordinato di tutte le VM su Proxmox
# Esegui come root sul nodo Proxmox
# =============================================

set -euo pipefail

echo "=== Proxmox - Shutdown di tutte le VM e Container ==="

# Configurazione
TIMEOUT=120          # secondi di attesa per shutdown graceful
FORCE_SHUTDOWN=true  # se true forza lo shutdown dopo il timeout

echo "1. Recupero lista VM e Container in esecuzione..."

# VM KVM
vms=$(qm list | awk 'NR>1 && $3=="running" {print $1}')

# Container LXC (se vuoi spegnerli)
containers=$(pct list | awk 'NR>1 && $2=="running" {print $1}')

if [ -z "$vms" ] && [ -z "$containers" ]; then
    echo "Nessuna VM o Container in esecuzione."
    exit 0
fi

echo "VM da spegnere: ${vms:-nessuna}"
echo "Container da spegnere: ${containers:-nessuna}"

# === Shutdown VM KVM ===
for vmid in $vms; do
    name=$(qm config "$vmid" | grep -E '^name:' | awk '{print $2}')
    echo "→ Spegnimento VM $vmid (${name:-senza nome}) con shutdown graceful..."
    
    qm shutdown "$vmid" --timeout "$TIMEOUT" || true
    
    # Attesa
    for ((i=1; i<=TIMEOUT; i+=5)); do
        status=$(qm status "$vmid" | awk '{print $2}')
        if [ "$status" = "stopped" ]; then
            echo "   VM $vmid spenta correttamente."
            break
        fi
        sleep 5
    done
    
    # Force shutdown se ancora in esecuzione
    if qm status "$vmid" | grep -q "running"; then
        if [ "$FORCE_SHUTDOWN" = true ]; then
            echo "   Timeout superato → Force stop VM $vmid"
            qm stop "$vmid" --skiplock
        else
            echo "   ATTENZIONE: VM $vmid non si è spenta gracefully!"
        fi
    fi
done

# === Shutdown Container LXC ===
for ctid in $containers; do
    name=$(pct config "$ctid" | grep -E '^hostname:' | awk '{print $2}')
    echo "→ Spegnimento Container $ctid (${name:-senza nome})..."
    
    pct shutdown "$ctid" --timeout "$TIMEOUT" || true
    
    for ((i=1; i<=TIMEOUT; i+=5)); do
        if pct status "$ctid" | grep -q "stopped"; then
            echo "   Container $ctid spento correttamente."
            break
        fi
        sleep 5
    done
    
    if pct status "$ctid" | grep -q "running"; then
        echo "   Force stop Container $ctid"
        pct stop "$ctid" --skiplock
    fi
done

echo "=== Tutti i guest sono stati spenti ==="

# Opzionale: spegni anche l'host Proxmox
read -p "Vuoi spegnere anche il nodo Proxmox adesso? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "Spegnimento del nodo in corso..."
    shutdown -h now
fi
