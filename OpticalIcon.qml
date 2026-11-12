import QtQuick

// A single glyph centered by its painted ink rather than the font's line box.
// Nerd Font icons carry uneven bearings, so centering the layout rectangle
// leaves them visibly off-center inside round hover targets.
Text {
  id: root

  // Measuring at 100x keeps TextMetrics' whole-pixel tight bounds from adding
  // rounding error at bar and popup sizes.
  readonly property int metricsScale: 100
  readonly property rect ink: Qt.rect(
    metrics.tightBoundingRect.x / metricsScale,
    metrics.tightBoundingRect.y / metricsScale,
    metrics.tightBoundingRect.width / metricsScale,
    metrics.tightBoundingRect.height / metricsScale)
  readonly property real inkWidth: Math.max(0, ink.width)
  readonly property real inkHeight: Math.max(0, ink.height)

  textFormat: Text.PlainText
  renderType: Text.NativeRendering

  x: parent ? (parent.width - inkWidth) / 2 - ink.x : 0
  y: parent ? (parent.height - inkHeight) / 2 - baselineOffset - ink.y : 0

  TextMetrics {
    id: metrics
    font.family: root.font.family
    font.weight: root.font.weight
    font.pixelSize: Math.max(1, root.font.pixelSize) * root.metricsScale
    text: root.text
  }
}
