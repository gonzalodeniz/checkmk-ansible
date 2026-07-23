# Automatización de agentes Checkmk

Este proyecto obtiene los hosts de un sitio Checkmk, genera un inventario para
Ansible y permite actualizar los agentes instalados en esos hosts. La selección
se basa en los tags configurados en Checkmk y puede limitarse a grupos o a
hosts concretos.

## Requisitos

- Python 3 para generar el inventario.
- Ansible (`ansible-playbook` y `ansible-galaxy`) en el controlador.
- Acceso SSH y privilegios suficientes en los hosts gestionados.
- La colección local `ansible-collection-checkmk.general`.

## Puesta en marcha

1. Copia `.env.example` a `.env` y completa los valores de conexión.
2. Genera o actualiza el inventario:

   ```bash
   python3 scripts/checkmk_inventory.py
   ```

3. Revisa el alcance antes de actualizar agentes:

   ```bash
   scripts/update_checkmk_agents.sh --limit linux --list-hosts
   ```

4. Ejecuta la actualización para el grupo o host deseado:

   ```bash
   scripts/update_checkmk_agents.sh --limit linux
   scripts/update_checkmk_agents.sh --limit cmk1
   ```

El lanzador instala la colección local en `.ansible/` si es necesario y usa el
rol de agentes de la colección. La versión del agente se consulta al propio
servidor Checkmk.

## Scripts principales

### `scripts/checkmk_inventory.py`

Consulta los hosts de Checkmk y crea `inventory/checkmk_hosts.yml`. Solo incluye
hosts con el tag de habilitación configurado y convierte cada tag cuyo nombre
empiece por `tag_ansible_group_` en un grupo de Ansible.

### `scripts/update_checkmk_agents.sh`

Ejecuta el playbook de actualización utilizando el inventario generado. Admite
los filtros estándar de Ansible, por ejemplo `--limit linux`, `--limit cmk1` o
`--limit 'linux:&dev'`. También permite otro inventario:

```bash
scripts/update_checkmk_agents.sh --inventory /ruta/hosts.yml --limit linux
```

### `scripts/register_checkmk_agents.sh`

Registra los agentes de los hosts contra Checkmk mediante TLS, Agent Updater o
ambos mecanismos. Admite `--limit` para grupos/hosts y `--dry-run`.

```bash
scripts/register_checkmk_agents.sh --dry-run --limit linux
scripts/register_checkmk_agents.sh --mode tls --limit cmk1
scripts/register_checkmk_agents.sh --mode update --limit dev
```

### `scripts/collect_checkmk_plugins.sh`

Busca los plugins del agente Checkmk instalados en cada host y genera
`inventory/checkmk_plugins.yml`. El manifiesto contiene el nombre, ruta,
checksum y otros metadatos de cada plugin, para que un proceso de actualización
posterior pueda decidir qué plugins debe actualizar.

```bash
scripts/collect_checkmk_plugins.sh
scripts/collect_checkmk_plugins.sh --limit linux
scripts/collect_checkmk_plugins.sh --output /ruta/plugins.yml
```

### `scripts/collect_host_inventory.sh`

Recopila información básica de los hosts remotos y genera
`inventory/host_inventory.yml`. Para cada host incluye el sistema detectado,
el sistema operativo, su versión y la versión de Python. Los hosts que no
responden o cuyos facts no se pueden obtener permanecen en el inventario con
los campos vacíos.

```bash
scripts/collect_host_inventory.sh
scripts/collect_host_inventory.sh --limit linux
scripts/collect_host_inventory.sh --inventory /ruta/hosts.yml --output /tmp/host_inventory.yml
scripts/collect_host_inventory.sh --user usuario --private-key /ruta/id_ed25519 --limit dev
```

El lanzador admite las opciones adicionales de `ansible-playbook`, como
`--limit`, `--list-hosts`, `--check` y variables `-e`.

### `scripts/update_checkmk_plugins.sh`

Actualiza los plugins incluidos en `inventory/checkmk_plugins.yml` desde el
sitio Checkmk. También permite copiar plugins concretos sin usar el manifiesto.
Usa `--dry-run` antes de una actualización real.

```bash
# Simular la actualización de todos los plugins del grupo linux
scripts/update_checkmk_plugins.sh --dry-run --limit linux

# Actualizar según el manifiesto, solo en un host
scripts/update_checkmk_plugins.sh --limit cmk1

# Copiar uno o varios plugins concretos
scripts/update_checkmk_plugins.sh --plugin mk_logwatch.py --limit linux
scripts/update_checkmk_plugins.sh --plugin mk_mysql --plugin mk_logwatch.py --limit dev

# Usar manifiesto e inventario alternativos
scripts/update_checkmk_plugins.sh --inventory /ruta/hosts.yml --manifest /ruta/plugins.yml --dry-run
```

### `scripts/install_checkmk_plugin.sh`

Instala un único plugin de agente en los hosts remotos. Recibe el nombre del
plugin, lo descarga desde el catálogo estándar o local de Checkmk y lo copia
con permisos de ejecución (`0755`) en `/usr/lib/check_mk_agent/plugins`.

```bash
scripts/install_checkmk_plugin.sh --plugin mk_docker.py --limit linux
scripts/install_checkmk_plugin.sh --plugin mk_apt.sh --limit docker-dev2.inerza.loc
scripts/install_checkmk_plugin.sh --plugin mk_custom.py --source local \
  --target-dir /usr/local/lib/check_mk_agent/plugins --limit dev
scripts/install_checkmk_plugin.sh --plugin mk_docker.py --dry-run --limit linux
scripts/install_checkmk_plugin.sh --plugin mk_docker.py --remove --limit linux
```

`--source` admite `auto` (valor predeterminado), `standard` o `local`.
`--remove` borra el plugin de la ruta destino. También se pueden usar
`--inventory`, `--user`, `--private-key` y las opciones adicionales de
`ansible-playbook`.

## Configuración `.env`

El fichero `.env` contiene secretos y no debe subirse al repositorio.

| Variable | Uso |
| --- | --- |
| `CMK_URL` | URL base de Checkmk, por ejemplo `http://localhost:8080`. No incluir `/cmk/check_mk/login.py`. |
| `CMK_SITE` | Nombre del sitio Checkmk, por ejemplo `cmk`. |
| `CMK_USERNAME` | Usuario utilizado para consultar la API y descargar el agente. |
| `CMK_PASSWORD` | Contraseña o secreto de ese usuario. |
| `CMK_VERIFY_TLS` | Verifica certificados TLS (`true`/`false`). Para HTTP local suele ser `false`. |
| `CMK_PLUGIN_STANDARD_URL` | URL base opcional para plugins estándar. Vacía: se deriva de `CMK_URL` y `CMK_SITE`. |
| `CMK_PLUGIN_LOCAL_URL` | URL base opcional para plugins locales. Vacía: se deriva de `CMK_URL` y `CMK_SITE`. |
| `CMK_ENABLE_ATTRIBUTE` | Tag que controla la inclusión del host en el inventario. Por defecto, `tag_ansible_enable`. |
| `CMK_ENABLE_VALUE` | Valor que habilita la inclusión. Por defecto, `ansible_enable`. |
| `CMK_GROUP_ATTRIBUTE_PREFIX` | Prefijo de tags que se convierten en grupos. Por defecto, `tag_ansible_group_`. |
| `ANSIBLE_REMOTE_USER` | Usuario SSH remoto alternativo. Vacío usa el usuario habitual de Ansible/SSH. |
| `ANSIBLE_PRIVATE_KEY_FILE` | Ruta a una clave privada SSH alternativa. Vacío usa la identidad habitual. |
| `CMK_AGENT_REGISTER_MODE` | Modo de registro por defecto: `tls`, `update` o `both`. |

Los valores de tags como `ansible_linux` o `ansible_dev` se convierten en los
grupos `linux` y `dev`. Un host puede pertenecer a varios grupos.

## Inventarios y seguridad

`inventory/checkmk_hosts.yml`, `inventory/checkmk_plugins.yml` y
`inventory/host_inventory.yml` son artefactos generados y están excluidos de
Git.
Si se utiliza un inventario alternativo, debe ser legible por Ansible y contener
los grupos/hosts que se quieran actualizar. No compartas `.env`, claves
privadas ni contraseñas.
