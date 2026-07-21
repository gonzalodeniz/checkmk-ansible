#!/usr/bin/env bash
# Registra agentes Checkmk contra el sitio configurado.
#
# Parámetros:
#   --mode: tls, update o both.
#   --inventory/-i: inventario alternativo.
#   --dry-run: simula el registro sin modificar hosts.
#   opciones de ansible-playbook: por ejemplo --limit.
# Requisitos: .env, Ansible/ansible-galaxy, colección local, SSH y sudo.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
INVENTORY_FILE="$ROOT_DIR/inventory/checkmk_hosts.yml"
PLAYBOOK_FILE="$ROOT_DIR/playbooks/register_checkmk_agents.yml"
COLLECTION_SOURCE="$ROOT_DIR/ansible-collection-checkmk.general"
COLLECTIONS_PATH="$ROOT_DIR/.ansible/collections"
COLLECTION_PATH="$COLLECTIONS_PATH/ansible_collections/checkmk/general"
REGISTER_MODE=""
DRY_RUN=false
ANSIBLE_ARGS=()
CLI_REMOTE_USER=""
CLI_PRIVATE_KEY_FILE=""

# Muestra la ayuda de registro.
usage() {
    cat <<'EOF'
Uso: register_checkmk_agents.sh [opciones] [opciones de ansible-playbook]

Opciones:
  --mode MODO          tls, update o both (por defecto, .env o tls).
  -i, --inventory RUTA Inventario alternativo.
  --dry-run            Muestra las acciones sin registrar agentes.
  --user USUARIO       Usuario SSH remoto (prevalece sobre .env).
  --private-key RUTA   Clave privada SSH (prevalece sobre .env).

Ejemplos:
  scripts/register_checkmk_agents.sh --dry-run --limit linux
  scripts/register_checkmk_agents.sh --mode tls --limit cmk1
  scripts/register_checkmk_agents.sh --mode update --limit dev
EOF
}

# Extrae opciones propias y conserva las restantes para Ansible.
while (($#)); do
    case "$1" in
        --mode)
            (($# >= 2)) || { echo "Error: --mode requiere tls, update o both." >&2; exit 2; }
            REGISTER_MODE="$2"
            shift 2
            ;;
        --mode=*)
            REGISTER_MODE="${1#*=}"
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
        --dry-run)
            DRY_RUN=true
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

# Valida configuración, inventario y herramientas del controlador.
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

# Carga las credenciales y valores de Checkmk.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
REGISTER_MODE="${REGISTER_MODE:-${CMK_AGENT_REGISTER_MODE:-tls}}"
case "$REGISTER_MODE" in
    tls|update|both) ;;
    *) echo "Error: modo no válido: $REGISTER_MODE" >&2; exit 2 ;;
esac

# Usa la colección local, instalándola en el caché aislado si falta.
if [[ ! -d "$COLLECTION_PATH" ]]; then
    echo "Instalando la colección local en $COLLECTIONS_PATH..." >&2
    ansible-galaxy collection install --force --collections-path "$COLLECTIONS_PATH" "$COLLECTION_SOURCE"
fi

# Aplica identidad SSH alternativa configurada en .env.
REMOTE_USER="${CLI_REMOTE_USER:-${ANSIBLE_REMOTE_USER:-}}"
PRIVATE_KEY_FILE="${CLI_PRIVATE_KEY_FILE:-${ANSIBLE_PRIVATE_KEY_FILE:-}}"
if [[ -n "$REMOTE_USER" ]]; then
    ANSIBLE_ARGS+=(--user "$REMOTE_USER")
fi
if [[ -n "$PRIVATE_KEY_FILE" ]]; then
    ANSIBLE_ARGS+=(--private-key "$PRIVATE_KEY_FILE")
fi

# Pasa el modo y la simulación al playbook.
EXTRA_VARS=(
    --extra-vars "register_mode=$REGISTER_MODE"
    --extra-vars "register_dry_run=$DRY_RUN"
)
export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_PATH${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
exec ansible-playbook --inventory "$INVENTORY_FILE" "$PLAYBOOK_FILE" \
    "${EXTRA_VARS[@]}" "${ANSIBLE_ARGS[@]}"
