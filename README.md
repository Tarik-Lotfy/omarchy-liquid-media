# Liquid Media

A liquid-glass now-playing popup for the Omarchy bar. It replaces the stock media
widget with a compact, pinned player that shows album art, synchronized lyrics,
a seek bar, transport controls, and per-song volume.


## Features

- Sticky liquid-glass popup that stays above normal windows.
- Album art, track title, artist, album, and playback state.
- Synchronized lyrics from [LRCLIB](https://lrclib.net), with plain-text
  [Genius](https://genius.com) lyrics as a fallback.
- Apple Music–style active-line highlighting and smooth lyric scrolling.
- Seek bar with elapsed and total time.
- Transport controls: previous, play/pause, next.
- Per-song volume using the player's own PipeWire stream, with MPRIS volume as
  a fallback.
- Remembers lyrics lookups so reopening the popup does not repeat searches.
- Click the bar widget to open or close. Middle-click or scroll to change tracks.

## Requirements

- Omarchy Quattro (4.0.6 or newer) with the Quickshell shell.
- `curl` and `jq` (both ship with Omarchy).
- PipeWire for per-song volume control.
- Network access for lyric lookups.

No API keys are required.

## Install

```bash
omarchy plugin add https://github.com/Tarik-Lotfy/omarchy-liquid-media.git --enable
```

The plugin declares `clonedFrom: omarchy.media`, so enabling it replaces the
built-in media widget in its existing bar slot and disables the built-in copy.
If you install without `--enable`, enable it manually:

```bash
omarchy plugin enable io.github.tarik-lotfy.liquid-media --section right
```

## Remove

```bash
omarchy plugin remove io.github.tarik-lotfy.liquid-media
```

Removing the clone restores the built-in `omarchy.media` widget.

## Privacy

Lyric lookup sends the current track title and artist to `lrclib.net`. If LRCLIB
has no match, the title and artist are sent to `genius.com`. No listening history
is stored by this plugin; the lyrics cache lives in memory for the current shell
session only.

## Notes

- Spotify does not publish MPRIS position updates while playing, so the popup
  keeps a local clock and resynchronizes it from D-Bus while open.
- Per-song volume uses the player's PipeWire playback stream, so it does not
  change the system output volume.
- The plugin is a modified copy of Omarchy's built-in `omarchy.media` plugin.
  See [LICENSE](LICENSE) for MIT attribution.

## License

MIT. Derived from Omarchy's `omarchy.media` plugin.
