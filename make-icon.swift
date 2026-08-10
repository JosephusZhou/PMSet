import AppKit

let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190).fill()

var drawn = false
if let base = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 620, weight: .medium)
    let tint = NSImage.SymbolConfiguration(paletteColors: [
        NSColor(calibratedRed: 0.96, green: 0.96, blue: 1.0, alpha: 1)
    ])
    if let icon = base.withSymbolConfiguration(config)?.withSymbolConfiguration(tint) {
        let target = NSRect(x: (size - 620) / 2, y: (size - 620) / 2, width: 620, height: 620)
        icon.draw(in: target)
        drawn = true
    }
}

if !drawn {
    let font = NSFont.systemFont(ofSize: 600, weight: .bold)
    let attr: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let str = NSAttributedString(string: "P", attributes: attr)
    let strSize = str.size()
    str.draw(at: NSPoint(x: (size - strSize.width) / 2, y: (size - strSize.height) / 2))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: "icon-1024.png"))
