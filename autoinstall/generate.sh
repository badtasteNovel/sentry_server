#!/usr/bin/env bash
# Generates user-data from user-data.tpl + .env
# Usage: bash generate.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found."
  echo "       cp .env.example .env  then fill in values."
  exit 1
fi

set -a
source .env
set +a

# Validate required vars
for var in STATIC_IP GATEWAY DNS SSH_PORT UBUNTU_PASSWORD_HASH SENTRY_DOMAIN ADMIN_EMAIL ADMIN_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

CERT_DIR="$(dirname "$SCRIPT_DIR")/cert"
SSH_KEY_FILE=""
for f in "$CERT_DIR"/*.pub; do
  [[ -f "$f" ]] && SSH_KEY_FILE="$f" && break
done
if [[ -z "$SSH_KEY_FILE" ]]; then
  echo "ERROR: cert/ 資料夾裡找不到 .pub 檔案"
  echo "       執行 task generate-ssh-key 將你的 SSH public key 複製過去"
  exit 1
fi
SSH_PUBLIC_KEY="$(cat "$SSH_KEY_FILE")"
export SSH_PUBLIC_KEY

python3 - << PYEOF
import os, re, sys

replacements = {
    '__UBUNTU_PASSWORD_HASH__':  os.environ['UBUNTU_PASSWORD_HASH'],
    '__STATIC_IP__':            os.environ['STATIC_IP'],
    '__GATEWAY__':              os.environ['GATEWAY'],
    '__DNS__':                  os.environ['DNS'],
    '__SSH_PORT__':             os.environ['SSH_PORT'],
    '__SSH_PUBLIC_KEY__':       os.environ['SSH_PUBLIC_KEY'],
    '__SENTRY_VERSION__':       os.environ.get('SENTRY_VERSION', '26.4.2'),
    '__COMPOSE_PROFILE__':      os.environ.get('COMPOSE_PROFILE', 'errors-only'),
    '__SENTRY_DOMAIN__':        os.environ['SENTRY_DOMAIN'],
    '__ADMIN_EMAIL__':          os.environ['ADMIN_EMAIL'],
    '__ADMIN_PASSWORD__':       os.environ['ADMIN_PASSWORD'],
    '__SMTP_HOST__':            os.environ.get('SMTP_HOST', ''),
    '__SMTP_PORT__':            os.environ.get('SMTP_PORT', '587'),
    '__SMTP_USER__':            os.environ.get('SMTP_USER', ''),
    '__SMTP_PASSWORD__':        os.environ.get('SMTP_PASSWORD', ''),
    '__SMTP_USE_TLS__':         os.environ.get('SMTP_USE_TLS', 'true'),
}

with open('user-data.tpl') as f:
    content = f.read()

for key, value in replacements.items():
    content = content.replace(key, value)

remaining = re.findall(r'__[A-Z_]+__', content)
if remaining:
    print(f"WARNING: unreplaced placeholders: {remaining}", file=sys.stderr)
    sys.exit(1)

with open('user-data', 'w') as f:
    f.write(content)

print("Generated: user-data")
PYEOF
