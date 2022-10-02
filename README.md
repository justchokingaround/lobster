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

### Windows
```sh
rm /usr/bin/lobster
```
