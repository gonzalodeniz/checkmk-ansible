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

## Usuario y clave SSH alternativos

El usuario que ejecuta el script no tiene que ser el usuario remoto. Define
opcionalmente en `.env`:

```dotenv
ANSIBLE_REMOTE_USER=usuario_remoto
ANSIBLE_PRIVATE_KEY_FILE=/ruta/absoluta/id_ed25519
```

El lanzador traducirá esos valores a `--user` y `--private-key`. Si se dejan
vacíos, Ansible usa su configuración SSH habitual. Una opción equivalente
pasada explícitamente al script tiene prioridad.
