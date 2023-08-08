#!/usr/bin/env python3
import subprocess
import sys
import re

from pypresence import Presence

CLIENT_ID = "1138159958748299265"

rpc_client = Presence(CLIENT_ID)
rpc_client.connect()


(
    _,
    mpv_executable,
    title,
    media,
    content_stream,
    subtitles,
    media_type,
    opts,
    *_,
) = sys.argv

if subtitles != "":
    args = [
        mpv_executable,
        content_stream,
        f"--force-media-title={title}",
        f"{subtitles}",
        "--msg-level=ffmpseg/demuxer=no",
        f"{opts}",
    ]
else:
    args = [
        mpv_executable,
        content_stream,
        f"--force-media-title={title}",
        "--msg-level=ffmpeg/demuxer=no",
        f"{opts}",
    ]

process = subprocess.Popen(
    args
)

if media_type == "tv":
    media_type = "TV Show"

file_path = '/tmp/lobster_position'

if media == "":
    media = "https://upload.wikimedia.org/wikipedia/commons/d/d5/Lobster_png_by_absurdwordpreferred_d2xqhvd.png"

while True:
    with open(file_path, 'r') as file:
        content = file.read()
    pattern = r'(\(Paused\)\s)?AV:\s([0-9:]*) / ([0-9:]*) \(([0-9]*)%\)'
    matches = re.findall(pattern, content)
    small_image = "https://cdn-icons-png.flaticon.com/128/3669/3669483.png"
    if matches:
        if matches[-1][0] == "(Paused) ":
            small_image = "https://cdn-icons-png.flaticon.com/128/3669/3669483.png"  # <- pause
            elapsed = matches[-1][1]
        else:
            small_image = "https://cdn-icons-png.flaticon.com/128/5577/5577228.png"  # <- play
            elapsed = matches[-1][1]
        duration = matches[-1][2]
        position = f"{elapsed} / {duration}"
    else:
        position = "00:00:00"

    rpc_client.update(
        details=title,
        state=position,
        large_image=media,
        small_image=small_image,
    )

    if process.poll() is not None:
        break

process.wait()
