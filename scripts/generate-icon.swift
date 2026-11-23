// Render the original pixel-art master at a macOS icon size.
// Usage: swift scripts/generate-icon.swift <output.png> [size]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let size = args.count > 2 ? Int(args[2]) ?? 0 : 1024
guard args.count > 1, size > 0 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <output.png> [positive size]\n".utf8))
    exit(1)
}

let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("assets")
let master = assets.appendingPathComponent(size <= 16 ? "app-icon-small.png" : "app-icon-grid.png")
let output = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(master as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot render \(master.path)")
}
ctx.interpolationQuality = .none
ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let result = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Cannot write \(output.path)")
}
CGImageDestinationAddImage(dest, result, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Cannot finish \(output.path)") }
