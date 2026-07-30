# Feedbin's "extract" full-content extraction service, built from source
# (https://github.com/feedbin/extract). Node 26 per upstream requirements.

FROM node:26-slim

# HEAD = the repo's default branch; also accepts a SHA, tag, or branch name.
ARG EXTRACT_REF=HEAD

ENV NODE_ENV=production \
    PORT=3000

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone https://github.com/feedbin/extract.git /app \
    && { git -C /app checkout --detach "$EXTRACT_REF" \
         || git -C /app checkout --detach "origin/$EXTRACT_REF"; } \
    && rm -rf /app/.git

RUN npm ci --omit=dev

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

EXPOSE 3000

ENTRYPOINT ["docker-entrypoint"]
CMD ["node", "app/server.js"]
