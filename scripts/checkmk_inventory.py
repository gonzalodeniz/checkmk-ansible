#!/usr/bin/env python3
"""Genera el inventario YAML de Ansible a partir de los hosts de Checkmk.

Parámetros:
  ``--env-file``: fichero de configuración .env.
  ``--output``: ruta del inventario generado.
Requisitos: Python 3 y un .env con las variables CMK_*; no requiere dependencias externas.
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENV_FILE = ROOT / ".env"
DEFAULT_OUTPUT = ROOT / "inventory" / "checkmk_hosts.yml"


def load_env(path: Path) -> dict[str, str]:
    """Lee un fichero .env sencillo sin sobrescribir variables del entorno."""
    if not path.is_file():
        raise FileNotFoundError(f"No existe el fichero de configuración: {path}")

    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            raise ValueError(f"{path}:{line_number}: se esperaba NOMBRE=VALOR")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            raise ValueError(f"{path}:{line_number}: variable vacía")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key] = value
    return {key: os.environ.get(key, value) for key, value in values.items()} | {
        key: value
        for key, value in os.environ.items()
        if key.startswith("CMK_") and key not in values
    }


def required(config: dict[str, str], name: str) -> str:
    """Comprueba y devuelve una variable de configuración obligatoria."""
    value = config.get(name, "").strip()
    if not value:
        raise ValueError(f"Falta la variable obligatoria {name} en el fichero .env")
    return value


def api_url(config: dict[str, str]) -> str:
    """Construye la URL de la API REST o usa CMK_API_URL si está definida."""
    if config.get("CMK_API_URL"):
        return config["CMK_API_URL"].rstrip("/")
    return "%s/%s/check_mk/api/1.0" % (
        required(config, "CMK_URL").rstrip("/"),
        required(config, "CMK_SITE").strip("/"),
    )


def get_hosts(config: dict[str, str]) -> list[dict[str, Any]]:
    """Consulta todos los hosts de Checkmk y devuelve su respuesta JSON."""
    query = urlencode(
        {
            "effective_attributes": "true",
            "include_links": "false",
            "fields": "!(links)",
        }
    )
    request = Request(
        "%s/domain-types/host_config/collections/all?%s" % (api_url(config), query),
        headers={
            "Accept": "application/json",
            "Authorization": "Bearer %s %s"
            % (required(config, "CMK_USERNAME"), required(config, "CMK_PASSWORD")),
        },
        method="GET",
    )
    verify_tls = config.get("CMK_VERIFY_TLS", "true").lower() not in {
        "0",
        "false",
        "no",
        "off",
    }
    context = None if verify_tls else ssl._create_unverified_context()
    try:
        with urlopen(request, context=context, timeout=30) as response:
            data = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Checkmk devolvió HTTP {error.code}: {body}") from error
    except URLError as error:
        raise RuntimeError(f"No se pudo conectar con Checkmk: {error.reason}") from error

    if isinstance(data, dict):
        data = data.get("value")
    if not isinstance(data, list):
        raise RuntimeError("Respuesta inesperada: se esperaba una lista de hosts")
    return data


def attributes_for(host: dict[str, Any]) -> dict[str, Any]:
    """Extrae los atributos efectivos del host desde la respuesta de la API."""
    extensions = host.get("extensions", {})
    attributes = extensions.get("attributes", {}) if isinstance(extensions, dict) else {}
    return attributes if isinstance(attributes, dict) else {}


def group_name(value: Any, fallback: str) -> str:
    """Normaliza valores de tags, por ejemplo ansible_linux a linux."""
    normalized = str(value or "").strip().lower()
    if normalized.startswith("ansible_"):
        normalized = normalized[len("ansible_") :]
    normalized = "".join(
        character if character.isalnum() or character == "_" else "_"
        for character in normalized
    ).strip("_")
    return normalized or fallback


def is_enabled_host(host: dict[str, Any], config: dict[str, str]) -> bool:
    """Indica si el host tiene habilitado el tag de gestión por Ansible."""
    attributes = attributes_for(host)
    enable_attribute = config.get("CMK_ENABLE_ATTRIBUTE", "tag_ansible_enable")
    enable_value = config.get("CMK_ENABLE_VALUE", "ansible_enable")
    return attributes.get(enable_attribute) == enable_value


def host_groups(host: dict[str, Any], config: dict[str, str]) -> tuple[str, ...] | None:
    """Obtiene los grupos de todos los tags de un host habilitado."""
    if not is_enabled_host(host, config):
        return None
    attributes = attributes_for(host)
    prefix = config.get("CMK_GROUP_ATTRIBUTE_PREFIX", "tag_ansible_group_")
    groups = {
        group_name(value, "")
        for name, value in attributes.items()
        if name.startswith(prefix) and value not in (None, "")
    }
    return tuple(sorted(groups)) or ("ungrouped",)


def host_ip(host: dict[str, Any]) -> str | None:
    """Devuelve la dirección IP configurada para el host, si existe."""
    attributes = attributes_for(host)
    return attributes.get("ipaddress") or attributes.get("ipv6address")


def yaml_string(value: Any) -> str:
    """Serializa una cadena como JSON, que también es YAML válido."""
    return json.dumps(str(value), ensure_ascii=False)


def inventory_yaml(hosts: list[dict[str, Any]], config: dict[str, str]) -> str:
    """Agrupa los hosts habilitados y compone el inventario YAML final."""
    groups: dict[str, list[str]] = {}
    for host in hosts:
        name = host.get("id")
        ip = host_ip(host)
        host_group_names = host_groups(host, config)
        if not isinstance(name, str) or not name or not ip or host_group_names is None:
            continue
        for group in host_group_names:
            groups.setdefault(group, []).append(name)

    lines = ["# Generado por scripts/checkmk_inventory.py. No editar manualmente.", "all:", "  children:"]
    for group in sorted(groups):
        lines.extend((f"    {group}:", "      hosts:"))
        for name in sorted(groups[group]):
            lines.append(f"        {yaml_string(name)}:")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    """Procesa argumentos, consulta Checkmk y escribe el inventario."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_FILE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    try:
        config = load_env(args.env_file)
        hosts = get_hosts(config)
        content = inventory_yaml(hosts, config)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content, encoding="utf-8")
    except (FileNotFoundError, RuntimeError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    included = sum(
        1
        for host in hosts
        if isinstance(host.get("id"), str)
        and host.get("id")
        and host_ip(host)
        and is_enabled_host(host, config)
    )
    print(f"Inventario escrito en {args.output} ({included}/{len(hosts)} hosts con IP).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
