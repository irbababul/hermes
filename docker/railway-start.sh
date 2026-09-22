#!/bin/sh
# Railway startup shim for Hermes Agent.
#
# Railway Variables are process environment variables, while Hermes expects
# provider routing in config.yaml and secrets in $HERMES_HOME/.env. This shim
# translates safe Railway aliases before starting the requested Hermes command.

set -eu

export HERMES_HOME="${HERMES_HOME:-/opt/data/.hermes}"
mkdir -p "$HERMES_HOME"

set_cfg() {
    key="$1"
    val="$2"
    if [ -n "${val:-}" ]; then
        hermes config set "$key" "$val" >/dev/null
    fi
}

# Non-secret model settings. Keep secrets out of config.yaml.
set_cfg model.provider "${MODEL_PROVIDER:-custom}"
set_cfg model.base_url "${MODEL_BASE_URL:-}"
set_cfg model.api_mode "${MODEL_API_MODE:-chat_completions}"
set_cfg model.default "${MODEL_DEFAULT:-}"

# Store the provider API key in .env, then point config.yaml at that env var.
# Supports either MODEL_API_KEY or HERMES_CUSTOM_RAILWAY_API_KEY in Railway Variables.
python - <<'PY'
import os, pathlib, re
home = pathlib.Path(os.environ.get("HERMES_HOME", "/opt/data/.hermes"))
home.mkdir(parents=True, exist_ok=True)
key = os.environ.get("MODEL_API_KEY") or os.environ.get("HERMES_CUSTOM_RAILWAY_API_KEY") or ""
if key:
    env_path = home / ".env"
    text = env_path.read_text(encoding="utf-8") if env_path.exists() else ""
    line = f"HERMES_CUSTOM_RAILWAY_API_KEY={key}\n"
    if re.search(r"^HERMES_CUSTOM_RAILWAY_API_KEY=.*$", text, flags=re.M):
        text = re.sub(r"^HERMES_CUSTOM_RAILWAY_API_KEY=.*$", line.rstrip("\n"), text, flags=re.M)
        if not text.endswith("\n"):
            text += "\n"
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += line
    env_path.write_text(text, encoding="utf-8")
PY

if [ -n "${MODEL_API_KEY:-}${HERMES_CUSTOM_RAILWAY_API_KEY:-}" ]; then
    hermes config set model.key_env HERMES_CUSTOM_RAILWAY_API_KEY >/dev/null
fi

# Safety default for this Railway deployment: do not connect the WhatsApp
# bridge unless the user explicitly re-enables it by changing this file back.
# This overrides stale Railway Variables and persisted WA sessions.
export WHATSAPP_ENABLED=false

# Railway sets PORT for web services. Hermes gateway can run without exposing
# HTTP, but keep the variable available for platforms that bind a port.
export PORT="${PORT:-8080}"

if [ "$#" -eq 0 ]; then
    set -- gateway
fi

exec hermes "$@"
