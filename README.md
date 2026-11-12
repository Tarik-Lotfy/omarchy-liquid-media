# Liquid Media

A liquid-glass now-playing popup for the Omarchy bar. It replaces the stock media
widget with a compact, pinned player that shows album art, synchronized lyrics,
a seek bar, transport controls, and per-song volume.

![Liquid Media](preview.png)

## Features

- Sticky liquid-glass popup that stays above normal windows.
- Album art, track title, artist, album, and playback state.
- Album thumb and a hairline progress line in the bar widget.
- Synchronized lyrics from [LRCLIB](https://lrclib.net), with plain-text
  [Genius](https://genius.com) lyrics as a fallback.
- Apple Music–style active-line highlighting and smooth lyric scrolling.
- Seek bar with elapsed and total time.
- Transport controls: previous, play/pause, next.
- Shuffle and repeat controls when the player supports them.
- Compact and expanded popup sizes. The expanded layout adds larger art and
  lyrics, a full source list, and bigger controls.
- Multi-player source switching: a compact `N/M` badge cycles sources, and the
  expanded popup lists every source.
- Per-song volume using the player's own PipeWire stream, with MPRIS volume as
  a fallback.
- Remembers lyrics lookups so reopening the popup does not repeat searches.
- Remembers compact/expanded size across shell restarts.

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

## Usage

- **Left-click the bar widget** to open or close the popup.
- **Right-click** to play or pause without opening the popup.
- **Middle-click** or **scroll** to change tracks.
- Hover the widget to see the track and elapsed/total time. Long titles scroll
  in a seamless loop.
- Use the expand button at the bottom-right of the popup to switch between the
  compact and expanded layouts. The choice is saved across shell restarts.
- Close the popup with the button at the top-right of the title row.
- Shuffle and repeat buttons dim when the active player does not expose those
  MPRIS properties (Firefox, for example, has no `Shuffle`).
- Click the `N/M` badge in compact mode to cycle players, or pick a source from
  the list in expanded mode.

## Scripting

The plugin exposes an IPC target for keybindings and scripts:

```bash
omarchy-shell liquid-media toggle       # open or close
omarchy-shell liquid-media open
omarchy-shell liquid-media close
omarchy-shell liquid-media toggleSize   # compact or expanded
omarchy-shell liquid-media expand
omarchy-shell liquid-media collapse
omarchy-shell liquid-media shuffle      # toggle shuffle
omarchy-shell liquid-media loop         # off -> all -> one -> off
omarchy-shell liquid-media source       # switch to the next player
omarchy-shell liquid-media status       # JSON state for scripts
```

Example Hyprland binding:

```conf
bind = SUPER, M, exec, omarchy-shell liquid-media toggle
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

## Troubleshooting

- **The popup does not appear.** Confirm the plugin is enabled with
  `omarchy plugin list` and that a player is visible on D-Bus:
  `busctl --user list | grep org.mpris.MediaPlayer2`.
- **No lyrics.** Lyrics need network access. Instrumental or very new tracks may
  not be indexed yet; the popup falls back to plain Genius text, then to a
  "no lyrics" message.
- **Shuffle or repeat is greyed out.** The active player does not expose those
  MPRIS properties. Switch players with the `N/M` badge.
- **Volume does nothing.** Per-song volume needs the player's PipeWire stream. If
  the stream is not visible, the plugin falls back to the player's MPRIS volume.
- **The popup is in the wrong place after changing bar settings.** Restart the
  shell with `omarchy-restart-shell`.

## Notes

- Spotify does not publish MPRIS position updates while playing, so the popup
  keeps a local clock and resynchronizes it from D-Bus while open.
- Per-song volume uses the player's PipeWire playback stream, so it does not
  change the system output volume.
- The plugin is a modified copy of Omarchy's built-in `omarchy.media` plugin.
  See [LICENSE](LICENSE) for MIT attribution.

## License

MIT. Derived from Omarchy's `omarchy.media` plugin.
