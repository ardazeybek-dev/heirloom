# syntax=docker/dockerfile:1

# ---- build: compile the Gleam sources and bundle the CLI into one file
FROM node:22-alpine AS build
ARG GLEAM_VERSION=v1.19.2
RUN apk add --no-cache curl tar \
 && curl -fsSL "https://github.com/gleam-lang/gleam/releases/download/${GLEAM_VERSION}/gleam-${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz -C /usr/local/bin
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY gleam.toml manifest.toml ./
COPY src ./src
COPY scripts ./scripts
RUN gleam build && node scripts/bundle.mjs --cli-only

# ---- runtime: just Node and the bundle; run it with --network none
FROM node:22-alpine
RUN addgroup -S heirloom && adduser -S heirloom -G heirloom
WORKDIR /work
COPY --from=build /src/dist/heirloom.mjs /app/heirloom.mjs
USER heirloom
ENTRYPOINT ["node", "/app/heirloom.mjs"]
CMD ["--help"]
