#!/bin/bash

# Configurazioni
DOMAIN="genesis-one-seven-1.online"
API_KEY="<PUT YOUR API KEY HERE>"  # Sostituisci con la tua API key Porkbun
SECRET_API_KEY="<PUT YOUR SECRET API KEY HERE>"  # Sostituisci con la tua secret API key Porkbun
CURRENT_DIR="/home/evernode/current-certs"
BACKUP_BASE="/home/evernode"
TODAY=$(date +%Y-%m-%d)
NEW_DIR="${BACKUP_BASE}/cert-${TODAY}"

# Controlla se jq è installato
if ! command -v jq &> /dev/null; then
    echo "jq non è installato. Installalo con: sudo apt install jq"
    exit 1
fi

# Crea directory correnti se non esistono
mkdir -p "$CURRENT_DIR"

# Funzione per salvare i file dal JSON response
save_files_from_json() {
    local json_data="$1"
    local target_dir="$2"

    mkdir -p "$target_dir"
    echo "$json_data" | jq -r '.certificatechain' > "${target_dir}/certificatechain.pem"
    echo "$json_data" | jq -r '.privatekey' > "${target_dir}/privatekey.pem"
    echo "$json_data" | jq -r '.publickey' > "${target_dir}/publickey.pem"
}

# Effettua la chiamata API
echo "Recupero certificato SSL per $DOMAIN da Porkbun..."
RESPONSE=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/ssl/retrieve/${DOMAIN}" \
    -H "Content-Type: application/json" \
    -d "{\"apikey\":\"${API_KEY}\",\"secretapikey\":\"${SECRET_API_KEY}\"}")

# Controlla status
STATUS=$(echo "$RESPONSE" | jq -r '.status')
if [ "$STATUS" != "SUCCESS" ]; then
    echo "Errore API: $(echo "$RESPONSE" | jq -r '.message')"
    exit 1
fi

echo "Certificati recuperati con successo."

# Crea directory temporanea
TEMP_DIR=$(mktemp -d)
save_files_from_json "$RESPONSE" "$TEMP_DIR"

# Controlla se i file sono cambiati
CHANGED=false
for file in certificatechain.pem privatekey.pem publickey.pem; do
    if [ -f "${CURRENT_DIR}/${file}" ]; then
        if ! diff -q "${TEMP_DIR}/${file}" "${CURRENT_DIR}/${file}" > /dev/null; then
            CHANGED=true
            echo "$file è cambiato."
        fi
    else
        CHANGED=true
        echo "$file è nuovo (prima installazione)."
    fi
done

# Se sono cambiati o è la prima volta: fai backup e aggiorna
if [ "$CHANGED" = true ]; then
    # Crea nuova cartella backup
    mkdir -p "$NEW_DIR"
    cp "${TEMP_DIR}"/*.pem "$NEW_DIR/"
    echo "Backup salvato in: $NEW_DIR"

    # Aggiorna file correnti
    cp "${TEMP_DIR}"/*.pem "$CURRENT_DIR/"
    echo "File aggiornati in: $CURRENT_DIR"

    # Salva percorso backup in cert-files.txt
    echo "$NEW_DIR" > "${CURRENT_DIR}/cert-files.txt"

    
    
else
    echo "Nessun cambiamento nei certificati."
fi

# SEMPRE: salva i file correnti se non esistono (prima installazione sicura)
for file in certificatechain.pem privatekey.pem publickey.pem; do
    if [ ! -f "${CURRENT_DIR}/${file}" ]; then
        echo "Salvataggio iniziale di $file in $CURRENT_DIR"
        cp "${TEMP_DIR}/${file}" "${CURRENT_DIR}/"
    fi
done

# Pulizia
rm -rf "$TEMP_DIR"

if [ "$CHANGED" = true ]; then
    sudo evernode applyssl ~/current-certs/privatekey.pem ~/current-certs/publickey.pem ~/current-certs/certificatechain.pem
    echo "Nuovi certificati applicati con successo."
fi

echo "Operazione completata."