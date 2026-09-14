#!/usr/bin/env python3
"""Send a sample AudioFormatBar v1 player metadata message."""

from __future__ import annotations

import argparse
import json
import os
import socket
import time

SOCKET_PATH = os.path.expanduser(
    "~/Library/Application Support/AudioFormatBar/player.sock"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", default=SOCKET_PATH)
    parser.add_argument("--bundle-id", default="com.example.Player")
    parser.add_argument("--name", default="My Player")
    parser.add_argument("--pid", type=int)
    parser.add_argument("--audio-pid", type=int)
    args = parser.parse_args()

    player_pid = args.pid or os.getpid()
    audio_pid = args.audio_pid or player_pid

    message = {
        "version": 1,
        "type": "state",
        "sent_at_ms": int(time.time() * 1000),
        "expires_in_ms": 5000,
        "sequence": 1,
        "player": {
            "bundle_id": args.bundle_id,
            "name": args.name,
            "pid": player_pid,
            "audio_pid": audio_pid,
        },
        "playback": {
            "state": "playing",
            "track": {
                "title": "Example Track",
                "artist": "Example Artist",
                "album": "Example Album",
                "url": "file:///Users/example/Music/example.flac",
            },
        },
        "source": {
            "codec": "FLAC",
            "sample_rate": 96000,
            "bit_depth": 24,
            "channels": 2,
            "lossless": True,
        },
        "output": {
            "hog_mode": True,
            "sample_rate": 96000,
            "bit_depth": 32,
            "non_mixable": True,
            "dsp": False,
            "bit_perfect": True,
        },
    }

    payload = (json.dumps(message, ensure_ascii=False) + "\n").encode("utf-8")

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(args.socket)
        client.sendall(payload)

    print(f"Sent sample metadata to {args.socket}")


if __name__ == "__main__":
    main()
