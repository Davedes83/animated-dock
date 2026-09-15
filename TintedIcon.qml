import QtQuick
import QtQuick.Effects

// App-icon artwork, optionally colorized to a single ink colour.
//
// Tinting is what lets an arbitrary app icon sit next to the curated
// glyphs without breaking the theme: MultiEffect's colorization maps the
// icon's luminance onto the ink colour, so shape and shading survive but
// every hue becomes the theme's. The untinted path is the plain Image
// exactly as v1 drew it.
Item {
  id: art

  property alias source: img.source
  // Oversampling size for raster icons, so hover magnification stays crisp.
  property int sourceOversample: 96
  property bool tinted: false
  // The ink when tinted. Follows the glyph grammar: the dock passes its
  // glyph colour at rest and the accent under the pointer.
  property color ink: "white"

  Image {
    id: img
    anchors.fill: parent
    // Hidden while tinted — MultiEffect samples it as a texture either way.
    visible: !art.tinted
    sourceSize.width: art.sourceOversample
    sourceSize.height: art.sourceOversample
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    mipmap: true
  }

  MultiEffect {
    anchors.fill: parent
    visible: art.tinted
    source: img
    colorization: 1.0
    colorizationColor: art.ink
    Behavior on colorizationColor { ColorAnimation { duration: 120 } }
  }
}