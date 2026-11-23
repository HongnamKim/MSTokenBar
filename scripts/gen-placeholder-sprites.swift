#!/usr/bin/env swift
// Generate the placeholders and convert the Gunpla base artwork to bundled idle GIFs.
// Usage: swift scripts/gen-placeholder-sprites.swift <outdir> [sample-png-dir]
//   outdir          Sources/PokeTokenBar/Resources/Gunpla/Sprites
//   default inputs  assets/sprites/rx-78-2 and assets/sprites/first-hguc
//   sample-png-dir  optional RX-78-2 sample directory to convert on its own
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: gen-placeholder-sprites.swift <outdir> [sample-png-dir]\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func write(_ frames: [CGImage], to url: URL, type: UTType, delay: Double?) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames.count, nil) else {
        fatalError("cannot create \(url.path)")
    }
    if type == .gif {
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
    }
    for frame in frames {
        let props: [String: Any] = delay.map { [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFDelayTime as String: $0]] } ?? [:]
        CGImageDestinationAddImage(dest, frame, props as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { fatalError("finalize failed \(url.path)") }
}

/// Two frames, the second shifted up by `shift` px.
func bob(_ draw: (CGContext, Int) -> Void, w: Int, h: Int, shift: Int = 1) -> [CGImage] {
    (0..<2).map { i in
        let ctx = makeContext(w, h)
        draw(ctx, i * shift)   // CG origin is bottom-left, so +y moves up
        return ctx.makeImage()!
    }
}

let gray = CGColor(red: 0.55, green: 0.57, blue: 0.6, alpha: 1)

// Silhouettes: SD 48x48 (big head, short body), real 48x64 (small head, tall body).
func silhouette(w: Int, h: Int, sd: Bool) -> [CGImage] {
    bob({ ctx, up in
        ctx.setFillColor(gray)
        let headH = sd ? 20 : 12, headW = sd ? 28 : 14
        let bodyW = sd ? 24 : 24, bodyH = sd ? 14 : 24, legH = sd ? 6 : 22
        let cx = w / 2
        ctx.fill(CGRect(x: cx - bodyW / 2 - 4, y: 2 + up, width: 8, height: legH))
        ctx.fill(CGRect(x: cx + bodyW / 2 - 4, y: 2 + up, width: 8, height: legH))
        ctx.fill(CGRect(x: cx - bodyW / 2, y: 2 + legH + up, width: bodyW, height: bodyH))
        ctx.fill(CGRect(x: cx - headW / 2, y: 2 + legH + bodyH + up, width: headW, height: headH))
        ctx.fill(CGRect(x: cx - bodyW / 2 - 6, y: 2 + legH + up, width: 6, height: bodyH))
        ctx.fill(CGRect(x: cx + bodyW / 2, y: 2 + legH + up, width: 6, height: bodyH))
    }, w: w, h: h)
}

func box() -> CGImage {
    let ctx = makeContext(32, 32)
    ctx.setFillColor(gray)
    ctx.fill(CGRect(x: 4, y: 4, width: 24, height: 20))
    ctx.setFillColor(CGColor(red: 0.4, green: 0.42, blue: 0.45, alpha: 1))
    ctx.fill(CGRect(x: 2, y: 22, width: 28, height: 6))
    return ctx.makeImage()!
}

write(silhouette(w: 48, h: 48, sd: true), to: outDir.appendingPathComponent("silhouette-sd.gif"), type: .gif, delay: 0.4)
write(silhouette(w: 48, h: 64, sd: false), to: outDir.appendingPathComponent("silhouette-real.gif"), type: .gif, delay: 0.4)
write([box()], to: outDir.appendingPathComponent("box.png"), type: .png, delay: nil)

// The HGUC base supersedes the earlier RX-78-2 HG sample with the same filename.
let sampleDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "assets/sprites/rx-78-2", isDirectory: true)
var inputs = ["sd", "hg", "rg", "mg", "pg"].map { sampleDir.appendingPathComponent("rx-78-2-\($0).png") }
if args.count == 2 {
    let hgucDir = URL(fileURLWithPath: "assets/sprites/first-hguc", isDirectory: true)
    let hguc = try FileManager.default.contentsOfDirectory(at: hgucDir, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasSuffix("-hg.png") }
    let replacements = Set(hguc.map(\.lastPathComponent))
    inputs = inputs.filter { !replacements.contains($0.lastPathComponent) } + hguc
}
for src in inputs {
    guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        FileHandle.standardError.write(Data("skip missing \(src.path)\n".utf8))
        continue
    }
    let w = image.width, h = image.height
    let frames = bob({ ctx, up in
        ctx.draw(image, in: CGRect(x: 0, y: up, width: w, height: h))
    }, w: w, h: h)
    write(frames, to: outDir.appendingPathComponent(src.deletingPathExtension().lastPathComponent + ".gif"), type: .gif, delay: 0.4)
}
print("wrote sprites to \(outDir.path)")
