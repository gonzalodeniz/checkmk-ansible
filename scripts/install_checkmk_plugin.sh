#!/usr/bin/env bash
# Instala un único plugin de agente Checkmk en los hosts seleccionados.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
INVENTORY_FILE="$ROOT_DIR/inventory/checkmk_hosts.yml"
PLAYBOOK_FILE="$ROOT_DIR/playbooks/install_checkmk_plugin.yml"
COLLECTION_SOURCE="$ROOT_DIR/ansible-collection-checkmk.general"
COLLECTIONS_PATH="$ROOT_DIR/.ansible/collections"
COLLECTION_PATH="$COLLECTIONS_PATH/ansible_collections/checkmk/general"
PLUGIN_NAME=""
TARGET_DIR="/usr/lib/check_mk_agent/plugins"
PLUGIN_SOURCE="auto"
REMOVE_PLUGIN=false
ANSIBLE_ARGS=()
CLI_REMOTE_USER=""
CLI_PRIVATE_KEY_FILE=""

usage() {
    cat <<'EOF'
Uso: install_checkmk_plugin.sh --plugin NOMBRE [opciones] [opciones de ansible-playbook]

Opciones:
  -p, --plugin NOMBRE   Nombre del plugin que se instalará (obligatorio).
  -i, --inventory RUTA  Inventario Ansible alternativo.
      --target-dir RUTA Directorio remoto de plugins.
      --source ORIGEN    auto, standard o local (por defecto: auto).
      --remove           Borra el plugin en lugar de instalarlo.
      --dry-run          Simula la instalación sin modificar los hosts.
      --user USUARIO     Usuario SSH remoto (prevalece sobre .env).
      --private-key RUTA Clave privada SSH (prevalece sobre .env).

Ejemplos:
  scripts/install_checkmk_plugin.sh --plugin mk_docker.py --limit linux
  scripts/install_checkmk_plugin.sh --plugin mk_apt.sh --limit docker-dev2.inerza.loc
  scripts/install_checkmk_plugin.sh --plugin mk_docker.py --remove --limit linux
  scripts/install_checkmk_plugin.sh --plugin mk_foo --source local --target-dir /usr/local/lib/check_mk_agent/plugins
EOF
}

valid_plugin_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

while (($#)); do
    case "$1" in
        --plugin|-p)
            (($# >= 2)) || { echo "Error: $1 requiere un nombre." >&2; exit 2; }
            PLUGIN_NAME="$2"
            shift 2
            ;;
        --plugin=*)
            PLUGIN_NAME="${1#*=}"
            shift
            ;;
        --inventory|-i)
            (($# >= 2)) || { echo "Error: $1 requiere una ruta." >&2; exit 2; }
            INVENTORY_FILE="$2"
            shift 2
            ;;
        --inventory=*)
            INVENTORY_FILE="${1#*=}"
            shift
            ;;
        --target-dir)
            (($# >= 2)) || { echo "Error: --target-dir requiere una ruta." >&2; exit 2; }
            TARGET_DIR="$2"
            shift 2
            ;;
        --target-dir=*)
            TARGET_DIR="${1#*=}"
            shift
            ;;
        --source)
            (($# >= 2)) || { echo "Error: --source requiere un origen." >&2; exit 2; }
            PLUGIN_SOURCE="$2"
            shift 2
            ;;
        --source=*)
            PLUGIN_SOURCE="${1#*=}"
            shift
            ;;
        --remove|--delete)
            REMOVE_PLUGIN=true
            shift
            ;;
        --dry-run)
            ANSIBLE_ARGS+=(--extra-vars plugin_install_dry_run=true)
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

if [[ -z "$PLUGIN_NAME" ]] || ! valid_plugin_name "$PLUGIN_NAME"; then
    echo "Error: indica un nombre de plugin válido con --plugin." >&2
    exit 2
fi
if [[ ! "$PLUGIN_SOURCE" =~ ^(auto|standard|local)$ ]]; then
    echo "Error: --source debe ser auto, standard o local." >&2
    exit 2
fi
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

REMOTE_USER="${CLI_REMOTE_USER:-${ANSIBLE_REMOTE_USER:-}}"
PRIVATE_KEY_FILE="${CLI_PRIVATE_KEY_FILE:-${ANSIBLE_PRIVATE_KEY_FILE:-}}"
if [[ -n "$REMOTE_USER" ]]; then
    ANSIBLE_ARGS+=(--user "$REMOTE_USER")
fi
if [[ -n "$PRIVATE_KEY_FILE" ]]; then
    ANSIBLE_ARGS+=(--private-key "$PRIVATE_KEY_FILE")
fi

if [[ ! -d "$COLLECTION_PATH" ]]; then
    echo "Instalando la colección local en $COLLECTIONS_PATH..." >&2
    ansible-galaxy collection install --force --collections-path "$COLLECTIONS_PATH" "$COLLECTION_SOURCE"
fi

export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_PATH${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
exec ansible-playbook --inventory "$INVENTORY_FILE" "$PLAYBOOK_FILE" \
    --extra-vars "plugin_install_name=$PLUGIN_NAME" \
    --extra-vars "plugin_install_target_dir=$TARGET_DIR" \
    --extra-vars "plugin_install_source=$PLUGIN_SOURCE" \
    --extra-vars "plugin_install_remove=$REMOVE_PLUGIN" \
    "${ANSIBLE_ARGS[@]}"
