#!/usr/bin/env bash
# Actualiza plugins de agentes Checkmk desde el sitio configurado.
#
# Parámetros:
#   --inventory: inventario Ansible alternativo.
#   --manifest: manifiesto de plugins alternativo.
#   --plugin: plugin explícito; se puede repetir.
#   --target-dir: directorio destino para plugins explícitos.
#   --dry-run: simula la actualización sin modificar hosts.
#   opciones de ansible-playbook: por ejemplo --limit.
# Requisitos: .env, Ansible, colección local, inventario y acceso SSH con
# privilegios de escritura.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
INVENTORY_FILE="$ROOT_DIR/inventory/checkmk_hosts.yml"
MANIFEST_FILE="$ROOT_DIR/inventory/checkmk_plugins.yml"
PLAYBOOK_FILE="$ROOT_DIR/playbooks/update_checkmk_plugins.yml"
COLLECTION_SOURCE="$ROOT_DIR/ansible-collection-checkmk.general"
COLLECTIONS_PATH="$ROOT_DIR/.ansible/collections"
COLLECTION_PATH="$COLLECTIONS_PATH/ansible_collections/checkmk/general"
PLUGIN_NAMES=()
ANSIBLE_ARGS=()
CLI_REMOTE_USER=""
CLI_PRIVATE_KEY_FILE=""
DRY_RUN=false
TARGET_DIR=""

# Muestra las opciones de actualización disponibles.
usage() {
    cat <<'EOF'
Uso: update_checkmk_plugins.sh [opciones] [opciones de ansible-playbook]

Sin --plugin, actualiza los plugins indicados para cada host en el manifiesto.

Opciones:
  -i, --inventory RUTA  Inventario Ansible alternativo.
  -m, --manifest RUTA   Manifiesto de plugins alternativo.
  -p, --plugin NOMBRE   Plugin a copiar/actualizar (repetible).
      --target-dir RUTA Directorio destino para plugins explícitos.
      --dry-run         Muestra las acciones sin modificar los hosts.
      --user USUARIO    Usuario SSH remoto (prevalece sobre .env).
      --private-key RUTA Clave privada SSH (prevalece sobre .env).

Ejemplos:
  scripts/update_checkmk_plugins.sh --dry-run --limit linux
  scripts/update_checkmk_plugins.sh --limit cmk1
  scripts/update_checkmk_plugins.sh --plugin mk_logwatch.py --limit linux
  scripts/update_checkmk_plugins.sh --plugin mk_mysql --target-dir /usr/lib/check_mk_agent/plugins --limit dev
EOF
}

# Impide nombres con separadores de ruta o caracteres peligrosos.
valid_plugin_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# Extrae opciones del script y conserva el resto para ansible-playbook.
while (($#)); do
    case "$1" in
        --inventory|-i)
            (($# >= 2)) || { echo "Error: $1 requiere una ruta." >&2; exit 2; }
            INVENTORY_FILE="$2"
            shift 2
            ;;
        --inventory=*)
            INVENTORY_FILE="${1#*=}"
            shift
            ;;
        --manifest|-m)
            (($# >= 2)) || { echo "Error: $1 requiere una ruta." >&2; exit 2; }
            MANIFEST_FILE="$2"
            shift 2
            ;;
        --manifest=*)
            MANIFEST_FILE="${1#*=}"
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
        --plugin|-p)
            (($# >= 2)) || { echo "Error: $1 requiere un nombre." >&2; exit 2; }
            valid_plugin_name "$2" || { echo "Error: nombre de plugin no válido: $2" >&2; exit 2; }
            PLUGIN_NAMES+=("$2")
            shift 2
            ;;
        --plugin=*)
            PLUGIN_NAME="${1#*=}"
            valid_plugin_name "$PLUGIN_NAME" || { echo "Error: nombre de plugin no válido: $PLUGIN_NAME" >&2; exit 2; }
            PLUGIN_NAMES+=("$PLUGIN_NAME")
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

# Valida los ficheros y comandos necesarios.
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: falta $ENV_FILE. Copia .env.example y completa sus valores." >&2
    exit 1
fi
if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "Error: falta $INVENTORY_FILE. Ejecuta scripts/checkmk_inventory.py primero." >&2
    exit 1
fi
if ((${#PLUGIN_NAMES[@]} == 0)) && [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "Error: falta $MANIFEST_FILE. Ejecútalo con --plugin o genera el manifiesto primero." >&2
    exit 1
fi
if ! command -v ansible-playbook >/dev/null || ! command -v ansible-galaxy >/dev/null; then
    echo "Error: instala Ansible y ansible-galaxy en el controlador." >&2
    exit 1
fi

# Exporta configuración y credenciales para el playbook.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Configura opcionalmente el usuario y la clave SSH remotos.
REMOTE_USER="${CLI_REMOTE_USER:-${ANSIBLE_REMOTE_USER:-}}"
PRIVATE_KEY_FILE="${CLI_PRIVATE_KEY_FILE:-${ANSIBLE_PRIVATE_KEY_FILE:-}}"
if [[ -n "$REMOTE_USER" ]]; then
    ANSIBLE_ARGS+=(--user "$REMOTE_USER")
fi
if [[ -n "$PRIVATE_KEY_FILE" ]]; then
    ANSIBLE_ARGS+=(--private-key "$PRIVATE_KEY_FILE")
fi

# Prepara la colección local utilizada por los hosts Windows y el entorno.
if [[ ! -d "$COLLECTION_PATH" ]]; then
    echo "Instalando la colección local en $COLLECTIONS_PATH..." >&2
    ansible-galaxy collection install --force --collections-path "$COLLECTIONS_PATH" "$COLLECTION_SOURCE"
fi

# Construye las variables extra para modo manifiesto o modo explícito.
EXTRA_VARS=(
    --extra-vars "plugin_manifest_file=$MANIFEST_FILE"
    --extra-vars "plugin_update_dry_run=$DRY_RUN"
)
if ((${#PLUGIN_NAMES[@]} > 0)); then
    PLUGIN_JSON='['
    for plugin_name in "${PLUGIN_NAMES[@]}"; do
        PLUGIN_JSON+="\"$plugin_name\","
    done
    PLUGIN_JSON="${PLUGIN_JSON%,}]"
    EXTRA_VARS+=(--extra-vars "plugin_update_mode=explicit")
    EXTRA_VARS+=(--extra-vars "{\"plugin_update_names\":$PLUGIN_JSON}")
    if [[ -n "$TARGET_DIR" ]]; then
        EXTRA_VARS+=(--extra-vars "plugin_update_target_dir=$TARGET_DIR")
    fi
fi

# Ejecuta el playbook con los filtros y el modo seleccionados.
export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_PATH${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
exec ansible-playbook --inventory "$INVENTORY_FILE" "$PLAYBOOK_FILE" \
    "${EXTRA_VARS[@]}" "${ANSIBLE_ARGS[@]}"
