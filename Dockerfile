FROM alpine:3.18 AS patch_builder
WORKDIR /app

# Squash all the changes into a single patch
RUN apk add --no-cache git subversion make
COPY Makefile ./
COPY moc ./moc
RUN make 0001-Add-FluidSynth-decoder-plugin.patch

FROM debian:bookworm-slim AS builder

WORKDIR /app

# Download dependencies, MOC sources and copy the patch inside
RUN sed -i 's/^Types: deb/Types: deb deb-src/g' /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && apt-get build-dep --no-install-recommends -y moc \
 && apt-get install --no-install-recommends -y devscripts quilt libfluidsynth-dev libsmf-dev \
 && apt-get source moc \
 && rm -rf /var/lib/apt/lists/*
COPY --from=patch_builder /app/0001-Add-FluidSynth-decoder-plugin.patch .

# Apply the patch over the Debian package and build it
RUN cd ./*/ \
 && sed -i "s/^Build-Depends: /&libfluidsynth-dev, libsmf-dev, /g" debian/control \
 && echo "usr/lib/*/moc/decoder_plugins/libfluidsynth_decoder.so" >>debian/moc.install \
 && cp ../0001-Add-FluidSynth-decoder-plugin.patch debian/patches \
 && echo "0001-Add-FluidSynth-decoder-plugin.patch" >>debian/patches/series \
 && quilt push -a \
 && quilt refresh \
 && dch --nmu "Add FluidSynth decoder plugin" \
 && dpkg-buildpackage --unsigned-source --unsigned-changes

FROM debian:bookworm-slim

# For better caching, install first the official Debian MOC package to pull all dependencies
RUN apt-get update \
 && apt-get install -y --no-install-recommends moc moc-ffmpeg-plugin libsndio7.0 libfluidsynth3 libsmf0 pulseaudio \
 && rm -rf /var/lib/apt/lists/*

# Overwrite the official Debian MOC package with our version
COPY --from=builder /app/moc_*.deb /app/moc-ffmpeg-plugin_*.deb /pkgs/
RUN dpkg -i /pkgs/*

# Fixes showing files with non-ASCII names
ENV LANG="C.UTF-8"

# Set up a basic configuration for testing
RUN useradd -m user
USER user
WORKDIR /app/music
# This MIDI is made by user 'Dogman15' at English Wikipedia, licensed "CC BY 3.0" (https://creativecommons.org/licenses/by/3.0/).
ADD --chmod=666 https://upload.wikimedia.org/wikipedia/commons/5/55/MIDI_sample.mid .
CMD ["mocp"]
