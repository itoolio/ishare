#!/bin/bash
set -euo pipefail

target="${1:-dev.adrian.ishare}"
shift || true
database="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
mkdir -p "$(dirname "$database")"

clients=(/usr/bin/osascript /bin/bash /bin/zsh /bin/sh "$@")
for provisioner in /usr/local/opt/runner/provisioner/provisioner /opt/runner/provisioner/provisioner; do
    if [ -e "$provisioner" ]; then
        clients+=("$provisioner")
    fi
done

for client in "${clients[@]}"; do
    sqlite3 "$database" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) VALUES ('kTCCServiceAppleEvents', '$client', 1, 2, 3, 1, 0, '$target', 0, CAST(strftime('%s','now') AS INTEGER));"
    echo "Allowed $client to send Apple Events to $target"
done
