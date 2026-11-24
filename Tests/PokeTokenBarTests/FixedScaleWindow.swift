import AppKit

/// An offscreen window that rasterizes at 2x on any main display.
/// A 1x external monitor otherwise makes layers draw at 1x, so OCR reads upscaled text and
/// release screenshots come out at half resolution.
final class FixedScaleWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
}
