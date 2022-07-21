#!/bin/sh

base="https://www5.himovies.to"

[ -z "$*" ] && printf "Enter a Movie/TV Show name: " && read -r query || query=$*
query=$(printf "%s" "$query"|tr " " "-")
movies_results=$(curl -s "${base}/search/${query}"|
  sed -nE '/class="film-name"/ {n; s/.*href="(.*)".*/\1/p;n; s/.*title="(.*)".*/\1/p;d;}'|
  sed -e 'N;s/\n/\{/' -e "s/&#39;/'/g")
movies_choice=$(printf "%s" "$movies_results"|sed -nE 's_/(.*)/(.*)\{(.*)_\2{\3 (\1)_p'|
  fzf -d"{" --with-nth 2..|sed -nE "s_(.*)\{(.*) \((.*)\)_/\3/\1\t\2_p")

movie_id=$(printf "%s" "$movies_choice"|sed -nE 's_.*/[movie/|tv/].*-([0-9]*).*_\1_p')
movie_title=$(printf "%s" "$movies_choice"|cut -f2)
media_type=$(printf "%s" "$movies_choice"|sed -nE 's_.*/([^/]*)/.*_\1_p')

yoinkity_yoink() {
  key=$(curl -s "$movie_page"|sed -nE "s@.*recaptcha_site_key = '(.*)'.*@\1@p")
  co=$(printf "https://www5.himovies.to:443"|base64|tr "=" ".")
  vtoken=$(curl -s "https://www.google.com/recaptcha/api.js?render=$key"|
    sed -nE "s_.*po\.src=.*releases/(.*)/recaptcha.*_\1_p")
  recaptcha_token=$(curl -s "https://www.google.com/recaptcha/api2/anchor?ar=1&hl=en\
    &size=invisible&cb=cs3&k=${key}&co=${co}&v=${vtoken}"|
    sed -En 's_.*id="recaptcha-token" value="([^"]*)".*_\1_p')
  id=$(curl -s "https://www5.himovies.to/ajax/get_link/${provider_id}?_token=${recaptcha_token}"|
    sed -nE 's_.*"link":".*/(.*)\?z=".*_\1_p')

  xml_links=$(curl -s "https://mzzcloud.life/ajax/embed-4/getSources?id=${id}" \
    -H "X-Requested-With: XMLHttpRequest"|
    tr "," "\n"|sed -nE 's_.*"file":"([^"]*)".*_\1_p')

  mpv_link=$(printf "%s" "$xml_links"|grep -Eo 'https://.*\.m3u8')
  subs_links=$(printf "%s" "$xml_links"|grep 'https://.*\.vtt'|
    sed -e 's/:/\\:/g' -e 'H;1h;$!d;x;y/\n/:/' -e 's/:$//')
  [ -z "$mpv_link" ] && printf "No links found\n" && exit 1
  [ -z "$subs_links" ] && printf "No subtitles found\n"
}

case "$media_type" in
  movie)
    movie_page="$base"$(curl -s "https://www5.himovies.to/ajax/movie/episodes/${movie_id}"|
      tr -d "\n"|sed -nE 's_.*href="([^"]*)".*UpCloud.*_\1_p')
    provider_id=$(printf "%s" "$movie_page"|sed -nE "s_.*\.([0-9]*)\$_\1_p")
    yoinkity_yoink
    mpv --sub-files="$subs_links" --force-media-title="$movie_title" "$mpv_link"
    ;;
  tv)
    seasons_ids=$(curl -s "https://www5.himovies.to/ajax/v2/tv/seasons/${movie_id}"|
      sed -nE 's_.*data-id="([0-9]*)".*_\1_p')
    number_of_seasons=$(( $(printf "%s" "$seasons_ids"|wc -l|tr -d "[:space:]") + 1 ))
    [ "$number_of_seasons" -gt 1 ] && printf "Please choose a season number between 1 and %s: " \
      "$number_of_seasons" && read -r season_number || season_number=1
    [ -z "$season_number" ] && season_number=$number_of_seasons
    season_id=$(printf "%s" "$seasons_ids"|sed -nE "${season_number}p")
    episode_ids=$(curl -s "https://www5.himovies.to/ajax/v2/season/episodes/${season_id}"|
      sed -nE 's_.*data-id="([0-9]*)".*_\1_p')
    number_of_episodes=$(( $(printf "%s" "$episode_ids"|wc -l|tr -d "[:space:]") + 1 ))
    printf "Please choose an episode number between 1 and %s: " "$number_of_episodes" && read -r episode_number
    [ -z "$episode_number" ] && episode_number=$number_of_episodes
    episode_id=$(printf "%s" "$episode_ids"|sed -nE "${episode_number}p")

    show_base=$(printf "%s" "$movies_choice"|cut -f1)
    movie_page="${base}${show_base}\."$(curl -s "https://www5.himovies.to/ajax/v2/episode/servers/${episode_id}"|
      tr -d "\n"|sed -nE 's_.*data-id="([0-9]*)".*title="Server UpCloud".*_\1_p')
    provider_id=$(printf "%s" "$movie_page"|sed -nE "s_.*\.([0-9]*)\$_\1_p")
    yoinkity_yoink
    mpv --sub-files="$subs_links" --force-media-title="${movie_title}: Ep ${episode_number}" "$mpv_link"
    ;;
  *)
    printf "Unknown media type: %s\n" "$media_type"
    exit 1
    ;;
esac
