// App Store tanıtıcı görsellerini üretir: ham simülatör ekran görüntüsü + başlık + marka zemini.
// Kullanım: swift compose.swift jobs.json
// Her iş: { "out", "width", "height", "layout", "shots": [ham görüntü yolları], "headline", "subhead", "icon" }
// layout: phone | tablet | mac | duoInner | duoOuter | header | search | universal | headerBrand
import AppKit

struct Job: Decodable {
    let out: String
    let width: CGFloat
    let height: CGFloat
    let layout: String
    let shots: [String]
    let headline: String?
    let subhead: String?
    let icon: String?
}

// Marka renkleri
let petrolTop = NSColor(srgbRed: 0x16/255, green: 0x72/255, blue: 0x69/255, alpha: 1)
let petrolBottom = NSColor(srgbRed: 0x09/255, green: 0x3D/255, blue: 0x39/255, alpha: 1)
let bezel = NSColor(srgbRed: 0x0E/255, green: 0x15/255, blue: 0x14/255, alpha: 1)
let amber = NSColor(srgbRed: 0xF2/255, green: 0xB0/255, blue: 0x4A/255, alpha: 1)

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawBackground(_ rect: NSRect) {
    NSGradient(starting: petrolTop, ending: petrolBottom)!.draw(in: rect, angle: -90)
    // Sol üstten yumuşak ışık
    let glow = NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])!
    glow.draw(fromCenter: NSPoint(x: rect.width * 0.2, y: rect.height * 0.95), radius: 0,
              toCenter: NSPoint(x: rect.width * 0.2, y: rect.height * 0.95), radius: max(rect.width, rect.height) * 0.7,
              options: [])
}

/// Metni verilen genişlikte, ortalı ya da sola dayalı çizer; kullandığı yüksekliği döndürür.
@discardableResult
func drawText(_ text: String, font: NSFont, color: NSColor, in box: NSRect, align: NSTextAlignment, lineSpacing: CGFloat = 0) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineSpacing = lineSpacing
    style.lineBreakMode = .byWordWrapping
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let bounds = attributed.boundingRect(with: NSSize(width: box.width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
    let height = ceil(bounds.height)
    attributed.draw(with: NSRect(x: box.minX, y: box.maxY - height, width: box.width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
    return height
}

/// Ekran görüntüsünü ince çerçeveli, yuvarlak köşeli ve gölgeli bir cihaz gibi çizer.
func drawDevice(_ image: NSImage, frame: NSRect, cornerRatio: CGFloat, bezelRatio: CGFloat, rotation: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    if rotation != 0 {
        let transform = NSAffineTransform()
        transform.translateX(by: frame.midX, yBy: frame.midY)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -frame.midX, yBy: -frame.midY)
        transform.concat()
    }
    let pad = frame.width * bezelRatio
    let outer = frame.insetBy(dx: -pad, dy: -pad)
    let radius = frame.width * cornerRatio
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.38)
    shadow.shadowBlurRadius = frame.width * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -frame.width * 0.02)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    bezel.setFill()
    NSBezierPath(roundedRect: outer, xRadius: radius + pad, yRadius: radius + pad).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
}

func aspectFit(_ size: NSSize, width: CGFloat) -> NSSize { NSSize(width: width, height: size.height * width / size.width) }

func render(_ job: Job) throws {
    let W = job.width, H = job.height
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let canvas = NSRect(x: 0, y: 0, width: W, height: H)
    drawBackground(canvas)
    let shots = job.shots.map { NSImage(contentsOfFile: $0)! }
    let white = NSColor.white, soft = NSColor(white: 1, alpha: 0.82)

    switch job.layout {
    case "phone", "duoOuter", "tablet", "duoInner", "mac":
        // Üstte başlık, altta cihaz (alttan taşabilir).
        let isTablet = job.layout == "tablet", isMac = job.layout == "mac", isWide = job.layout == "duoInner"
        let textWidth = W * (isMac || isWide ? 0.70 : 0.86)
        let headSize = (isMac || isWide) ? H * 0.062 : W * (isTablet ? 0.058 : 0.074)
        var y = H * (isMac || isWide ? 0.92 : 0.94)
        // Cihaz her görselde aynı yükseklikte başlar: iki satırlık başlık ve tek satırlık alt başlık için yer ayrılır.
        let deviceTop = y - (headSize * 1.22 * 2 + headSize * 0.30 + headSize * 0.52 * 1.25 + headSize * 0.9)
        let h1 = drawText(job.headline ?? "", font: roundedFont(headSize, .heavy), color: white,
                          in: NSRect(x: (W - textWidth) / 2, y: 0, width: textWidth, height: y), align: .center)
        y -= h1 + headSize * 0.30
        let h2 = drawText(job.subhead ?? "", font: roundedFont(headSize * 0.52, .medium), color: soft,
                          in: NSRect(x: (W - textWidth) / 2, y: 0, width: textWidth, height: y), align: .center)
        y -= h2 + headSize * 0.9
        y = min(y, deviceTop)
        let deviceWidth = W * (isTablet ? 0.84 : (isMac ? 0.82 : (isWide ? 0.78 : 0.80)))
        let size = aspectFit(shots[0].size, width: deviceWidth)
        let frame = NSRect(x: (W - size.width) / 2, y: y - size.height, width: size.width, height: size.height)
        if isMac {
            // Mac penceresi kendi gölgesiyle gelir; çerçeve çizmeden yerleştir.
            shots[0].draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            drawDevice(shots[0], frame: frame, cornerRatio: isTablet ? 0.035 : (isWide ? 0.045 : 0.115), bezelRatio: isTablet ? 0.012 : 0.022)
        }

    case "raw":
        // Saat görüntüleri olduğu gibi kullanılır (Apple Watch'ta başlık eklenmez).
        shots[0].draw(in: canvas, from: .zero, operation: .copy, fraction: 1)

    case "header", "universal":
        // Ortada üç telefon (yelpaze); evrensel görselde üstte kısa başlık.
        let isUniversal = job.layout == "universal"
        var top = H
        if isUniversal, let headline = job.headline {
            let size = H * 0.07
            let used = drawText(headline, font: roundedFont(size, .heavy), color: white,
                                in: NSRect(x: W * 0.15, y: 0, width: W * 0.70, height: H * 0.93), align: .center)
            top = H * 0.93 - used - size * 0.8
        }
        let phoneHeight = isUniversal ? top * 1.12 : H * 1.08
        let phoneSize = NSSize(width: phoneHeight * shots[0].size.width / shots[0].size.height, height: phoneHeight)
        // Evrensel görselde telefonların üstü başlığın altında kalır (yan telefonlar eğik olduğu için biraz pay bırakılır).
        let centerY = isUniversal ? top - phoneHeight * 0.04 - phoneHeight / 2 : H * 0.42
        let offsets: [(CGFloat, CGFloat, CGFloat)] = [(-0.62, -0.06, 8), (0.62, -0.06, -8), (0, 0, 0)] // x (telefon genişliği oranı), y, açı
        for (index, (dx, dy, angle)) in offsets.enumerated() {
            let shot = shots[[1, 2, 0][index] % shots.count]
            let frame = NSRect(x: W / 2 + dx * phoneSize.width * 1.15 - phoneSize.width / 2,
                               y: centerY + dy * phoneHeight - phoneHeight / 2,
                               width: phoneSize.width, height: phoneSize.height)
            drawDevice(shot, frame: frame, cornerRatio: 0.115, bezelRatio: 0.022, rotation: angle)
        }

    case "headerBrand":
        // Ortada ikon, ad ve tek cümle: marka odaklı başlık.
        let icon = NSImage(contentsOfFile: job.icon!)!
        let iconSize = H * 0.42
        let iconFrame = NSRect(x: (W - iconSize) / 2, y: H * 0.50, width: iconSize, height: iconSize)
        let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.35); shadow.shadowBlurRadius = iconSize * 0.08
        shadow.shadowOffset = NSSize(width: 0, height: -iconSize * 0.03)
        NSGraphicsContext.saveGraphicsState(); shadow.set(); icon.draw(in: iconFrame); NSGraphicsContext.restoreGraphicsState()
        let used = drawText(job.headline ?? "", font: roundedFont(H * 0.085, .heavy), color: white,
                            in: NSRect(x: W * 0.15, y: 0, width: W * 0.70, height: H * 0.46), align: .center)
        drawText(job.subhead ?? "", font: roundedFont(H * 0.042, .medium), color: soft,
                 in: NSRect(x: W * 0.2, y: 0, width: W * 0.60, height: H * 0.46 - used - H * 0.02), align: .center)

    case "search":
        // Solda başlık, sağda tek telefon (arama sonucu kartı).
        let textBox = NSRect(x: W * 0.07, y: 0, width: W * 0.46, height: H * 0.80)
        let used = drawText(job.headline ?? "", font: roundedFont(H * 0.085, .heavy), color: white, in: textBox, align: .left)
        drawText(job.subhead ?? "", font: roundedFont(H * 0.040, .medium), color: soft,
                 in: NSRect(x: textBox.minX, y: 0, width: textBox.width * 0.92, height: textBox.maxY - used - H * 0.03), align: .left)
        let bar = NSRect(x: textBox.minX, y: H * 0.20, width: H * 0.09, height: H * 0.012)
        amber.setFill(); NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
        let phoneHeight = H * 1.05
        let phoneSize = NSSize(width: phoneHeight * shots[0].size.width / shots[0].size.height, height: phoneHeight)
        drawDevice(shots[0], frame: NSRect(x: W * 0.74 - phoneSize.width / 2, y: H * 0.10 - phoneHeight * 0.18,
                                           width: phoneSize.width, height: phoneSize.height),
                   cornerRatio: 0.115, bezelRatio: 0.022, rotation: -4)
    default:
        throw NSError(domain: "compose", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bilinmeyen layout \(job.layout)"])
    }

    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: job.out)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // App Store alfa kanalı kabul etmez: zemin opak çizildi, JPEG'e alfasız yazılır.
    let opaque = NSBitmapImageRep(cgImage: rep.cgImage!.copy(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
    // Ürün sayfası başlığı ve evrensel görsel için Asset Library yalnızca PNG kabul ediyor.
    let data = url.pathExtension == "png"
        ? opaque.representation(using: .png, properties: [:])!
        : opaque.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    try data.write(to: url)
}

let jobs = try JSONDecoder().decode([Job].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
for job in jobs {
    try render(job)
    print("✓", job.out.split(separator: "/").suffix(3).joined(separator: "/"))
}
