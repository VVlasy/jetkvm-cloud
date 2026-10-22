# JetKVM cloud-api, built from a pinned upstream commit.
#
# Based on upstream's Dockerfile (jetkvm/cloud-api @ d08418e) but fetches the
# source itself, so the build context is this directory only and the result is
# reproducible from CLOUD_API_REF. Unlike upstream (ts-node at start-up) the
# app is compiled with tsc and run from dist/, which boots faster and uses
# less memory; the full dependency set is kept because the `prisma` CLI is a
# devDependency and the chart's migrate init container needs it.
#
#   docker build --build-arg CLOUD_API_REF=<full-sha-or-tag> -t ghcr.io/vvlasy/jetkvm-cloud-api:<tag> .
#
# Migrations are NOT run here; the chart runs `npx prisma migrate deploy` in an
# init container from this same image.

ARG NODE_VERSION=22.23.4
ARG CLOUD_API_REPO=https://github.com/jetkvm/cloud-api.git
# Full commit SHA (40 chars), tag, or branch. Default: main @ 2026-10-21 (Node 22.23.4 security bump).
ARG CLOUD_API_REF=d08418e650b6a03c17dbdc90bbd7cde2b105c7f2

# ---------------------------------------------------------------- source
FROM node:${NODE_VERSION}-bookworm-slim AS src
ARG CLOUD_API_REPO
ARG CLOUD_API_REF
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# `git fetch <ref>` accepts full SHAs, tags and branches; `clone --branch` does not take SHAs.
RUN git init -q \
  && git remote add origin "${CLOUD_API_REPO}" \
  && git fetch -q --depth 1 origin "${CLOUD_API_REF}" \
  && git checkout -q FETCH_HEAD \
  && git rev-parse HEAD > /src/.git-sha \
  && rm -rf /src/.git

# ---------------------------------------------------------------- app
FROM node:${NODE_VERSION}-bookworm-slim
ARG CLOUD_API_REF
LABEL org.opencontainers.image.source="https://github.com/jetkvm/cloud-api" \
      org.opencontainers.image.revision="${CLOUD_API_REF}" \
      org.opencontainers.image.description="JetKVM cloud-api (self-hosted build)"

# Prisma needs OpenSSL at runtime
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
COPY --from=src --chown=node:node /src/package.json /src/package-lock.json ./
COPY --from=src --chown=node:node /src/prisma ./prisma
RUN npm ci && npm cache clean --force

COPY --from=src --chown=node:node /src ./
RUN npx prisma generate && npm run build

ENV NODE_ENV=production \
    PORT=3000
EXPOSE 3000
USER node
CMD ["node", "./dist/index.js"]
