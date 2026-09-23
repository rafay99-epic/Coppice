#!/usr/bin/env swift

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: SetFileIcon.swift <target> <icon.icns>\n".utf8))
    exit(1)
}

let target = arguments[1]
guard let icon = NSImage(contentsOfFile: arguments[2]) else {
    FileHandle.standardError.write(Data("could not read icon: \(arguments[2])\n".utf8))
    exit(1)
}

if NSWorkspace.shared.setIcon(icon, forFile: target, options: []) {
    print("Icon set on \(target)")
} else {
    FileHandle.standardError.write(Data("could not set icon on \(target)\n".utf8))
    exit(1)
}
