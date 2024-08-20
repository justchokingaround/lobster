### Showcase

https://github.com/justchokingaround/lobster/assets/44473782/d597335c-42a9-4e45-8948-122744aa5ca9

## Join the discord server (it is bridged to the matrix space)

### https://discord.gg/JTDS2CKjQU

## Join the matrix server (I am more active there)

### https://matrix.to/#/#lobster-and-jerry:matrix.org

## Overview

- [Install](#install)
  - [Arch linux](#arch)
  - [Debian linux](#debian-using-makedeb-and-mist)
  - [Linux](#linux-from-source)
  - [Android](#android-requires-termux-and-mpv-android)
  - [NixOS](#nixos-flake)
  - [Mac](#mac)
  - [Windows](#windows)
- [Usage](#usage)
  - [`-c` / `--continue`](#-c----continue-argument)
  - [`--clear-history / --delete-history`](#--clear-history----delete-history-argument)
  - [`-d` / `--download`](#-d----download-path-argument)
  - [`--discord` / `--discord-presence` / `--rpc` / `--presence`](#--discord----discord-presence----rpc----presence-argument)
  - [`-e` / `--edit`](#-e----edit-argument)
  - [`-i` / `--image-preview`](#-i----image-preview-argument)
  - [`-j` / `--json`](#-j----json-argument)
  - [`-l` / `--language`](#-l----language-language-argument)
  - [`--rofi` / `--external-menu`](#--rofi----external-menu-argument)
  - [`-p` / `--provider`](#-p----provider-provider-argument)
  - [`-q` / `--quality`](#-q----quality-quality-argument)
  - [`--quiet`](#--quiet-argument)
  - [`-r` / `--recent`](#r----recent-tvmovie-argument)
  - [`-s` / `--syncplay`](#-s----syncplay-argument)
  - [`-t` / `--trending`](#-t----trending-argument)
  - [`-u` / `-U` / `--update`](#u---u----update-argument)
  - [`-v` / `-V` / `--version`](#v---v----version-argument)
  - [`-x` / `--debug`](#-x----debug-argument)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [Uninstall](#uninstall)

## Install

#### Arch

Note: it is recommended to use the `lobster-git` package, as it is more up to
date, and as the project is currently being actively maintained

```sh
paru -S lobster-git
```

or

```sh
paru -S lobster
```

#### Debian (using makedeb and mist)

Here are the full installation instructions for Debian:

Install the dependencies:

```sh
sudo apt update && sudo apt upgrade && sudo apt install git wget
```

During this step write `makedeb` and enter, when prompted:

```sh
bash -ci "$(wget -qO - 'https://shlink.makedeb.org/install')"
```

```sh
wget -qO - 'https://proget.makedeb.org/debian-feeds/prebuilt-mpr.pub' | gpg --dearmor | sudo tee /usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg 1> /dev/null
```

```
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg] https://proget.makedeb.org prebuilt-mpr $(lsb_release -cs)" | sudo tee /etc/apt/sources.list.d/prebuilt-mpr.list
```

```
sudo apt update && sudo apt install mist
```

During this step when prompted to `Review files for 'lobster-git'? [Y/n]`, write
`n` and enter.

```sh
mist update && mist install lobster-git
```

#### Linux (from source)

```sh
sudo curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o /usr/local/bin/lobster &&
sudo chmod +x /usr/local/bin/lobster
```

#### Android (requires Termux and [mpv-android](https://github.com/mpv-android/mpv-android))

```sh
curl -sLO github.com/justchokingaround/lobster/raw/main/lobster.sh &&
chmod +x lobster.sh &&
mv lobster.sh /data/data/com.termux/files/usr/bin/lobster
```

If you're using Android 14 or newer make sure to run this before:
```sh
pkg install termux-am
```

#### Nixos (Flake)

Add this to you flake.nix

```nix
inputs.lobster.url = "github:justchokingaround/lobster";
```

Add this to you configuration.nix

```nix
environment.systemPackages = [
  inputs.lobster.packages.<architecture>.lobster
];
```

##### Or for run the script once use

```sh
nix run github:justchokingaround/lobster#lobster
```

##### Nixos (Flake) update

When encoutering errors first run the nix flake update command in the cloned
project and second add new/missing [dependencies](#dependencies) to the
default.nix file. Use the
[nixos package search](https://search.nixos.org/packages) to find the correct
name.

```nix
nix flake update
```

#### Mac

```sh
curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o "$(brew --prefix)"/bin/lobster &&
chmod +x "$(brew --prefix)"/bin/lobster
```

#### Windows

<details>
<summary>Windows installation instructions</summary>

- This guide covers how to install and use lobster with the windows terminal,
  you could also use a different terminal emulator, that supports fzf, like for
  example wezterm
- Note that the git bash terminal does _not_ have proper fzf support

1. Install scoop

Open a PowerShell terminal
https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi
(version 5.1 or later) and run:

```ps
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
```

2. Install git,mpv and fzf

```ps
scoop bucket add extras
scoop install git mpv fzf
```

3. Install windows terminal (you don't need to have a microsoft account for
   that) https://learn.microsoft.com/en-us/windows/terminal/install

4. Install git bash (select the option to add it to the windows terminal during
   installation) https://git-scm.com/download/win

(The next steps are to be done in the windows terminal, in a bash shell)

5. Download the script file to the current directory

```sh
curl -O "https://raw.githubusercontent.com/justchokingaround/lobster/main/lobster.sh"
```

6. Give it executable permissions

```sh
chmod +x lobster.sh
```

7. Copy the script to path

```sh
cp lobster.sh /usr/bin/lobster
```

8. Use lobster

```sh
lobster <args> or lobster [movie/tv show]
```

</details>

## Usage

```txt
Usage: lobster [options] [query]
If a query is provided, it will be used to search for a Movie/TV Show

Options:
    -c, --continue
      Continue watching from current history
    -d, --download [path]
      Downloads movie or episode that is selected (if no path is provided, it defaults to the current directory)
    --discord, --discord-presence, --rpc, --presence
      Enables discord rich presence (beta feature, but should work fine on Linux)
    -e, --edit
      Edit config file using an editor defined with lobster_editor in the config (\$EDITOR by default)
    -h, --help
      Show this help message and exit
    -i, --image-preview
      Shows image previews during media selection (requires chafa, you can optionally use ueberzugpp)
    -j, --json
      Outputs the json containing video links, subtitle links, referrers etc. to stdout
    -l, --language [language]
      Specify the subtitle language (if no language is provided, it defaults to english)
    --rofi, --external-menu
      Use rofi instead of fzf
    -p, --provider
      Specify the provider to watch from (if no provider is provided, it defaults to Vidcloud) (currently supported: Vidcloud, UpCloud)
    -q, --quality
      Specify the video quality (if no quality is provided, it defaults to 1080)
    -r, --recent [movies|tv]
      Lets you select from the most recent movies or tv shows (if no argument is provided, it defaults to movies)
    -s, --syncplay
      Use Syncplay to watch with friends
    -t, --trending
      Lets you select from the most popular movies and shows
    -u, -U, --update
      Update the script
    -v, -V, --version
      Show the version of the script
    -x, --debug
      Enable debug mode (prints out debug info to stdout and also saves it to /tmp/lobster.log)

  Note:
    All arguments can be specified in the config file as well.
    If an argument is specified in both the config file and the command line, the command line argument will be used.

  Some example usages:
    lobster -i a silent voice --rofi
    lobster -l spanish -q 720 fight club -i -d
    lobster -l spanish blade runner --json
```

### `-c` / `--continue` argument

This feature is disabled by default because it relies on history, to enable it,
you need add the following line to the `lobster_config.sh` file:

```sh
history=true
```

In a similar fashion to how saving your position when you watch videos on
YouTube or Netflix works, lobster has history support and saves the last minute
you watched for a Movie or TV Show episode. To use this feature, simply watch a
Movie or an Episode from a TV Show, and after you quit mpv the history will be
automatically updated. The next time you want to resume from the last position
watched, you can just run

```sh
lobster -c
```

which will prompt you to chose which of the saved Movies/TV Shows you'd like to
resume from. Upon the completion of a movie or an episode, the corresponding
entry is either deleted (in case of a movie, or the last episode of a show), or
it is updated to the next available episode (if it's the last episode of a
season, it will update to the first episode of the next season).

<details>
<summary>Showcase</summary>

![image](https://github.com/justchokingaround/lobster/assets/44473782/5ed98fb9-008d-4068-a854-577245cfe1ee)

![image](https://github.com/justchokingaround/lobster/assets/44473782/cd59329e-a1c8-408a-be48-690db2d52642)

![image](https://github.com/justchokingaround/lobster/assets/44473782/fae5ea52-4dc4-41ee-b7a2-cbb2476f5819)

</details>

#### Please note:

- The history file can be found at `~/.local/share/lobster/lobster_history.txt`
- A movie or TV show episode is automatically marked as completed/updated after
  the user watches more than 90% of its content

### --`clear-history` / `--delete-history` argument

This argument allows you to delete the history file

### `-d` / `--download` `<path>` argument

This option lets you use lobster as you normally would, with the exception that
instead of playing the video in your player of choice, it will instead download
the video. If no path is specified when passing this argument, then it will
download to the current working directory, as an example, it would look like
this:

```sh
lobster -d '.' rick and morty
```

or

```sh
lobster rick and morty -d
```

If you want to specify a path to which you would like to download the video, you
can do so by passing an additional parameter to the `-d` or `--download`
argument, for instance: using a full path:

```sh
lobster -d "/home/chomsky/tv_shows/rick_and_morty/" rick and morty
```

or using a relative path:

```sh
lobster -d "../rick_and_morty/" rick and morty
```

### `--discord` / `--discord-presence` / `--rpc` / `--presence` argument

#### Note: beta feature

By passing this argument you make use of discord rich presence so you can let
your friends know what you are watching.

This argument requires BSD netcat to be installed.

On Arch Linux you can install it using either pacman or your aur helper of
choice with:

```sh
paru -S openbsd-netcat
```

### `-e` / `--edit` argument

By passing this argument you can edit the config file using an editor of your
choice. By default it will use the editor defined in the `lobster_config.sh`
file, but if you don't have one defined, it will use the `$EDITOR` environment
variable (if it's not set, it will default to `vim`).

### `-i` / `--image-preview` argument

By passing this argument you can see image previews when selecting an entry.

For `rofi` it will work out of the box, if you have icons enabled in your
default configuration.

Example using my custom rofi configuration (to customize how your rofi image
preview looks, please check the [configuration](#configuration) section)

<details>
<summary>Showcase</summary>

![image](https://github.com/justchokingaround/lobster/assets/44473782/a8850f00-9491-4f86-939d-2f63bcb36e96)

</details>

For `fzf` you will need to either install
[chafa](https://github.com/hpjansson/chafa/) or
[ueberzugpp](https://github.com/jstkdng/ueberzugpp/).

<details>
<summary>Showcase</summary>

![image](https://github.com/justchokingaround/lobster/assets/44473782/8d8057d8-4d85-4f0e-b6c0-3b7dd5dce557)

</details>

<details>
<summary>Installation instructions for chafa/ueberzugpp</summary>

On Arch Linux you can install it using your aur helper of choice with:

```sh
paru -S chafa
```

or

```sh
paru -S ueberzugpp
```

On Mac you can install it using homebrew with:

```sh
curl -s -O "https://raw.githubusercontent.com/jstkdng/ueberzugpp/master/homebrew/ueberzugpp.rb"
brew install ./ueberzugpp
rm ueberzugpp
```

In other cases, you can build it from
[source](https://github.com/jstkdng/ueberzugpp/#build-from-source).

Using ueberzugpp is disabled by default in favor of chafa, to enable it, you
need add the following line to the `lobster_config.sh` file:

```sh
use_ueberzugpp=true
```

</details>

### `-j` / `--json` argument

By passing this argument, you can output the json for the currently selected
media to stdout, with the decrypted video link.

### `-l` / `--language` `<language>` argument

By passing this argument, you can specify your preferred language for the
subtitles of a video. If no parameter is specified, it will default to
`english`.

Example use case:

```sh
lobster seven -l spanish
```

This is also valid, and will use english as the defined subtitles language:

```sh
lobster -l weathering with you
```

### `--rofi` / `--external-menu` argument

By passing this argument, you can use rofi instead of fzf to interact with the
lobster script.

This is the recommended way to use lobster, and is a core philosophy of this
script. My use case is that I have a keybind in my WM configuration that calls
lobster, that way I can watch Movies and TV Shows without ever even opening the
terminal.

Here is an example of that looks like (without image preview):

<details>
<summary>Showcase</summary>

![image](https://github.com/justchokingaround/lobster/assets/44473782/d1243c17-0ef1-44b3-99a8-f2c4a4ab5da9)

</details>

### `-p` / `--provider` `<provider>` argument

By passing this argument, you can specify a preferred provider. The script
currently supports the following providers: `UpCloud`, `Vidcloud`. If you don't
pass any provider in the parameters, it will default to `UpCloud`.

Example use case:

```sh
lobster -p Vidcloud shawshank redemption
```

This is also valid, but will use `UpCloud` instead:

```sh
lobster -p shawshank redemption
```

### `-q` / `--quality` `<quality>` argument

By passing this argument, you can specify a preferred quality for the video (if
those are present in the source). If you don't pass any quality in the
parameters, it will default to `1080`.

Example use case:

```sh
lobster -q 720 the godfather
```

This is also valid, but will use `1080` instead:

```sh
lobster the godfather -q
```

### `-r` / `--recent` `<tv|movie>` argument

By passing this argument, you can see watch most recently released movies and TV
shows. You can specify if you want to see movies or TV shows by passing the `tv`
or `movie` parameter. If you don't pass any parameter, it will default to
`movie`.

Example use case:

```sh
lobster -r tv
```

This is also valid, but will use `movie` instead:

```sh
lobster -r
```

### `-s` / `--syncplay` argument

By passing this argument, you can use [syncplay](https://syncplay.pl/) to watch
videos with your friends. This will only work if you have syncplay installed and
configured.

### `-t` / `--trending` argument

By passing this argument, you can see the most trending movies and TV shows.

### `-u` / `-U` / `--update` argument

By passing this argument, you can update the script to the latest version.

Note: you will most likely need to run this with `sudo`

Example use case:

```sh
sudo lobster -u
```

### `-v` / `-V` / `--version` argument

By passing this argument, you can see the current version of the script. This is
useful if you want to check if you have the latest version installed.

### `-x` / `--debug` argument

By passing this argument, you can see the debug output of the script. This will
redirect all the stderr output to stdout, printing it to the terminal, while
also saving it to a log file: `/tmp/lobter.log`

Note: fzf prints the finder to stderr, so this will also be redirected to
stdout, and by extension printed to the terminal and saved to the log file.

## Configuration

Please refer to the
[wiki](https://github.com/justchokingaround/lobster/wiki/Configuration) for
information on how to configure the script using the config file.

## Contributing

All contributions are welcome, and I will to review them as soon as possible. If
you want to contribute, please follow the following recommendations:

- All help is appreciated, even if it's just a typo fix, or a small improvement
- You do not need to be a programmer to contribute, you can also help by opening
  issues, or by testing the script and reporting bugs
- You do not need to be very experienced with shell scripting to contribute, I
  will gladly help you with any questions you might have, and I will also review
  your code
- If you are unsure about something, please open an issue first, start a
  discussion or message me personally
- Please make sure that your code is POSIX compliant (no bashisms)
- Please make sure that your code passes `shellcheck`
- Please use `shfmt` to format your code
- If you are adding a new feature, please make sure that it is configurable
  (either through the config file and/or through command line arguments)
- I recommend reading the philosophy section of the README, to get a better
  understanding of the project (TODO)

You can find the current roadmap here, which contains TODOs and the current
progress of the project:
https://github.com/users/justchokingaround/projects/2/views/1?query=is%3Aopen+sort%3Aupdated-desc

## Dependencies

- fzf
- curl
- grep
- sed
- patch
- awk
- mpv
- html-xml-utils (for fixing html encoded characters) (optional)
- rofi (external menu)
- socat (for getting the player position from the mpv socket)
- vlc (optional)
- iina (optional)

### In case you don't have fzf installed, you can install it like this:

```sh
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

## Uninstall

### Arch Linux

```sh
paru -R lobster
```

### Linux

```sh
sudo rm $(which lobster)
```

### Mac

```sh
rm "$(brew --prefix)"/bin/lobster
```

### Windows

```sh
rm /usr/bin/lobster
```
