import AppKit

/// Icon app: squircle xanh + đồ thị đường có vùng tô, chấm cam ở đỉnh.
/// Vẽ vector riêng cho từng cỡ; cỡ nhỏ dùng ít điểm hơn để đường không bị nát.
func render(_ s: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setAllowsAntialiasing(true)

    let inset = s * 100.0 / 1024.0
    let side  = s * 824.0 / 1024.0
    let radius = s * 185.0 / 1024.0
    let box = CGRect(x: inset, y: inset, width: side, height: side)

    cg.saveGState()
    cg.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.clip()

    let bg = [NSColor(srgbRed: 0.353, green: 0.686, blue: 0.965, alpha: 1).cgColor,
              NSColor(srgbRed: 0.043, green: 0.361, blue: 0.722, alpha: 1).cgColor] as CFArray
    cg.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bg, locations: [0, 1])!,
                          start: CGPoint(x: box.minX, y: box.maxY),
                          end: CGPoint(x: box.minX, y: box.minY), options: [])

    // Lưới mờ như nền đồ thị của app; cỡ nhỏ bỏ lưới cho sạch.
    if s >= 64 {
        cg.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
        cg.setLineWidth(max(s * 0.006, 0.5))
        for i in 1..<4 {
            let y = box.minY + side * CGFloat(i) / 4
            cg.move(to: CGPoint(x: box.minX, y: y)); cg.addLine(to: CGPoint(x: box.maxX, y: y))
            let x = box.minX + side * CGFloat(i) / 4
            cg.move(to: CGPoint(x: x, y: box.minY)); cg.addLine(to: CGPoint(x: x, y: box.maxY))
        }
        cg.strokePath()
    }

    let values: [CGFloat] = s >= 64
        ? [0.20, 0.28, 0.22, 0.46, 0.36, 0.62, 0.52, 0.88, 0.60, 0.72]
        : [0.22, 0.42, 0.30, 0.88, 0.66]
    let peakIndex = values.firstIndex(of: 0.88) ?? 0

    let left = box.minX + side * 0.08
    let width = side * 0.84
    let base = box.minY + side * 0.16
    let height = side * 0.62
    let points = values.enumerated().map { index, value in
        CGPoint(x: left + width * CGFloat(index) / CGFloat(values.count - 1),
                y: base + height * value)
    }

    let area = CGMutablePath()
    area.move(to: CGPoint(x: points[0].x, y: base))
    points.forEach { area.addLine(to: $0) }
    area.addLine(to: CGPoint(x: points[points.count - 1].x, y: base))
    area.closeSubpath()
    cg.addPath(area)
    cg.setFillColor(NSColor(white: 1, alpha: 0.42).cgColor)
    cg.fillPath()

    let line = CGMutablePath()
    line.move(to: points[0])
    points.dropFirst().forEach { line.addLine(to: $0) }
    cg.addPath(line)
    cg.setStrokeColor(NSColor.white.cgColor)
    cg.setLineWidth(max(s * 0.05, 1.4))
    cg.setLineJoin(.round)
    cg.setLineCap(.round)
    cg.strokePath()

    let peak = points[peakIndex]
    let r = max(s * 0.06, 1.6)
    cg.setFillColor(NSColor(srgbRed: 0.965, green: 0.478, blue: 0.180, alpha: 1).cgColor)
    cg.fillEllipse(in: CGRect(x: peak.x - r, y: peak.y - r, width: r * 2, height: r * 2))

    cg.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let files: [(String, CGFloat)] = [
    ("icon_16.png", 16), ("icon_16@2x.png", 32),
    ("icon_32.png", 32), ("icon_32@2x.png", 64),
    ("icon_128.png", 128), ("icon_128@2x.png", 256),
    ("icon_256.png", 256), ("icon_256@2x.png", 512),
    ("icon_512.png", 512), ("icon_512@2x.png", 1024)
]
for (name, size) in files { render(size, to: dir.appendingPathComponent(name)) }
print("ok")
