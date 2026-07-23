#!/usr/bin/env bash
# Genera un inventario YAML con el sistema operativo y Python de cada host.
#
# Parámetros:
#   --inventory/-i: inventario Ansible de entrada.
#   --output: fichero YAML de salida.
#   opciones adicionales de ansible-playbook: por ejemplo --limit.
# Requisitos: .env, inventario generado, Ansible y acceso SSH.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
INVENTORY_FILE="$ROOT_DIR/inventory/checkmk_hosts.yml"
OUTPUT_FILE="$ROOT_DIR/inventory/host_inventory.yml"
PLAYBOOK_FILE="$ROOT_DIR/playbooks/collect_host_inventory.yml"
ANSIBLE_ARGS=()
CLI_REMOTE_USER=""
CLI_PRIVATE_KEY_FILE=""

usage() {
    cat <<'EOF'
Uso: collect_host_inventory.sh [--inventory RUTA|-i RUTA] [--output RUTA] [opciones de ansible-playbook]

Opciones SSH:
  --user USUARIO          Usuario SSH remoto (prevalece sobre .env).
  --private-key RUTA      Clave privada SSH (prevalece sobre .env).

Ejemplos:
  scripts/collect_host_inventory.sh
  scripts/collect_host_inventory.sh --limit linux
  scripts/collect_host_inventory.sh --inventory /ruta/hosts.yml --output /tmp/hosts.yml
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
        --user|--remote-user)
            (($# >= 2)) || { echo "Error: $1 requiere un usuario." >&2; exit 2; }
            CLI_REMOTE_USER="$2"
            shift 2
            ;;
        --user=*|--remote-user=*)
            CLI_REMOTE_USER="${1#*=}"
            shift
            ;;
        --private-key)
            (($# >= 2)) || { echo "Error: --private-key requiere una ruta." >&2; exit 2; }
            CLI_PRIVATE_KEY_FILE="$2"
            shift 2
            ;;
        --private-key=*)
            CLI_PRIVATE_KEY_FILE="${1#*=}"
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

# El segundo play escribe el manifiesto en localhost. Añádelo al límite para
# que no se omita cuando se seleccionen grupos u hosts concretos.
for ((i = 0; i < ${#ANSIBLE_ARGS[@]}; i++)); do
    case "${ANSIBLE_ARGS[i]}" in
        --limit|-l)
            if ((i + 1 < ${#ANSIBLE_ARGS[@]})); then
                ANSIBLE_ARGS[i + 1]="${ANSIBLE_ARGS[i + 1]}:localhost"
                i=$((i + 1))
            fi
            ;;
        --limit=*)
            ANSIBLE_ARGS[i]="${ANSIBLE_ARGS[i]}:localhost"
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
if ! command -v ansible-playbook >/dev/null; then
    echo "Error: instala Ansible en el controlador." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

REMOTE_USER="${CLI_REMOTE_USER:-${ANSIBLE_REMOTE_USER:-}}"
PRIVATE_KEY_FILE="${CLI_PRIVATE_KEY_FILE:-${ANSIBLE_PRIVATE_KEY_FILE:-}}"
if [[ -n "$REMOTE_USER" ]]; then
    ANSIBLE_ARGS+=(--user "$REMOTE_USER")
fi
if [[ -n "$PRIVATE_KEY_FILE" ]]; then
    ANSIBLE_ARGS+=(--private-key "$PRIVATE_KEY_FILE")
fi

# localhost permite escribir el manifiesto incluso cuando se utiliza --limit.
exec ansible-playbook --inventory "$INVENTORY_FILE" --inventory 'localhost,' "$PLAYBOOK_FILE" \
    --extra-vars "host_inventory_output=$OUTPUT_FILE" "${ANSIBLE_ARGS[@]}"
