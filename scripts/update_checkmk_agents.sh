#!/usr/bin/env bash
# Actualiza agentes Checkmk usando la colección local y el inventario generado.
#
# Parámetros:
#   --inventory/-i: inventario Ansible alternativo.
#   --help: muestra la ayuda.
#   opciones de ansible-playbook: por ejemplo --limit.
# Requisitos: .env, inventario, Ansible/ansible-galaxy, SSH y privilegios sudo.
# Ejemplos:
#   scripts/update_checkmk_agents.sh --limit linux
#   scripts/update_checkmk_agents.sh --limit dev
#   scripts/update_checkmk_agents.sh --limit cmk1
#   scripts/update_checkmk_agents.sh --limit 'linux:&dev'
#   scripts/update_checkmk_agents.sh --inventory /ruta/hosts.yml --limit linux

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Rutas de entrada, playbook y caché local de la colección.
ENV_FILE="$ROOT_DIR/.env"
INVENTORY_FILE="$ROOT_DIR/inventory/checkmk_hosts.yml"
PLAYBOOK_FILE="$ROOT_DIR/playbooks/update_checkmk_agents.yml"
COLLECTION_SOURCE="$ROOT_DIR/ansible-collection-checkmk.general"
COLLECTIONS_PATH="$ROOT_DIR/.ansible/collections"
COLLECTION_PATH="$COLLECTIONS_PATH/ansible_collections/checkmk/general"
ANSIBLE_ARGS=()

# Muestra la ayuda y ejemplos del lanzador.
usage() {
    cat <<'EOF'
Uso: update_checkmk_agents.sh [--inventory RUTA|-i RUTA] [opciones de ansible-playbook]

Por defecto usa inventory/checkmk_hosts.yml. --inventory (o -i) lo sustituye.
Ejemplos:
  scripts/update_checkmk_agents.sh --limit linux
  scripts/update_checkmk_agents.sh -i /ruta/hosts.yml --limit cmk1
EOF
}

# Separa las opciones propias de las que se reenvían a Ansible.
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

# Comprueba configuración, inventario y herramientas requeridas.
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

# El fichero pertenece al operador local y contiene las credenciales de Checkmk.
# Carga y exporta las credenciales y parámetros del fichero .env.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Solo imponer usuario/clave SSH cuando se han configurado explícitamente.
# Al usar argumentos, una opción pasada manualmente al script puede sobrescribirlos.
# Añade credenciales SSH alternativas solo cuando están configuradas.
if [[ -n "${ANSIBLE_REMOTE_USER:-}" ]]; then
    ANSIBLE_ARGS+=(--user "$ANSIBLE_REMOTE_USER")
fi
if [[ -n "${ANSIBLE_PRIVATE_KEY_FILE:-}" ]]; then
    ANSIBLE_ARGS+=(--private-key "$ANSIBLE_PRIVATE_KEY_FILE")
fi

# Instala la colección local si todavía no está disponible.
if [[ ! -d "$COLLECTION_PATH" ]]; then
    echo "Instalando la colección local en $COLLECTIONS_PATH..." >&2
    ansible-galaxy collection install --force --collections-path "$COLLECTIONS_PATH" "$COLLECTION_SOURCE"
fi

# Ejecuta el playbook con el inventario y filtros solicitados.
export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_PATH${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
exec ansible-playbook --inventory "$INVENTORY_FILE" "$PLAYBOOK_FILE" "${ANSIBLE_ARGS[@]}"
