"""Global S3-compatible storage settings for this VPS."""
import json
import os
import re
import tempfile
import threading
from pathlib import Path
from urllib.parse import urlsplit

SETTINGS_FILE = Path("/var/lib/apoiarcred-minio/settings.json")
FIELDS = {"endpoint": "", "bucket": "", "region": "us-east-1", "access_key": "", "secret_key": ""}
LOCK = threading.Lock()


class SettingsError(Exception):
    def __init__(self, message, status=422):
        super().__init__(message)
        self.status = status


def read_settings():
    try:
        return json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"enabled": False, **FIELDS}


def public_settings(config):
    return {key: config[key] for key in ("enabled", "endpoint", "bucket", "region")} | {
        "has_credentials": bool(config["access_key"] and config["secret_key"])
    }


def validate_settings(payload, saved):
    if set(payload) != {"enabled", *FIELDS} or type(payload["enabled"]) is not bool:
        raise SettingsError("Configuração inválida.")
    if any(not isinstance(payload[key], str) or len(payload[key]) > 512 for key in FIELDS):
        raise SettingsError("Confira os dados informados.")
    config = {"enabled": payload["enabled"], **{key: payload[key].strip() for key in FIELDS}}
    if not config["access_key"] and not config["secret_key"]:
        config.update(access_key=saved["access_key"], secret_key=saved["secret_key"])
    if not config["access_key"] or not config["secret_key"]:
        raise SettingsError("Informe a Access Key e a Secret Key juntas.")
    try:
        endpoint = urlsplit(config["endpoint"])
        endpoint.port
        valid_endpoint = (
            endpoint.scheme == "https" and endpoint.hostname
            and not endpoint.username and not endpoint.password and "@" not in endpoint.netloc
            and endpoint.path in ("", "/") and not endpoint.query and not endpoint.fragment
            and not re.search(r"[\\\s?#]", config["endpoint"])
        )
    except ValueError:
        valid_endpoint = False
    if not valid_endpoint:
        raise SettingsError("Informe o endereço HTTPS da API S3, sem caminho.")
    if config["endpoint"].rstrip("/") != saved["endpoint"] and not payload["access_key"].strip():
        raise SettingsError("Informe as duas chaves ao trocar o endereço da API S3.")
    config["endpoint"] = config["endpoint"].rstrip("/")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", config["bucket"]):
        raise SettingsError("Informe um nome de bucket válido.")
    if not re.fullmatch(r"[a-z0-9-]{1,64}", config["region"]):
        raise SettingsError("Informe uma região S3 válida.")
    return config


def write_settings(config):
    fd, temporary = tempfile.mkstemp(dir=SETTINGS_FILE.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(config, file)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, SETTINGS_FILE)
    finally:
        Path(temporary).unlink(missing_ok=True)


def test_connection(config):
    import boto3
    from botocore.config import Config
    from botocore.exceptions import BotoCoreError, ClientError

    try:
        client = boto3.client(
            "s3", endpoint_url=config["endpoint"], region_name=config["region"],
            aws_access_key_id=config["access_key"], aws_secret_access_key=config["secret_key"],
            config=Config(signature_version="s3v4", s3={"addressing_style": "path"},
                          connect_timeout=4, read_timeout=6, retries={"total_max_attempts": 1}),
        )
        try:
            client.head_bucket(Bucket=config["bucket"])
        finally:
            client.close()
    except (BotoCoreError, ClientError, ValueError, OSError):
        raise SettingsError(
            "A VPS não conseguiu acessar o bucket. Confira endereço, certificado, região e permissões.", 502
        ) from None


def handle_settings(method, path, payload):
    if method == "GET" and path == "/api/admin/minio":
        return public_settings(read_settings())
    if method == "POST" and path == "/api/admin/minio/test":
        test_connection(validate_settings(payload, read_settings()))
        return {"connected": True}
    if method == "POST" and path == "/api/admin/minio":
        with LOCK:
            saved = read_settings()
            config = validate_settings(payload, saved)
            if config["enabled"]:
                test_connection(config)
            write_settings(config)
        return public_settings(config)
    raise SettingsError("Rota não encontrada.", 404)
