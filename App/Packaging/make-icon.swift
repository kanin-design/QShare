import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Apple icon grid: body ~824 centered in 1024 (transparent margin for shadow).
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)

// Continuous-corner "squircle" via superellipse.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let cx = r.midX, cy = r.midY, a = r.width/2, b = r.height/2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i)/CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(Double(ct)), 2.0/Double(n)), Double(ct)))
        let y = cy + b * CGFloat(copysign(pow(abs(Double(st)), 2.0/Double(n)), Double(st)))
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

let path = squircle(rect)
ctx.saveGState()
ctx.addPath(path); ctx.clip()
// Subtle vertical gradient blue (lighter top) for a little depth.
let cs = CGColorSpaceCreateDeviceRGB()
let top = CGColor(colorSpace: cs, components: [0.33, 0.60, 1.0, 1])!
let bot = CGColor(colorSpace: cs, components: [0.16, 0.45, 0.94, 1])!
let grad = CGGradient(colorsSpace: cs, colors: [top, bot] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
ctx.restoreGState()

// White two-way arrows glyph (SF Symbol), centered.
let glyphSize: CGFloat = 470
if let base = NSImage(systemSymbolName: "arrow.2.circlepath",
                      accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: glyphSize, weight: .semibold)) {
    // Tint template white.
    let tinted = NSImage(size: base.size)
    tinted.lockFocus()
    NSColor.white.set()
    let br = NSRect(origin: .zero, size: base.size)
    base.draw(in: br)
    br.fill(using: .sourceAtop)
    tinted.unlockFocus()
    let gx = rect.midX - base.size.width/2
    let gy = rect.midY - base.size.height/2
    tinted.draw(in: NSRect(x: gx, y: gy, width: base.size.width, height: base.size.height))
}

img.unlockFocus()

let out = "/private/tmp/claude-501/-Users-stian-dev-QuickShare2/a7a15797-9551-4899-9e0a-3264b0882fbf/scratchpad/icon-1024.png"
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
