# Feedbin built from source (https://github.com/feedbin/feedbin).
# Pin a specific commit/tag with: docker compose build --build-arg FEEDBIN_REF=<ref>

FROM ruby:4.0.4-slim

# HEAD = the repo's default branch; also accepts a SHA, tag, or branch name.
ARG FEEDBIN_REF=HEAD

ENV RAILS_ENV=production \
    RACK_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_LOG_TO_STDOUT=true

# Build deps (native gems: pg, nokogiri, llhttp, ruby-vips, ffi) and runtime
# libs. nodejs provides the JS runtime uglifier/execjs needs at precompile.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      libcurl4-openssl-dev \
      libffi-dev \
      libidn11-dev \
      libpq-dev \
      libssl-dev \
      libvips-dev \
      libyaml-dev \
      nodejs \
      pkg-config \
      postgresql-client \
      shared-mime-info \
      tzdata \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone https://github.com/feedbin/feedbin.git /app \
    && { git -C /app checkout --detach "$FEEDBIN_REF" \
         || git -C /app checkout --detach "origin/$FEEDBIN_REF"; } \
    && rm -rf /app/.git

RUN bundle install

# Dummy values so Rails can boot for asset precompilation without real
# services attached; none of them end up in the compiled assets.
RUN SECRET_KEY_BASE=dummy-key-for-precompile-only \
    DATABASE_URL=postgres://dummy:dummy@127.0.0.1:5432/dummy \
    REDIS_URL=redis://127.0.0.1:6379/0 \
    ELASTICSEARCH_URL=http://127.0.0.1:9200 \
    bundle exec rails assets:precompile

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

EXPOSE 8080

ENTRYPOINT ["docker-entrypoint"]
CMD ["web"]
