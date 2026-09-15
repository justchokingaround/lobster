#!/usr/bin/env sh
# Minimal assert-based smoke test for lobster.sh. No framework, no fixtures -
# just enough to catch a broken record shape, arg parser, or history rule
# before it ships. Run with: sh tests/smoke.sh
#
# shellcheck disable=SC2034,SC2154,SC2312
# SC2034/SC2154: many variables here are only read/written by functions
# sourced from lobster.sh, which shellcheck can't see through a dynamic ".".
# SC2312: the inline command substitutions in assert_eq calls are intentional.

cd "$(dirname "$0")/.." || exit 1

fail=0
# assert_eq <description> <actual> <expected>
assert_eq() {
    if [ "$2" != "$3" ]; then
        printf 'FAIL: %s\n  got:      %s\n  expected: %s\n' "$1" "$2" "$3" >&2
        fail=$((fail + 1))
    else
        printf 'ok - %s\n' "$1"
    fi
}

# Source the script for its function/variable definitions only; LOBSTER_TEST
# skips the real entry point (arg parsing, dep checks, launching a picker).
export LOBSTER_TEST=1
export XDG_CONFIG_HOME="$PWD/tests/.tmp-config"
export XDG_DATA_HOME="$PWD/tests/.tmp-data"
rm -rf "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
# shellcheck disable=SC1091
. ./lobster.sh
configuration

### tmdb_extract_media: parses both card layouts TMDB serves (search-page
### cards wrap the title in a <span>; popular/now-playing grid cards don't) ###
search_card='<a class="flex w-full" href="/movie/603-the-matrix"><img src="https://media.themoviedb.org/t/p/w94_and_h141_face/p.jpg"></a><a href="/movie/603-the-matrix"><h2><span>The Matrix</span></h2></a><span class="release_date w-full font-light">June 23, 1999</span>'
grid_card='<a class="flex w-full" href="/tv/1399-game-of-thrones"><img src="https://media.themoviedb.org/t/p/w220_and_h330_face/g.jpg"></a><a href="/tv/1399-game-of-thrones"><h2>Game of Thrones</h2></a><span class="release_date w-full font-light">April 17, 2011</span>'
row=$(printf '%s%s' "$search_card" "$grid_card" | tmdb_extract_media)
assert_eq "tmdb_extract_media: finds both cards" "$(printf '%s\n' "$row" | wc -l | tr -d ' ')" "2"
movie_row=$(printf '%s' "$row" | awk -F'\t' '$2==603')
tv_row=$(printf '%s' "$row" | awk -F'\t' '$2==1399')
assert_eq "tmdb_extract_media: poster column" "$(printf '%s' "$movie_row" | cut -f1)" "https://media.themoviedb.org/t/p/w94_and_h141_face/p.jpg"
assert_eq "tmdb_extract_media: type column" "$(printf '%s' "$movie_row" | cut -f3)" "movie"
assert_eq "tmdb_extract_media: span-wrapped title+year" "$(printf '%s' "$movie_row" | cut -f4)" "The Matrix (1999)"
assert_eq "tmdb_extract_media: bare (unwrapped) title+year" "$(printf '%s' "$tv_row" | cut -f4)" "Game of Thrones (2011)"
assert_eq "tmdb_extract_media: bare title type column" "$(printf '%s' "$tv_row" | cut -f3)" "tv"
# Some cards ship an empty release_date span (unreleased titles) - the row
# keeps its plain title and stays at 4 fields.
nodate_card='<a class="flex w-full" href="/tv/100001-no-date"><img src="https://media.themoviedb.org/t/p/w94_and_h141_face/n.jpg"></a><a href="/tv/100001-no-date"><h2>No Date Yet</h2></a><span class="release_date w-full font-light"></span>'
nodate_row=$(printf '%s' "$nodate_card" | tmdb_extract_media)
assert_eq "tmdb_extract_media: no-date card field count" "$(printf '%s' "$nodate_row" | awk -F'\t' '{print NF}')" "4"
assert_eq "tmdb_extract_media: no-date card keeps plain title" "$(printf '%s' "$nodate_row" | cut -f4)" "No Date Yet"

### tmdb_parse_seasons: falls back to "Season N" when TMDB ships an
### unrendered client-side template instead of real alt text ###
# shellcheck disable=SC2016 # the ${data.name} is literal fixture text, not meant to expand
seasons_html='<a href="/tv/95396-severance/season/0"><img alt="Specials"></a><a href="/tv/95396-severance/season/1"><img alt="Season 1"></a><a href="/tv/95396-severance/season/2"><img alt="${data.name}"></a>'
row=$(printf '%s' "$seasons_html" | tmdb_parse_seasons)
assert_eq "tmdb_parse_seasons: real alt text kept" "$(printf '%s' "$row" | awk -F'\t' '$2==1{print $1}')" "Season 1"
assert_eq "tmdb_parse_seasons: unrendered template falls back" "$(printf '%s' "$row" | awk -F'\t' '$2==2{print $1}')" "Season 2"

### tmdb_parse_seasons: dedupes the poster+title anchor pair per season
### (TMDB emits each season's link twice, same as episodes) ###
dup_seasons_html='<a href="/tv/201834-ted/season/1"><img alt="Season 1"></a><a href="/tv/201834-ted/season/1"><img alt="Season 1"></a><a href="/tv/201834-ted/season/2"><img alt="Season 2"></a><a href="/tv/201834-ted/season/2"><img alt="Season 2"></a>'
dup_row=$(printf '%s' "$dup_seasons_html" | tmdb_parse_seasons)
assert_eq "tmdb_parse_seasons: dedupes to one row per season" "$(printf '%s\n' "$dup_row" | wc -l | tr -d ' ')" "2"

### tmdb_parse_episodes: dedupes the poster+title anchor pair per episode ###
episodes_html='<a class="no_click open" data-episode-number="1" title="Severance: Season 1 (2022): Episode 1 - Good News About Hell">a</a><a class="no_click open" data-episode-number="1" title="Severance: Season 1 (2022): Episode 1 - Good News About Hell">b</a><a class="no_click open" data-episode-number="2" title="Severance: Season 1 (2022): Episode 2 - Half Loop">a</a>'
row=$(printf '%s' "$episodes_html" | tmdb_parse_episodes)
assert_eq "tmdb_parse_episodes: dedupes to one row per episode" "$(printf '%s\n' "$row" | wc -l | tr -d ' ')" "2"
assert_eq "tmdb_parse_episodes: episode title extracted" "$(printf '%s' "$row" | awk -F'\t' '$1==1{print $2}')" "Good News About Hell"

### resolve_stream helpers (pure, no network) ###
# resolve_stream itself hits the network, so we test its deterministic parsers.
variant_fixture="$PWD/tests/.tmp-variant.m3u8"
printf '%s\n' \
    '#EXTM3U' \
    '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720' \
    'https://example.com/720.m3u8' \
    '#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1920x1080' \
    'https://example.com/1080.m3u8' > "$variant_fixture"
assert_eq "pick_variant: closest height" "$(pick_variant "$variant_fixture" 1080)" "https://example.com/1080.m3u8"

quality_fixture='{"source":{"qualities":[{"quality":"720p","codec":"h264","url":"https://example.com/720.mp4","type":"mp4"},{"quality":"1080p","codec":"h264","url":"https://example.com/1080.mp4","type":"mp4"}]}}'
assert_eq "pick_quality: closest height" "$(pick_quality "$quality_fixture" 1080)" "https://example.com/1080.mp4"

### penguplay: streams describe quality in "title" (no "quality" field),
### nested behaviorHints/subs objects break the naive whole-object regex, so
### pairs are sliced off the front of each stream object. Real addons emit
### spaces after colons ("url": "..."), so the parser must accept both ###
penguplay_fixture='{"streams": [{"url": "https://example.com/720.m3u8", "title": "PenguPlay · VidLink · 720p", "behaviorHints": {"notWebReady": true}}, {"url": "https://example.com/1080.m3u8", "title": "PenguPlay · VAPlayer · 1080p"}, {"subtitles": [{"url": "https://s.vtt"}], "url": "https://example.com/cinejoy.m3u8", "title": "PenguPlay · CineJoy · 1080p"}]}'
lr_target=1080
pp_pairs=$(penguplay_pairs "$penguplay_fixture")
# Emits every ranked candidate, best first. stremio_addon_stream takes
# only the first as the primary pick; the rest are saved for the download
# retry to fall through to when the top link is dead.
assert_eq "penguplay_pairs: emits every candidate, best first" "$(printf '%s\n' "$pp_pairs" | grep -c .)" "3"
assert_eq "penguplay_pairs: picks 1080p over nested-object 720p" "$(quality_candidates "$(printf '%s\n' "$pp_pairs" | head -1)" 1080 | head -1 | cut -f2)" "https://example.com/1080.m3u8"

### The live format has no "title" at all - quality/size/source live in
### "name"/"description". Matching only "title" silently produced zero pairs,
### so stremio_addon_stream fell back to "first url in the response":
### a 4K HLS proxy whose fragments 403 ("downloaded file is empty"), or a
### multi-GB season pack, with $quality ignored entirely. ###
pengu_live='{"streams": [{"url": "https://example.com/ad", "name": "support the project!", "description": "donate"}, {"url": "https://example.com/4k.m3u8", "behaviorHints": {"notWebReady": true}, "name": "PenguPlay 4K - VidFast", "description": "S01E01\n4K - HLS"}, {"url": "https://example.com/live1080.mkv", "behaviorHints": {"notWebReady": true}, "name": "PenguPlay 1080p - 2Peckle", "description": "S01E01\n1080p - MKV - WEB-DL\n530 MB"}]}'
lr_target=1080
assert_eq "penguplay_pairs: name/description format honors 1080 target" "$(quality_candidates "$(penguplay_pairs "$pengu_live" | head -1)" 1080 | head -1 | cut -f2)" "https://example.com/live1080.mkv"
lr_target=2160
assert_eq "penguplay_pairs: 4K still reachable when asked for" "$(quality_candidates "$(penguplay_pairs "$pengu_live" | head -1)" 2160 | head -1 | cut -f2)" "https://example.com/4k.m3u8"

### A year or size in free-text metadata is not a resolution: only a real
### "1080p"/"4K" token counts, or the 720p entry loses to a bogus 1994. ###
pengu_year='{"streams": [{"url": "https://example.com/yr.mkv", "name": "PenguPlay - Src", "description": "Movie 1994 - WEB-DL\n1994 MB"}, {"url": "https://example.com/720.mkv", "name": "PenguPlay 720p - Src", "description": "720p - MKV\n800 MB"}]}'
lr_target=1080
assert_eq "penguplay_pairs: a year in metadata is not a resolution" "$(quality_candidates "$(penguplay_pairs "$pengu_year" | head -1)" 1080 | head -1 | cut -f2)" "https://example.com/720.mkv"

### A season pack ("S01E01-04") is one multi-GB file re-downloaded once per
### episode - lose the tie to a single episode at the same quality. ###
pengu_pack='{"streams": [{"url": "https://example.com/pack.mkv", "name": "PenguPlay 1080p - CineFreak", "description": "Show S01E01-04 WEB-DL\n1080p"}, {"url": "https://example.com/single.mkv", "name": "PenguPlay 1080p - 2Peckle", "description": "Show S01E01\n1080p\n530 MB"}]}'
lr_target=1080
assert_eq "penguplay_pairs: single episode beats a season pack" "$(quality_candidates "$(penguplay_pairs "$pengu_pack" | head -1)" 1080 | head -1 | cut -f2)" "https://example.com/single.mkv"

### Some sources advertise "S01E01" but serve the whole season as one
### multi-GB file. They're only distinguishable by declaring no size, while
### honest single-episode entries always do - so a declared size wins. ###
pengu_sizeless='{"streams": [{"url": "https://example.com/sizeless.mkv", "name": "PenguPlay 720p - CineFreak", "description": "Show S01E01\n720p - WEB-DL"}, {"url": "https://example.com/sized.m3u8", "name": "PenguPlay 720p - Cinejoy", "description": "Show S01E01\n720p - HLS\n236 MB"}]}'
lr_target=720
assert_eq "penguplay_pairs: declared size beats a sizeless entry" "$(quality_candidates "$(penguplay_pairs "$pengu_sizeless" | head -1)" 720 | head -1 | cut -f2)" "https://example.com/sized.m3u8"
# ...but a sizeless entry is still used when it's the only match, so an
# HLS-only quality (commonly 4K) doesn't become unreachable.
pengu_only_sizeless='{"streams": [{"url": "https://example.com/only4k.m3u8", "name": "PenguPlay 4K - VidFast", "description": "Show S01E01\n4K - HLS"}]}'
lr_target=2160
assert_eq "penguplay_pairs: sizeless still used when only option" "$(quality_candidates "$(penguplay_pairs "$pengu_only_sizeless" | head -1)" 2160 | head -1 | cut -f2)" "https://example.com/only4k.m3u8"
unset lr_target
penguplay_4k='{"streams": [{"title": "PenguPlay · 4K", "url": "https://example.com/4k.m3u8"}]}'
assert_eq "penguplay_pairs: 4K title maps to 2160p" "$(quality_candidates "$(penguplay_pairs "$penguplay_4k" | head -1)" 2160 | head -1 | cut -f2)" "https://example.com/4k.m3u8"
# "4K Restoration ... 1080p" is a 1080p file: the explicit height token wins.
pengu_restoration='{"streams":[{"url":"https://example.com/1080.mkv","name":"Oldboy 4K Restoration 1080p BluRay","description":"2.1 GB"},{"url":"https://example.com/uhd.mkv","name":"Oldboy 2160p UHD Remux","description":"60 GB"}]}'
assert_eq "penguplay_pairs: a 4K-in-the-name 1080p release stays 1080p" "$(penguplay_pairs "$pengu_restoration" | head -1)" '{"quality":"1080p","url":"https://example.com/1080.mkv"}'
penguplay_tight='{"streams":[{"title":"PenguPlay · 480p","url":"https://example.com/480.m3u8"}]}'
assert_eq "penguplay_pairs: also accepts compact json" "$(quality_candidates "$(penguplay_pairs "$penguplay_tight" | head -1)" 480 | head -1 | cut -f2)" "https://example.com/480.m3u8"

### penguplay: explicitly requesting the provider without a url is a clear
### error, not a silent skip (the backend is optional only when unrequested) ###
( export LOBSTER_TEST=1; provider=penguplay; penguplay_url=""
    resolve_stream movie 550 ) >/dev/null 2>&1
assert_eq "resolve_stream: penguplay without penguplay_url fails loudly" "$?" "1"

### history: upsert / check / delete round-trip ###
histfile="$PWD/tests/.tmp-data/lobster/history_test.txt"
mkdir -p "$(dirname "$histfile")"
: >"$histfile"

# movie: save, then confirm history_check finds the resume position
title="The Matrix (1999)" position="00:10:00" media_type="movie" media_id="603"
season="" episode="" episode_title="" image_link="poster.jpg" progress=50
history_upsert
row=$(awk -F'\t' '$4=="603"' "$histfile")
assert_eq "history_upsert: field count" "$(printf '%s' "$row" | awk -F'\t' '{print NF}')" "9"
assert_eq "history_upsert: progress field stored" "$(printf '%s' "$row" | cut -f9)" "50"

displayed_title="$title"
history_check
assert_eq "history_check: resumes from saved position" "$resume_from" "00:10:00"

# re-upsert (same id) should update in place, not duplicate the row
position="00:20:00"
history_upsert
assert_eq "history_upsert: updates in place (no duplicate rows)" "$(wc -l <"$histfile" | tr -d ' ')" "1"
assert_eq "history_upsert: position updated" "$(awk -F'\t' '$4=="603"{print $2}' "$histfile")" "00:20:00"

# history_save: progress > 90 deletes a movie entry entirely
progress=95
history_save
assert_eq "history_save: movie >90% progress is removed" "$(wc -l <"$histfile" | tr -d ' ')" "0"

### history_rows_for_menu: newest first, display column prepended ###
histfile="$PWD/tests/.tmp-data/lobster/history_menu_test.txt"
: >"$histfile"
title="Severance" position="00:10:00" media_type="tv" media_id="95396" season="1" episode="2" episode_title="Half Loop" image_link="p.jpg" progress=40
history_upsert
title="The Matrix (1999)" position="00:05:00" media_type="movie" media_id="603" season="" episode="" episode_title="" image_link="m.jpg" progress=80
history_upsert
out=$(history_rows_for_menu)
assert_eq "history_rows_for_menu: two rows" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
assert_eq "history_rows_for_menu: newest first" "$(printf '%s\n' "$out" | sed -n '1p' | cut -f5)" "603"
tv_disp=$(printf '%s\n' "$out" | awk -F'\t' '$5==95396 {print $1}')
assert_eq "history_rows_for_menu: tv display has S01E02" "$(printf '%s' "$tv_disp" | grep -c 'S01E02')" "1"
# A movie row has three empty fields in the middle; anything splitting on
# whitespace collapses them and shifts the poster/percentage columns.
movie_row=$(printf '%s\n' "$out" | awk -F'\t' '$5==603')
assert_eq "history_rows_for_menu: movie poster column intact" "$(printf '%s' "$movie_row" | cut -f9)" "m.jpg"
assert_eq "history_rows_for_menu: movie percentage intact" "$(printf '%s' "$movie_row" | cut -f10)" "80"
assert_eq "history_rows_for_menu: movie display has the bar" "$(printf '%s' "$movie_row" | cut -f1 | grep -c '████████░░ 80%')" "1"

### genre_key: name -> id-slug for both types ###
assert_eq "genre_key: movie by name" "$(genre_key action movie)" "28-action"
assert_eq "genre_key: tv by name" "$(genre_key 'sci-fi' tv)" "10765-sci-fi-fantasy"
assert_eq "genre_key: case-insensitive" "$(genre_key COMEDY movie)" "35-comedy"

### mark_watched: ✓/▶ markers on the episode list ###
histfile="$PWD/tests/.tmp-data/lobster/watched_test.txt"
: >"$histfile"
title="Severance" position="00:10:00" media_type="tv" media_id="95396" season="1" episode="3" episode_title="In Perpetuity" image_link="p.jpg" progress=40
history_upsert
media_id="95396" season="1"
out=$(printf '1\tE1\t1. E1\n2\tE2\t2. E2\n3\tE3\t3. E3\n4\tE4\t4. E4\n' | mark_watched)
assert_eq "mark_watched: earlier episode gets ✓" "$(printf '%s\n' "$out" | awk -F'\t' '$1==2 {print $3}')" "✓ 2. E2"
assert_eq "mark_watched: current episode gets ▶" "$(printf '%s\n' "$out" | awk -F'\t' '$1==3 {print $3}')" "▶ 3. E3"
assert_eq "mark_watched: later episode unmarked" "$(printf '%s\n' "$out" | awk -F'\t' '$1==4 {print ($3 ~ /[✓▶]/) ? "marked" : "plain"}')" "plain"

### delete_history_row: removes one entry by type+id ###
histfile="$PWD/tests/.tmp-data/lobster/delete_test.txt"
: >"$histfile"
title="The Matrix (1999)" position="00:05:00" media_type="movie" media_id="603" season="" episode="" episode_title="" image_link="m.jpg" progress=80
history_upsert
title="Severance" position="00:10:00" media_type="tv" media_id="95396" season="1" episode="2" episode_title="Half Loop" image_link="p.jpg" progress=40
history_upsert
row=$(history_rows_for_menu | awk -F'\t' '$5==603 {print; exit}')
delete_history_row "$row"
assert_eq "delete_history_row: one row remains" "$(wc -l <"$histfile" | tr -d ' ')" "1"
assert_eq "delete_history_row: remaining is Severance" "$(cut -f1 "$histfile")" "Severance"

### arg parsing: flags set their variables, unknown args accumulate into query ###
unset download image_preview json_output trending no_subs subs_language quality recent player download_dir
player="mpv"
parse_args -i -j -t -n -q 720 -l french the matrix
assert_eq "parse_args: -i sets image_preview" "$image_preview" "true"
assert_eq "parse_args: -j sets json_output" "$json_output" "true"
assert_eq "parse_args: -t sets trending" "$trending" "1"
assert_eq "parse_args: -n sets no_subs" "$no_subs" "true"
assert_eq "parse_args: -q consumes its value" "$quality" "720"
assert_eq "parse_args: -l consumes its value" "$subs_language" "french"
assert_eq "parse_args: bare words accumulate into query" "$query" "the matrix"

unset provider
parse_args --provider rivestream the matrix
assert_eq "parse_args: --provider consumes its value" "$provider" "rivestream"

unset top_rated
parse_args --top-rated tv
assert_eq "parse_args: --top-rated consumes its value" "$top_rated" "tv"
unset top_rated
parse_args --top-rated
assert_eq "parse_args: --top-rated defaults to movie" "$top_rated" "movie"

unset genre genre_type
parse_args --genre action
assert_eq "parse_args: --genre consumes name" "$genre" "action"
assert_eq "parse_args: --genre type defaults to movie" "$genre_type" "movie"
unset genre genre_type
parse_args --genre action tv
assert_eq "parse_args: --genre optional type" "$genre_type" "tv"
unset action
parse_args --last
assert_eq "parse_args: --last sets action" "$action" "last"

unset binge
parse_args --binge
assert_eq "parse_args: --binge sets binge" "$binge" "true"
unset year year_type
parse_args --year 1999
assert_eq "parse_args: --year consumes value" "$year" "1999"
assert_eq "parse_args: --year type defaults to movie" "$year_type" "movie"
unset year year_type
parse_args --year 1999 tv
assert_eq "parse_args: --year optional type" "$year_type" "tv"

# -d without a following path falls back to the configured download_dir
# instead of silently swallowing the next flag (the old script's bug).
download_dir="/configured/default"
parse_args -d -j
assert_eq "parse_args: -d with no path keeps configured download_dir" "$download_dir" "/configured/default"
parse_args -d /custom/path -j
assert_eq "parse_args: -d with a path uses it" "$download_dir" "/custom/path"

### pick_quality / collect_subs: order- and extra-field-agnostic ###
# Regression test for a real bug: the old grep patterns hardcoded the exact
# field order APIs happen to emit today ("quality","codec","url","type"), so
# a reorder or an added key would silently zero out a whole backend. These
# fixtures deliberately shuffle the order and add an unknown field.
shuffled_quality='{"url":"https://example.com/1080.mp4","extra":"x","quality":"1080p"}'
assert_eq "pick_quality: shuffled field order + extra field" "$(pick_quality "$shuffled_quality" 1080)" "https://example.com/1080.mp4"

shuffled_subs='{"file":"https://example.com/en.vtt","extra":"x","label":"English"}'
assert_eq "collect_subs: shuffled field order + extra field" "$(collect_subs "$shuffled_subs" "english")" "https://example.com/en.vtt"

### collect_subs: stremio-shaped subtitle objects (url + lang codes,
### opensubtitles returns "en"/"eng" not the full name, and real addons
### emit spaces after colons), deduped ###
stremio_subs='{"subtitles": [{"id": "1", "url": "https://example.com/en.vtt", "lang": "en"}, {"id": "2", "url": "https://example.com/es.vtt", "lang": "es"}, {"id": "3", "url": "https://example.com/en2.vtt", "lang": "eng"}, {"id": "4", "url": "https://example.com/en.vtt", "lang": "en"}]}'
assert_eq "collect_subs: stremio url+lang codes, deduped" "$(collect_subs "$stremio_subs" "english")" "https://example.com/en.vtt,https://example.com/en2.vtt"
assert_eq "collect_subs: spanish matched via lang code" "$(collect_subs "$stremio_subs" "spanish")" "https://example.com/es.vtt"

### collect_subs: $max_subs caps the list (0 = no cap) ###
many_subs='{"subtitles": [{"url": "https://e.com/1.vtt", "lang": "en"}, {"url": "https://e.com/2.vtt", "lang": "en"}, {"url": "https://e.com/3.vtt", "lang": "en"}]}'
max_subs=2
assert_eq "collect_subs: capped at max_subs" "$(collect_subs "$many_subs" "english")" "https://e.com/1.vtt,https://e.com/2.vtt"
max_subs=0
assert_eq "collect_subs: max_subs=0 means no cap" "$(collect_subs "$many_subs" "english")" "https://e.com/1.vtt,https://e.com/2.vtt,https://e.com/3.vtt"
unset max_subs

### parse_args: -c is deferred, so flag order can't change its behavior ###
unset action image_preview
parse_args -c -i
assert_eq "parse_args: -c before -i still sets image_preview" "$image_preview" "true"
assert_eq "parse_args: -c before -i sets action=continue" "$action" "continue"

unset action image_preview
parse_args -i -c
assert_eq "parse_args: -i before -c sets image_preview" "$image_preview" "true"
assert_eq "parse_args: -i before -c sets action=continue" "$action" "continue"

### save_progress: reads live position/duration off $tmp_dir/pos, so a
### direct-mp4 stream (no HLS EXTINF markers to sum) still gets a real
### progress percentage instead of always reading as 0% ###
have_ipc="true"
printf '540 600\n' >"$tmp_dir/pos"
title="Test Movie" media_type="movie" media_id="1" image_link=""
save_progress
assert_eq "save_progress: reads position/duration from \$tmp_dir/pos" "$position" "00:09:00"
assert_eq "save_progress: computes percentage for a direct (non-HLS) stream" "$progress" "90"

### save_progress: no IPC means no duration, but the resume point is still
### valid - it used to be thrown away as 00:00:00 ###
have_ipc="false"
watchlater_subdir="$tmp_dir/wl-test"
mkdir -p "$watchlater_subdir"
printf 'start=125.5\n' >"$watchlater_subdir/redirect"
save_progress
assert_eq "save_progress: keeps watch_later position without duration" "$position" "00:02:05"
assert_eq "save_progress: unknown duration means 0%" "$progress" "0"
have_ipc="true"
rm -rf "$watchlater_subdir"

rm -rf "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$tmp_dir/pos"

### collect_subs: whole-token language matching ("en" is a substring of
### "french"/"german"/"slovenian", so substring matching pulled in the wrong
### track) ###
boundary_subs='[{"file":"https://example.com/en.vtt","label":"English (SDH)"},{"file":"https://example.com/fr.vtt","label":"French"},{"url":"https://example.com/en2.vtt","lang":"en-US"}]'
assert_eq "collect_subs: whole-token match, no false positives" "$(collect_subs "$boundary_subs" "english")" "https://example.com/en.vtt,https://example.com/en2.vtt"
assert_eq "collect_subs: french not swallowed by english" "$(collect_subs "$boundary_subs" "french")" "https://example.com/fr.vtt"

### LANGS: the one language table, read three different ways ###
assert_eq "lang_name: iso 639-2 code" "$(lang_name eng)" "English"
assert_eq "lang_name: alternate code" "$(lang_name fra)" "French"
assert_eq "lang_name: untagged" "$(lang_name und)" ""
assert_eq "lang_name: unknown falls through" "$(lang_name xyz)" "xyz"
assert_eq "lang_code: mpv --alang list" "$(lang_code English)" "en,eng,eng-US,en-US"
assert_eq "lang_code: unknown falls through" "$(lang_code klingon)" "klingon"
assert_eq "lang_aliases: name plus every code" "$(lang_aliases dutch)" "dutch nl dut nld"

### expand_selection: numbered_menu's multi-select "1,3,5-7" parsing ###
assert_eq "expand_selection: single number" "$(expand_selection '2')" "2"
assert_eq "expand_selection: comma list" "$(expand_selection '1,3' | tr '\n' ' ')" "1 3 "
assert_eq "expand_selection: range" "$(expand_selection '5-7' | tr '\n' ' ')" "5 6 7 "
assert_eq "expand_selection: mixed comma+range" "$(expand_selection '1,3,5-7' | tr '\n' ' ')" "1 3 5 6 7 "

if [ "$fail" -eq 0 ]; then
    echo "All smoke tests passed."
    exit 0
else
    echo "$fail smoke test(s) failed."
    exit 1
fi
