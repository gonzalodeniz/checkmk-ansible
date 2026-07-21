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

## Configuración `.env`

El fichero `.env` contiene secretos y no debe subirse al repositorio.

| Variable | Uso |
| --- | --- |
| `CMK_URL` | URL base de Checkmk, por ejemplo `http://localhost:8080`. No incluir `/cmk/check_mk/login.py`. |
| `CMK_SITE` | Nombre del sitio Checkmk, por ejemplo `cmk`. |
| `CMK_USERNAME` | Usuario utilizado para consultar la API y descargar el agente. |
| `CMK_PASSWORD` | Contraseña o secreto de ese usuario. |
| `CMK_VERIFY_TLS` | Verifica certificados TLS (`true`/`false`). Para HTTP local suele ser `false`. |
| `CMK_ENABLE_ATTRIBUTE` | Tag que controla la inclusión del host en el inventario. Por defecto, `tag_ansible_enable`. |
| `CMK_ENABLE_VALUE` | Valor que habilita la inclusión. Por defecto, `ansible_enable`. |
| `CMK_GROUP_ATTRIBUTE_PREFIX` | Prefijo de tags que se convierten en grupos. Por defecto, `tag_ansible_group_`. |
| `ANSIBLE_REMOTE_USER` | Usuario SSH remoto alternativo. Vacío usa el usuario habitual de Ansible/SSH. |
| `ANSIBLE_PRIVATE_KEY_FILE` | Ruta a una clave privada SSH alternativa. Vacío usa la identidad habitual. |

Los valores de tags como `ansible_linux` o `ansible_dev` se convierten en los
grupos `linux` y `dev`. Un host puede pertenecer a varios grupos.

## Inventarios y seguridad

`inventory/checkmk_hosts.yml` es un artefacto generado y está excluido de Git.
Si se utiliza un inventario alternativo, debe ser legible por Ansible y contener
los grupos/hosts que se quieran actualizar. No compartas `.env`, claves
privadas ni contraseñas.
