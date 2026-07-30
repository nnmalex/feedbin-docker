#!/usr/bin/env bash
# Creates (or repairs) a Feedbin login: seeds the Plans table if it's empty,
# then creates the user or, if the email already exists, fixes a nil plan_id
# left over from signing up before Plans were seeded.
#
# Usage: scripts/create-user.sh <email> <password> [--admin]
set -euo pipefail

EMAIL="${1:?Usage: $0 <email> <password> [--admin]}"
PASSWORD="${2:?Usage: $0 <email> <password> [--admin]}"
ADMIN="false"
[ "${3:-}" = "--admin" ] && ADMIN="true"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker compose exec -T \
  -e PROVISION_EMAIL="$EMAIL" \
  -e PROVISION_PASSWORD="$PASSWORD" \
  -e PROVISION_ADMIN="$ADMIN" \
  web bin/rails runner - < "$SCRIPT_DIR/provision_user.rb"
