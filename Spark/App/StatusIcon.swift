import AppKit

/// Menu bar icons. Built as template images so the system tints them for light/dark menu bars.
@MainActor
enum StatusIcon {
    /// The plain sparkle.
    static let normal = makeIcon(badged: false)
    /// The sparkle with an exclamation badge, shown when a provider is unavailable.
    /// SF Symbols has no badged sparkle, so it's composited here.
    static let degraded = makeIcon(badged: true)

    private static func makeIcon(badged: Bool) -> NSImage {
        let sparkle = symbol("sparkle", pointSize: 15, weight: .regular)
        let badge = symbol("exclamationmark.circle.fill", pointSize: 8.5, weight: .bold)
        let size = NSSize(width: sparkle.size.width + 3, height: sparkle.size.height + 1)

        let image = NSImage(size: size, flipped: false) { rect in
            sparkle.draw(at: NSPoint(x: 0, y: rect.maxY - sparkle.size.height), from: .zero, operation: .sourceOver, fraction: 1)
            guard badged else { return true }

            let badgeRect = NSRect(origin: NSPoint(x: rect.maxX - badge.size.width, y: 0), size: badge.size)
            // Knock out a ring around the badge so it stays legible where it overlaps the sparkle.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.draw(in: badgeRect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badged ? "Spark (a provider is unavailable)" : "Spark"
        return image
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { preconditionFailure("Missing SF Symbol \(name)") }
        return image
    }
}
