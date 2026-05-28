# arti-docker

A minimal container image for [Arti](https://gitlab.torproject.org/tpo/core/arti) — the Rust implementation of Tor — bundled with a SOCKS5-capable `curl` so the SOCKS proxy can be health-checked with real traffic.

## Motivation

The existing arti container images (and arti itself) expose a SOCKS5 proxy on port `9150`, but provide no way to verify the proxy is *actually usable*. A naive container health check that probes the TCP port flips green the moment arti binds the socket — potentially before a working Tor circuit has been built. That false-positive makes the container appear healthy while every connection through it still fails.

This image solves that by adding `curl` with SOCKS5 support, so a health check can send real traffic *through* arti and only succeed once arti has finished bootstrapping a circuit:

```sh
curl --socks5-hostname localhost:9150 -fsS -o /dev/null -m 15 https://check.torproject.org/api/ip
```

The endpoint at `check.torproject.org` only responds when reached over Tor, so a passing health check proves end-to-end Tor reachability, not just port binding.

The intended use case is as an ECS task sidecar feeding another container that needs to dial onion services or reach the clearnet over Tor.

One downside is that the health of the service now depends on the availability of the `check.torproject.org` endpoint over Tor. A solution would be to point the health check to an endpoint you control.

## Image tags

Images are published to GHCR on every push to `main`:

- `ghcr.io/probe-lab/arti-docker:arti-<arti-version>-<short-sha>`

The registry receives a multi-arch manifest (`linux/amd64` + `linux/arm64`). Tags are immutable per build, e.g. `arti-2.3.0-a1b2c3d`.

## Usage

### Run the proxy

```sh
docker run --rm -p 9150:9150 ghcr.io/probe-lab/arti-docker:arti-2.3.0-a1b2c3d
```

The container listens on `0.0.0.0:9150` so the SOCKS port is reachable from other containers, hosts, or sidecars sharing the network namespace.

### Verify connectivity

```sh
curl --socks5-hostname localhost:9150 -fsS https://check.torproject.org/api/ip
```

### Container health check

The image is designed to be paired with a health check that sends real traffic through the proxy. Example for an ECS task definition:

```hcl
healthCheck = {
  command = [
    "CMD-SHELL",
    "curl --socks5-hostname localhost:9150 -fsS -o /dev/null -m 15 https://check.torproject.org/api/ip",
  ]
  interval    = 30
  timeout     = 20
  retries     = 10
  startPeriod = 120  # Tor bootstrap takes ~30-60s on a cold start
}
```

`startPeriod` should comfortably exceed the typical Tor bootstrap time so the container isn't killed before its first circuit is built.

## Configuration

By default the container runs `arti -o 'proxy.socks_listen="0.0.0.0:9150"' proxy`. To override:

```sh
# Different port
docker run --rm -p 1080:1080 ghcr.io/probe-lab/arti-docker:<tag> \
  -o 'proxy.socks_listen="0.0.0.0:1080"' proxy

# Custom config file
docker run --rm -v $(pwd)/arti.toml:/etc/arti.toml ghcr.io/probe-lab/arti-docker:<tag> \
  -c /etc/arti.toml proxy
```

See the [Arti CLI reference](https://gitlab.torproject.org/tpo/core/arti/-/blob/main/crates/arti/README.md) and the [config schema](https://gitlab.torproject.org/tpo/core/arti/-/blob/main/crates/arti/src/arti-example-config.toml) for the full set of options.

## Building locally

```sh
docker build -t arti:local --build-arg VERSION=2.3.0 .
```

Build arguments:

- `VERSION` — arti release tag from the upstream repo (default `2.3.0`)
- `RUST_VERSION` — Rust toolchain version (default `1.94`)

The build is a two-stage multi-stage build: it clones the official [`tpo/core/arti`](https://gitlab.torproject.org/tpo/core/arti) repository, statically links arti against musl + OpenSSL + SQLite, and copies the stripped binary into an Alpine runtime with `curl` and `ca-certificates`.

## CI

`.github/workflows/build-and-push.yml` builds for both architectures on native GitHub runners (`ubuntu-latest` for amd64, `ubuntu-24.04-arm` for arm64), pushes per-arch images by digest, then merges them into a single multi-arch manifest.

## License

Arti is distributed under the MIT / Apache-2.0 dual license by the Tor Project. This repository's packaging (Dockerfile, workflow) is provided under the same terms.

- Upstream source: <https://gitlab.torproject.org/tpo/core/arti>
- Arti documentation: <https://arti.torproject.org>
