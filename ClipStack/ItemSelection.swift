import AppKit
import SwiftUI

struct ItemSelection<ID: Hashable> {
    private(set) var isActive = false
    private(set) var selectedIDs = Set<ID>()

    var count: Int {
        selectedIDs.count
    }

    mutating func setActive(_ isActive: Bool) {
        self.isActive = isActive
        if !isActive {
            selectedIDs.removeAll()
        }
    }

    mutating func toggle(_ id: ID) {
        guard isActive else {
            return
        }

        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    mutating func selectAll<S: Sequence>(_ ids: S) where S.Element == ID {
        guard isActive else {
            return
        }

        selectedIDs = Set(ids)
    }

    mutating func reconcile<S: Sequence>(withAvailableIDs ids: S) where S.Element == ID {
        selectedIDs.formIntersection(Set(ids))
    }

    func contains(_ id: ID) -> Bool {
        selectedIDs.contains(id)
    }

    func selectedItems<Item>(from items: [Item], id: KeyPath<Item, ID>) -> [Item] {
        items.filter { selectedIDs.contains($0[keyPath: id]) }
    }

    func dragItems<Item>(startingWith draggedID: ID, from items: [Item], id: KeyPath<Item, ID>) -> [Item] {
        guard isActive, selectedIDs.contains(draggedID) else {
            return items.filter { $0[keyPath: id] == draggedID }
        }

        return selectedItems(from: items, id: id)
    }
}

struct ItemDragPayload {
    let writer: NSPasteboardWriting
    let preview: NSImage
}

struct MultiItemDragSource: NSViewRepresentable {
    let payloads: () -> [ItemDragPayload]
    let onClick: () -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.payloads = payloads
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.payloads = payloads
        nsView.onClick = onClick
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var payloads: () -> [ItemDragPayload] = { [] }
    var onClick: () -> Void = {}

    private var mouseDownLocation: NSPoint?
    private var didBeginDragging = false

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        didBeginDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDragging,
              let mouseDownLocation,
              hypot(
                convert(event.locationInWindow, from: nil).x - mouseDownLocation.x,
                convert(event.locationInWindow, from: nil).y - mouseDownLocation.y
              ) >= 4 else {
            return
        }

        let payloads = payloads()
        guard !payloads.isEmpty else {
            return
        }

        didBeginDragging = true
        let dragOrigin = convert(event.locationInWindow, from: nil)
        let draggingItems = payloads.enumerated().map { index, payload in
            let item = NSDraggingItem(pasteboardWriter: payload.writer)
            let stackOffset = CGFloat(min(index, 5)) * 3
            let frame = NSRect(
                x: dragOrigin.x - 22 + stackOffset,
                y: dragOrigin.y - 22 - stackOffset,
                width: 44,
                height: 44
            )
            item.setDraggingFrame(frame, contents: payload.preview)
            return item
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginDragging {
            onClick()
        }

        mouseDownLocation = nil
        didBeginDragging = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        mouseDownLocation = nil
        didBeginDragging = false
    }
}

struct RoundSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 22, height: 46)
            .contentShape(Circle())
            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }
}
