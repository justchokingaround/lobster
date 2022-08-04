[![thumbnail](https://user-images.githubusercontent.com/44473782/182946079-a05a6075-041e-473a-88fa-590f44ac6899.png)](https://youtu.be/j7cI7a-gRUo)

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
-c,           continue from history (works only for TV shows you will need to watch at least one episode for it to work)
-d,           delete history
-u, -U        update script
-v, -V        show script version
-t,           suggest a trending TV Show or Movie
-h            show help
```

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
- mpv

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

