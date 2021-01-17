FROM debian:stable-slim AS builder
WORKDIR /build
#install deps
RUN apt-get update && \
    apt-get install -y libass-dev libbz2-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev \
    libnuma-dev libogg-dev libopus-dev libsamplerate-dev libspeex-dev libtheora-dev libtool libtool-bin libturbojpeg0-dev libvorbis-dev libx264-dev \
    libxml2-dev libvpx-dev autoconf automake build-essential cmake git m4 make meson nasm ninja-build patch pkg-config tar zlib1g-dev curl gperf
# build ffmpeg
COPY ./ffmpeg_build.sh ./ffmpeg/ffmpeg_build.sh
RUN cd ./ffmpeg && /bin/bash ./ffmpeg_build.sh --build --full-static && cd ../ && rm -rf ./ffmpeg
# build handbrake
RUN git clone https://github.com/HandBrake/HandBrake.git && cd ./HandBrake && \
    ./configure --disable-gtk --disable-gtk-update-checks --disable-nvenc --enable-fdk-aac --snapshot --launch-jobs=$(nproc) --launch && \
    mv ./build/HandBrakeCLI /usr/local/bin/handbrake && cd ../ && rm -rf ./HandBrake

FROM python:3.9-slim-buster
WORKDIR /root
COPY --from=builder /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /usr/local/bin/handbrake /usr/local/bin/
RUN chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /usr/local/bin/handbrake
RUN apt-get update && \
    apt-get install -y libass-dev libmp3lame-dev libvpx-dev libtheora0 libvorbis-dev libx264-dev libjansson-dev libopus-dev libspeex-dev libturbojpeg0-dev libnuma-dev