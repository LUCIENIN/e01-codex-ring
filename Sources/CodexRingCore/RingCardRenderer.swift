import AppKit
import Foundation

public enum RingCardRendererError: Error, Equatable {
    case invalidCanvas
    case pngEncodingFailed
}

public struct RingCardRenderer: Sendable {
    public init() {}

    public func renderDashboard(
        _ presentation: QuotaDashboardPresentation,
        size: CGSize,
        now: Date
    ) throws -> Data {
        guard presentation.hasData else {
            return try renderUnavailable(size: size, now: now)
        }
        let isStale = presentation.codex?.freshness == .stale
            || presentation.kimi?.freshness == .stale
        return try makeDashboardCard(
            metrics: presentation.metrics,
            isStale: isStale,
            size: size
        )
    }

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

    private func makeDashboardCard(
        metrics: [QuotaDashboardMetric],
        isStale: Bool,
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

        context.imageInterpolation = .high
        context.shouldAntialias = true

        let canvas = NSRect(x: 0, y: 0, width: width, height: height)
        let background = NSGradient(
            starting: color(0x050A13),
            ending: color(0x0B1B30)
        )
        background?.draw(in: canvas, angle: 90)

        let shortestSide = CGFloat(min(width, height))
        let scale = shortestSide / 368
        let outerRing = NSBezierPath(
            ovalIn: canvas.insetBy(dx: 11 * scale, dy: 11 * scale)
        )
        color(0x2B405C, alpha: 0.82).setStroke()
        outerRing.lineWidth = max(1.5, 1.5 * scale)
        outerRing.stroke()

        let innerRing = NSBezierPath(
            ovalIn: canvas.insetBy(dx: 17 * scale, dy: 17 * scale)
        )
        color(0x18304B, alpha: 0.48).setStroke()
        innerRing.lineWidth = max(1, scale)
        innerRing.stroke()

        drawCentered(
            "AI QUOTA",
            font: roundedFont(ofSize: max(12, 13 * scale), weight: .semibold),
            color: color(0xDDE9F8),
            at: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) - 43 * scale),
            kern: 2.2 * scale
        )

        let cardWidth = min(CGFloat(width) - 88 * scale, 268 * scale)
        let cardHeight = 58 * scale
        let centerX = CGFloat(width) / 2
        let firstCenterY = CGFloat(height) - 103 * scale
        let rowGap = 66 * scale

        for (index, metric) in metrics.prefix(3).enumerated() {
            let centerY = firstCenterY - CGFloat(index) * rowGap
            let rect = NSRect(
                x: centerX - cardWidth / 2,
                y: centerY - cardHeight / 2,
                width: cardWidth,
                height: cardHeight
            )
            drawMetric(metric, in: rect, scale: scale)
        }

        let footerColor = isStale ? color(0xFBBF24) : color(0x5EEAD4)
        let footerText = isStale ? "STALE · CACHED" : "LIVE · AUTO 30S"
        drawCentered(
            footerText,
            font: roundedFont(ofSize: max(10, 10.5 * scale), weight: .semibold),
            color: footerColor,
            at: CGPoint(x: centerX, y: 47 * scale),
            kern: 0.8 * scale
        )

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RingCardRendererError.pngEncodingFailed
        }
        return data
    }

    private func drawMetric(_ metric: QuotaDashboardMetric, in rect: NSRect, scale: CGFloat) {
        let accent = statusColor(metric.status)
        let card = NSBezierPath(roundedRect: rect, xRadius: 15 * scale, yRadius: 15 * scale)
        color(0x101E31, alpha: 0.96).setFill()
        card.fill()
        color(0x2B405C, alpha: 0.88).setStroke()
        card.lineWidth = max(1, scale)
        card.stroke()

        let markerRect = NSRect(
            x: rect.minX + 10 * scale,
            y: rect.minY + 14 * scale,
            width: 4 * scale,
            height: rect.height - 28 * scale
        )
        accent.setFill()
        NSBezierPath(
            roundedRect: markerRect,
            xRadius: 2 * scale,
            yRadius: 2 * scale
        ).fill()

        drawLeftAligned(
            metric.label,
            font: roundedFont(ofSize: max(11, 12.5 * scale), weight: .semibold),
            color: color(0xD7E3F3),
            at: CGPoint(x: rect.minX + 24 * scale, y: rect.midY + 9 * scale),
            kern: 0.45 * scale
        )
        drawLeftAligned(
            metric.status.rawValue,
            font: roundedFont(ofSize: max(8, 8.5 * scale), weight: .bold),
            color: accent,
            at: CGPoint(x: rect.minX + 24 * scale, y: rect.midY - 10 * scale),
            kern: 0.75 * scale
        )

        drawRightAligned(
            "\(metric.remainingPercent)%",
            font: NSFont.monospacedDigitSystemFont(
                ofSize: max(23, 27 * scale),
                weight: .bold
            ),
            color: color(0xF8FAFC),
            at: CGPoint(x: rect.maxX - 17 * scale, y: rect.midY + 1 * scale)
        )

        let trackRect = NSRect(
            x: rect.minX + 24 * scale,
            y: rect.minY + 7 * scale,
            width: rect.width - 41 * scale,
            height: 3 * scale
        )
        color(0x32445C, alpha: 0.72).setFill()
        NSBezierPath(
            roundedRect: trackRect,
            xRadius: 1.5 * scale,
            yRadius: 1.5 * scale
        ).fill()

        let progress = CGFloat(min(max(metric.remainingPercent, 0), 100)) / 100
        guard progress > 0 else { return }
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(3 * scale, trackRect.width * progress),
            height: trackRect.height
        )
        accent.setFill()
        NSBezierPath(
            roundedRect: fillRect,
            xRadius: 1.5 * scale,
            yRadius: 1.5 * scale
        ).fill()
    }

    private func makeCard(
        primary: String,
        reset: String,
        secondary: String?,
        freshness: String,
        size: CGSize,
        detailScale: CGFloat = 0.04,
        secondaryScale: CGFloat = 0.046
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
        let detailFont = NSFont.monospacedSystemFont(
            ofSize: max(10, shortestSide * detailScale),
            weight: .medium
        )
        let secondaryFont = NSFont.monospacedSystemFont(
            ofSize: max(10, shortestSide * secondaryScale),
            weight: .regular
        )
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

    private func drawCentered(
        _ text: String,
        font: NSFont,
        color: NSColor,
        at point: CGPoint,
        kern: CGFloat = 0
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: kern,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawLeftAligned(
        _ text: String,
        font: NSFont,
        color: NSColor,
        at point: CGPoint,
        kern: CGFloat = 0
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: kern,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: point.x, y: point.y - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawRightAligned(
        _ text: String,
        font: NSFont,
        color: NSColor,
        at point: CGPoint
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: point.x - textSize.width, y: point.y - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size)
        else {
            return fallback
        }
        return rounded
    }

    private func statusColor(_ status: QuotaHealthStatus) -> NSColor {
        switch status {
        case .good:
            return color(0x5EEAD4)
        case .watch:
            return color(0xFBBF24)
        case .low:
            return color(0xFB7185)
        }
    }

    private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
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
