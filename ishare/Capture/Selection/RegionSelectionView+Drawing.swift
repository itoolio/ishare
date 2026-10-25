import AppKit
import Defaults
import ishareCore

extension RegionSelectionView {
    private var keptRegions: [SelectionRegion] {
        guard let displayID else { return [] }
        return session.regions.regions(onDisplay: displayID)
    }

    private var hudText: String {
        var parts = ["Drag to select".localized()]
        if options.allowsWindowMode {
            parts.append("Space for windows".localized())
        }
        parts.append("⌥ drag to measure".localized())
        if lastRegion != nil {
            parts.append("L for last region".localized())
        }
        parts.append("G for guides".localized())
        parts.append(hasMagnifier ? "Z for zoom and position".localized() : "Z for position".localized())
        parts.append("Return for full screen".localized())
        return parts.joined(separator: "  ·  ")
    }

    private var toolsHudText: String {
        if session.isEnteringSize {
            return "Type a size like 800x600 or 400x300pt, then press Return".localized()
        }
        var parts: [String] = []
        if session.constraint.fixedSize != nil {
            parts.append("Click to place, Return to capture".localized())
        }
        parts.append("A for aspect ratio".localized())
        parts.append("F for fixed size".localized())
        parts.append("S to type a size".localized())
        if options.allowsMultipleRegions {
            if session.regions.isEmpty {
                parts.append("⇧ or + to keep several regions".localized())
            } else {
                parts.append(String(format: "Return to capture %d regions".localized(), session.regions.count))
                parts.append("⌫ removes the hovered region".localized())
            }
        }
        if options.allowsFreezeToggle {
            parts.append(session.freezeMode == .frozen ? "Tab for the live screen".localized() : "Tab to freeze the screen".localized())
        }
        return parts.joined(separator: "  ·  ")
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let backdrop {
            context.interpolationQuality = .high
            context.draw(backdrop, in: bounds)
        }
        let activeSelection = selection.flatMap { $0.isEmpty ? nil : $0 }
        let preview = activeSelection == nil ? fixedPreview : nil
        drawDimming(context: context, holes: keptRegions.map(\.rect) + [activeSelection ?? preview].compactMap { $0 })
        drawKeptRegions()

        let isOnThisScreen = mouseLocation != nil || NSScreen.underMouse == screen
        if let activeSelection {
            drawSelection(activeSelection)
        } else {
            if let preview {
                drawSelection(preview, dashed: true)
            }
            if let lastRegion, Defaults[.showLastRegionOutline], keptRegions.isEmpty {
                drawLastRegionGhost(lastRegion)
            }
            if isOnThisScreen, measurement == nil, preview == nil {
                if let hint = options.hint {
                    SelectionStyle.drawPill(hint, centeredAt: CGPoint(x: bounds.midX, y: toolbar.frame.minY - 24), in: bounds)
                }
                SelectionStyle.drawPill(hudText, centeredAt: CGPoint(x: bounds.midX, y: bounds.minY + 84), in: bounds)
                SelectionStyle.drawPill(toolsHudText, centeredAt: CGPoint(x: bounds.midX, y: bounds.minY + 56), in: bounds)
            } else if isOnThisScreen, preview != nil {
                SelectionStyle.drawPill(toolsHudText, centeredAt: CGPoint(x: bounds.midX, y: bounds.minY + 56), in: bounds)
            }
        }
        if showsToolbar {
            toolbar.draw(hovered: hoveredToolbarItem)
        }

        if let measurement {
            drawMeasurement(measurement)
        }

        guard let location = mouseLocation else { return }
        let isMeasuringGuides = isMeasureModifierHeld || isMeasuring
        if isMeasuringGuides || Defaults[.showSelectionGuides] {
            drawGuides(at: location, labelled: isMeasuringGuides)
        }
        switch magnifierSource {
        case .backdrop:
            if let backdrop {
                drawMagnifier(image: backdrop, pixelOrigin: .zero, at: location, context: context)
            }
        case .liveSample:
            if let liveSample, liveSample.displayID == displayID {
                drawMagnifier(image: liveSample.image, pixelOrigin: liveSample.pixelOrigin, at: location, context: context)
            } else {
                drawPositionPill(at: location)
            }
        case .position:
            drawPositionPill(at: location)
        case .pending, .hidden:
            break
        }
    }

    private func drawPositionPill(at location: CGPoint) {
        guard selection == nil, !isMeasureModifierHeld else { return }
        SelectionStyle.drawPill(DisplayCoordinates.label(for: location, in: bounds), near: CGPoint(x: location.x + 14, y: location.y - 34), in: bounds)
    }

    private func drawDimming(context: CGContext, holes: [CGRect]) {
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        SelectionStyle.dimColor.setFill()
        bounds.fill()
        context.setBlendMode(.clear)
        for hole in holes {
            context.fill(hole)
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawKeptRegions() {
        for region in keptRegions {
            let isHovered = session.hoveredRegionID == region.id
            let border = NSBezierPath(rect: region.rect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = isHovered ? 2 : 1
            (isHovered ? SelectionStyle.accentColor : SelectionStyle.borderColor).setStroke()
            border.stroke()
            guard let number = session.regions.number(of: region.id) else { continue }
            drawBadge(number: number, at: CGPoint(x: region.rect.minX, y: region.rect.maxY), highlighted: isHovered)
        }
    }

    private func drawBadge(number: Int, at corner: CGPoint, highlighted: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: "\(number)", attributes: attributes)
        let size = text.size()
        let side = max(22, size.width + 10)
        var frame = CGRect(x: corner.x + 6, y: corner.y - side - 6, width: side, height: 22)
        frame.origin.x = min(max(bounds.minX + 4, frame.origin.x), bounds.maxX - frame.width - 4)
        frame.origin.y = min(max(bounds.minY + 4, frame.origin.y), bounds.maxY - frame.height - 4)
        let path = NSBezierPath(roundedRect: frame, xRadius: 11, yRadius: 11)
        (highlighted ? SelectionStyle.accentColor : NSColor.black.withAlphaComponent(0.75)).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }

    private func selectionLabel(for selection: CGRect) -> String {
        let pixelSize = CGSize(width: (selection.width * scale).rounded(), height: (selection.height * scale).rounded())
        var label = "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        switch session.constraint {
        case .free:
            break
        case let .aspect(ratio):
            if !NSEvent.modifierFlags.contains(.shift) {
                label += " · \(ratio.label)"
            }
        case .fixed:
            label += " px"
            if scale != 1 {
                label += " · \(SelectionMeasurement.format(selection.width)) × \(SelectionMeasurement.format(selection.height)) pt"
            }
        }
        return label
    }

    private func drawSelection(_ selection: CGRect, dashed: Bool = false) {
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        if dashed {
            border.setLineDash([6, 4], count: 2, phase: 0)
        }
        SelectionStyle.borderColor.setStroke()
        border.stroke()
        SelectionStyle.drawPill(
            selectionLabel(for: selection),
            near: CGPoint(x: selection.minX, y: selection.maxY),
            in: bounds,
            above: selection.maxY + 32 < bounds.maxY
        )
    }

    private func drawLastRegionGhost(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        path.lineWidth = 1
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.55).setStroke()
        path.stroke()
    }

    private func drawGuides(at location: CGPoint, labelled: Bool) {
        let x = location.x.rounded(.down) + 0.5
        let y = location.y.rounded(.down) + 0.5
        let guides = NSBezierPath()
        guides.move(to: CGPoint(x: bounds.minX, y: y))
        guides.line(to: CGPoint(x: bounds.maxX, y: y))
        guides.move(to: CGPoint(x: x, y: bounds.minY))
        guides.line(to: CGPoint(x: x, y: bounds.maxY))
        guides.lineWidth = 1
        NSColor.black.withAlphaComponent(0.45).setStroke()
        guides.stroke()
        guides.setLineDash([4, 4], count: 2, phase: 0)
        SelectionStyle.accentColor.setStroke()
        guides.stroke()
        let source = magnifierSource
        if labelled, source != .backdrop, source != .liveSample, source != .pending {
            SelectionStyle.drawPill(DisplayCoordinates.label(for: location, in: bounds), near: CGPoint(x: location.x + 8, y: location.y + 4), in: bounds)
        }
    }

    private func drawMeasurement(_ measurement: SelectionMeasurement) {
        let line = NSBezierPath()
        line.move(to: measurement.start)
        line.line(to: measurement.end)
        line.lineCapStyle = .round
        line.lineWidth = 3
        NSColor.black.withAlphaComponent(0.5).setStroke()
        line.stroke()
        line.lineWidth = 1.5
        SelectionStyle.accentColor.setStroke()
        line.stroke()
        for point in [measurement.start, measurement.end] {
            let dot = NSBezierPath(ovalIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            NSColor.white.setFill()
            dot.fill()
            SelectionStyle.accentColor.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
        let midpoint = CGPoint(x: (measurement.start.x + measurement.end.x) / 2, y: (measurement.start.y + measurement.end.y) / 2)
        SelectionStyle.drawPill(measurement.label(scale: scale), centeredAt: CGPoint(x: midpoint.x, y: midpoint.y + 18), in: bounds)
    }

    private func drawMagnifier(image: CGImage, pixelOrigin: CGPoint, at location: CGPoint, context: CGContext) {
        let samples = CGFloat(MagnifierLayout.sampleCount)
        let half = floor(samples / 2)
        let side = MagnifierLayout.loupeSide
        let cell = side / samples
        let card = MagnifierLayout.cardFrame(for: location, in: bounds)
        let loupe = CGRect(x: card.minX, y: card.maxY - side, width: side, height: side)
        let displayPixel = DisplayCoordinates.pixel(for: location, in: bounds, scale: scale)
        let pixel = CGPoint(x: displayPixel.x - pixelOrigin.x, y: displayPixel.y - pixelOrigin.y)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let source = CGRect(x: pixel.x - half, y: pixel.y - half, width: samples, height: samples)
        let visible = source.intersection(imageBounds)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)

        context.saveGState()
        NSColor(white: 0.08, alpha: 0.94).setFill()
        cardPath.fill()
        cardPath.addClip()
        if !visible.isNull, let crop = image.cropping(to: visible) {
            context.interpolationQuality = .none
            let drawRect = CGRect(
                x: loupe.minX + (visible.minX - source.minX) * cell,
                y: loupe.minY + (source.maxY - visible.maxY) * cell,
                width: visible.width * cell,
                height: visible.height * cell
            )
            context.draw(crop, in: drawRect)
        }
        drawLoupeGrid(in: loupe, cell: cell, samples: Int(samples))
        let center = CGRect(x: loupe.minX + half * cell, y: loupe.minY + half * cell, width: cell, height: cell)
        let centerPath = NSBezierPath(rect: center.insetBy(dx: -0.5, dy: -0.5))
        centerPath.lineWidth = 2.5
        NSColor.black.withAlphaComponent(0.8).setStroke()
        centerPath.stroke()
        centerPath.lineWidth = 1.2
        NSColor.white.setStroke()
        centerPath.stroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: card.minX, y: loupe.minY))
        divider.line(to: CGPoint(x: card.maxX, y: loupe.minY))
        divider.lineWidth = 1
        NSColor.white.withAlphaComponent(0.25).setStroke()
        divider.stroke()
        context.restoreGState()

        let outline = NSBezierPath(roundedRect: card.insetBy(dx: 0.75, dy: 0.75), xRadius: 14, yRadius: 14)
        outline.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.8).setStroke()
        outline.stroke()

        let info = CGRect(x: card.minX, y: card.minY, width: card.width, height: MagnifierLayout.infoHeight)
        drawMagnifierInfo(in: info, location: location, color: ImageProcessing.pixelColor(of: image, at: pixel))
    }

    private func drawLoupeGrid(in loupe: CGRect, cell: CGFloat, samples: Int) {
        let grid = NSBezierPath()
        for index in 1 ..< samples {
            let offset = CGFloat(index) * cell
            grid.move(to: CGPoint(x: loupe.minX + offset, y: loupe.minY))
            grid.line(to: CGPoint(x: loupe.minX + offset, y: loupe.maxY))
            grid.move(to: CGPoint(x: loupe.minX, y: loupe.minY + offset))
            grid.line(to: CGPoint(x: loupe.maxX, y: loupe.minY + offset))
        }
        grid.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.18).setStroke()
        grid.stroke()
    }

    private func drawMagnifierInfo(in info: CGRect, location: CGPoint, color: CaptureColor?) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let primary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.75)]
        let coordinates = NSAttributedString(string: DisplayCoordinates.label(for: location, in: bounds), attributes: primary)
        let coordinatesSize = coordinates.size()
        coordinates.draw(at: CGPoint(x: info.minX + 12, y: info.midY - coordinatesSize.height / 2))

        guard let color else { return }
        let hex = NSAttributedString(string: color.hex, attributes: secondary)
        let hexSize = hex.size()
        let hexOrigin = CGPoint(x: info.maxX - 12 - hexSize.width, y: info.midY - hexSize.height / 2)
        hex.draw(at: hexOrigin)
        let swatch = CGRect(x: hexOrigin.x - 20, y: info.midY - 7, width: 14, height: 14)
        let swatchPath = NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3)
        NSColor(cgColor: color.cgColor)?.setFill()
        swatchPath.fill()
        swatchPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.6).setStroke()
        swatchPath.stroke()
    }
}
