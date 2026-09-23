#!/usr/bin/env swift

import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: MakeIcon.swift <out.png> [channel]\n".utf8))
    exit(1)
}
let outputPath = arguments[1]
let channel = arguments.count >= 3 ? arguments[2] : "stable"

let inverted = channel == "nightly"
let paper = inverted ? NSColor.white : NSColor.black
let ink = inverted ? NSColor.black : NSColor.white

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write(Data("no graphics context\n".utf8))
    exit(1)
}

let inset = size * 0.094
let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = CGPath(
    roundedRect: plate,
    cornerWidth: plate.width * 0.225,
    cornerHeight: plate.height * 0.225,
    transform: nil
)

context.saveGState()
context.addPath(squircle)
context.setFillColor(paper.cgColor)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(squircle)
context.setStrokeColor(ink.withAlphaComponent(0.14).cgColor)
context.setLineWidth(size * 0.006)
context.strokePath()
context.restoreGState()

let art = CGRect(x: 170, y: 40, width: 260, height: 440)
let scale = plate.height * 0.66 / art.height
let origin = CGPoint(
    x: plate.midX - art.midX * scale,
    y: plate.midY + art.midY * scale
)
var flip = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: -scale)

func stroke(_ build: (CGMutablePath) -> Void, width: Double, alpha: Double = 1) {
    let path = CGMutablePath()
    build(path)
    context.saveGState()
    context.addPath(path.copy(using: &flip)!)
    context.setStrokeColor(ink.withAlphaComponent(alpha).cgColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()
}

let line = size * 0.024

stroke({ path in
    path.move(to: CGPoint(x: 226, y: 474))
    path.addCurve(to: CGPoint(x: 232, y: 376), control1: CGPoint(x: 232, y: 440), control2: CGPoint(x: 228, y: 404))
    path.move(to: CGPoint(x: 374, y: 474))
    path.addCurve(to: CGPoint(x: 368, y: 376), control1: CGPoint(x: 368, y: 440), control2: CGPoint(x: 372, y: 404))
    path.move(to: CGPoint(x: 232, y: 376))
    path.addCurve(to: CGPoint(x: 368, y: 376), control1: CGPoint(x: 250, y: 356), control2: CGPoint(x: 350, y: 356))
    path.addCurve(to: CGPoint(x: 232, y: 376), control1: CGPoint(x: 350, y: 396), control2: CGPoint(x: 250, y: 396))
    path.move(to: CGPoint(x: 206, y: 474))
    path.addLine(to: CGPoint(x: 394, y: 474))
}, width: line)

stroke({ path in
    path.move(to: CGPoint(x: 272, y: 372))
    path.addCurve(to: CGPoint(x: 204, y: 150), control1: CGPoint(x: 262, y: 300), control2: CGPoint(x: 222, y: 230))
    path.move(to: CGPoint(x: 300, y: 368))
    path.addCurve(to: CGPoint(x: 302, y: 110), control1: CGPoint(x: 302, y: 290), control2: CGPoint(x: 298, y: 190))
    path.move(to: CGPoint(x: 328, y: 372))
    path.addCurve(to: CGPoint(x: 396, y: 150), control1: CGPoint(x: 338, y: 300), control2: CGPoint(x: 378, y: 230))
}, width: line)

func leaf(_ tip: CGPoint, toward angle: Double, length: Double = 96, width: Double = 30) -> (CGMutablePath) -> Void {
    { path in
        let dx = cos(angle), dy = sin(angle)
        let end = CGPoint(x: tip.x + dx * length, y: tip.y + dy * length)
        let nx = -dy * width, ny = dx * width
        let mid = CGPoint(x: (tip.x + end.x) / 2, y: (tip.y + end.y) / 2)
        path.move(to: tip)
        path.addQuadCurve(to: end, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        path.addQuadCurve(to: tip, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
    }
}

stroke(leaf(CGPoint(x: 204, y: 150), toward: -.pi * 0.66), width: line)
stroke(leaf(CGPoint(x: 302, y: 110), toward: -.pi * 0.5), width: line)
stroke(leaf(CGPoint(x: 396, y: 150), toward: -.pi * 0.34), width: line)

if channel == "dev" {
    let band = CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: plate.height * 0.16)
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    context.setFillColor(ink.cgColor)
    context.fill(band)
    context.restoreGState()

    let label = NSAttributedString(string: "DEV", attributes: [
        .font: NSFont.systemFont(ofSize: band.height * 0.52, weight: .heavy),
        .foregroundColor: paper,
        .kern: band.height * 0.06,
    ])
    let bounds = label.size()
    label.draw(at: CGPoint(x: band.midX - bounds.width / 2, y: band.midY - bounds.height / 2))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Icon written → \(outputPath)  [\(channel)]")
