# lobster

watch movies and tv shows in your terminal. no account, no api key, no
electron app eating 900mb of ram to show you a grid of posters.

it's one posix shell script. you search, you pick, mpv opens.

https://github.com/justchokingaround/lobster/assets/44473782/d597335c-42a9-4e45-8948-122744aa5ca9

discord: https://discord.gg/JTDS2CKjQU (bridged to matrix)
matrix: https://matrix.to/#/#lobster-and-jerry:matrix.org (i'm more active there)

---

## quick start

```sh
sudo curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o /usr/local/bin/lobster
sudo chmod +x /usr/local/bin/lobster
lobster
```

you need `curl`, `sed`, `grep`, `awk` (you already have those), plus `fzf`
and `mpv`. everything else is optional, see [dependencies](#dependencies).
other install methods (arch, debian, nix, mac, android, ios, windows) are
[further down](#install).

```sh
lobster                        # home menu: continue, search, trending, genres…
lobster fight club             # straight to the results
lobster -c                     # continue watching
lobster --binge severance      # next episode auto-plays, no menu
lobster -d ~/tv breaking bad   # download instead of play
```

## contents

- [what it does](#what-it-does)
- [install](#install)
- [flags](#flags)
- [menus and keys](#menus-and-keys)
- [history](#history)
- [downloads](#downloads)
- [where the data comes from](#where-the-data-comes-from)
- [providers](#providers)
- [config](#config)
- [dependencies](#dependencies)
- [json output](#json-output)
- [roadmap](#roadmap)
- [contributing](#contributing)
- [uninstall](#uninstall)

## what it does

- **search / browse** - live search-as-you-type, trending, now playing,
  top rated, genres, by year. metadata straight from themoviedb.org.
- **plays in your player** - mpv by default, also vlc, iina, celluloid,
  syncplay, mpv-android, or any command that takes a url.
- **remembers where you stopped** - per-episode resume, progress bars,
  watched (✓) markers, auto-advance to the next episode.
- **subtitles + dubs** - picks your language, labels audio tracks, or skip
  the whole thing with `-n`.
- **downloads** - single episode or a whole season in parallel, with a live
  progress table.
- **posters in the terminal** - chafa, ueberzugpp or kitty graphics, if you
  like your tui pretty.
- **rofi mode** - bind it to a key in your wm and never open a terminal at
  all. this is the intended endgame, honestly.
- **discord rich presence** - let your friends know what you're watching,
  for better or worse.
- **copy the stream url or a ready-to-paste player command** - referer,
  subs, resume position and all.
- **json output** - `-j` gives you every resolved source, pipe it wherever.

## install

**linux / any unix**

```sh
sudo curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o /usr/local/bin/lobster &&
sudo chmod +x /usr/local/bin/lobster
```

**arch** - `lobster-git` is the maintained one, `lobster` can sometimes lags behind

```sh
paru -S lobster-git
```

**mac**

```sh
curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o "$(brew --prefix)"/bin/lobster &&
chmod +x "$(brew --prefix)"/bin/lobster
```

**android** - needs [termux](https://termux.dev) and
[mpv-android](https://github.com/mpv-android/mpv-android)

```sh
curl -sLO github.com/justchokingaround/lobster/raw/main/lobster.sh &&
chmod +x lobster.sh &&
mv lobster.sh /data/data/com.termux/files/usr/bin/lobster
```

on android 14+ run `pkg install termux-am` first.

**nixos (flake)**

```nix
inputs.lobster.url = "github:justchokingaround/lobster";
# then, in configuration.nix:
environment.systemPackages = [ inputs.lobster.packages.<architecture>.lobster ];
```

or just `nix run github:justchokingaround/lobster#lobster`. if an update
breaks, run `nix flake update` in the cloned repo and add any missing
[dependencies](#dependencies) to `default.nix` (names via
[nixos package search](https://search.nixos.org/packages)).

<details>
<summary><b>debian</b> (via makedeb + mist)</summary>

```sh
sudo apt update && sudo apt upgrade && sudo apt install git wget
bash -ci "$(wget -qO - 'https://shlink.makedeb.org/install')"   # type: makedeb
wget -qO - 'https://proget.makedeb.org/debian-feeds/prebuilt-mpr.pub' | gpg --dearmor | sudo tee /usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg 1> /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg] https://proget.makedeb.org prebuilt-mpr $(lsb_release -cs)" | sudo tee /etc/apt/sources.list.d/prebuilt-mpr.list
sudo apt update && sudo apt install mist
mist update && mist install lobster-git
```

answer `n` when it asks `Review files for 'lobster-git'? [Y/n]`.

</details>

<details>
<summary><b>ios</b> (iSH + VLC)</summary>

install iSH and VLC from the app store, then:

```sh
apk update; apk add grep sed curl fzf patch
curl -O "https://raw.githubusercontent.com/justchokingaround/lobster/main/lobster.sh"
chmod +x lobster.sh
mv lobster.sh /usr/local/bin/lobster
```

</details>

<details>
<summary><b>windows</b> (scoop + windows terminal)</summary>

use windows terminal or wezterm. git bash's own terminal does *not* do fzf
properly.

1. install scoop, in powershell 5.1+:

```ps
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
```

2. install the deps:

```ps
scoop bucket add extras
scoop install git mpv fzf
```

3. install [windows terminal](https://learn.microsoft.com/en-us/windows/terminal/install)
   and [git bash](https://git-scm.com/download/win) (tick the option to add it
   to windows terminal)

4. then, in a bash shell inside windows terminal:

```sh
curl -O "https://raw.githubusercontent.com/justchokingaround/lobster/main/lobster.sh"
chmod +x lobster.sh
cp lobster.sh /usr/bin/lobster
```

</details>

**no fzf?**

```sh
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
```

without it lobster falls back to a numbered prompt. it works, it's just sad.

## flags

everything here can also live in the [config file](#config). a flag always
wins over the config.

| flag | what it does |
| --- | --- |
| `-c`, `--continue` | continue watching from history |
| `--last` | resume the most recent entry, skip the picker |
| `--binge` | auto-play next episode, no menu, no countdown |
| `--clear-history` | delete the history file |
| `-d`, `--download [path]` | download instead of play (default: current dir) |
| `--discord`, `--rpc`, `--presence` | discord rich presence (linux, beta, needs bsd netcat) |
| `-e`, `--edit` | open the config in `$lobster_editor` / `$VISUAL` / `$EDITOR` / nano |
| `--genre <name> [movie\|tv]` | browse a tmdb genre (`action`, `sci-fi`, …) |
| `-h`, `--help` | the help text |
| `-i`, `--image-preview` | cover art while picking (needs chafa or ueberzugpp) |
| `-j`, `--json` | print metadata + every resolved source, then exit |
| `-l`, `--language <lang>` | subtitle language (default `english`) |
| `-n`, `--no-subs` | no subtitles, anywhere, also slightly faster |
| `--provider <name>` | pin one source backend, see [providers](#providers) |
| `-q`, `--quality <n>` | preferred quality: `1080`, `720`, `4k`/`2160`… (default `1080`) |
| `-r`, `--recent [movie\|tv]` | currently airing / now playing |
| `--rofi`, `--external-menu` | rofi instead of fzf |
| `-s`, `--syncplay` | watch in sync with friends via [syncplay](https://syncplay.pl/) |
| `-t`, `--trending` | this week's trending |
| `-T`, `--top-rated [movie\|tv]` | top rated titles |
| `--year <year> [movie\|tv]` | titles from one year |
| `-u`, `-U`, `--update` | update the script (probably needs sudo, needs `patch`) |
| `-v`, `-V`, `--version` | version |
| `-x`, `--debug` | stderr to terminal *and* `$TMPDIR/lobster.log` |

anything that isn't a flag is the search query, so you don't have to quote
your movie titles:

```sh
lobster -i a silent voice --rofi
lobster -l spanish -q 720 fight club -i -d
lobster -l spanish blade runner --json
```

the `[movie|tv]` arguments default to `movie` when you leave them off.
`-q` and `-l` with nothing after them fall back to `1080` and `english`
instead of yelling at you.

## menus and keys

with no query and no flags, you land on the home menu:

```txt
continue watching / search / trending / now playing / top rated / genres / quit
```

search is live in fzf mode: results refresh as you type (debounced), with a
title/genre/rating preview on the side. every query is saved to
`~/.local/share/lobster/search_history`, so up arrow recalls the thing you
watched last tuesday.

**keys**

| key | does |
| --- | --- |
| enter / shift+right | confirm |
| esc / shift+left | back one menu (quits at the top) |
| ctrl-c | quit, obviously |
| `?` | expand/collapse the preview pane |
| up arrow | previous search (in the search box) |
| ctrl-d | delete the highlighted entry (in the continue list) |
| `q` + enter | the `quit` entry, because typing `q` is easier than `exit` |

**after the video ends**

shows get `next episode`, `replay episode`, `select episode`,
`select season`, `copy stream url`, `copy player command`, `search`, `quit`.
movies get the same minus the episode/season entries. esc goes up one level:
the episode list for a show, out the door for a movie.

`copy player command` copies a full, pasteable command for whatever player
you've configured, referer header and subtitle files included, so you can
send it to a friend or paste it on another machine:

```sh
mpv --start='412' --sub-file='https://…/en.vtt' \
    --http-header-fields='Referer: https://…/' \
    --demuxer-lavf-o=allowed_extensions=ALL --alang=eng \
    --force-media-title='Show (S01E03)' 'https://…/master.m3u8'
```

`copy stream url` copies just the url. both use wl-copy / xclip / xsel /
pbcopy / clip.exe / termux-clipboard-set, whichever exists, and print to the
terminal when none do. these links are signed and short-lived, so a copied
command usually rots within a few hours.

when an episode ends past 90%, lobster counts down 3 seconds and rolls into
the next one. press enter to stop it and get the menu instead.

## history

on by default. lobster saves your position the moment you quit the player,
like netflix but without the subscription or the cancelled show. `lobster -c`
gives you the picker, `lobster --last` skips straight back into the most
recent thing.

it's a local text file, nothing leaves your machine, and the first run prints
a one-line note saying so. to opt out:

```sh
history=false
```

- lives in `~/.local/share/lobster/lobster_history.txt` (`histfile` to move it)
- past 90% watched counts as done: movies drop off the list, shows roll over
  to the next episode, including across season boundaries
- the continue list is newest-first with a progress bar and `SxxEyy` marker
- the episode list marks watched (✓) and current (▶) episodes
- ctrl-d in the continue list deletes that entry
- `--clear-history` nukes the file
- with `history=false`, `-c` just tells you it's off instead of pretending
  nothing happened

## downloads

```sh
lobster -d rick and morty              # current dir
lobster -d ~/tv_shows/ rick and morty  # somewhere specific
lobster rick and morty -d              # flag order doesn't matter
```

picking a season downloads the whole thing: `download_concurrency` episodes
at once (default 8), a new one starting at most every `download_pace`
seconds (default 1). you get a live table, one season-wide percentage and a
per-episode one, finished episodes scrolling off the top. anything that
failed gets retried once with a freshly resolved link, since these urls are
signed and expire. a desktop notification fires when it's done.

if a batch fails across the board with 4xx/429s, the backend is rate-limiting
you by request *rate*, not by connection count (penguplay: ~15 per 15s), so
raise `download_pace` rather than just lowering concurrency.

the chain is `yt-dlp` → `ffmpeg` → `mpv --stream-record`, first one installed
wins. yt-dlp handles obfuscated sources best; the mpv fallback exists for
streams whose segments wear a fake `.jpg` extension, which ffmpeg refuses on
purpose. set `downloader="aria2c"` to prefer aria2c for plain direct files.

external subtitles are saved as `.vtt` next to the video (most sources
already embed them in the mkv anyway). `-n` skips that.

want something else entirely? define `custom_downloader` in the config and it
wins over all of it. paths, season subfolders and filename sanitizing are
already done by the time it's called:

```sh
# custom_downloader <url> <dest_file> <referer> <subs_csv> [progress_file]
#   referer may be empty; subs_csv is comma-separated (may be empty);
#   progress_file is only set for batch downloads and can be ignored
# exit non-zero to fall back to the built-in chain
custom_downloader() {
    wget -O "$2" "$1"
}
```

## where the data comes from

search, trending, seasons, episodes: all scraped from
[themoviedb.org](https://www.themoviedb.org/)'s public pages. no account, no
api key, nothing to sign up for. downside of reading html instead of the v3
api: a tmdb redesign can break browsing overnight. if that happens it's a
`lobster.sh` bug, not something you misconfigured.

playing is a separate step, see [providers](#providers).

lobster does not host, decrypt or upload anything. it talks to the same json
backends third-party players do. see
[docs/stream-resolution.md](docs/stream-resolution.md) for the
reverse-engineered flow and `contrib/resolve-streams.mjs` for a js
reference implementation.

## providers

six backends, tried best-first until one coughs up a stream. the default
order is:

| provider | backend | notes |
| --- | --- | --- |
| `videasy` | `api.speedracelight.com` | needs `node`, skipped without it |
| `rivestream` | `scrapper.rivestream.app` | queries its sub-providers in parallel |
| `cinezo` | `proxy1.flikhub.net` | direct files |
| `vidlove` | `api.shows.st` | direct files, hls master fallback |
| `penguplay` | your [penguplay](https://pengu.uk/) stremio addon | needs `penguplay_url` |
| `aiostreams` | your aiostreams addon | needs `aiostreams_url` |

**which one to use.** configure `aiostreams` if you have a debrid service or
can torrent, and put it first - it's the best source. otherwise configure
`penguplay` and put it first. the scraped backends (`videasy`, `rivestream`,
`cinezo`, `vidlove`) work but aren't as good; keep them behind the addon as
fallbacks.

change the order with `provider_order` in the config, best first. names not
listed are never tried, unknown names are skipped with a warning (so an old
config keeps working when a backend is added or retired):

```sh
# default
provider_order="aiostreams penguplay videasy rivestream cinezo vidlove"

# only scraped backends, vidlove first
provider_order="vidlove rivestream cinezo"
```

the stremio addons lead the default order for the reason above: an addon you
configured is a deliberate source choice, not a last resort. an addon with no
url configured is skipped, so the default works untouched either way.

pin a single one with `--provider rivestream` or `provider=` in the config;
that ignores `provider_order` entirely:

```sh
penguplay_url="https://pengu.uk/<your-token>/manifest.json"
aiostreams_url="https://<your-host>/<your-token>/manifest.json"
provider="penguplay"   # optional
```

either url can be the full `manifest.json` or just the base path. the stremio
backends resolve `tmdb:*` ids through the addon's own `/stream` and
`/subtitles` resources (series ids carry `:season:episode`), so whatever
source/quality/audio filters you set up in the addon still apply. picking
`provider="penguplay"` without the url is a hard error, not a silent
fallback.

**your own resolver.** none of the above required, if you'd rather plug in a
self-hosted extractor, a yt-dlp plugin, your own api. define this in the
config and lobster uses it instead:

```sh
# resolve_stream <type> <tmdb_id> [season] [episode]
#   type is "movie" or "tv"
# stdout, one tab-separated line:
#   <video_url>\t<referer>\t<sub_url,sub_url,...>
#   referer and the subtitle list may both be empty
# exit non-zero if nothing could be resolved
resolve_stream() {
    ...
}
```

`$quality`, `$subs_language` and `$no_subs` are set as globals by then, if
your resolver cares.

## config

plain shell, sourced before arguments are parsed, so flags always override
it. lives at `~/.config/lobster/lobster_config.sh` (or
`$XDG_CONFIG_HOME/lobster/…`). open it with `lobster -e`.

on first run lobster writes that file for you: every option below, grouped
and commented out, with its default next to it. uncomment what you want to
change. since nothing in the generated file is active, defaults keep coming
from the script itself, so upgrading never fights your config. delete the
file and run lobster again to get a fresh template, or run
`lobster --config-regenerate` (your old one is kept as `.bak`).

| option | default | what it does |
| --- | --- | --- |
| `player` | `mpv` | `mpv`, `vlc`, `iina`, `celluloid`, `syncplay`, or any command taking a url |
| `quality` | `1080` | preferred quality: `1080`, `720`, `4k`/`2160`… |
| `provider` | (empty) | pin one backend, ignores `provider_order` |
| `provider_order` | `aiostreams penguplay videasy rivestream cinezo vidlove` | which backends are tried, best first |
| `penguplay_url` / `aiostreams_url` | (empty) | stremio addon manifest urls |
| `subs_language` | `english` | subtitle language |
| `audio_language` | `english` | preferred dub / audio track |
| `blocked_audio_languages` | (empty) | never pick these, e.g. `"hindi"` |
| `max_subs` | `5` | subtitle tracks handed to the player (`0` = all) |
| `max_audio_tracks` | `5` | audio candidates probed before picking (`0` = all) |
| `no_subs` | `false` | skip subtitles entirely |
| `history` | `true` | watch history, `-c`, `--last` |
| `histfile` | `$XDG_DATA_HOME/lobster/lobster_history.txt` | where history lives |
| `binge` | `false` | auto-play next episode, no menu |
| `download_dir` | `$PWD` | where `-d` saves |
| `downloader` | `ffmpeg` | `aria2c` to prefer it for plain direct links |
| `download_concurrency` | `8` | episodes at once in a batch |
| `download_pace` | `1` | minimum seconds between episode starts |
| `live_search` | `true` | search-as-you-type in fzf |
| `use_external_menu` | `false` | rofi instead of fzf |
| `image_preview` | `false` | cover art in the picker |
| `images_cache_dir` | `<data dir>/posters` | where downloaded cover art is kept |
| `use_ueberzugpp` | `false` | ueberzugpp instead of chafa |
| `preview_window_size` | `right:70%:wrap` | fzf preview geometry |
| `ueberzug_x` / `ueberzug_y` / `ueberzug_max_width` / `ueberzug_max_height` | `10` / `3` / half the terminal | ueberzugpp placement |
| `ueberzug_output` | (auto) | ueberzugpp backend (`x11`, `wayland`, …) |
| `image_config_path` | (empty) | rofi theme for the image picker |
| `rofi_prompt_config` | (empty) | rofi theme for the search prompt |
| `discord_presence` | `false` | discord rich presence (linux, beta) |
| `lr_continue_back` | `exit` | what esc does in the continue list |
| `watchlater_dir` | temp dir | mpv resume data (auto-detected on windows) |
| `remove_tmp_lobster` | `true` | wipe the temp dir on exit |
| `json_output` | `false` | same as `-j` |
| `debug` | `false` | same as `-x` |
| `lobster_editor` | `$VISUAL` / `$EDITOR` | editor for `-e` |

plus the two functions you can redefine: `resolve_stream`
([providers](#providers)) and `custom_downloader` ([downloads](#downloads)).

rofi theming and other cosmetics live in the
[wiki](https://github.com/justchokingaround/lobster/wiki/Configuration).

## dependencies

posix `sh`, runs under dash, busybox ash, bash and zsh.

**required:** `curl`, `sed`, `grep`, `awk`, and a player (`mpv` by default).

**optional, and lobster degrades instead of dying:**

| tool | needed for | without it |
| --- | --- | --- |
| `fzf` | the normal picker | numbered `read` prompt |
| `rofi` | `--rofi` | that flag only |
| `patch` | `--update` | that flag only |
| `chafa` | `-i` image preview | that flag only (unless `use_ueberzugpp=true`) |
| `ueberzugpp` | `use_ueberzugpp=true` | falls back to chafa |
| `kitten` | posters in kitty/ghostty | falls back to chafa |
| `node` | the videasy backend | that backend is skipped |
| `nc` | live position over mpv's ipc socket | per-episode `watch_later` files |
| `ffprobe` | naming audio tracks by language | tracks show as "track N" |
| `yt-dlp` | best downloader for awkward hls | ffmpeg, then `mpv --stream-record` |
| `aria2c` | `downloader=aria2c` | falls back to ffmpeg |
| `notify-send` / `osascript` | desktop notifications | a terminal line |
| `wl-copy` / `xclip` / `xsel` / `pbcopy` / `clip.exe` / `termux-clipboard-set` | the copy menu entries | prints the text instead |

two non-posix things are assumed anyway, because every shell lobster actually
runs on has them: fractional `sleep` (spinner, search debounce) and `read -t`
(the 3s "press enter to stop" window; without it the episode just advances
with no cancel window).

image previews need chafa or ueberzugpp:

<details>
<summary>installing chafa / ueberzugpp</summary>

arch:

```sh
paru -S chafa      # or: paru -S ueberzugpp
```

mac:

```sh
curl -s -O "https://raw.githubusercontent.com/jstkdng/ueberzugpp/master/homebrew/ueberzugpp.rb"
brew install ./ueberzugpp
rm ueberzugpp.rb
```

otherwise [build from source](https://github.com/jstkdng/ueberzugpp/#build-from-source).
chafa is the default; `use_ueberzugpp=true` switches. rofi does image
previews out of the box if you have icons enabled.

</details>

## json output

`-j` prints everything it found and exits, instead of playing:

```json
{
  "type": "movie",
  "tmdb_id": "550",
  "title": "Fight Club",
  "poster": "...",
  "video_url": "...",
  "referer": "https://player.videasy.to/",
  "sources": {
    "videasy":    [ { "quality": "1080p", "url": "...", "referer": "..." } ],
    "rivestream": [],
    "cinezo":     [],
    "vidlove":    []
  },
  "subtitles": [ "..." ]
}
```

`video_url`/`referer` is what would have played. `sources` lists every
quality variant across the four scraped backends, narrowed to `--provider`
if you set one. stremio addons contribute the chosen `video_url` only, no
listing.

## roadmap

not built yet, listed here so it's tracked in public instead of in someone's
head:

- **mpv next-episode hotkey** - advance without leaving the player. needs a
  small mpv script + ipc back to lobster.
- **watchlist / favorites** - save titles, jump to the next unwatched episode.
- **skip intro** - via mpv chapters/scripts.
- **recommendations** - blocked: tmdb's `/recommendations` and `/similar`
  pages are client-side only (404 to a scraper), unlike everything else
  lobster reads. revisit if a scrapeable source shows up.
- **cast to tv** - chromecast/dlna.
- **subtitle fallback** - fetch subs externally when the backends return none.

there's also a
[project board](https://github.com/users/justchokingaround/projects/2/views/1?query=is%3Aopen+sort%3Aupdated-desc).

## contributing

all of it welcome, typo fixes included. you don't have to be a programmer:
opening issues and reporting bugs counts. you don't have to be good at shell
either, ask and i'll help.

if you're writing code:

- posix compliant, no bashisms
- passes `shellcheck`
- formatted with `shfmt`
- new features configurable via config file and/or flag
- unsure about something? open an issue or message me first

## uninstall

```sh
paru -R lobster                     # arch
sudo rm $(which lobster)            # linux
rm "$(brew --prefix)"/bin/lobster   # mac
rm /usr/bin/lobster                 # windows
```

see [DISCLAIMER.md](DISCLAIMER.md). lobster hosts nothing, it just reads
public pages, same as your browser would.
