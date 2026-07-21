#!/usr/bin/env bash
# Genera un manifiesto YAML de plugins Checkmk instalados por host.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
INVENTORY_FILE="$ROOT_DIR/inventory/checkmk_hosts.yml"
OUTPUT_FILE="$ROOT_DIR/inventory/checkmk_plugins.yml"
PLAYBOOK_FILE="$ROOT_DIR/playbooks/collect_checkmk_plugins.yml"
COLLECTION_SOURCE="$ROOT_DIR/ansible-collection-checkmk.general"
COLLECTIONS_PATH="$ROOT_DIR/.ansible/collections"
COLLECTION_PATH="$COLLECTIONS_PATH/ansible_collections/checkmk/general"
ANSIBLE_ARGS=()

usage() {
    cat <<'EOF'
Uso: collect_checkmk_plugins.sh [--inventory RUTA|-i RUTA] [--output RUTA] [opciones de ansible-playbook]

Ejemplos:
  scripts/collect_checkmk_plugins.sh
  scripts/collect_checkmk_plugins.sh --limit linux
  scripts/collect_checkmk_plugins.sh --inventory /ruta/hosts.yml --output /tmp/plugins.yml
EOF
}

while (($#)); do
    case "$1" in
        --inventory|-i)
            if (($# < 2)); then
                echo "Error: $1 requiere una ruta de inventario." >&2
                exit 2
            fi
            INVENTORY_FILE="$2"
            shift 2
            ;;
        --inventory=*)
            INVENTORY_FILE="${1#*=}"
            shift
            ;;
        --output)
            if (($# < 2)); then
                echo "Error: --output requiere una ruta de salida." >&2
                exit 2
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --output=*)
            OUTPUT_FILE="${1#*=}"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            ANSIBLE_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: falta $ENV_FILE. Copia .env.example y completa sus valores." >&2
    exit 1
fi
if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "Error: falta $INVENTORY_FILE. Ejecuta scripts/checkmk_inventory.py primero." >&2
    exit 1
fi
if ! command -v ansible-playbook >/dev/null || ! command -v ansible-galaxy >/dev/null; then
    echo "Error: instala Ansible y ansible-galaxy en el controlador." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -n "${ANSIBLE_REMOTE_USER:-}" ]]; then
    ANSIBLE_ARGS+=(--user "$ANSIBLE_REMOTE_USER")
fi
if [[ -n "${ANSIBLE_PRIVATE_KEY_FILE:-}" ]]; then
    ANSIBLE_ARGS+=(--private-key "$ANSIBLE_PRIVATE_KEY_FILE")
fi

if [[ ! -d "$COLLECTION_PATH" ]]; then
    echo "Instalando la colección local en $COLLECTIONS_PATH..." >&2
    ansible-galaxy collection install --force --collections-path "$COLLECTIONS_PATH" "$COLLECTION_SOURCE"
fi

export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_PATH${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
exec ansible-playbook --inventory "$INVENTORY_FILE" "$PLAYBOOK_FILE" \
    --extra-vars "plugin_manifest_output=$OUTPUT_FILE" "${ANSIBLE_ARGS[@]}"
