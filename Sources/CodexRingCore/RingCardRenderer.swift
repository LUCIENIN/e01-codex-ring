import AppKit
import Foundation

public enum RingCardRendererError: Error, Equatable {
    case invalidCanvas
    case pngEncodingFailed
}

public struct RingCardRenderer: Sendable {
    public init() {}

    public func render(_ presentation: UsagePresentation, size: CGSize, now: Date) throws -> Data {
        let reset = formatReset(presentation.primary.resetsAt)
        let secondary = presentation.secondary.map { "WEEK \($0.remainingPercent)%" }
        let freshness = formatFreshness(presentation.freshness, observedAt: now)

        return try makeCard(
            primary: "\(presentation.primary.remainingPercent)% LEFT",
            reset: reset,
            secondary: secondary,
            freshness: freshness,
            size: size
        )
    }

    public func renderUnavailable(size: CGSize, now: Date) throws -> Data {
        try makeCard(
            primary: "NO CODEX DATA",
            reset: "waiting for local session",
            secondary: nil,
            freshness: "UNAVAILABLE",
            size: size
        )
    }

    private func makeCard(
        primary: String,
        reset: String,
        secondary: String?,
        freshness: String,
        size: CGSize
    ) throws -> Data {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width <= 4_096,
              size.height <= 4_096
        else {
            throw RingCardRendererError.invalidCanvas
        }

        let width = Int(size.width.rounded(.down))
        let height = Int(size.height.rounded(.down))
        guard width > 0,
              height > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: width,
                  pixelsHigh: height,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw RingCardRendererError.pngEncodingFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        let canvas = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.black.setFill()
        canvas.fill()

        let shortestSide = CGFloat(min(width, height))
        let inset = max(8, shortestSide * 0.06)
        let circle = NSBezierPath(ovalIn: canvas.insetBy(dx: inset, dy: inset))
        NSColor.white.setStroke()
        circle.lineWidth = max(2, shortestSide * 0.012)
        circle.stroke()

        let titleFont = NSFont.monospacedSystemFont(ofSize: max(15, shortestSide * 0.092), weight: .bold)
        let detailFont = NSFont.monospacedSystemFont(ofSize: max(10, shortestSide * 0.04), weight: .medium)
        let secondaryFont = NSFont.monospacedSystemFont(ofSize: max(10, shortestSide * 0.046), weight: .regular)
        let textColor = NSColor.white
        let top = CGFloat(height) * 0.60

        drawCentered(primary, font: titleFont, color: textColor, at: CGPoint(x: CGFloat(width) / 2, y: top))
        drawCentered(reset, font: detailFont, color: textColor, at: CGPoint(x: CGFloat(width) / 2, y: top - shortestSide * 0.17))
        if let secondary {
            drawCentered(secondary, font: secondaryFont, color: textColor, at: CGPoint(x: CGFloat(width) / 2, y: top - shortestSide * 0.32))
        }
        drawCentered(freshness, font: detailFont, color: textColor, at: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.18))

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RingCardRendererError.pngEncodingFailed
        }
        return data
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func formatReset(_ date: Date?) -> String {
        guard let date else { return "RESET --" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return "RESET \(formatter.string(from: date))"
    }

    private func formatFreshness(_ freshness: Freshness, observedAt now: Date) -> String {
        switch freshness {
        case .fresh:
            return "CODEX LEFT"
        case .stale:
            return "STALE DATA"
        case .unavailable:
            return "UNAVAILABLE"
        }
    }
}
