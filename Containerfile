# Multi-stage build: Flutter Linux release → slim runtime image (omniscope:runtime).
# Builder stage is discarded; final image has GTK/EGL runtime libs + the release bundle only.
#
# When Linux OS packages (builder or runtime), Flutter install channel/flags, or the
# Linux bundle path change, update this file in the same change. Keep README Fedora
# build list + CI apt-get list consistent with the builder stage.

# -----------------------------------------------------------------------------
# Builder
# -----------------------------------------------------------------------------
FROM fedora:42 AS builder

RUN dnf install -y --setopt=install_weak_deps=False \
    clang \
    cmake \
    ninja-build \
    gtk3-devel \
    pkgconf-pkg-config \
    xz-libs \
    libstdc++-devel \
    mesa-libEGL-devel \
    git \
    curl \
    unzip \
    xz \
    zip \
    which \
    make \
    ca-certificates \
  && dnf clean all

ENV FLUTTER_ROOT=/opt/flutter
ENV PATH="${FLUTTER_ROOT}/bin:${PATH}"
# Rootless Podman: Flutter's precache tarballs fail on chown without this.
ENV TAR_OPTIONS=--no-same-owner

RUN git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${FLUTTER_ROOT}" \
  && flutter config --no-analytics \
  && flutter precache --linux \
  && flutter doctor

WORKDIR /src

COPY . .

RUN cp -n .env.example .env \
  && flutter pub get \
  && flutter build linux --release

# -----------------------------------------------------------------------------
# Runtime (final)
# -----------------------------------------------------------------------------
FROM fedora:42

# OCI labels link the GHCR package to this repo (override SOURCE_REPO in CI).
ARG SOURCE_REPO=https://github.com/fabriziosta/omniscope
LABEL org.opencontainers.image.source=$SOURCE_REPO
LABEL org.opencontainers.image.description="Omniscope Linux desktop (slim runtime)"
LABEL org.opencontainers.image.licenses=MIT

RUN dnf install -y --setopt=install_weak_deps=False \
    gtk3 \
    mesa-libEGL \
    libstdc++ \
    mesa-dri-drivers \
    libX11 \
  && dnf clean all

COPY --from=builder /src/build/linux/x64/release/bundle/ /opt/omniscope/

WORKDIR /opt/omniscope

CMD ["/opt/omniscope/omniscope"]
