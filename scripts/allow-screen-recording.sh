#!/bin/bash
set -euo pipefail

client="${1:-dev.adrian.ishare}"
database="/Library/Application Support/com.apple.TCC/TCC.db"

for service in kTCCServiceScreenCapture kTCCServicePostEvent; do
    sudo sqlite3 "$database" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) VALUES ('$service', '$client', 0, 2, 4, 1, 0, 'UNUSED', 0, CAST(strftime('%s','now') AS INTEGER));"
    echo "Allowed $client to use $service"
done
