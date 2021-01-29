FROM ubuntu:20.04 AS builder
WORKDIR /build
#install deps
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y autoconf automake autopoint build-essential cmake git libass-dev libbz2-dev \
    libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev libnuma-dev libogg-dev \
    libopus-dev libsamplerate-dev libspeex-dev libtheora-dev libtool libtool-bin libvorbis-dev libx264-dev libxml2-dev libvpx-dev m4 make nasm \
    ninja-build patch pkg-config python tar zlib1g-dev meson libturbojpeg-dev
# build handbrake
RUN git clone https://github.com/HandBrake/HandBrake.git && cd ./HandBrake \
    && ./configure --disable-gtk --disable-gtk-update-checks --disable-nvenc --enable-fdk-aac --launch-jobs=$(nproc) --launch \
    && mv ./build/HandBrakeCLI /usr/local/bin/handbrake

FROM jrottenberg/ffmpeg:4.3.1-ubuntu2004
COPY --from=builder /usr/local/bin/handbrake /usr/local/bin/
ENTRYPOINT []
# RUN apt-get update \
#     && apt-get install -y libass-dev libmp3lame-dev libvpx-dev libtheora0 libvorbis-dev libx264-dev libjansson-dev libopus-dev libspeex-dev libturbojpeg0-dev libnuma-dev \
#     && export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu
