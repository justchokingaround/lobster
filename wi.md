## Contents

1. <a href="#lobster-editor">Lobster Editor</a>
2. <a href="#player">Player</a>
3. <a href="#download-directory">Download Directory</a>
4. <a href="#provider">Provider</a>
5. <a href="#history">History</a>
6. <a href="#subtitle-language">Subtitle Language</a>
7. <a href="#history-file">History File</a>
8. <a href="#rofi">Rofi</a>
9. <a href="#image-preview">Image Preview</a>
10. <a href="#debug">Debug</a>
11. <a href="#download-video">Download Video</a>

## Introduction

Lobster is a posix shell script that scrapes [flixhq](https://flixhq.to) and allows you to stream and download movies and tv shows, with various features such as history, image previews, and more.

I have a habit of implementing new features before documenting them properly, but I will try to keep this document up to date. If you have any questions, always feel free to open an issue, start a discussion, or contact me directly. I am always happy to help. :)

## Lobster Editor

- The `lobster_editor` is used to edit the lobster config file
- By default, this value is set to the `$VISUAL` environment variable, or `$EDITOR` if `$VISUAL` is not set. If neither are set, it defaults to `vim`
- You can change this value by setting the `lobster_editor` variable in your lobster config file (which is located at `~/.config/lobster/lobster_config.txt` by default)
- Both a terminal and graphical editor can be used

Example (using [lite-xl](https://github.com/lite-xl/lite-xl)):

```sh
lobster_editor=lite-xl
```

To then use this feature, you can run the following command:

```sh
lobster -e
```

or

```sh
lobster --edit
```

## Player

- The `player` variable is used to set the default player for lobster to use
- By default, this value is set to `mpv`
- You can change this value by setting the `player` variable in your lobster config file
- Any player that can play an m3u8 stream can be used, the script will use the `player` variable and pass the `video_link` (stream url) to it
- Here is a list of players that lobster has been tested with:
  - [mpv](https://mpv.io)
  - [vlc](https://www.videolan.org/vlc/index.html) (no subtitles support)
  - [iina](https://iina.io) (macOS only)
  - [celluloid](https://celluloid-player.github.io) (Linux only)
  - [syncplay](https://syncplay.pl) (please check the [syncplay](https://github.com/justchokingaround/lobster#-s----syncplay-argument) section of the README for more information)

Example (using celluloid):

```sh
player=celluloid
```

Note: only `mpv` supports the history feature, other players can only be used to stream content

## Download Directory

- The `download_dir` variable is used to set the default download directory for lobster to use
- By default, this value is set to `$PWD`
- You can change this value by setting the `download_dir` variable in your lobster config file
- The `download_dir` variable can be set to any directory, but it is recommended to set it to a directory that is not temporary, as the script will not check if the directory exists before downloading the video

Example:

```sh
download_dir=~/Videos
```

To then use this feature, you can run the following command:

```sh
lobster -d
```

or

```sh
lobster --download
```

## Provider

- The `provider` variable is used to set the default provider for lobster to use
- By default, this value is set to `UpCloud`
- Here is a list of the currently supported providers:
  - UpCloud
  - Vidcloud

It is currently not my priority to implement more providers, but I will try to add more in the future. I am also open to pull requests if you would like to add more providers yourself.

Example (using Vidcloud):

```sh
provider=Vidcloud
```

## History

- The `history` variable is used to set the default history feature for lobster to use
- By default, this value is set to `0`
- The history feature allows you to keep track of the movies and tv shows you have watched, while also allowing you to conveniently resume them from the exact second you left off (similar to YouTube or Netflix)
- This feature requires you to use `mpv` as your player and have `socat` installed (to interact with mpv's socket)
- Accepted values are `0` and `1`

Example of how to enable the history feature:

```sh
history=1
```

To then use this feature, you can either look up a movie or tv show you have watched before and play it, or you can run the following command, in order to view your current history:

```sh
lobster -c
```

or

```sh
lobster --continue
```

## Subtitle Language

- The `subs_language` variable is used to set the default subtitle language for lobster to use
- By default, this value is set to `english`
- This variable can be set to any language that is supported by the provider you are using
- Both the `english` and `English` syntaxes are supported

Example (using spanish):

```sh
subs_language=spanish
```

## History File

- The `histfile` variable is used to set the default history file for lobster to use
- By default, this value is set to `$HOME/.local/share/lobster/lobster_history.txt`

Example:

```sh
histfile=~/.config/lobster/foo.bar
```

## Rofi

- The `use_external_menu` variable is used to tell lobster whether to use rofi or fzf as the selection menu
- By default, this value is set to `0` (meaning fzf will be used)
- The purpose of this feature is to allow you to use rofi as the selection menu, which will allow you to use the script without having to launch a terminal windows
- Make sure you have `rofi` installed
- Accepted values are `0` and `1`

Example:

```sh
use_external_menu=1
```

## Image Preview

- The `image_preview` variable is used to set the default image preview feature for lobster to use
- By default, this value is set to `0`
- The image preview feature allows you to preview the posters of movies and tv shows during the selection process
- Accepted values are `0` and `1`
- To use this feature:

  - Using fzf:

    - You must have `ueberzugpp` installed, please refer to [this part of the README for installation instructions](https://github.com/justchokingaround/lobster#-i----image-preview-argument)

  - Using rofi:

    - Make sure your `rofi` configuration has `show-icons` set to `true`, otherwise the feature will not work
    - You can specify a specific configuration file to use by setting the `image_config_path` variable in your lobster config
    - If you would like the menu to look like the one in the screenshot, please checkout the TODO section of the wiki

Example using fzf:

```sh
image_preview=1
```

Example using rofi (with a custom theme):

```sh
use_external_menu=1
image_preview=1
image_config_path=~/.config/rofi/styles/launcher.rasi
```

## Debug Mode

- The `debug` variable is used to set the default debug mode for lobster to use
- By default, this value is set to `0`
- Accepted values are `0` and `1`
- After running the script with the debug mode enabled, you can find the debug log in the `/tmp/lobster.log` file

Note: fzf prints the finder to stderr, so this will also be redirected to stdout, and by extension printed to the terminal and saved to the log file.

## Download Video Function

- The `download_video` function is used to download the video of the movie or tv show you are currently watching, and it can be overridden in your lobster config file
- Inside of the `download_video` function, you can use the following variables, passed to the function by the script:
  - `$1` is the video link
  - `$2` the title
  - `$3` the path
  - `$4` the thumbnail (this is only passed to the function if the `image_preview` feature is enabled, and is currently untested)

Example of a custom `download_video` function using `yt-dlp`:

```sh
download_video() {
  yt-dlp "$1" --no-skip-unavailable-fragments --fragment-retries infinite -N 16 -o "$3/$2".mp4
}
```
