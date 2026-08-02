# The image contains no toolchain and runs no build step: site/dist is committed and copied in
# verbatim. A broken generator therefore cannot reach production — the worst it can do is fail
# review in a diff. Regenerating the site is a local step whose output is read before it ships.
FROM caddy:2-alpine

COPY site/Caddyfile /etc/caddy/Caddyfile
COPY site/dist /srv

# Fail the build on a malformed Caddyfile, rather than crash-looping the deployment.
RUN caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

EXPOSE 8080
