FROM debian:stable-slim AS builder
WORKDIR /build
#install deps
RUN apt-get update && \
    apt-get install -y libass-dev libbz2-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev \
    libnuma-dev libogg-dev libopus-dev libsamplerate-dev libspeex-dev libtheora-dev libtool libtool-bin libturbojpeg0-dev libvorbis-dev libx264-dev \
    libxml2-dev libvpx-dev autoconf automake build-essential cmake git m4 make meson nasm ninja-build patch pkg-config tar zlib1g-dev curl
# build handbrake
RUN git clone https://github.com/HandBrake/HandBrake.git && cd ./HandBrake && \
    ./configure --disable-gtk --disable-gtk-update-checks --disable-nvenc --enable-fdk-aac --snapshot --launch-jobs=$(nproc) --launch && \
    mv ./build/HandBrakeCLI /usr/local/bin/handbrake

FROM jrottenberg/ffmpeg:4.3.1-ubuntu2004
COPY --from=builder /usr/local/bin/handbrake /usr/local/bin/
RUN apt-get update && \
    # apt-get install -y libass-dev libmp3lame-dev libvpx-dev libtheora0 libvorbis-dev libx264-dev libjansson-dev libopus-dev libspeex-dev libturbojpeg0-dev libnuma-dev