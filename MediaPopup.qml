import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

// A "liquid glass" media popup drawn as an overlay layer surface. Unlike an
// xdg-popup (PopupWindow), it does not grab focus and does not dismiss when you
// click another window: it stays pinned above normal windows until the media
// widget toggles it closed.
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property color borderColor: Commons.Color.popups.border
  property bool open: false
  property bool centerOnBar: false
  // Retained for API compatibility with the old PopupWindow implementation.
  property string triggerMode: "click"

  // Glass surface tuning.
  property url artUrl: ""
  property real glassOpacity: 0.58
  property real artOpacity: 0.55

  // Open/close animation tuning. The window stays put; the card itself springs
  // out of the bar widget and fades so the transition feels anchored.
  property int openAnimationDuration: 320
  property int closeAnimationDuration: 160
  readonly property int animationOrigin: {
    if (!bar) return Item.Center
    if (bar.position === "bottom") return Item.Bottom
    if (bar.position === "left") return Item.TopLeft
    if (bar.position === "right") return Item.TopRight
    return Item.Top
  }

  readonly property int borderWidth: Math.max(1, Math.round(Style.space(1)))
  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: cardHover.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  // The bar window can expand to host menus or panels. Use the configured bar
  // thickness instead, otherwise the popup's available height collapses to its
  // minimum while the bar window is full-screen.
  readonly property real barThickness: bar && bar.barSize > 0 ? bar.barSize
    : (anchorWindow ? (bar && bar.vertical ? anchorWindow.width : anchorWindow.height) : 0)
  readonly property real barW: bar && bar.vertical ? barThickness
    : (anchorWindow ? anchorWindow.width : 0)
  readonly property real barH: bar && bar.vertical
    ? (anchorWindow ? anchorWindow.height : 0) : barThickness

  // Position of the owning widget inside the bar window. The layer surface is
  // re-anchored when the popup opens and whenever the widget resizes, since
  // itemPosition() is not reactive on its own.
  property point anchorPoint: Qt.point(0, 0)

  function refreshAnchor() {
    if (!anchorWindow || !anchorItem) return
    var p = anchorWindow.itemPosition(anchorItem)
    anchorPoint = Qt.point(p.x, p.y)
  }

  Component.onCompleted: refreshAnchor()

  Connections {
    target: anchorItem

    function onWidthChanged() { root.refreshAnchor() }
    function onHeightChanged() { root.refreshAnchor() }
  }

  // Layer surfaces are positioned relative to their output, so translate the
  // bar window's local coordinates into screen-relative ones.
  readonly property real barOffsetX: {
    if (!bar || !anchorWindow) return 0
    return bar.position === "right" ? Math.max(0, screenW - barW) : 0
  }
  readonly property real barOffsetY: {
    if (!bar || !anchorWindow) return 0
    return bar.position === "bottom" ? Math.max(0, screenH - barH) : 0
  }
  readonly property real anchorScreenX: anchorPoint.x + barOffsetX
  readonly property real anchorScreenY: anchorPoint.y + barOffsetY

  // The bar reserves a layer-shell exclusive zone. Other layer surfaces
  // anchored to the same edge are placed after that zone, so subtract it from
  // our margins to avoid counting the bar thickness twice.
  readonly property real reservedTop: bar && bar.position === "top" ? barH : 0
  readonly property real reservedLeft: bar && bar.position === "left" ? barW : 0

  readonly property real popupX: {
    if (screenW <= 0) return margin
    var x
    if (bar && bar.position === "left") x = anchorScreenX + anchorItem.width + margin
    else if (bar && bar.position === "right") x = anchorScreenX - width - margin
    else x = anchorScreenX + anchorItem.width / 2 - width / 2
    return Math.round(Math.max(margin, Math.min(x, screenW - width - margin)))
  }

  readonly property real popupY: {
    if (screenH <= 0) return margin
    var y
    if (bar && bar.position === "bottom") y = anchorScreenY - height - margin
    else if (bar && (bar.position === "left" || bar.position === "right"))
      y = anchorScreenY + anchorItem.height / 2 - height / 2
    else y = anchorScreenY + anchorItem.height + margin
    return Math.round(Math.max(margin, Math.min(y, screenH - height - margin)))
  }

  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding * 2 + borderWidth * 2

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight
  screen: popupScreen

  // A small overlay surface: no reserved space, no keyboard focus, sits above
  // regular windows. Pointer input still reaches the card's own controls, but
  // clicks elsewhere go to whatever is underneath.
  anchors {
    top: true
    left: true
  }
  margins {
    top: Math.max(0, Math.round(root.popupY - root.reservedTop))
    left: Math.max(0, Math.round(root.popupX - root.reservedLeft))
  }
  exclusiveZone: 0
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "liquid-media"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  onOpenChanged: {
    refreshAnchor()
    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  Rectangle {
    id: card
    anchors.fill: parent
    radius: Style.cornerRadius
    color: "transparent"
    border.width: root.borderWidth
    border.color: Qt.rgba(root.borderColor.r, root.borderColor.g, root.borderColor.b, 0.45)
    opacity: root.open ? 1.0 : 0
    scale: root.open ? 1.0 : 0.9
    transformOrigin: root.animationOrigin

    Behavior on opacity {
      NumberAnimation {
        duration: root.open ? 180 : root.closeAnimationDuration
        easing.type: Easing.OutCubic
      }
    }

    Behavior on scale {
      NumberAnimation {
        duration: root.open ? root.openAnimationDuration : root.closeAnimationDuration
        easing.type: root.open ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: 1.25
      }
    }

    // ---- glass surface ---------------------------------------------------
    Item {
      id: glass
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.margins: root.borderWidth

      readonly property real innerRadius: Math.max(0, card.radius - root.borderWidth)

      // Tinted translucent base so text stays readable over any wallpaper.
      Rectangle {
        anchors.fill: parent
        radius: glass.innerRadius
        color: Qt.rgba(Commons.Color.popups.background.r,
                       Commons.Color.popups.background.g,
                       Commons.Color.popups.background.b,
                       root.glassOpacity)
      }

      // Blurred album art gives the glass its colour and light.
      Item {
        id: artLayer
        anchors.fill: parent
        visible: root.artUrl !== ""
        layer.enabled: visible
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: artMask
          blurEnabled: true
          blur: 0.85
          saturation: 0.35
          brightness: -0.08
        }

        Image {
          anchors.fill: parent
          source: root.artUrl
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          opacity: root.artOpacity
        }
      }

      // Rounded mask for the art layer.
      Item {
        id: artMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
          anchors.fill: parent
          radius: glass.innerRadius
          color: "white"
          antialiasing: true
        }
      }

      // Glass sheen: light from the top, shadow towards the bottom.
      Rectangle {
        anchors.fill: parent
        radius: glass.innerRadius
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.13) }
          GradientStop { position: 0.28; color: Qt.rgba(1, 1, 1, 0.03) }
          GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.0) }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
        }
      }
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: root.borderWidth + root.padding
      anchors.rightMargin: root.borderWidth + root.padding
      anchors.bottomMargin: root.borderWidth + root.padding
      anchors.leftMargin: root.borderWidth + root.padding
    }

    HoverHandler {
      id: cardHover
    }
  }
}
