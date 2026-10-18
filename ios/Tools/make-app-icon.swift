#!/usr/bin/env swift
// Renders the 1024x1024 app icon: the Loop logo in near-black on white.
// The outline comes from ios/Tools/loop-logo.json (made by ios/Tools/trace-logo.py from the approved artwork),
// the same outline the in-app logo (LoopLogoShape) draws.
// Usage: swift ios/Tools/make-app-icon.swift [output.png]
// Default output: ios/Loop/Assets.xcassets/AppIcon.appiconset/AppIcon.png (no alpha, as the App Store requires).
// The colors are baked into the PNG, so they are written here too; in the app they are Theme.ink and white.
import CoreGraphics
import Foundation
import ImageIO

let side = 1024
let logoWidth = CGFloat(side) * 0.70
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ios/Loop/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ink = CGColor(colorSpace: srgb, components: [0x19 / 255.0, 0x19 / 255.0, 0x19 / 255.0, 1])!
let white = CGColor(colorSpace: srgb, components: [1, 1, 1, 1])!

guard let data = FileManager.default.contents(atPath: "ios/Tools/loop-logo.json"),
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let aspect = json["aspect"] as? Double,
      let contours = json["contours"] as? [[String: Any]] else { fatalError("run from the repo root; loop-logo.json missing") }

guard let cg = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }
cg.setFillColor(white)
cg.fill(CGRect(x: 0, y: 0, width: side, height: side))

// The outline is y-down in units of the logo's width; center it in the icon (CoreGraphics is y-up).
let originX = (CGFloat(side) - logoWidth) / 2
let logoHeight = logoWidth * CGFloat(aspect)
let originY = (CGFloat(side) - logoHeight) / 2
func point(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: originX + CGFloat(x) * logoWidth, y: CGFloat(side) - (originY + CGFloat(y) * logoWidth))
}
let path = CGMutablePath()
for contour in contours {
    let start = contour["start"] as! [Double]
    path.move(to: point(start[0], start[1]))
    for segment in contour["segments"] as! [[Any]] {
        let kind = segment[0] as! String
        let v = segment.dropFirst().map { ($0 as! NSNumber).doubleValue }
        if kind == "l" {
            path.addLine(to: point(v[0], v[1]))
        } else {
            path.addCurve(to: point(v[4], v[5]), control1: point(v[0], v[1]), control2: point(v[2], v[3]))
        }
    }
    path.closeSubpath()
}
cg.setFillColor(ink)
cg.addPath(path)
cg.fillPath(using: .evenOdd)

guard let image = cg.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("png") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("write") }
print("wrote \(out)")
