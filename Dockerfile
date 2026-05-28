ARG VERSION=2.3.0
ARG RUST_VERSION=1.94

FROM rust:${RUST_VERSION}-alpine AS builder

ARG VERSION

WORKDIR /app

RUN apk add --no-cache \
      git \
      musl-dev \
      openssl-dev \
      openssl-libs-static \
      sqlite-dev \
      sqlite-static

RUN git clone https://gitlab.torproject.org/tpo/core/arti.git . \
 && git checkout "arti-v${VERSION}"

RUN cargo build -p arti --release --locked --features=onion-service-service \
 && strip target/release/arti

FROM alpine:latest AS runner

ARG VERSION

LABEL org.opencontainers.image.title="arti" \
      org.opencontainers.image.description="Arti (Tor in Rust) SOCKS proxy with SOCKS-capable curl for health checks" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/probe-lab/arti-docker" \
      org.opencontainers.image.url="https://gitlab.torproject.org/tpo/core/arti"

RUN apk add --no-cache curl ca-certificates tini \
 && adduser -D -h /home/arti arti

COPY --from=builder /app/target/release/arti /usr/local/bin/arti

WORKDIR /home/arti
USER arti

EXPOSE 9150

ENTRYPOINT ["/sbin/tini", "--", "arti"]
CMD ["-o", "proxy.socks_listen=\"0.0.0.0:9150\"", "proxy"]
