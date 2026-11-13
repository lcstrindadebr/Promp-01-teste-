"""Emergency stop for the single-VPS installation; never starts services."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

SERVICES = ("apoiarcred-robo", "apoiarcred-api")
MESSAGE = "Interrompida pelo autoinstalador; devolvida à fila."
COMMON = dict(status="aguardando", locked_at=None, consultado_em=None, message=MESSAGE)
PAYLOADS = {
    "consulta_jobs": dict(COMMON, progress=0, stage="Aguardando na fila",
        robot_slot=None, api_slot=None, saldo_liquidacao=None, total_parcelas=None,
        valor_parcela=None, resultado_saldo=None, resultado_parcela=None),
    "tjba_jobs": dict(COMMON, progress=0, stage="Aguardando na fila",
        robot_slot=None, matricula=None, tipo_servidor=None, situacao_atual=None,
        emprestimo_disponivel=None, cartao_disponivel=None,
        tjba_status=None, resultado_tjba=None),
    "amigoz_jobs": dict(COMMON, lease=None, resultado=None),
}

def stop_services(run=subprocess.run, sleep=time.sleep):
    # Queue stop before KILL so Restart=always cannot relaunch an executor.
    run(["systemctl", "stop", "--no-block", *SERVICES], check=True,
        capture_output=True, timeout=15)
    run(["systemctl", "kill", "--kill-who=all", "--signal=SIGKILL", *SERVICES],
        check=False, capture_output=True, timeout=15)
    for _ in range(20):
        stopped = True
        for service in SERVICES:
            result = run(["systemctl", "show", service, "--property=ActiveState",
                          "--property=MainPID"], check=True, capture_output=True,
                         text=True, timeout=10)
            state = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
            if state.get("ActiveState") not in ("inactive", "failed") or state.get("MainPID") != "0":
                stopped = False
        if stopped:
            return
        sleep(0.5)
    raise RuntimeError("Executores ainda ativos; a fila não foi alterada.")

def api_client(app):
    env = dict(line.split("=", 1) for line in (app / ".env").read_text().splitlines()
               if "=" in line and not line.startswith("#"))
    url = env["SUPABASE_URL"].strip().strip('"').rstrip("/")
    key = env["SUPABASE_SERVICE_ROLE_KEY"].strip().strip('"')
    if not url.startswith("https://") or not key:
        raise ValueError("Configuração inválida.")
    headers = {"apikey": key, "Content-Type": "application/json", "Prefer": "return=minimal"}
    if not key.startswith("sb_secret_"):
        headers["Authorization"] = "Bearer " + key
    def request(path, payload=None):
        body = json.dumps(payload).encode() if payload is not None else None
        req = Request(url + "/rest/v1/" + path, data=body, headers=headers,
                      method="PATCH" if payload is not None else "GET")
        with urlopen(req, timeout=30) as response:
            data = response.read()
            return json.loads(data) if data else None
    return request

def requeue(request):
    failures = []
    for table, payload in PAYLOADS.items():
        try:
            # Existing rows only: no INSERT, retry RPC, quota charge or completed result changes.
            while True:
                rows = request(table + "?status=eq.processando&select=id&order=id&limit=50")
                if not rows:
                    break
                ids = ",".join(row["id"] for row in rows)
                request(table + "?status=eq.processando&id=in.(" + ids + ")", payload)
                if request(table + "?status=eq.processando&id=in.(" + ids + ")&select=id&limit=1"):
                    raise RuntimeError("O lote ainda contém consultas em processamento.")
            print(table + ": fila verificada e consultas devolvidas.", flush=True)
        except HTTPError as error:
            failures.append(f"{table} (HTTP {error.code})")
        except Exception as error:
            failures.append(f"{table} ({type(error).__name__})")
    if failures:
        raise RuntimeError("Falha ao devolver/verificar: " + ", ".join(failures)
                           + ". Serviços continuam parados. Corrija a conexão e repita a opção 6.")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=Path("/opt/apoiarcred"))
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Execute como root.")
    try:
        stop_services()
        print("Robôs e API interrompidos. Devolvendo as consultas à fila...", flush=True)
        requeue(api_client(args.app))
    except Exception as error:
        # Never print HTTP responses, credentials or raw subprocess output.
        print(str(error) if isinstance(error, RuntimeError) else
              "Não foi possível concluir. Confira os serviços e a conexão; repita a opção 6.",
              flush=True)
        return 1
    print("Concluído. Robôs e API permanecem parados (inclusive os endpoints HTTP).")
    print("Para retomar: sudo systemctl start apoiarcred-robo apoiarcred-api")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
