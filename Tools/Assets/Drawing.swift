import AppKit
import SwiftUI

let imageScale: CGFloat = 2
/// Charts draw after the first layout pass. The renderer waits this long before it captures a view.
let viewSettleSeconds: TimeInterval = 0.6

enum AssetError: Error, CustomStringConvertible {
    case couldNotCreateBitmap(width: Int, height: Int)
    case couldNotEncodePng(path: String)
    case couldNotWrite(path: String, detail: String)
    case missingSymbol(name: String)
    case commandFailed(command: String, exitCode: Int32)

    var description: String {
        switch self {
        case .couldNotCreateBitmap(let width, let height): return "Could not create a \(width)x\(height) bitmap"
        case .couldNotEncodePng(let path): return "Could not encode PNG for \(path)"
        case .couldNotWrite(let path, let detail): return "Could not write \(path): \(detail)"
        case .missingSymbol(let name): return "SF Symbol \(name) is missing on this Mac"
        case .commandFailed(let command, let exitCode): return "\(command) failed with exit code \(exitCode)"
        }
    }
}

/// An RGBA bitmap with a point size and `imageScale` pixels per point.
func makeBitmap(pointSize: CGSize) throws -> NSBitmapImageRep {
    let pixelWidth = Int(pointSize.width * imageScale)
    let pixelHeight = Int(pointSize.height * imageScale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0,
    ) else {
        throw AssetError.couldNotCreateBitmap(width: pixelWidth, height: pixelHeight)
    }
    bitmap.size = pointSize
    return bitmap
}

/// Draws into the bitmap with AppKit drawing calls. The origin is at the bottom left.
func drawInto(_ bitmap: NSBitmapImageRep, drawing: (CGContext) -> Void) {
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        preconditionFailure("NSGraphicsContext cannot draw into an RGBA bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    drawing(graphicsContext.cgContext)
    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

func writePng(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw AssetError.couldNotEncodePng(path: url.path)
    }
    do {
        try pngData.write(to: url, options: .atomic)
    } catch {
        throw AssetError.couldNotWrite(path: url.path, detail: error.localizedDescription)
    }
    print("Wrote \(url.path)")
}

/// Renders a SwiftUI view in an offscreen window. AppKit controls (pickers, toggles, menus) render as well.
@MainActor
func renderView<Content: View>(_ content: Content, appearanceName: NSAppearance.Name) throws -> NSBitmapImageRep {
    let appearance = NSAppearance(named: appearanceName)
    let hostingView = NSHostingView(rootView: content)
    hostingView.appearance = appearance
    let fittingSize = hostingView.fittingSize
    let window = NSWindow(
        contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: fittingSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false,
    )
    window.appearance = appearance
    window.contentView = hostingView
    window.orderFrontRegardless()
    hostingView.frame = CGRect(origin: .zero, size: fittingSize)
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(viewSettleSeconds))
    let bitmap = try makeBitmap(pointSize: hostingView.bounds.size)
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    window.orderOut(nil)
    return bitmap
}

func symbolImage(name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) throws -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
        throw AssetError.missingSymbol(name: name)
    }
    return image
}
