## v3 works again
## will document everything soon :tm: (if you wanna go through the code and document it in the readme pls pr i'll be grateful)

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

### Termux (Android)
```sh
pkg up -y && pkg install fzf
curl -sL github.com/justchokingaround/lobster/raw/main/lobster.sh -o "$PREFIX"/bin/lobster
chmod +x "$PREFIX"/bin/lobster
```

## Arguments
```
-c,           continue from history (saves the your progress in minutes)
-d,           delete history
-u, -U        update script
-v, -V        show script version
-t,           suggest a trending TV Show or Movie
-h            show help
```
*A movie or TV show episode is automatically marked as completed/updated after the user watches more than 85% of its content*

## Config file
```sh
~/.config/lobster
```
## Example config file
```
player=iina
subs_language=French
```
Currently supported players:
```
- mpv
- iina (Mac OS only)
- vlc (No subtitles)
```

## Dependencies
- fzf 
- curl
- grep
- sed
- patch
- mpv
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
