#!/usr/bin/env bash
# Genera un manifiesto YAML de plugins Checkmk instalados por host.
#
# Parámetros:
#   --inventory/-i: inventario Ansible de entrada.
#   --output: fichero YAML de salida.
#   opciones adicionales de ansible-playbook: por ejemplo --limit.
# Requisitos: .env, inventario generado, Ansible/ansible-galaxy y acceso SSH.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Rutas de configuración, entrada, salida y playbook.
ENV_FILE="$ROOT_DIR/.env"
INVENTORY_FILE="$ROOT_DIR/inventory/checkmk_hosts.yml"
OUTPUT_FILE="$ROOT_DIR/inventory/checkmk_plugins.yml"
PLAYBOOK_FILE="$ROOT_DIR/playbooks/collect_checkmk_plugins.yml"
COLLECTION_SOURCE="$ROOT_DIR/ansible-collection-checkmk.general"
COLLECTIONS_PATH="$ROOT_DIR/.ansible/collections"
COLLECTION_PATH="$COLLECTIONS_PATH/ansible_collections/checkmk/general"
ANSIBLE_ARGS=()
CLI_REMOTE_USER=""
CLI_PRIVATE_KEY_FILE=""

# Muestra la ayuda de uso del lanzador.
usage() {
    cat <<'EOF'
Uso: collect_checkmk_plugins.sh [--inventory RUTA|-i RUTA] [--output RUTA] [opciones de ansible-playbook]

Opciones SSH:
  --user USUARIO          Usuario SSH remoto (prevalece sobre .env).
  --private-key RUTA      Clave privada SSH (prevalece sobre .env).

Ejemplos:
  scripts/collect_checkmk_plugins.sh
  scripts/collect_checkmk_plugins.sh --limit linux
  scripts/collect_checkmk_plugins.sh --inventory /ruta/hosts.yml --output /tmp/plugins.yml
EOF
}

# Separa las opciones propias del lanzador de las opciones de Ansible.
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

# Valida los ficheros y comandos necesarios antes de ejecutar Ansible.
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

# Exporta las variables del entorno para que el playbook pueda leerlas.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Aplica opcionalmente usuario y clave SSH alternativos.
REMOTE_USER="${CLI_REMOTE_USER:-${ANSIBLE_REMOTE_USER:-}}"
PRIVATE_KEY_FILE="${CLI_PRIVATE_KEY_FILE:-${ANSIBLE_PRIVATE_KEY_FILE:-}}"
if [[ -n "$REMOTE_USER" ]]; then
    ANSIBLE_ARGS+=(--user "$REMOTE_USER")
fi
if [[ -n "$PRIVATE_KEY_FILE" ]]; then
    ANSIBLE_ARGS+=(--private-key "$PRIVATE_KEY_FILE")
fi

# Instala la colección local en un directorio aislado si hace falta.
if [[ ! -d "$COLLECTION_PATH" ]]; then
    echo "Instalando la colección local en $COLLECTIONS_PATH..." >&2
    ansible-galaxy collection install --force --collections-path "$COLLECTIONS_PATH" "$COLLECTION_SOURCE"
fi

# Ejecuta el playbook de descubrimiento con el inventario seleccionado.
export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_PATH${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
exec ansible-playbook --inventory "$INVENTORY_FILE" "$PLAYBOOK_FILE" \
    --extra-vars "plugin_manifest_output=$OUTPUT_FILE" "${ANSIBLE_ARGS[@]}"
