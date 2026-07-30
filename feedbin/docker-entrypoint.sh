#!/bin/sh
set -e

# Rails' HostAuthorization (config.hosts, config/environments/production.rb)
# reads ENV["FEEDBIN_HOST"] as a comma-separated allow-list. FEEDBIN_HOST
# itself must stay a single hostname at the compose level (FEEDBIN_URL,
# DEFAULT_URL_OPTIONS_HOST, and PUSH_URL are built from it), so an optional
# extra hostname (e.g. an api.* host for API clients) is appended here,
# after those other vars are already fixed, rather than in docker-compose.yml.
if [ -n "$FEEDBIN_API_HOST" ]; then
  export FEEDBIN_HOST="$FEEDBIN_HOST,$FEEDBIN_API_HOST"
fi

case "$1" in
  web)
    # Idempotent: creates + loads schema on first run, migrates afterwards.
    # SAFETY_ASSURED bypasses strong_migrations checks meant for zero-downtime
    # multi-server deploys, which don't apply to a single-host setup.
    SAFETY_ASSURED=1 bin/rails db:prepare
    exec bundle exec pitchfork -c config/pitchfork.rb -l 0.0.0.0:8080 config.ru
    ;;
  workers)
    # sidekiq-development.yml is the only queue config the repo ships; it
    # lists every queue Feedbin uses, including the hostname-derived ones
    # (which match because all Feedbin containers share hostname "feedbin").
    exec bundle exec sidekiq -C config/sidekiq-development.yml
    ;;
  clock)
    exec bundle exec clockwork lib/clock.rb
    ;;
  *)
    exec "$@"
    ;;
esac
