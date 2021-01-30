FROM debian:buster-slim AS handbrake_builder
WORKDIR /build
#install deps
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y autoconf automake autopoint build-essential cmake git libass-dev libbz2-dev \
    libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev libnuma-dev libogg-dev \
    libopus-dev libsamplerate-dev libspeex-dev libtheora-dev libtool libtool-bin libvorbis-dev libx264-dev libx265-dev libxml2-dev libvpx-dev \
    m4 make nasm ninja-build patch pkg-config python tar zlib1g-dev meson libturbojpeg-dev
# build handbrake
RUN git clone https://github.com/HandBrake/HandBrake.git && cd ./HandBrake \
    && ./configure --disable-gtk --disable-gtk-update-checks --disable-nvenc --enable-fdk-aac --launch-jobs=$(nproc) --launch \
    && mv ./build/HandBrakeCLI /usr/local/bin/handbrake

# see https://github.com/zimbatm/ffmpeg-static
FROM debian:buster-slim AS ffmpeg_builder
WORKDIR /build
#install deps
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y bzip2 perl tar wget xz-utils autoconf automake bash build-essential cmake curl \
    frei0r-plugins-dev gawk libfontconfig-dev libfreetype6-dev libopencore-amrnb-dev libopencore-amrwb-dev libsdl2-dev libspeex-dev libtheora-dev \
    libtool libva-dev libvdpau-dev libvo-amrwbenc-dev libvorbis-dev libwebp-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev libxvidcore-dev \
    lsb-release pkg-config sudo tar texi2html yasm
COPY ffmpeg_build.sh download.pl env.source fetchurl /build/
# build ffmpeg
RUN chmod +x download.pl fetchurl && bash ffmpeg_build.sh -j$(nproc) && mv ./bin/ffmpeg ./bin/ffprobe /usr/local/bin/

FROM debian:buster-slim
COPY --from=handbrake_builder /usr/local/bin/handbrake /usr/local/bin/
COPY --from=ffmpeg_builder /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /usr/local/bin/
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get install -y libass-dev libmp3lame-dev libvpx-dev libtheora-dev libvorbis-dev libx264-dev libx265-dev libjansson-dev libopus-dev \
    libspeex-dev libturbojpeg0-dev libnuma-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev libogg-dev libsamplerate-dev \
    && export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu
