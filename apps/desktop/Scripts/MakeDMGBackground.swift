#!/usr/bin/env swift
// Renders the drag-to-install background for the DMG window.
//   swift Scripts/MakeDMGBackground.swift <out.png>
//
// Sized 660×428 at 2×, matching the window bounds make-dmg.sh sets in Finder.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: MakeDMGBackground.swift <out.png>\n".utf8))
    exit(1)
}

let width = 1320.0, height = 856.0
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }

// True black, matching the app itself.
context.setFillColor(NSColor.black.cgColor)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

// A faint vertical lift so the window has some depth under the icons.
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(white: 0.09, alpha: 1).cgColor,
        NSColor(white: 0.0, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: width / 2, y: height),
    end: CGPoint(x: width / 2, y: height * 0.25),
    options: []
)

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    string.draw(at: NSPoint(x: (width - bounds.width) / 2, y: y))
}

draw("Coppice", size: 46, weight: .semibold, color: .white, y: height - 132)
draw(
    "Drag Coppice into Applications",
    size: 25,
    weight: .regular,
    color: NSColor(white: 0.56, alpha: 1),
    y: height - 186
)

// The arrow between the app and the Applications alias. Finder places those two
// at x = 165 and x = 495 in a 660pt window, so this sits in the gap at 2×.
let arrowY = height - 415.0
let start = 610.0, end = 710.0
context.setStrokeColor(NSColor(white: 0.30, alpha: 1).cgColor)
context.setLineWidth(5)
context.setLineCap(.round)
context.move(to: CGPoint(x: start, y: arrowY))
context.addLine(to: CGPoint(x: end, y: arrowY))
context.strokePath()

context.setFillColor(NSColor(white: 0.30, alpha: 1).cgColor)
context.move(to: CGPoint(x: end + 18, y: arrowY))
context.addLine(to: CGPoint(x: end - 8, y: arrowY + 14))
context.addLine(to: CGPoint(x: end - 8, y: arrowY - 14))
context.closePath()
context.fillPath()

draw(
    "Menu bar app — look for the scissors, not the Dock",
    size: 19,
    weight: .regular,
    color: NSColor(white: 0.34, alpha: 1),
    y: 62
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[1]))
print("DMG background written → \(arguments[1])")
