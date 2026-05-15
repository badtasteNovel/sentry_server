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

source .env

# Validate required vars
for var in UBUNTU_PASSWORD_HASH SENTRY_DOMAIN ADMIN_EMAIL ADMIN_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

python3 - << PYEOF
import os, re, sys

replacements = {
    '__UBUNTU_PASSWORD_HASH__': os.environ['UBUNTU_PASSWORD_HASH'],
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
