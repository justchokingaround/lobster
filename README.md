### If you're upgrading from v3 to v4, please delete your old history and configuration file as they might cause the script to break. That can be done with

```sh
rm ~/.config/lobster_history.txt && rm ~/.config/lobster/lobster_config.txt
```

## Install

### Linux

```sh
sudo curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o /usr/local/bin/lobster &&
sudo chmod +x /usr/local/bin/lobster
```

### Mac

```sh
curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o "$(brew --prefix)"/bin/lobster &&
chmod +x "$(brew --prefix)"/bin/lobster
```

### Windows

1. Install scoop

Open a PowerShell terminal https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi (version 5.1 or later) and run:

```sh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
```

2. Install git,mpv and fzf

```sh
scoop bucket add extras
scoop install git mpv fzf
```

3. Install git bash
   https://git-scm.com/download/win
4. Install windows terminal (you don't need to have a microsoft account for that)
   https://learn.microsoft.com/en-us/windows/terminal/install
5. Adding git bash to windows terminal.

   a) Install windows terminal from the Microsoft store.

   b) Open the terminal.

   c) Open settings.

   d) Click "Add a new profile"

   e) Click "New empty profile"

   f) Click on "name" and rename it to "Git Bash"

   g) Click on "Command line" and click "Browse..."

   h) If you installed git using scoop then follow this(else the steps are mostly the same just a different path)
   navigate to `C:\User\USERNAME\scoop\apps\git\2.37.1.windows.1\bin\bash.exe`
   Where USERNAME is your username
   note that the name `2.37.1.windows.1` might be slightly different on your system

   j) Click "Open"

   k) Click "Starting directory" and uncheck "Use parent process directory"

   l) Click "Save"

   m) Now you can open gitbash from the windows terminal

6. Clone the repo and go inside it

```sh
git clone https://github.com/justchokingaround/lobster && cd lobster
```

7. Add the script to default path for binaries

```sh
cp lobster.sh /usr/bin/lobster
```

8. Denote permission to access the file in executable mode

```sh
sudo chmod +x /usr/bin/lobster
```

9. Use lobster (either with git bash or windows terminal)

```sh
lobster <args> or lobster [movie/tv show]
```

## Configuration

Settings are stored in `~/.config/lobster/lobster_config.txt`. Here is an example configuration file containing the values that you can change:

```
use_external_menu="0"
image_preview="0"
image_config_path="$HOME/.config/rofi/styles/launcher.rasi"
subs_language="English"
player="mpv"
json_output="0"
histfile="$HOME/.local/share/lobster_history.txt"
cache_dir="/tmp/lobster"
images_cache_dir="/tmp/lobster-images"
applications_dir="$HOME/.local/share/applications/lobster"
tmp_position="/tmp/lobster_position"
```

Note: all the values in this sample configuration are the default values, with the exception of `image_config_path`.

### External Menu

By setting this value to `1` you can run the script using `rofi` instead of `fzf`.

Also supported as command line arguments: `--rofi`, `--dmenu`, `--external-menu`

### Image Preview

By setting this value to `1` you can see image previews when selecting an entry.

For `rofi` it will work out of the box, if you have icons enabled in your default configuration (to see how you can use a custom configuration for properly displaying images in the section below).

For `fzf` you will need to install [ueberzugpp](https://github.com/jstkdng/ueberzugpp/).

On Arch Linux you can install it using your aur helper of choice with:

```sh
paru -S ueberzugpp
```

On Mac you can install it using homebrew with:

```sh
curl -s -O "https://raw.githubusercontent.com/jstkdng/ueberzugpp/master/homebrew/ueberzugpp.rb"
brew install ./ueberzugpp
rm ueberzugpp
```

In other cases, you can build it from [source](https://github.com/jstkdng/ueberzugpp/#build-from-source).

Also supported as command line arguments: `-i`, `--image-preview`

### Image Config Path

In the case that you use `rofi` with image preview (that means that `use_external_menu` and `image_preview` are both set to `1`), you have the ability to point to a specific config file to be used only for when rofi runs in the mode where it displays images (it will not affect other prompts). An example of such a configuration, and then one I use in the demo can be found here:

https://github.com/justchokingaround/dotfiles/blob/main/rofi/styles/launcher.rasi

### Subtitles Language

The `subs_language` setting can be any language, e.g. `English`, `French`, `German`, `Spanish` and so on. Please note that not all streams have subtitles in every language, so `English` is the safest option.

Also supported as command line arguments: `-l`, `--language`

### Player

There are 3 available video players to chose from : `mpv`, `iina` or `vlc`.

Note that only `mpv` supports the history feature.

### JSON Output

By setting the value of `json_output` to `1` you can output the json for the currently selected media to stdout, with the decrypted video link.

Also supported as command line arguments: `-j`, `--json`

## History

In a similar fashion to how saving your position when you watch videos on YouTube or Netflix, lobster has history support and saves the last minute you watched for a Movie or TV Show episode. To use this feature, simply watch a Movie or an episode from a TV Show, and after you quit mpv the history will be automatically updated. The next time you want to resume from the last position watched, you can just run

```sh
lobster -c
```

which will prompt you to chose which of the saved Movies/TV Showvs you'd like to resume from.

#### Please note:

- The history file can be found at `~/.local/share/lobster/lobster_history.txt`
- A movie or TV show episode is automatically marked as completed/updated after the user watches more than 90% of its content\*

## Arguments

```
 -c, --continue
      Continue watching from current history
    -d, --download
      Downloads movie or episode that is selected
    -h, --help
      Show this help message and exit
    -e, --edit
      Edit config file using an editor defined with lobster_editor in the config ($EDITOR by default)
    -p, --provider
      Specify the provider to watch from (default: Vidcloud) (currently supported: Vidcloud)
    -j, --json
      Outputs the json containing video links, subtitle links, referrers etc. to stdout
    --rofi, --dmenu, --external-menu
      Use rofi instead of fzf
    -t, --trending
      Lets you select from the most popular movies
    -r, --recent
      Lets you select from the most recent movies
    -i, --image-preview
      Shows image previews during media selection (requires ueberzugpp to be installed to work with fzf)
    -l, --language
      Specify the subtitle language
    -u, -U, --update
      Update the script
    -v, -V, --version
      Show the version of the script
```

## Dependencies

- fzf
- curl
- grep
- sed
- patch
- mpv
- html-xml-utils (for fixing html encoded characters)
- socat (for getting the player position from the mpv socket)
- vlc (optional)
- iina (optional)

### In case you don't have fzf installed, you can install it like this:

```sh
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

## Uninstall

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
