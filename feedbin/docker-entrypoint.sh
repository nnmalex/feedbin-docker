#!/bin/sh
set -e

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
