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
```

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
`update_checkmk_plugins.sh` y `collect_checkmk_plugins.sh`.
