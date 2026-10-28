// Dessine l'icône de l'application (1024 × 1024, PNG), sans aucune ressource externe.
// Usage : swift Scripts/make-icon.swift <fichier.png>
// Scripts/make-app.sh en tire les tailles du .icns avec sips et iconutil.
import AppKit

let size = 1024.0
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.png>\n".data(using: .utf8)!)
    exit(64)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255, alpha: alpha)
}

// Fond : carré arrondi de la grille macOS (824 px dans 1024), dégradé diagonal, ombre légère.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, 0.30)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(0x312E81).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x4338CA), ending: color(0x0F766E))!.draw(in: tilePath, angle: -45)

// Feuille blanche au coin replié.
let sheet = NSRect(x: 262, y: 200, width: 500, height: 624)
let fold = 110.0
let sheetPath = NSBezierPath()
sheetPath.move(to: NSPoint(x: sheet.minX, y: sheet.minY))
sheetPath.line(to: NSPoint(x: sheet.maxX, y: sheet.minY))
sheetPath.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
sheetPath.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
sheetPath.line(to: NSPoint(x: sheet.minX, y: sheet.maxY))
sheetPath.close()
NSGraphicsContext.saveGraphicsState()
let sheetShadow = NSShadow()
sheetShadow.shadowColor = color(0x000000, 0.25)
sheetShadow.shadowBlurRadius = 18
sheetShadow.shadowOffset = NSSize(width: 0, height: -8)
sheetShadow.set()
color(0xFFFFFF).setFill()
sheetPath.fill()
NSGraphicsContext.restoreGraphicsState()
let foldPath = NSBezierPath()
foldPath.move(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
foldPath.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY - fold))
foldPath.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
foldPath.close()
color(0xC7D2FE).setFill()
foldPath.fill()

// Petit diagramme : une table de faits en haut, deux dimensions en bas, reliées.
func table(_ rect: NSRect, header: NSColor) {
    let body = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    color(0xF1F5F9).setFill()
    body.fill()
    color(0xCBD5E1).setStroke()
    body.lineWidth = 4
    body.stroke()
    let headerRect = NSRect(x: rect.minX, y: rect.maxY - 46, width: rect.width, height: 46)
    let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: 18, yRadius: 18)
    headerPath.append(NSBezierPath(rect: NSRect(x: rect.minX, y: headerRect.minY, width: rect.width, height: 20)))
    header.setFill()
    headerPath.fill()
    color(0xCBD5E1).setFill()
    for i in 0..<2 {
        let y = headerRect.minY - 34 - Double(i) * 30
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 22, y: y, width: rect.width * (i == 0 ? 0.62 : 0.45), height: 12),
                     xRadius: 6, yRadius: 6).fill()
    }
}

let fact = NSRect(x: 382, y: 540, width: 260, height: 150)
let dimLeft = NSRect(x: 300, y: 270, width: 190, height: 140)
let dimRight = NSRect(x: 534, y: 270, width: 190, height: 140)
let link = NSBezierPath()
link.lineWidth = 12
link.lineCapStyle = .round
link.move(to: NSPoint(x: fact.midX - 50, y: fact.minY))
link.line(to: NSPoint(x: dimLeft.midX, y: dimLeft.maxY))
link.move(to: NSPoint(x: fact.midX + 50, y: fact.minY))
link.line(to: NSPoint(x: dimRight.midX, y: dimRight.maxY))
color(0x64748B).setStroke()
link.stroke()
table(fact, header: color(0x4338CA))
table(dimLeft, header: color(0x0F766E))
table(dimRight, header: color(0x0F766E))

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
