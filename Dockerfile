# ============================================================================
# Deadline Board — container image
#
# A static site served by Caddy. There is no build step: the application is a
# single self-contained HTML file, so the image is just Caddy plus that file.
# Railway detects this Dockerfile and needs no further configuration.
# ============================================================================

# Pinned to a specific Caddy release so a future Caddy change cannot alter the
# behaviour of a redeploy. Bump this deliberately, not accidentally.
FROM caddy:2.8.4-alpine

# ---- server configuration --------------------------------------------------
COPY Caddyfile /etc/caddy/Caddyfile

# ---- the application -------------------------------------------------------
# ONLY the public directory is copied in. The SQL migrations, the test suite
# and the documentation stay out of the image, so they can never be requested
# over HTTP even by guessing the path.
COPY public/ /srv/public/

# ---- start-up --------------------------------------------------------------
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Run as an unprivileged user. Caddy needs no root privileges here: it binds a
# high port and serves read-only files.
RUN addgroup -g 10001 -S app \
 && adduser  -u 10001 -S app -G app \
 && mkdir -p /srv/public /config /data \
 && chown -R app:app /srv/public /config /data

USER app

# Default for running the image outside Railway. Railway overrides PORT.
ENV PORT=8080
EXPOSE 8080

# Validate the config at build time: a Caddyfile typo fails the build rather
# than producing an image that crash-loops on deploy.
RUN caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
