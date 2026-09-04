#!/bin/sh
set -e
cd "$(dirname "$0")"
docker run --rm -v "$PWD:/src" -w /src debian:bookworm bash -c '
  dpkg --add-architecture armhf
  apt-get update -qq
  apt-get install -y -qq g++-arm-linux-gnueabihf zlib1g-dev:armhf > /dev/null
  arm-linux-gnueabihf-g++ -O2 -std=c++11 \
    -Istubs -I. \
    gpt-utils.cpp bootctl.cpp main.cpp \
    -lz -static-libgcc -static-libstdc++ \
    -o bootctl-anki-arm
'
file bootctl-anki-arm
ls -la bootctl-anki-arm
