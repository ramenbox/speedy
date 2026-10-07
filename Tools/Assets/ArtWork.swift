import AppKit

// Brand colors of the icon and the hero background. They are artwork, not interface colors.
let brandTopColor = NSColor(srgbRed: 0.15, green: 0.39, blue: 0.92, alpha: 1)
let brandBottomColor = NSColor(srgbRed: 0.05, green: 0.58, blue: 0.53, alpha: 1)
let heroTopColor = NSColor(srgbRed: 0.09, green: 0.16, blue: 0.42, alpha: 1)
let heroBottomColor = NSColor(srgbRed: 0.04, green: 0.46, blue: 0.47, alpha: 1)

let iconCanvasPoints: CGFloat = 512
/// Apple's macOS icon grid: the body is 824 of 1024 pixels, centered.
let iconBodyInsetPoints: CGFloat = 50
let iconCornerRadiusPoints: CGFloat = 92
let iconSymbolPointSize: CGFloat = 220

let heroWidth: CGFloat = 1200
let heroBottomMargin: CGFloat = 56
let heroMenuBarHeight: CGFloat = 30
let heroPanelCornerRadius: CGFloat = 12
let heroPanelGap: CGFloat = 48

func drawAppIcon() throws -> NSBitmapImageRep {
    let bitmap = try makeBitmap(pointSize: CGSize(width: iconCanvasPoints, height: iconCanvasPoints))
    let bodyRect = CGRect(x: 0, y: 0, width: iconCanvasPoints, height: iconCanvasPoints).insetBy(dx: iconBodyInsetPoints, dy: iconBodyInsetPoints)
    let symbol = try symbolImage(name: "gauge.with.dots.needle.67percent", pointSize: iconSymbolPointSize, weight: .semibold, color: .white)
    drawInto(bitmap) { context in
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: iconCornerRadiusPoints, yRadius: iconCornerRadiusPoints)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        brandBottomColor.setFill()
        bodyPath.fill()
        context.restoreGState()

        NSGradient(starting: brandTopColor, ending: brandBottomColor)?.draw(in: bodyPath, angle: -90)

        let symbolSize = symbol.size
        let symbolRect = CGRect(
            x: bodyRect.midX - symbolSize.width / 2,
            y: bodyRect.midY - symbolSize.height / 2,
            width: symbolSize.width,
            height: symbolSize.height,
        )
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        symbol.draw(in: symbolRect)
        context.restoreGState()
    }
    return bitmap
}

/// A menu bar strip with the Speedy icon, the light panel below it, and the dark panel next to it.
func drawHero(leftPanel: NSBitmapImageRep, rightPanel: NSBitmapImageRep) throws -> NSBitmapImageRep {
    let heroSize = CGSize(width: heroWidth, height: heroMenuBarHeight + 14 + leftPanel.size.height + heroBottomMargin)
    let bitmap = try makeBitmap(pointSize: heroSize)
    let menuBarSymbol = try symbolImage(name: "gauge.with.dots.needle.67percent", pointSize: 15, weight: .medium, color: .white)
    let totalPanelWidth = leftPanel.size.width + heroPanelGap + rightPanel.size.width
    let leftPanelOrigin = CGPoint(
        x: (heroSize.width - totalPanelWidth) / 2,
        y: heroSize.height - heroMenuBarHeight - 14 - leftPanel.size.height,
    )
    let rightPanelOrigin = CGPoint(
        x: leftPanelOrigin.x + leftPanel.size.width + heroPanelGap,
        y: heroSize.height - heroMenuBarHeight - 90 - rightPanel.size.height,
    )
    drawInto(bitmap) { context in
        NSGradient(starting: heroTopColor, ending: heroBottomColor)?.draw(in: CGRect(origin: .zero, size: heroSize), angle: -60)
        drawMenuBar(heroSize: heroSize, symbol: menuBarSymbol, symbolCenterX: leftPanelOrigin.x + leftPanel.size.width / 2)
        drawPanel(leftPanel, origin: leftPanelOrigin, context: context)
        drawPanel(rightPanel, origin: rightPanelOrigin, context: context)
    }
    return bitmap
}

private func drawMenuBar(heroSize: CGSize, symbol: NSImage, symbolCenterX: CGFloat) {
    let barRect = CGRect(x: 0, y: heroSize.height - heroMenuBarHeight, width: heroSize.width, height: heroMenuBarHeight)
    NSColor.white.withAlphaComponent(0.14).setFill()
    barRect.fill()
    let highlightRect = CGRect(x: symbolCenterX - 17, y: barRect.minY + 4, width: 34, height: heroMenuBarHeight - 8)
    NSColor.white.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: highlightRect, xRadius: 6, yRadius: 6).fill()
    symbol.draw(in: CGRect(
        x: symbolCenterX - symbol.size.width / 2,
        y: barRect.midY - symbol.size.height / 2,
        width: symbol.size.width,
        height: symbol.size.height,
    ))
    let clockAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.white,
    ]
    let clockText = NSAttributedString(string: dayAndClockTimeFormatter.string(from: Date()), attributes: clockAttributes)
    clockText.draw(at: CGPoint(x: heroSize.width - clockText.size().width - 18, y: barRect.midY - clockText.size().height / 2))
}

private func drawPanel(_ panel: NSBitmapImageRep, origin: CGPoint, context: CGContext) {
    let panelRect = CGRect(origin: origin, size: panel.size)
    let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: heroPanelCornerRadius, yRadius: heroPanelCornerRadius)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.setFill()
    panelPath.fill()
    context.restoreGState()
    context.saveGState()
    panelPath.addClip()
    panel.draw(in: panelRect)
    context.restoreGState()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    panelPath.lineWidth = 1
    panelPath.stroke()
}
