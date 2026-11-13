# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-12

### Added

- Compact and expanded popup modes, with the choice saved across shell restarts.
- Shuffle and repeat controls, disabled automatically when the player does not
  expose the matching MPRIS properties.
- Multi-player source switching: an `N/M` badge in compact mode and a full
  source list in expanded mode.
- Album thumbnail and a hairline progress line in the bar widget.
- Elapsed/total time in the bar tooltip.
- `liquid-media` IPC target with `open`, `close`, `toggle`, `expand`,
  `collapse`, `toggleSize`, `shuffle`, `loop`, `source`, and `status`.
- CI manifest validation and a bug-report issue template.

### Changed

- Right-click on the bar widget now toggles play/pause instead of opening the
  popup.
- The bar widget is about two thirds of its previous width, with a thumbnail
  and a seamless looping title marquee.
- The expanded layout uses larger art, lyrics, and transport controls.
- Round buttons center their glyph by painted ink instead of the font line box.
- The close button moved to the top-right of the popup title row.

### Security

- Bound lyrics input and state: response size, scanned and kept rows, plain
  text length, and the in-memory cache are all capped.
- Genius lyric pages are only fetched from an `https` URL on `genius.com`, and
  redirects are no longer followed.

### Fixed

- Popup height and offsets stay correct when the bar window spans the screen.
- The bar progress line keeps advancing while the popup is closed instead of
  freezing until it opens.
- The blurred album-art glass no longer reloads on every popup open: the cover
  stays in Qt's pixmap cache instead of being downloaded again each time the
  overlay surface is remapped.
- Reopening the popup jumps straight to the current lyric line instead of
  starting at the top and catching up on the next line change.

## [1.0.2] - 2026-11-05

### Fixed

- Popup vertical offset when the bar window spans the whole screen.

## [1.0.1] - 2026-11-05

### Fixed

- Popup height when the bar window is full-screen.

## [1.0.0] - 2026-11-03

### Added

- Initial release: liquid-glass media popup with album art, synchronized
  LRCLIB lyrics, Genius fallback, seek bar, transport controls, per-song
  volume, and multi-source switching.
