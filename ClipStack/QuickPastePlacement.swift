import CoreGraphics

enum QuickPasteDirection: Equatable {
    case above
    case below
}

struct QuickPastePanelPlacement: Equatable {
    let frame: CGRect
    let direction: QuickPasteDirection

    static func make(
        anchor: CGRect,
        requestedSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        minimumHeight: CGFloat = 220
    ) -> QuickPastePanelPlacement {
        let width = min(requestedSize.width, visibleFrame.width)
        let availableBelow = max(0, anchor.minY - visibleFrame.minY)
        let availableAbove = max(0, visibleFrame.maxY - anchor.maxY)
        let requiredHeight = requestedSize.height + gap

        let direction: QuickPasteDirection
        if availableBelow >= requiredHeight {
            direction = .below
        } else if availableAbove >= requiredHeight {
            direction = .above
        } else {
            direction = availableBelow >= availableAbove ? .below : .above
        }

        let availableHeight = direction == .below ? availableBelow : availableAbove
        let safeMinimumHeight = min(minimumHeight, visibleFrame.height)
        let height = min(
            requestedSize.height,
            max(safeMinimumHeight, availableHeight - gap)
        )

        let widthOffsetToPointer = CGFloat(32)
        let idealX = anchor.midX - widthOffsetToPointer
        let x = min(
            max(idealX, visibleFrame.minX),
            visibleFrame.maxX - width
        )

        let idealY: CGFloat
        switch direction {
        case .below:
            idealY = anchor.minY - gap - height
        case .above:
            idealY = anchor.maxY + gap
        }

        let y = min(
            max(idealY, visibleFrame.minY),
            visibleFrame.maxY - height
        )

        return QuickPastePanelPlacement(
            frame: CGRect(x: x, y: y, width: width, height: height),
            direction: direction
        )
    }
}
