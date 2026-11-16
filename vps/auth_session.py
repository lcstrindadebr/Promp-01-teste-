"""Same-origin session gateway using the project's public Supabase key."""
import json
import os
import socket
import threading
import time
from collections import deque
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

SLOTS = threading.BoundedSemaphore(4)
ATTEMPTS = deque()
LOCK = threading.Lock()
ROUTES = {
    "/api/session/login": ("/auth/v1/token?grant_type=password", "POST"),
    "/api/session/refresh": ("/auth/v1/token?grant_type=refresh_token", "POST"),
    "/api/session/user": ("/auth/v1/user", "GET"),
    "/api/session/access": ("/rest/v1/rpc/my_access", "POST"),
    "/api/session/logout": ("/auth/v1/logout", "POST"),
}

def configuration():
    app = Path(os.environ.get("APOIARCRED_APP", "/opt/apoiarcred"))
    text = (app / "dist" / "supabase-config.js").read_text(encoding="utf-8")
    data = json.loads(text[text.index("{"):text.rindex("}") + 1])
    url = os.environ["SUPABASE_URL"].rstrip("/")
    if data.get("url", "").rstrip("/") != url:
        raise ValueError("configuration_mismatch")
    key = data["key"]
    if not key.startswith("sb_publishable_"):
        import base64
        claims = json.loads(base64.urlsafe_b64decode(key.split(".")[1] + "==="))
        if claims.get("role") != "anon":
            raise ValueError("public_key_required")
    return url, key

def exchange(route, payload, authorization):
    path, method = ROUTES[route]
    url, key = configuration()
    headers = {"apikey": key, "Content-Type": "application/json"}
    if route in ("/api/session/user", "/api/session/access", "/api/session/logout"):
        if not authorization.startswith("Bearer ") or len(authorization) > 16384:
            return 401, {"code": "session_required"}
        headers["Authorization"] = authorization
    body = None if method == "GET" else json.dumps(payload).encode()
    request = Request(url + path, data=body, headers=headers, method=method)
    try:
        with urlopen(request, timeout=55) as response:
            raw = response.read(1024 * 1024)
            return response.status, json.loads(raw) if raw else {}
    except HTTPError as error:
        status = error.code
        try:
            result = json.loads(error.read(8192))
        except (ValueError, OSError):
            result = {}
        finally:
            error.close()
        code = (result.get("error_code") or result.get("code")) if isinstance(result, dict) else None
        allowed = {"invalid_credentials", "email_not_confirmed", "refresh_token_not_found",
                   "refresh_token_already_used", "user_banned", "over_request_rate_limit"}
        return status, {"code": code if code in allowed else
                        ("upstream_unavailable" if status >= 500 else "auth_rejected")}
    except (URLError, socket.timeout, TimeoutError):
        return 504, {"code": "upstream_timeout"}

def handle(handler, route):
    if route not in ROUTES or handler.command != ROUTES[route][1]:
        return handler.error(405, "method_not_allowed", "Método não permitido.")
    if handler.headers.get("Sec-Fetch-Site") == "cross-site":
        return handler.error(403, "origin_denied", "Origem não permitida.")
    payload = {}
    if handler.command == "POST":
        if handler.headers.get("Transfer-Encoding"):
            return handler.error(400, "invalid_body", "Envie JSON com tamanho definido.")
        try:
            length = int(handler.headers.get("Content-Length", "0"))
            if length < 0 or length > 16384:
                raise ValueError()
            if handler.headers.get("Content-Type", "").split(";")[0] != "application/json":
                raise ValueError()
            payload = json.loads(handler.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError()
        except (ValueError, UnicodeError):
            return handler.error(400, "invalid_body", "Requisição de acesso inválida.")
    if route.endswith("/login"):
        email, password = payload.get("email"), payload.get("password")
        if not isinstance(email, str) or not 3 <= len(email) <= 254 or not isinstance(password, str) or not 1 <= len(password) <= 4096:
            return handler.error(422, "invalid_credentials", "Preencha e-mail e senha.")
        payload = {"email": email.strip(), "password": password}
        with LOCK:
            now = time.monotonic()
            while ATTEMPTS and ATTEMPTS[0] <= now - 60:
                ATTEMPTS.popleft()
            if len(ATTEMPTS) >= 60:
                return handler.error(429, "rate_limit", "Aguarde antes de tentar novamente.")
            ATTEMPTS.append(now)
    elif route.endswith("/refresh"):
        token = payload.get("refresh_token")
        if not isinstance(token, str) or not 1 <= len(token) <= 8192:
            return handler.error(400, "invalid_refresh", "Sessão inválida.")
        payload = {"refresh_token": token}
    else:
        payload = {}
    if not SLOTS.acquire(blocking=False):
        return handler.error(503, "auth_busy", "O acesso está ocupado. Tente novamente.")
    try:
        status, data = exchange(route, payload, handler.headers.get("Authorization", ""))
        handler.send_json(status, data)
    except (ValueError, KeyError, IndexError, TypeError, OSError):
        handler.error(503, "auth_configuration", "Não foi possível conectar ao serviço de acesso.")
    finally:
        SLOTS.release()
