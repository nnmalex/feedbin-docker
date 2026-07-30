#!/bin/sh
set -e

# Extract reads its credentials from a YAML file (username: secret).
# Generate it from the environment so the compose file is the single
# source of truth for the shared secret.
if [ -n "$EXTRACT_USER" ] && [ -n "$EXTRACT_SECRET" ]; then
  printf '%s: "%s"\n' "$EXTRACT_USER" "$EXTRACT_SECRET" > /app/users.yml
  export EXTRACT_USERS=/app/users.yml
fi

exec "$@"
