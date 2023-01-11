yy### If you're upgrading from v2 to v3, please delete your old history and configuration file as they might cause the script to break. That can be done with 
```sh
rm ~/.cache/lobster_history.txt && rm ~/.config/lobster/lobster_config.txt
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
   
   h) If you installed git using scoop then follow this(else the steps are mostly  the same just a different path)
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
8. Use lobster (either with git bash or windows terminal)
```sh
lobster <args> or lobster [movie/tv show]
```

### Termux (Android)
```sh
pkg up -y && pkg install fzf
curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o "$PREFIX"/bin/lobster
chmod +x "$PREFIX"/bin/lobster
```

## Configuration
Settings are stored in `~/.config/lobster/lobster_config.txt`. The file is created on first launch with the default options and looks like this
```
player=mpv
subs_language=English
video_quality=1080
preferred_server=vidcloud
```

### Player
There are 3 available video players to chose from : `mpv`, `iina` or `vlc`.
### Subtitles Language
The `subs_language` setting can be any language, e.g. `English`, `French`, `German`, `Spanish` and so on. Please note that not all streams have subtitles in every language, so `English` is the safest option. It is also important to capitalize the first letter of the language, otherwise it might trigger unexpected behavior.
### Video Quality
The `video_quality` setting can be set to either `1080`, `720`, `360` or `auto`. `auto` will select the best quality depending on your bandwith
### Preferred Server
The `preferred_server` setting can be either `vidcloud` or `upcloud`.

#### Please note: 
* If any of the above settings is wrong, e.g. if `video_quality` is set to a value like 480, the script will fail with a `No links found` message and nothing will be played. However, if the subs_language is set to a language that is not available, the script will just show a `No subtitles found` message but will play the stream.

## History
In a similar fashion to how saving your position when you watch videos on YouTube or Netflix, lobster has history support and saves the last minute you watched for a movie or tv show. To use this feature, simply watch a movie or an episode from a tv show, and after you quit mpv press Enter to save the position (there will be a prompt telling you to do that). The next time you want to resume from the last position watched, you can just run 
```sh
lobster -c
```
which will prompt you to chose which of the saved movies/tv shows you'd like to resume from.

#### Please note:
* If there is only one entry in the history file, it'll be automatically selected
* The history file can be found at `~/.config/lobster_history.txt` 
* A movie or TV show episode is automatically marked as completed/updated after the user watches more than 85% of its content*

## Arguments
```
-w,           download movie or episode
-s,           download full season
-c,           continue from history (saves the your progress in minutes)
-d,           delete history
-u, -U        update script
-v, -V        show script version
-h            show help
```

## Dependencies
- fzf 
- curl
- grep
- sed
- patch
- mpv
- ffmpeg (optional)
- vlc (optional)
- iina (optional)
- android vlc & mpv (optional)

### In case you don't have fzf installed, you can install it like this:
```sh
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

## Uninstall
### Linux
```sh
sudo rm /usr/local/bin/lobster
```

### Mac
```sh
rm "$(brew --prefix)"/bin/lobster
```

### Windows
```sh
rm /usr/bin/lobster
```
