# Container (Podman / GHCR)

Agent handbook: [`AGENTS.md`](../AGENTS.md). Fedora host packages: [`development.md`](development.md). Release tagging: [`build-and-release.md`](build-and-release.md).

## Slim Linux runtime image

A multi-stage [`Containerfile`](../Containerfile) builds the Flutter Linux release bundle in a throwaway stage and ships only **`omniscope:runtime`** (GTK/EGL runtime libs + the bundle). No Flutter SDK in the final image. Linux/x64 GUI only — forward the host display.

```bash
make container-build     # podman build -t omniscope:runtime
make container-run       # needs DISPLAY; mounts /tmp/.X11-unix
```

## GitHub Container Registry

On each `v*` tag (and via **Actions → Container → Run workflow**), CI builds the same [`Containerfile`](../Containerfile) and pushes to GitHub Container Registry:

```bash
# After a release tag (example)
podman pull ghcr.io/fabriziosta/omniscope:latest
# or: podman pull ghcr.io/fabriziosta/omniscope:1.0.1
podman run --rm -it -e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  ghcr.io/fabriziosta/omniscope:latest
```

Packages start **private** on first publish; set visibility under the repo’s **Packages** settings if you want public pulls. Auth for private images: [GitHub Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

## Sync rules

Do not bake secrets into the image.

Whenever Linux OS packages (builder or runtime), Flutter install channel/flags used in the Containerfile, or the Linux bundle packaging path change, update [`Containerfile`](../Containerfile) in the **same** change. Keep the Fedora build list in [`development.md`](development.md) and CI `apt-get` Linux deps consistent with the builder stage. Do not leave the image definition stale.
