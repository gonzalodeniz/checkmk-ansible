# Playbooks locales

`update_checkmk_agents.yml` usa el rol `checkmk.general.agent` de la colección
local. La versión del agente se obtiene mediante el lookup
`checkmk.general.version` y el rol descarga e instala el paquete desde el sitio
Checkmk configurado en `.env`.

Ejecutar siempre mediante el lanzador, que usa
`inventory/checkmk_hosts.yml` e instala la colección local bajo `.ansible/` si
todavía no existe:

```bash
scripts/update_checkmk_agents.sh --limit linux
scripts/update_checkmk_agents.sh --limit dev
scripts/update_checkmk_agents.sh --limit cmk1
scripts/update_checkmk_agents.sh --limit 'linux:&dev'
# Usar un inventario alternativo
scripts/update_checkmk_agents.sh --inventory /ruta/hosts.yml --limit linux
```

`--limit` acepta cualquier grupo producido por `checkmk_inventory.py` o el
nombre de un host individual. La actualización requiere conectividad Ansible y
privilegios de elevación hacia los hosts seleccionados. Antes de una ejecución
real, se puede revisar el alcance con `--list-hosts`. `--inventory RUTA` (o
`-i RUTA`) sustituye `inventory/checkmk_hosts.yml`; admite inventarios YAML,
INI o dinámicos que Ansible pueda leer.

## Registrar agentes

`scripts/register_checkmk_agents.sh` registra agentes mediante TLS (`tls`),
Agent Updater (`update`) o ambos (`both`). `--dry-run` muestra el alcance sin
ejecutar comandos en los hosts.

```bash
scripts/register_checkmk_agents.sh --dry-run --limit linux
scripts/register_checkmk_agents.sh --mode tls --limit cmk1
scripts/register_checkmk_agents.sh --mode both --limit dev
```

## Descubrir plugins instalados

El lanzador `scripts/collect_checkmk_plugins.sh` explora las rutas estándar de
plugins del agente en Linux y Windows y genera
`inventory/checkmk_plugins.yml`. Incluye nombre, ruta y checksum SHA-256 por
host para que otro playbook pueda identificar plugins instalados y actualizarlos.

```bash
scripts/collect_checkmk_plugins.sh
scripts/collect_checkmk_plugins.sh --limit linux
scripts/collect_checkmk_plugins.sh --output /ruta/plugins.yml
scripts/collect_checkmk_plugins.sh --update --limit linux
```

Sin `--update`, el manifiesto se reemplaza con los hosts del alcance
seleccionado. Con `--update` se requiere `--limit`: solo se actualizan esos
hosts y se mantienen los demás hosts existentes.

## Recopilar inventario de sistemas remotos

El lanzador `scripts/collect_host_inventory.sh` obtiene los facts básicos de
los hosts remotos y genera `inventory/host_inventory.yml`. El resultado
incluye el sistema, el sistema operativo, su versión y la versión de Python.
Los hosts que fallan se conservan con esos campos vacíos.

```bash
scripts/collect_host_inventory.sh
scripts/collect_host_inventory.sh --limit linux
scripts/collect_host_inventory.sh --inventory /ruta/hosts.yml --output /tmp/host_inventory.yml
scripts/collect_host_inventory.sh --user usuario --private-key /ruta/id_ed25519 --limit dev
```

También acepta las opciones adicionales de `ansible-playbook`, como
`--list-hosts`, `--check` y variables `-e`.

## Actualizar plugins

`scripts/update_checkmk_plugins.sh` descarga plugins desde Checkmk y los copia
en los hosts seleccionados. Por defecto usa `inventory/checkmk_plugins.yml`;
`--plugin` permite indicar uno o varios plugins sin manifiesto. `--limit`
acepta grupos o hosts individuales y `--dry-run` no modifica los hosts.

```bash
scripts/update_checkmk_plugins.sh --dry-run --limit linux
scripts/update_checkmk_plugins.sh --limit cmk1
scripts/update_checkmk_plugins.sh --plugin mk_logwatch.py --limit linux
scripts/update_checkmk_plugins.sh --inventory /ruta/hosts.yml --manifest /ruta/plugins.yml --dry-run
```

## Instalar un plugin individual

El lanzador `scripts/install_checkmk_plugin.sh` descarga un plugin concreto
desde el catálogo de Checkmk y lo instala en los hosts remotos con permisos de
ejecución. Por defecto utiliza `/usr/lib/check_mk_agent/plugins`.

```bash
scripts/install_checkmk_plugin.sh --plugin mk_docker.py --limit linux
scripts/install_checkmk_plugin.sh --plugin mk_apt.sh --limit docker-dev2.inerza.loc
scripts/install_checkmk_plugin.sh --plugin mk_custom.py --source local \
  --target-dir /usr/local/lib/check_mk_agent/plugins --limit dev
scripts/install_checkmk_plugin.sh --plugin mk_docker.py --dry-run --limit linux
```

`--source` puede ser `auto`, `standard` o `local`. El lanzador también admite
`--inventory`, `--user`, `--private-key` y las opciones adicionales de
`ansible-playbook`.

## Borrar un plugin individual

El lanzador `scripts/remove_checkmk_plugin.sh` elimina un plugin concreto de
los hosts remotos. Por defecto utiliza `/usr/lib/check_mk_agent/plugins`.

```bash
scripts/remove_checkmk_plugin.sh --plugin mk_docker.py --limit linux
scripts/remove_checkmk_plugin.sh --plugin mk_docker.py --dry-run --limit dev
scripts/remove_checkmk_plugin.sh --plugin mk_custom.py \
  --target-dir /usr/local/lib/check_mk_agent/plugins --limit dev
```

## Usuario y clave SSH alternativos

El usuario que ejecuta el script no tiene que ser el usuario remoto. Define
opcionalmente en `.env`:

```dotenv
ANSIBLE_REMOTE_USER=usuario_remoto
ANSIBLE_PRIVATE_KEY_FILE=/ruta/absoluta/id_ed25519
```

El lanzador traducirá esos valores a `--user` y `--private-key`. Si se dejan
vacíos, Ansible usa su configuración SSH habitual. Una opción equivalente
pasada explícitamente al script tiene prioridad:

```bash
scripts/update_checkmk_agents.sh --user usuario_remoto \
  --private-key /ruta/absoluta/id_ed25519 --limit linux
```

Estas opciones están disponibles también en `register_checkmk_agents.sh`,
`update_checkmk_plugins.sh`, `collect_checkmk_plugins.sh`,
`collect_host_inventory.sh`, `install_checkmk_plugin.sh` y
`remove_checkmk_plugin.sh`.
