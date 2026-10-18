#!/usr/bin/env swift
// Renders the 1024x1024 app icon: "loop." in SF Pro Rounded Bold, Loop Lime on near-black.
// Usage: swift ios/Tools/make-app-icon.swift [output.png]
// Default output: ios/Loop/Assets.xcassets/AppIcon.appiconset/AppIcon.png (no alpha, as the App Store requires).
// The colors are baked into the PNG, so the hex values live here too; the in-app token is Theme.lime.
import AppKit
import CoreText

let side = 1024
let background = NSColor(srgbRed: 0x19 / 255, green: 0x19 / 255, blue: 0x19 / 255, alpha: 1)
let lime = NSColor(srgbRed: 0xC7 / 255, green: 0xE7 / 255, blue: 0x5A / 255, alpha: 1)
let wordWidth = CGFloat(side) * 0.74

let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ios/Loop/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

func font(size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return NSFont(descriptor: rounded, size: size) ?? base
}

func line(size: CGFloat) -> CTLine {
    let text = NSAttributedString(string: "loop.", attributes: [.font: font(size: size), .foregroundColor: lime, .kern: -size * 0.01])
    return CTLineCreateWithAttributedString(text)
}

// Size the word to a fixed share of the icon width, measured on the ink, not the advance.
let probe = CTLineGetImageBounds(line(size: 100), nil)
let size = 100 * wordWidth / probe.width
let ctLine = line(size: size)
let ink = CTLineGetImageBounds(ctLine, nil)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
guard let cg = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }
cg.setFillColor(background.cgColor)
cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
// Center the ink box: the tall "l" and the descending "p" balance around the middle.
cg.textPosition = CGPoint(x: (CGFloat(side) - ink.width) / 2 - ink.minX,
                          y: (CGFloat(side) - ink.height) / 2 - ink.minY)
CTLineDraw(ctLine, cg)

guard let image = cg.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("png") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("write") }
print("wrote \(out) (font size \(Int(size)))")
