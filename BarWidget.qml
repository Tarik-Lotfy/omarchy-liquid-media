import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "io.github.tarik-lotfy.liquid-media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property real trackLength: activePlayer && activePlayer.length > 0 ? activePlayer.length : 0

  // MPRIS players such as Spotify never emit Position updates while playing,
  // so activePlayer.position goes stale. Keep a local clock anchored to the
  // player's real position and resync it from D-Bus while the popup is open.
  property real trackPosition: 0
  property real anchorPosition: 0
  property double anchorMs: 0

  // The player's own PipeWire playback stream is what lets us change the
  // volume of Spotify without touching the system output. Some players also
  // expose an MPRIS volume, which we fall back to.
  readonly property var playerStream: mediaService && mediaService.playerPlaybackStream
    ? mediaService.playerPlaybackStream(activePlayer) : null
  readonly property bool hasStreamVolume: !!(playerStream && playerStream.audio)
  readonly property bool hasMprisVolume: !!(activePlayer && activePlayer.volumeSupported)
  readonly property bool canControlVolume: hasStreamVolume || hasMprisVolume
  readonly property real volumeValue: hasStreamVolume ? playerStream.audio.volume
    : (hasMprisVolume ? activePlayer.volume : 0)
  readonly property bool volumeMuted: hasStreamVolume ? playerStream.audio.muted
    : (hasMprisVolume && activePlayer ? activePlayer.volume <= 0.001 : false)

  property bool popupOpen: false
  property real maxLabelWidth: 180

  // Lyrics are fetched from LRCLIB (free, no API key) when the popup opens.
  // When LRCLIB has nothing, fall back to Genius (plain lyrics only).
  property var lyricsLines: []
  property string lyricsPlain: ""
  property bool lyricsSynced: false
  property bool lyricsLoading: false
  property bool lyricsInstrumental: false
  property string lyricsError: ""
  property string lyricsKey: ""
  property string lyricsSource: ""
  property string pendingLyricsKey: ""
  property string queuedLyricsKey: ""
  property string geniusKey: ""
  property var lyricsCache: ({})
  property int currentLyricIndex: -1
  property bool lyricsScrolled: false

  // Seeking keeps the progress slider from fighting live position updates
  // while the pointer is down.
  property bool seeking: false
  property real seekValue: 0

  function close() { popupOpen = false }

  function formatTime(seconds) {
    var value = Number(seconds)
    if (!isFinite(value) || value <= 0) return "0:00"
    var minutes = Math.floor(value / 60)
    var secs = Math.floor(value % 60)
    return minutes + ":" + (secs < 10 ? "0" : "") + secs
  }

  function trackKey() {
    return [title, artist, album, Math.round(trackLength)].join("\u001f")
  }

  function updatePosition() {
    if (!activePlayer) {
      trackPosition = 0
      return
    }

    var value = anchorPosition
    if (activePlayer.isPlaying && anchorMs > 0) value += (Date.now() - anchorMs) / 1000
    if (trackLength > 0 && value > trackLength) value = trackLength
    if (!isFinite(value) || value < 0) value = 0
    trackPosition = value
  }

  function anchorPositionNow(value) {
    var seconds = Number(value)
    if (!isFinite(seconds) || seconds < 0) seconds = 0
    anchorPosition = seconds
    anchorMs = Date.now()
    updatePosition()
  }

  function resyncPosition() {
    if (!activePlayer) {
      anchorPositionNow(0)
      return
    }
    // Prefer the player's real Position over MPRIS PropertiesChanged: some
    // players (Spotify) report Position once and then never update it, so the
    // cached value can be minutes behind. Fall back to it only when polling
    // is not available.
    if (activePlayer.positionSupported && activePlayer.dbusName) {
      pollPosition()
      return
    }
    anchorPositionNow(activePlayer.position)
  }

  function pollPosition() {
    if (!activePlayer || !activePlayer.positionSupported || positionProc.running) return
    positionProc.command = ["busctl", "--user", "get-property",
      String(activePlayer.dbusName), "/org/mpris/MediaPlayer2",
      "org.mpris.MediaPlayer2.Player", "Position"]
    positionProc.running = true
  }

  function lyricsUrl() {
    // Album names on streaming services often differ from LRCLIB's releases,
    // so search by track + artist only and disambiguate by duration below.
    var url = "https://lrclib.net/api/search?track_name=" + encodeURIComponent(title)
    if (artist !== "") url += "&artist_name=" + encodeURIComponent(artist)
    return url
  }

  function scheduleLyricsRefresh() {
    if (!popupOpen) return
    lyricsDebounce.restart()
  }

  function requestLyrics() {
    if (!popupOpen || title === "") return

    var key = trackKey()

    // One lookup at a time. If the track changes mid-flight, remember the
    // newest key and pick it up when the current curl exits.
    if (lyricsProc.running) {
      queuedLyricsKey = key
      return
    }

    if (key === lyricsKey && (lyricsLoading || lyricsLines.length > 0 || lyricsPlain !== "" || lyricsInstrumental))
      return

    queuedLyricsKey = ""
    lyricsKey = key
    var cached = lyricsCache[key]
    if (cached) {
      applyCache(cached)
      return
    }

    lyricsLoading = true
    lyricsSynced = false
    lyricsInstrumental = false
    lyricsLines = []
    lyricsPlain = ""
    lyricsError = ""
    lyricsSource = ""
    currentLyricIndex = -1
    pendingLyricsKey = key

    lyricsProc.command = ["curl", "-fsS", "--max-time", "8", "-H",
      "User-Agent: OmarchyMediaWidget/1.0", lyricsUrl()]
    lyricsStart.restart()
  }

  function applyCache(entry) {
    lyricsLoading = false
    lyricsSynced = entry.synced === true
    lyricsInstrumental = entry.instrumental === true
    lyricsLines = entry.lines || []
    lyricsPlain = entry.plain || ""
    lyricsError = entry.error || ""
    lyricsSource = entry.source || ""
    lyricsScrolled = false
    refreshLyricIndex()
    Qt.callLater(root.positionLyrics)
  }

  function pickLyrics(data) {
    if (!data) return null
    var list = Array.isArray(data) ? data : [data]
    var synced = null
    var syncedScore = Infinity
    var plain = null
    var plainScore = Infinity
    var instrumental = null

    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (!item) continue

      if (item.instrumental === true && !instrumental) instrumental = item

      var duration = parseFloat(item.duration)
      var score = (trackLength > 0 && isFinite(duration))
        ? Math.abs(duration - trackLength) : 999

      if (item.syncedLyrics && score < syncedScore) {
        synced = item
        syncedScore = score
      }
      if (item.plainLyrics && score < plainScore) {
        plain = item
        plainScore = score
      }
    }

    return synced || plain || instrumental
  }

  function parseLrc(text) {
    var lines = []
    var rows = String(text || "").split("\n")
    var stamp = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/g

    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var times = []
      var match
      stamp.lastIndex = 0
      while ((match = stamp.exec(row)) !== null) {
        var minutes = parseInt(match[1], 10)
        var seconds = parseFloat(String(match[2]).replace(":", "."))
        if (isFinite(minutes) && isFinite(seconds)) times.push(minutes * 60 + seconds)
      }
      if (times.length === 0) continue

      var content = row.replace(/\[[^\]]*\]/g, "").trim()
      for (var j = 0; j < times.length; j++) lines.push({ t: times[j], text: content })
    }

    lines.sort(function(a, b) { return a.t - b.t })
    return lines
  }

  function applyLyrics(data) {
    if (!lyricsLoading) return

    var candidate = pickLyrics(data)
    if (!candidate) {
      // LRCLIB has nothing for this track: try Genius before giving up.
      if (pendingLyricsKey === trackKey()) {
        requestGeniusLyrics()
      } else {
        lyricsLoading = false
      }
      return
    }

    lyricsLoading = false

    if (candidate.instrumental === true) {
      lyricsCache[pendingLyricsKey] = { instrumental: true }
      if (pendingLyricsKey === trackKey()) applyCache({ instrumental: true })
      return
    }

    var entry = { synced: false, lines: [], plain: "", error: "", source: "LRCLIB" }
    if (candidate.syncedLyrics) {
      entry.lines = parseLrc(candidate.syncedLyrics)
      entry.synced = entry.lines.length > 0
    }
    if (!entry.synced && candidate.plainLyrics) entry.plain = String(candidate.plainLyrics).trim()

    if (!entry.synced && entry.plain === "") {
      entry.error = "No lyrics found"
    }

    lyricsCache[pendingLyricsKey] = entry
    if (pendingLyricsKey === trackKey()) applyCache(entry)
  }

  // Genius has no public lyrics API, so fetch the song page and pull the
  // lyrics out of its data-lyrics-container blocks. Results are plain text,
  // never synced.
  function requestGeniusLyrics() {
    if (!lyricsLoading || title === "") return

    // One lookup at a time. If a Genius fetch is still finishing for the
    // previous track, don't feed its result to this one.
    if (geniusSearchProc.running || geniusPageProc.running) {
      lyricsLoading = false
      if (pendingLyricsKey === trackKey()) lyricsError = "No lyrics found"
      return
    }

    geniusKey = pendingLyricsKey
    lyricsSource = ""

    geniusSearchProc.command = ["curl", "-fsS", "--max-time", "8", "-H",
      "User-Agent: OmarchyMediaWidget/1.0", "-H", "Accept: application/json",
      "https://genius.com/api/search/song?q=" + encodeURIComponent(title + " " + artist)]
    geniusSearchProc.running = true
  }

  function geniusTokens(value) {
    return String(value || "").toLowerCase()
      .split(/[\s\-_,.;:!?()[\]{}"'\/&+]+/)
      .filter(function(token) { return token.length > 0 })
  }

  function geniusArtistMatches(name) {
    var wanted = geniusTokens(artist)
    var found = geniusTokens(name)
    if (wanted.length === 0 || found.length === 0) return false

    var hits = 0
    for (var i = 0; i < wanted.length; i++) {
      if (found.indexOf(wanted[i]) >= 0) hits++
    }
    return hits / Math.min(wanted.length, found.length) >= 0.5
  }

  function pickGeniusHit(data) {
    var sections = data && data.response ? data.response.sections : null
    if (!sections) return null

    var best = null
    var bestScore = -1
    for (var s = 0; s < sections.length; s++) {
      var hits = sections[s] ? sections[s].hits : null
      if (!hits) continue

      for (var i = 0; i < hits.length; i++) {
        var hit = hits[i] ? hits[i].result : null
        if (!hit || !hit.url) continue
        if (!geniusArtistMatches(hit.artist_names || (hit.primary_artist ? hit.primary_artist.name : "")))
          continue

        var score = 0
        if (String(hit.full_title || "").toLowerCase().indexOf(title.toLowerCase()) >= 0) score += 2
        if (hit.lyrics_state === "complete") score += 1

        if (score > bestScore) {
          best = hit
          bestScore = score
        }
      }
    }

    return best
  }

  function handleGeniusSearch(raw) {
    if (!lyricsLoading || geniusKey !== pendingLyricsKey) return

    var data = null
    if (String(raw || "").trim() !== "") {
      try { data = JSON.parse(String(raw).trim()) } catch (e) { data = null }
    }

    var hit = pickGeniusHit(data)
    if (!hit) {
      geniusNoLyrics()
      return
    }

    geniusPageProc.command = ["curl", "-fLsS", "--max-time", "12", "-H",
      "User-Agent: OmarchyMediaWidget/1.0", String(hit.url)]
    geniusPageProc.running = true
  }

  function matchingDivEnd(html, start) {
    var tags = /<div\b|<\/div>/gi
    tags.lastIndex = start
    var depth = 0
    var match
    while ((match = tags.exec(html)) !== null) {
      if (match[0].charAt(1) === "/") {
        depth -= 1
        if (depth <= 0) return tags.lastIndex
      } else {
        depth += 1
      }
    }
    return -1
  }

  function stripExcludedDivs(chunk) {
    var marker = 'data-exclude-from-selection="true"'
    var at
    while ((at = chunk.indexOf(marker)) >= 0) {
      var start = chunk.lastIndexOf("<div", at)
      if (start < 0) break
      var end = matchingDivEnd(chunk, start)
      if (end < 0) break
      chunk = chunk.slice(0, start) + chunk.slice(end)
    }
    return chunk
  }

  function decodeEntities(value) {
    return String(value)
      .replace(/&#x([0-9a-f]+);/gi, function(_, hex) { return String.fromCharCode(parseInt(hex, 16)) })
      .replace(/&#([0-9]+);/g, function(_, dec) { return String.fromCharCode(parseInt(dec, 10)) })
      .replace(/&nbsp;/g, " ")
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&amp;/g, "&")
  }

  function parseGeniusLyrics(page) {
    if (!page) return ""

    var marker = 'data-lyrics-container="true"'
    var chunks = []
    var index = 0
    while (true) {
      var at = page.indexOf(marker, index)
      if (at < 0) break
      var start = page.lastIndexOf("<div", at)
      if (start < 0) break
      var end = matchingDivEnd(page, start)
      if (end < 0) break
      chunks.push(page.slice(start, end))
      index = end
    }

    var lines = []
    for (var i = 0; i < chunks.length; i++) {
      var chunk = stripExcludedDivs(chunks[i])
      chunk = chunk.replace(/<br\s*\/?>/gi, "\n")
      chunk = chunk.replace(/<[^>]*>/g, "")
      chunk = decodeEntities(chunk)

      var rows = chunk.split("\n")
      for (var j = 0; j < rows.length; j++) {
        var line = rows[j].replace(/[ \t]+/g, " ").trim()
        if (line === "You might also like") continue
        if (line === "" && (lines.length === 0 || lines[lines.length - 1] === "")) continue
        lines.push(line)
      }
    }

    while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
    return lines.join("\n")
  }

  function handleGeniusPage(raw) {
    if (!lyricsLoading || geniusKey !== pendingLyricsKey) return

    var plain = parseGeniusLyrics(String(raw || ""))
    if (plain === "") {
      geniusNoLyrics()
      return
    }

    var entry = { synced: false, lines: [], plain: plain, error: "", source: "Genius" }
    lyricsLoading = false
    lyricsCache[geniusKey] = entry
    if (geniusKey === trackKey()) applyCache(entry)
  }

  function geniusNoLyrics() {
    if (!lyricsLoading || geniusKey !== pendingLyricsKey) return
    lyricsLoading = false

    // Remember the miss for this track so reopening the popup does not hit
    // LRCLIB/Genius again until the track changes.
    var entry = { synced: false, lines: [], plain: "", error: "No lyrics found", source: "", instrumental: false }
    if (geniusKey !== "") lyricsCache[geniusKey] = entry
    if (geniusKey === trackKey()) applyCache(entry)
  }

  function refreshLyricIndex() {
    if (!lyricsSynced || lyricsLines.length === 0) {
      currentLyricIndex = -1
      return
    }

    var position = root.trackPosition
    var index = -1
    for (var i = 0; i < lyricsLines.length; i++) {
      if (lyricsLines[i].t <= position + 0.05) index = i
      else break
    }

    if (index !== currentLyricIndex) {
      currentLyricIndex = index
      Qt.callLater(root.positionLyrics)
    }
  }

  function positionLyrics() {
    if (!popupOpen || !lyricsSynced || currentLyricIndex < 0) return
    if (lyricsFlick.dragging) return

    var item = lyricsRepeater.itemAt(currentLyricIndex)
    if (!item) return

    var target = item.y + item.height / 2 - lyricsFlick.height / 2
    var maxY = Math.max(0, lyricsFlick.contentHeight - lyricsFlick.height)
    target = Math.max(0, Math.min(target, maxY))

    // Jump straight to the current line when the panel opens or the track
    // changes; animate between lines afterwards.
    if (!lyricsScrolled) {
      lyricsScrollAnim.stop()
      lyricsFlick.contentY = target
      lyricsScrolled = true
      return
    }

    if (Math.abs(lyricsFlick.contentY - target) < 1) return
    lyricsScrollAnim.stop()
    lyricsScrollAnim.from = lyricsFlick.contentY
    lyricsScrollAnim.to = target
    lyricsScrollAnim.start()
  }

  function setVolume(value) {
    var next = Math.max(0, Math.min(1.5, Number(value) || 0))
    if (hasStreamVolume) playerStream.audio.volume = next
    else if (hasMprisVolume && activePlayer) activePlayer.volume = Math.min(1, next)
  }

  function toggleMute() {
    if (hasStreamVolume) {
      playerStream.audio.muted = !playerStream.audio.muted
    } else if (hasMprisVolume && activePlayer) {
      activePlayer.volume = activePlayer.volume > 0.001 ? 0 : 0.5
    }
  }

  onTitleChanged: scheduleLyricsRefresh()
  onArtistChanged: scheduleLyricsRefresh()
  onAlbumChanged: scheduleLyricsRefresh()
  onTrackPositionChanged: refreshLyricIndex()
  onPopupOpenChanged: {
    if (popupOpen) {
      lyricsScrolled = false
      resyncPosition()
      requestLyrics()
      Qt.callLater(root.refreshLyricIndex)
    }
  }

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== ""

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width

        NumberAnimation on x {
          id: scrollAnim
          running: labelText.needsScroll && !root.popupOpen && !root.bar.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          // Start visible instead of off the right edge, so the song name is
          // readable the moment the popup closes (or the track changes).
          from: 0
          to: scrollClip.width - labelText.implicitWidth
          easing.type: Easing.Linear

          // When scrolling stops (popup opens, or the title gets short enough
          // to fit), snap back to the start instead of staying mid-scroll.
          onRunningChanged: if (!running) labelText.x = 0
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else {
        // Left and right both open the expanded player. Play/pause lives in
        // the popup controls now.
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Timer {
    id: lyricsDebounce
    interval: 500
    onTriggered: root.requestLyrics()
  }

  Timer {
    id: lyricsStart
    interval: 10
    onTriggered: if (root.lyricsLoading && !lyricsProc.running) lyricsProc.running = true
  }

  Timer {
    id: positionClock
    interval: 500
    repeat: true
    running: root.popupOpen && root.activePlayer !== null && root.activePlayer.isPlaying
    onTriggered: root.updatePosition()
  }

  Timer {
    id: positionResync
    interval: 5000
    repeat: true
    running: root.popupOpen && root.activePlayer !== null && root.activePlayer.isPlaying
    onTriggered: root.pollPosition()
  }

  Connections {
    target: root.activePlayer

    function onPositionChanged() {
      if (root.activePlayer) root.anchorPositionNow(root.activePlayer.position)
    }
    function onIsPlayingChanged() {
      root.resyncPosition()
    }
    function onTrackTitleChanged() {
      root.resyncPosition()
    }
    function onLengthChanged() {
      root.resyncPosition()
    }
  }

  Process {
    id: positionProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fields = String(text).trim().split(/\s+/)
        var micros = parseFloat(fields[fields.length - 1])
        if (isFinite(micros) && micros >= 0) root.anchorPositionNow(micros / 1000000)
      }
    }
  }

  Process {
    id: lyricsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.lyricsLoading) return
        var raw = String(text || "").trim()
        var data = null
        if (raw !== "") {
          try { data = JSON.parse(raw) } catch (e) { data = null }
        }
        root.applyLyrics(data)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.lyricsLoading) {
        if (root.pendingLyricsKey === root.trackKey()) root.applyLyrics(null)
        else root.lyricsLoading = false
      }
      if (root.queuedLyricsKey !== "") {
        root.queuedLyricsKey = ""
        Qt.callLater(root.requestLyrics)
      }
    }
  }

  Process {
    id: geniusSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleGeniusSearch(String(text || ""))
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.geniusNoLyrics()
    }
  }

  Process {
    id: geniusPageProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleGeniusPage(String(text || ""))
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.geniusNoLyrics()
    }
  }

  MediaPopup {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    artUrl: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(wideRoot.implicitHeight, Style.space(520))

    Column {
      id: wideRoot
      width: parent.width
      height: implicitHeight
      spacing: Style.space(8)

      Row {
        id: mainRow
        width: parent.width
        height: mainRow.wideTopHeight + Style.space(8) + mainRow.wideBottomHeight

        readonly property real wideTopHeight: Style.space(140)
        readonly property real wideBottomHeight: Style.space(34)

        Column {
          id: leftStack
          width: parent.width - volumeColumn.width - Style.space(10)
          spacing: Style.space(8)

          Row {
            id: wideTopRow
            width: parent.width
            height: mainRow.wideTopHeight
            spacing: Style.space(12)

            BorderSurface {
              id: wideArt
              width: parent.height
              height: parent.height
              radius: Style.spacing.labelGap
              color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)

              Image {
                anchors.fill: parent
                anchors.margins: Style.space(2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
                visible: source !== ""
              }

              Text {
                anchors.centerIn: parent
                visible: !root.activePlayer || !root.activePlayer.trackArtUrl
                text: "󰝚"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              id: lyricColumn
              width: parent.width - wideArt.width - parent.spacing
              height: parent.height
              spacing: Style.space(4)

              Column {
                id: wideSongInfo
                width: parent.width
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: root.title || "Nothing playing"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }

                Row {
                  id: wideMetaRow
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    width: Math.max(0, parent.width - wideLyricsStatus.width - parent.spacing)
                    textFormat: Text.PlainText
                    text: {
                      if (root.artist === "") return root.album
                      if (root.album === "") return root.artist
                      return root.artist + "  ·  " + root.album
                    }
                    color: Qt.darker(root.bar.foreground, 1.35)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    id: wideLyricsStatus
                    textFormat: Text.PlainText
                    text: {
                      if (root.lyricsLoading) return "searching…"
                      if (root.lyricsInstrumental) return "instrumental"
                      if (root.lyricsError !== "") return "not found"
                      if (root.lyricsSynced) return "synced"
                      if (root.lyricsPlain !== "") return root.lyricsSource === "Genius" ? "Genius" : "plain"
                      return ""
                    }
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }

              Item {
                id: wideLyricsArea
                width: parent.width
                height: Math.max(0, lyricColumn.height - wideSongInfo.height - lyricColumn.spacing)

                Item {
                  id: wideLyricsBox
                  width: parent.width
                  height: parent.height
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: root.lyricsLoading || root.lyricsInstrumental || (root.lyricsError !== "")
                      || (!root.lyricsSynced && root.lyricsPlain === "" && !root.lyricsLoading)
                    text: {
                      if (root.lyricsLoading) return "Searching lyrics…"
                      if (root.lyricsInstrumental) return "♪  Instrumental  ♪"
                      if (root.lyricsError !== "") return root.lyricsError
                      if (root.title === "") return "Nothing playing"
                      return "No lyrics found"
                    }
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Flickable {
                    id: lyricsFlick
                    width: parent.width
                    height: parent.height
                    visible: root.lyricsSynced && root.lyricsLines.length > 0
                    clip: true
                    contentWidth: width
                    contentHeight: lyricsColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    onDraggingChanged: if (dragging) lyricsScrollAnim.stop()

                    Column {
                      id: lyricsColumn
                      width: lyricsFlick.width
                      spacing: Style.space(3)

                      Repeater {
                        id: lyricsRepeater
                        model: root.lyricsLines

                        delegate: Text {
                          required property var modelData
                          required property int index

                          width: lyricsColumn.width
                          textFormat: Text.PlainText
                          text: modelData.text !== "" ? modelData.text : "♪"
                          wrapMode: Text.Wrap
                          horizontalAlignment: Text.AlignHCenter

                          readonly property int distance: root.currentLyricIndex < 0
                            ? 99 : Math.abs(index - root.currentLyricIndex)

                          color: "#ffffff"
                          opacity: root.currentLyricIndex < 0
                            ? 0.8
                            : (distance === 0 ? 1.0 : (distance === 1 ? 0.72 : (distance === 2 ? 0.5 : 0.34)))
                          scale: index === root.currentLyricIndex ? 1.06 : 1.0

                          font.family: root.bar.fontFamily
                          font.pixelSize: index === root.currentLyricIndex ? Style.font.body : Style.font.bodySmall
                          font.bold: index === root.currentLyricIndex

                          Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                          Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                        }
                      }
                    }
                  }

                  NumberAnimation {
                    id: lyricsScrollAnim
                    target: lyricsFlick
                    property: "contentY"
                    duration: 520
                    easing.type: Easing.InOutCubic
                  }

                  Flickable {
                    width: parent.width
                    height: parent.height
                    visible: !root.lyricsSynced && root.lyricsPlain !== ""
                    clip: true
                    contentWidth: width
                    contentHeight: plainLyrics.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Text {
                      id: plainLyrics
                      width: parent.width
                      textFormat: Text.PlainText
                      text: root.lyricsPlain
                      wrapMode: Text.Wrap
                      color: "#ffffff"
                      opacity: 0.95
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      lineHeight: 1.25
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }
                }
              }
            }
          }

          Item {
            id: wideBottom
            width: parent.width
            height: mainRow.wideBottomHeight

            // Transport sits centered under the album art.
            Item {
              id: wideTransportSlot
              width: wideArt.width
              height: parent.height
              anchors.left: parent.left

              Row {
                id: wideTransport
                anchors.centerIn: parent
                spacing: Style.space(4)

                readonly property real controlSize: Style.space(30)
                readonly property real controlIconSize: Style.font.iconLarge

                Button {
                  iconText: ""
                  width: wideTransport.controlSize
                  height: wideTransport.controlSize
                  radius: width / 2
                  horizontalPadding: 0
                  verticalPadding: 0
                  foreground: root.bar.foreground
                  enabled: root.activePlayer && root.activePlayer.canGoPrevious
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))

                  Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: Style.space(0.75)
                    anchors.verticalCenterOffset: Style.space(0.75)
                    text: "󰙤" // skip-previous-circle-outline
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: wideTransport.controlIconSize
                  }
                }

                Button {
                  iconText: ""
                  width: wideTransport.controlSize
                  height: wideTransport.controlSize
                  radius: width / 2
                  horizontalPadding: 0
                  verticalPadding: 0
                  foreground: root.bar.foreground
                  enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))

                  Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: Style.space(0.75)
                    anchors.verticalCenterOffset: Style.space(0.75)
                    text: root.activePlayer && root.activePlayer.isPlaying ? "󰏦" : "󰐍"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: wideTransport.controlIconSize
                  }
                }

                Button {
                  iconText: ""
                  width: wideTransport.controlSize
                  height: wideTransport.controlSize
                  radius: width / 2
                  horizontalPadding: 0
                  verticalPadding: 0
                  foreground: root.bar.foreground
                  enabled: root.activePlayer && root.activePlayer.canGoNext
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))

                  Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: Style.space(0.75)
                    anchors.verticalCenterOffset: Style.space(0.75)
                    text: "󰙢" // skip-next-circle-outline
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: wideTransport.controlIconSize
                  }
                }
              }
            }

            // Song progress sits centered under the lyrics column.
            Item {
              id: wideSeekSlot
              anchors.left: wideTransportSlot.right
              anchors.leftMargin: wideTopRow.spacing
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom

              Text {
                id: wideElapsed
                textFormat: Text.PlainText
                text: root.formatTime(root.seeking ? root.seekValue : root.trackPosition)
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: wideTotal
                textFormat: Text.PlainText
                text: root.formatTime(root.trackLength)
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }

              PanelSlider {
                anchors.left: wideElapsed.right
                anchors.leftMargin: Style.space(8)
                anchors.right: wideTotal.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter

                minimum: 0
                maximum: Math.max(1, root.trackLength)
                step: 1
                value: root.seeking ? root.seekValue : root.trackPosition
                enabled: root.activePlayer && root.activePlayer.canSeek && root.trackLength > 0
                opacity: enabled ? 1.0 : 0.45

                onMoved: function(v) {
                  root.seeking = true
                  root.seekValue = v
                }
                onReleased: function(v) {
                  if (root.activePlayer && root.activePlayer.canSeek) root.activePlayer.position = v
                  root.anchorPositionNow(v)
                  root.seeking = false
                }
              }
            }
          }
        }

        Column {
          id: volumeColumn
          width: Style.space(34)
          height: parent.height
          spacing: Style.space(4)

          Button {
            id: wideMute
            width: parent.width
            iconText: root.volumeMuted ? "󰝟" : "󰕾"
            foreground: root.bar.foreground
            horizontalPadding: 0
            verticalPadding: Style.space(2)
            iconSize: Style.font.iconSmall
            enabled: root.canControlVolume
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.toggleMute()
          }

          Item {
            id: wideVolumeSlider
            width: parent.width
            height: parent.height - wideMute.height - wideVolumePct.height - parent.spacing * 2

            readonly property real range: root.hasStreamVolume ? 1.5 : 1
            readonly property real progress: Math.max(0, Math.min(1, root.volumeValue / range))
            readonly property real knobSize: Style.space(12)
            readonly property real travel: Math.max(1, height - knobSize)

            Rectangle {
              id: wideVolumeTrack
              anchors.horizontalCenter: parent.horizontalCenter
              y: wideVolumeSlider.knobSize / 2
              width: Math.max(3, Style.space(4))
              height: wideVolumeSlider.travel
              radius: width / 2
              color: Style.selectedFillFor(root.bar.foreground, Commons.Color.accent)
            }

            Rectangle {
              anchors.horizontalCenter: wideVolumeTrack.horizontalCenter
              width: wideVolumeTrack.width
              height: wideVolumeTrack.height * wideVolumeSlider.progress
              y: wideVolumeTrack.y + wideVolumeTrack.height - height
              radius: width / 2
              color: root.bar.foreground
              opacity: root.canControlVolume ? 1.0 : 0.4
            }

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: wideVolumeSlider.knobSize
              height: width
              radius: width / 2
              color: root.bar.foreground
              y: Math.max(0, Math.min(wideVolumeSlider.height - height,
                    wideVolumeTrack.y + wideVolumeTrack.height * (1 - wideVolumeSlider.progress) - height / 2))
              opacity: root.canControlVolume ? 1.0 : 0.4

              Behavior on y {
                enabled: !wideVolumeMouse.dragging
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
              }
            }

            MouseArea {
              id: wideVolumeMouse
              anchors.fill: parent
              property bool dragging: false
              hoverEnabled: true
              enabled: root.canControlVolume
              cursorShape: Qt.PointingHandCursor

              function valueAt(py) {
                var t = 1 - Math.max(0, Math.min(1, (py - wideVolumeTrack.y) / wideVolumeTrack.height))
                return t * wideVolumeSlider.range
              }

              onPressed: function(mouse) {
                dragging = true
                root.setVolume(valueAt(mouse.y))
              }
              onPositionChanged: function(mouse) {
                if (dragging) root.setVolume(valueAt(mouse.y))
              }
              onReleased: dragging = false
              onWheel: function(wheel) {
                root.setVolume(root.volumeValue + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
              }
            }
          }

          Text {
            id: wideVolumePct
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.canControlVolume ? Math.round(root.volumeValue * 100) + "%" : "—"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            opacity: root.canControlVolume ? 1.0 : 0.5
          }
        }
      }

      PanelSeparator {
        width: parent.width
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: wideSourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: wideSourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: wideSourceList.width
            height: wideSourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Commons.Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent) : Border.none()

            Row {
              id: wideSourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: wideSourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: wideSourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: wideSourceRow.player && wideSourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: wideSourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: wideSourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: wideSourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(wideSourceRow.player))
            }
          }
        }
      }
    }
  }
}
