#!/usr/bin/env swift
// Renders the app icon as a 1024×1024 PNG.
//   swift Scripts/MakeIcon.swift <out.png> [stable|nightly|dev]
//
// The mark is a coppiced stump: one horizontal cut, three shoots of different
// heights growing back out of it. It reads at 16pt because it is three bars and
// a line, and it says what the app does without a metaphor anyone has to decode.

import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: MakeIcon.swift <out.png> [channel]\n".utf8))
    exit(1)
}
let outputPath = arguments[1]
let channel = arguments.count >= 3 ? arguments[2] : "stable"

/// Each channel gets its own accent so three installed copies are distinguishable
/// in the Dock, in Finder, and on the DMG.
let accent: NSColor
switch channel {
case "nightly": accent = NSColor(srgbRed: 0.69, green: 0.49, blue: 1.00, alpha: 1)
case "dev":     accent = NSColor(srgbRed: 1.00, green: 0.75, blue: 0.26, alpha: 1)
default:        accent = NSColor(srgbRed: 0.24, green: 0.86, blue: 0.52, alpha: 1)
}

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write(Data("no graphics context\n".utf8))
    exit(1)
}

// macOS icon geometry: the artwork sits inside a squircle with a margin, so it
// lines up with every other app in the Dock rather than looking oversized.
let inset = size * 0.094
let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = CGPath(
    roundedRect: plate,
    cornerWidth: plate.width * 0.225,
    cornerHeight: plate.height * 0.225,
    transform: nil
)

// Near-black plate with a slight vertical lift, so the icon has depth without
// looking like a gradient-heavy 2015 icon.
context.saveGState()
context.addPath(squircle)
context.clip()
let backdrop = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 0.10, green: 0.11, blue: 0.11, alpha: 1).cgColor,
        NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    backdrop,
    start: CGPoint(x: plate.midX, y: plate.maxY),
    end: CGPoint(x: plate.midX, y: plate.minY),
    options: []
)
context.restoreGState()

// Hairline rim, the way Apple's own utility icons separate from a dark Dock.
context.saveGState()
context.addPath(squircle)
context.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
context.setLineWidth(size * 0.006)
context.strokePath()
context.restoreGState()

/// Fills a rounded bar. Every element of the mark is one of these, which is what
/// keeps it legible when the whole icon is 16 points wide.
func bar(_ rect: CGRect, color: NSColor) {
    context.saveGState()
    context.setFillColor(color.cgColor)
    let radius = min(rect.width, rect.height) / 2
    context.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    ))
    context.fillPath()
    context.restoreGState()
}

// Optical centre sits slightly above the geometric one, because the shoots carry
// more visual weight than the stool below them.
let markWidth = plate.width * 0.54
let markX = plate.midX - markWidth / 2
let cutHeight = size * 0.040
let cutY = plate.midY - plate.height * 0.055

// The stool: what is left standing after the cut. Dim accent rather than grey,
// so it reads as the same plant rather than a stray shape.
let stoolWidth = markWidth * 0.30
bar(
    CGRect(
        x: plate.midX - stoolWidth / 2,
        y: cutY - plate.height * 0.185,
        width: stoolWidth,
        height: plate.height * 0.19 + cutHeight
    ),
    color: accent.withAlphaComponent(0.26)
)

// Shoots first, so the cut bar overlaps them and they read as growing out from
// behind it rather than crossing it.
let shootWidth = size * 0.055
let gap = (markWidth - shootWidth * 3) / 2
let heights = [0.19, 0.30, 0.24].map { plate.height * $0 }
let opacities = [0.55, 1.0, 0.76]

for index in 0..<3 {
    bar(
        CGRect(
            x: markX + Double(index) * (shootWidth + gap),
            y: cutY,
            width: shootWidth,
            height: heights[index] + cutHeight
        ),
        color: accent.withAlphaComponent(opacities[index])
    )
}

// The cut itself, drawn last so it sits cleanly across the base of the shoots.
bar(
    CGRect(x: markX, y: cutY, width: markWidth, height: cutHeight),
    color: accent
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Icon written → \(outputPath)  [\(channel)]")
