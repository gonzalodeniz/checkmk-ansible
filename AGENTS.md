# Instrucciones para asistentes de código

## Resumen

El proyecto se encuentra en `ansible-collection-checkmk.general/`: es la
colección Ansible `checkmk.general` para administrar Checkmk mediante API REST,
plugins y roles. Consulta `CONTEXT.md` para la arquitectura, compatibilidad y
detalles operativos.

No modifiques ningún fichero dentro de `ansible-collection-checkmk.general/`
sin autorización expresa del usuario. Mantén este fichero y `CLAUDE.md`
idénticos en todo momento.

## Comandos habituales

Ejecutar dentro de `ansible-collection-checkmk.general/` solo si el cambio está
autorizado:

```bash
uv venv && uv sync
uv run ansible-galaxy collection build --force ./
uv run black --check --diff plugins
uv run isort --check --diff plugins
uv run yamllint -c .yamllint ./roles/ ./playbooks/ ./tests/
uv run ansible-lint -c .ansible-lint ./roles/ ./playbooks/ ./tests/
uv run ansible-test sanity --docker
uv run ansible-test units --docker
uv run ansible-test integration --docker
(cd roles/server && uv run molecule test -s 2.5)
```

En `ansible-test`, deja `--docker` como último argumento. El `Makefile` usa un
entorno histórico Vagrant/KVM; prefiere `uv run` y los workflows de CI.

## Dónde realizar cambios

- API REST y utilidades comunes: `plugins/module_utils/`.
- Módulos de recursos Checkmk: `plugins/modules/`.
- Lookups, inventario: `plugins/lookup/`, `plugins/inventory/`.
- Roles: `roles/agent/` y `roles/server/`.
- Pruebas: `tests/unit/plugins/` y `tests/integration/targets/`; alinear el
  nombre con el plugin que cubren.
- Ejemplos: `playbooks/`.
- Metadatos/compatibilidad: `galaxy.yml`, `meta/runtime.yml`.
- Cambios publicados: nuevo YAML en `changelogs/fragments/`.

## Estilo y reglas

- Python: aplicar Black e isort (perfil Black).
- YAML/Ansible: respetar `.yamllint` y `.ansible-lint`.
- Variables: `snake_case`; roles con `checkmk_server_*` o `checkmk_agent_*`,
  generales con `checkmk_var_*`, internas con prefijo `__`; tags con guiones.
- Documentar módulos inline con `DOCUMENTATION`, `EXAMPLES` y `RETURN`.
- Reutilizar `plugins/module_utils/api.py`; no reimplementar cliente HTTP/REST.
- Para módulos de una entidad, usar opciones simples como `name`; para varias,
  opciones cualificadas como `host_name`.

## Evitar

- No editar `docs/`: se genera durante el release.
- No almacenar secretos, tokens o contraseñas en el repositorio ni en la
  documentación.
- No usar `site` como opción de módulo de primer nivel: colisiona con
  `base_argument_spec()`; usar un nombre como `target_site`.
- No abrir contribuciones contra `main`; el destino indicado es `devel`.
- No olvidar el fragmento de changelog para cambios funcionales.

## Verificación antes de terminar

Ejecutar como mínimo el formatter/linter pertinente y
`uv run ansible-test sanity --docker`. Para cambios Python, ejecutar también
Black, isort y unitarias; para módulos/lookups, integración; para roles,
Molecule. Documentar las pruebas no ejecutadas y el motivo.

Hay un Checkmk local en el contenedor Docker `monitoring`, sitio `cmk`, útil
para pruebas manuales autorizadas. No registrar sus credenciales; solicitarlas
al propietario del entorno si son necesarias.
