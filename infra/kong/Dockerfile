FROM kong:3.9

USER root
RUN apt-get update && apt-get install -y gettext-base && rm -rf /var/lib/apt/lists/*

# Bake in the config template and entrypoint (as root so we can set ownership)
COPY infra/kong/kong.yml /etc/kong/kong.yml.template
COPY infra/kong/entrypoint.sh /entrypoint.sh
RUN chown kong:kong /etc/kong/kong.yml.template /entrypoint.sh && chmod +x /entrypoint.sh

USER kong

ENV KONG_DATABASE=off
ENV KONG_DECLARATIVE_CONFIG=/etc/kong/kong.yml
ENV KONG_PROXY_ACCESS_LOG=/dev/stdout
ENV KONG_ADMIN_ACCESS_LOG=/dev/stdout
ENV KONG_PROXY_ERROR_LOG=/dev/stderr
ENV KONG_ADMIN_ERROR_LOG=/dev/stderr
ENV KONG_PROXY_LISTEN=0.0.0.0:8000
ENV KONG_ADMIN_LISTEN=0.0.0.0:8001

EXPOSE 8000

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
