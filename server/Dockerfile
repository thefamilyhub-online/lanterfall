# Lanternfall dedicated server: runs the game headless (no graphics).
# Build from the repo root:  docker compose -f server/docker-compose.yml up -d --build
FROM ubuntu:24.04

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot /tmp/godot.zip

RUN useradd --create-home lanternfall && mkdir -p /data && chown lanternfall:lanternfall /data
WORKDIR /game
COPY --chown=lanternfall:lanternfall . /game
USER lanternfall

# Import resources once at build time so the server starts fast.
RUN godot --headless --path /game --import > /dev/null 2>&1 || true

ENV LANTERNFALL_DATA=/data \
    LANTERNFALL_PORT=7777
EXPOSE 7777/udp

CMD ["godot", "--headless", "--path", "/game", "--", "--server"]
