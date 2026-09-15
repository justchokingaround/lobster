# Implementation notes

Background for the non-obvious parts of `lobster.sh`. The script keeps a
two-or-three-line summary at each site and points here for the full reasoning.

## Terminal previews (`image_preview_cell`, `tmdb_preview_text`)

fzf's preview pane is not a real terminal from our side: it is fzf's own
renderer reading our stdout line by line. Cursor-addressing escapes ("move up
N, over M") emitted as their *own* output lines get eaten or overridden by
fzf's layout instead of landing where they were sent. Two routes around that,
depending on what draws the poster:

* **kitty / ghostty** — `kitten icat --place` *without* `--unicode-placeholder`
  leaves the cursor at the image's top-left corner (documented behaviour), so
  the info text is printed straight after it and indented past the poster with
  literal space characters. No placeholder means no character cells are
  reserved for the poster, so nothing needs the image's real rendered height;
  the overview/cast text simply waits a fixed number of blank lines equal to
  the *requested* placement height, which is always enough clearance whatever
  the aspect fit inside that box turns out to be.
  * Padding is literal spaces and blank lines, not escapes — fzf ignores the
    escapes but prints the characters.
  * The default z-index (0, image above text in shared cells) is what we want:
    the leading pad lands in cells the poster occupies and the poster keeps
    winning there, while the real text further right shares no cell with it.
  * `--scale-up` is required: TMDB thumbnails are ~200x300 and icat otherwise
    renders at native pixel size instead of filling the placement box.
  * `--clear` drops the previous highlight's placement.
  * Height is derived from a fixed width as `w / 2` (terminal cells run taller
    than chafa's symbol-cell approximation), then `+2` rows of slack because at
    some zoom levels `--scale-up` rounds a hair taller than the requested box
    and text landing one row early prints over the poster.

* **everything else (chafa)** — `--format symbols` is plain multi-line ANSI
  text, one real row per line, so the poster and the info text are rendered as
  two independent line-lists and glued together with `paste(1)`. This is why
  the format cannot be `auto`: a sixel/iTerm-capable terminal would get a
  pixel-graphics format, which is a single line no matter how many rows it
  visually spans, and there would be nothing to pair text against.
  `--scale max` is needed for the same reason as icat's `--scale-up`.
  Chafa's half-block cells are about twice as tall as wide, so a box N rows
  tall needs ~4N/3 columns to hold a 2:3 poster at its real aspect ratio
  (measured against chafa, not guessed). Height is derived from the width
  budget so the box is never wider than the budget without shrinking height to
  match — that mismatch is what letterboxes the poster.

Layout modes passed to `tmdb_preview_text`:

| mode | meaning |
| --- | --- |
| (empty) | one unbroken block, no poster on screen |
| `side` | split at a `LOBSTER_SPLIT` marker line: title/tagline/meta/genres above, overview/cast below, so the chafa branch can `paste` only the narrow half beside the poster |
| `overlay:COL:H` | indent the first half by COL columns and pad to H lines, for the icat branch |

`side` gets its own preview cache slot, otherwise the no-poster caller would be
served a block with a stray marker line in the middle of it (or vice versa).

Text gets first claim on the pane width: the poster takes at most 40% (with a
floor), because a 50/50 split starves titles/genres into wrapping when fzf
hands over fewer columns at high zoom.

Not done: rendering chafa art in the plain (no-image-preview) picker. fzf's
`:wrap` re-flows lines narrower than the art's fixed width, mid escape
sequence, which turns it into color noise. It would need the chafa width
matched to the real pane width and `:wrap` dropped for the image portion.

## Stremio addon source ranking (`penguplay_pairs`)

penguplay/aiostreams streams carry no `quality` field: resolution, size, source
and audio language all live as free text in `name`/`description`. There is no
`title` key at all in the current shape — an older format had one, and matching
on it silently yielded zero pairs, which fell through to "just take the first
url in the response". That first entry is whatever the addon happens to list
first: in practice a 4K HLS proxy whose fragments all 403, or a multi-GB
"S01E01-04" season pack re-downloaded once per episode, with `$quality` ignored
the whole time.

The function emits one winning `{"quality","url"}` line rather than every
candidate: the addon already supplies the metadata the generic tie-breaker
would otherwise fetch over the network (one `ffprobe` per candidate). At 1080p
roughly seven entries tie, so emitting them all meant seven probes plus a
pointless "which track?" prompt per episode.

Ranking: closest to the requested height, then a single episode over a season
pack, then an entry that declares its size over one that does not, then the
addon's own order. The size rule is load-bearing — some sources (CineFreak)
advertise "S01E01" but serve the whole season as one multi-GB file, and they
are not identifiable by name, but they never declare a `MB`/`GB` size while
honest single-episode entries do. HLS entries legitimately have no size either
and rank alongside them, so they stay reachable.

Audio language is deliberately *not* ranked on: the addon mislabels it, and the
player picks a track from `$audio_language` at playback time anyway.

## Quality/height parsing (`quality_candidates`, `rivestream_candidates`)

Height comes only from an actual resolution token (`1080p`, or a bare 3-4 digit
run), never from concatenating every digit in the string. Some providers suffix
quality with a meaningless index — rivestream's `guru` emits `HLS 1` / `HLS 2` —
and naive digit-concatenation treated that `1`/`2` as a height, letting a dead
guru link outrank a working unlabeled `HLS` entry on the distance tiebreak.

## Ctrl-C and background resolve (`resolve_stream_bg`)

A plain `$(resolve_stream ...)` leaves Ctrl-C undependable: bash only checks a
pending trap once the foreground command finishes, and the curl/node/ffprobe
hops inside are not guaranteed to die from the same SIGINT on every
platform/shell. `wait` on an explicit background pid is documented to return
(and run the trap) immediately on a trapped signal regardless of what the child
is doing; `cleanup()` then takes the whole process group down.

That guarantee only holds at the top level. A command substitution is its own
subshell and the "wait returns early" behaviour does not propagate out of it —
hence `resolve_stream_bg` sets `$lr_resolve_out` instead of printing, and
callers must invoke it as a bare statement.

The same class of bug one level deeper: `status()` backgrounds a spinner that
inherits stdout, so capturing a function that calls it with `$(...)` holds a
pipe open (never seeing EOF) for as long as the spinner runs.

`cleanup()` kills the whole process group rather than just itself because
backgrounded curl/node/ffprobe outlive the trap otherwise, and the calling
shell keeps waiting on the group (job control waits for it to empty), which
looks like a hung terminal.

## Batch downloads (`download_episodes_parallel`, `render_downloads`)

**Resolving stays sequential.** `resolve_stream` and friends key scratch files
off `$$`, and POSIX `$$` does *not* change inside a `(...) &` subshell of the
same process, so concurrent resolves corrupt each other's temp files. Spawning
each resolve as a real `sh $0 ...` process (genuinely distinct `$$`) was tried
and works, but N of those run N full multi-provider probe sequences at once for
what is just a small metadata lookup. Only the video transfer is parallel, and
each download starts the moment its own resolve returns.

**Concurrency and pace.** `download_concurrency` (default 8) is a sliding
window of in-flight transfers — a provider CDN happily 4xx's a burst of a dozen
simultaneous connections. `download_pace` (default 1s) is a separate minimum
gap between starting each episode, because a requests-per-window quota
(PenguPlay: ~15 requests per 15s) is about cumulative rate over time and a
concurrency cap cannot fix it.

**The manifest is built for every episode up front**, before any of them start,
purely so the live table can animate the whole time. It used to be appended to
as each episode resolved, which meant the renderer could only start after the
launch loop finished — i.e. after nearly every download was already done — so a
season download appeared to show no progress at all.

**The live block only ever shrinks.** Rows leave from the top, in strict
episode order, once flushed to permanent scrollback, so "cursor up by last
frame's height, then redraw this frame's (possibly smaller) height" always
lands correctly even though episodes finish in arbitrary order underneath.
Lines are clamped to terminal width for the same reason: a wrapped line breaks
the cursor math. The clamp is byte-based, so a multi-byte boundary may cut a
hair short — never overflow, which is the part that matters.

An episode that has finished but has not reached its in-order flush shows its
real outcome (✔/✘), not a placeholder — an earlier version rendered a hardcoded
"✔ (queued)" that read as "not started" and lied about failures until the flush
flipped them.

`status()`'s own spinner is muted (`lr_no_status`) for the duration, since it
writes `\r` lines to the same stderr the table redraws in place.

**One retry pass** over whatever failed, guarded by a flag so a dead provider
cannot recurse. These CDN links are signed and near single-use, so a failure is
usually a one-off 403 on that specific link; retrying re-resolves from scratch
and gets a fresh URL, possibly from a different source. Several failures in one
batch at concurrency > 1 usually means the provider forbids simultaneous
streams, which is why the "try download_concurrency=1" hint fires.

## Downloader chain (`download_video`)

Order: a user-defined `custom_downloader` wins outright; then `aria2c` if
explicitly configured *and* the URL is a plain non-HLS file with no subs to mux
(aria2c cannot segment `.m3u8`); then yt-dlp when installed, as the most robust
option for obfuscated HLS; then ffmpeg; then mpv `--stream-record`.

* yt-dlp does not know about `$subs_csv` (those are URLs `resolve_stream`
  found, not from a site it recognises), so they are dropped as sidecar `.vtt`
  files next to the video — mpv/vlc auto-load a same-basename subtitle.
* `--progress-template` prints a stable greppable `lobster-pct:` line. The
  `download:` prefix is yt-dlp's template-TYPE selector and is consumed, not
  printed, so the literal marker has to come after it. `PYTHONUNBUFFERED=1` is
  required or Python block-buffers stdout once it is not a tty and the progress
  file looks frozen.
* yt-dlp's failure output is copied aside before ffmpeg runs, because ffmpeg's
  `-progress` truncates the same file on open and every failure would otherwise
  be blamed on ffmpeg.
* The mpv fallback exists for CDN mirrors that disguise HLS segments with a
  non-media extension (`.jpg`/`.png`). ffmpeg's HLS demuxer hard-rejects those
  as deliberate, non-configurable SSRF hardening; mpv has no such check, which
  is why playback of the same URL works. `--stream-record` copies without
  decoding, so it is not a re-encode. No subtitle muxing on that path, and the
  output is raw MPEG-TS wearing an `.mkv` name — fine for mpv/vlc, which sniff
  content over extension.
* There is deliberately **no percentage** for the ffmpeg path in batch mode. It
  used to run an extra `ffprobe` duration probe purely to turn `out_time_ms`
  into a `%`, which is a third request per episode against the same host, on
  top of yt-dlp's attempt and ffmpeg's own. Providers enforcing a request-count
  quota burned through it faster for a cosmetic number.
* `$referer` is sent as a header on every path: playback always sent it, and
  the CDNs 403 or serve a decoy `.jpg` "segment" without it.

## Progress tracking (`poll_position`, `save_progress`)

`nc` is a soft dependency. With it, position and duration come live off mpv's
IPC socket, which works for direct files and HLS alike and survives the signed
URL changing between runs; one poller writes `$tmp_dir/pos` and both
`save_progress` and the Discord presence read that file, so there is a single
source of truth. Without `nc`, mpv writes to a *per-episode* `watch_later`
directory whose single file is unambiguous to read back — unlike grepping the
shared directory for a URL that differs every session.

## TMDB scraping

No API key: lobster scrapes `www.themoviedb.org`'s public pages. The site
serves two card layouts (search results vs. popular/now-playing grids) but both
wrap each poster in `<a class="flex w-full" href="/(movie|tv)/ID-slug">`, so
that anchor is the one stable per-card boundary and every listing goes through
`tmdb_extract_media`.

Detail-page scraping (`tp_render`) uses `sed -n ...p`, never a plain `s///`
substitution: on a miss, a substitution leaves the input unchanged and the
following "cut at the first closing tag" step grabs whatever is at the start of
the page instead. A WAF challenge page kept the literal string
`class="overview"` inside its own bot-check JS with no real overview div, and
that is how raw page JS ended up rendered in the preview pane. The overview is
also bounded at the div's close, not the `<p>`'s — a title with no synopsis
renders an empty div with no `<p>` at all, and cutting at the next `</p>` ran
on into the cast list.

Poster downloads verify the JPEG magic bytes and delete the file otherwise:
TMDB 403s occasionally, and a saved HTML error page named `.jpg` makes chafa
fail with "Unknown file format" forever, since nothing else cleans it out.

Previews sleep briefly before hitting the network. fzf kills and re-runs the
preview command on every highlight change, so the sleep debounces a fast scroll
into zero requests instead of a burst that trips TMDB's bot check.
