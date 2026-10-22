# JetKVM cloud UI (the `ui/` app from jetkvm/kvm, built in cloud-production mode)
# served by nginx.
#
#   docker build --build-arg KVM_REF=release/0.5.9 -t ghcr.io/vvlasy/jetkvm-cloud-ui:0.5.9 .
#
# The API URL is a build-time constant in Vite. To keep one image usable for
# several environments, the build bakes in a placeholder and the container
# replaces it at start from the CLOUD_API_URL env var (see 40-cloud-api-url.sh).
# Pass --build-arg VITE_CLOUD_API=https://api.example.com to bake a real value
# instead; the start script then does nothing.

ARG NODE_VERSION=22.23.4
ARG NGINX_VERSION=1.28-alpine
ARG KVM_REPO=https://github.com/jetkvm/kvm.git
# Full commit SHA (40 chars), tag or branch of jetkvm/kvm. Must match the firmware line your devices run.
ARG KVM_REF=release/0.5.9
ARG VITE_CLOUD_API=https://__JETKVM_CLOUD_API__
# "true" enables the per-device-version UI switcher in 0.5.9+. Keep off for a single self-hosted build.
ARG VITE_CLOUD_ENABLE_VERSIONED_UI=false

# ---------------------------------------------------------------- build
FROM node:${NODE_VERSION}-alpine AS build
ARG KVM_REPO
ARG KVM_REF
ARG VITE_CLOUD_API
ARG VITE_CLOUD_ENABLE_VERSIONED_UI
RUN apk add --no-cache git
WORKDIR /src
RUN git init -q \
  && git remote add origin "${KVM_REPO}" \
  && git fetch -q --depth 1 origin "${KVM_REF}" \
  && git checkout -q FETCH_HEAD \
  && git rev-parse HEAD > /src/.git-sha \
  && rm -rf /src/.git
WORKDIR /src/ui
RUN npm ci
# .local takes precedence over the repo's .env.cloud-production without clobbering it
RUN printf 'VITE_CLOUD_API=%s\nVITE_CLOUD_ENABLE_VERSIONED_UI=%s\n' \
      "${VITE_CLOUD_API}" "${VITE_CLOUD_ENABLE_VERSIONED_UI}" > .env.cloud-production.local \
  && npm run build:prod \
  && cp /src/.git-sha dist/.git-sha

# ---------------------------------------------------------------- serve
FROM nginx:${NGINX_VERSION}
ARG KVM_REF
LABEL org.opencontainers.image.source="https://github.com/jetkvm/kvm" \
      org.opencontainers.image.revision="${KVM_REF}" \
      org.opencontainers.image.description="JetKVM cloud UI (self-hosted build)"
COPY nginx-default.conf /etc/nginx/conf.d/default.conf
COPY 40-cloud-api-url.sh /docker-entrypoint.d/40-cloud-api-url.sh
RUN chmod +x /docker-entrypoint.d/40-cloud-api-url.sh
COPY --from=build /src/ui/dist /usr/share/nginx/html
EXPOSE 80
