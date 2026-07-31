#!/bin/bash

# Script per creare VM da 120 a 138 a partire dal template
for i in $(seq 120 138); do
    echo "================================================================="
    echo "Creazione VM numero: $i"
    echo "================================================================="
    
    # qm stop "$i"
    # qm destroy "$i"	 	
    ./create-vm-from-template.sh "$i"
    
    # Controllo se il comando è andato a buon fine (opzionale ma consigliato)
    if [ $? -eq 0 ]; then
        echo "VM $i creata con successo"
    else
        echo "ERRORE durante la creazione della VM $i"
        # Se vuoi fermarti al primo errore, decommenta la riga sotto
        # exit 1
    fi
    
    echo ""  # riga vuota per separare i log
done

echo "Tutte le VM da , da 120 a 138, sono state processate!"
