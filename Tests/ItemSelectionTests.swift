@testable import ClipStack
import XCTest

final class ItemSelectionTests: XCTestCase {
    private struct TestItem: Equatable {
        let id: Int
        let value: String
    }

    func testInactiveSelectionIgnoresToggles() {
        var selection = ItemSelection<Int>()

        selection.toggle(1)

        XCTAssertFalse(selection.contains(1))
        XCTAssertEqual(selection.count, 0)
    }

    func testToggleSelectsAndDeselectsWhileActive() {
        var selection = ItemSelection<Int>()
        selection.setActive(true)

        selection.toggle(1)
        XCTAssertTrue(selection.contains(1))

        selection.toggle(1)
        XCTAssertFalse(selection.contains(1))
    }

    func testLeavingSelectionModeClearsSelection() {
        var selection = ItemSelection<Int>()
        selection.setActive(true)
        selection.selectAll([1, 2, 3])

        selection.setActive(false)

        XCTAssertFalse(selection.isActive)
        XCTAssertEqual(selection.count, 0)
    }

    func testReconcileDropsItemsThatAreNoLongerAvailable() {
        var selection = ItemSelection<Int>()
        selection.setActive(true)
        selection.selectAll([1, 2, 3])

        selection.reconcile(withAvailableIDs: [2, 3, 4])

        XCTAssertEqual(selection.selectedIDs, Set([2, 3]))
    }

    func testSelectedItemsPreserveSourceOrdering() {
        let items = [
            TestItem(id: 1, value: "first"),
            TestItem(id: 2, value: "second"),
            TestItem(id: 3, value: "third")
        ]
        var selection = ItemSelection<Int>()
        selection.setActive(true)
        selection.selectAll([3, 1])

        let selectedItems = selection.selectedItems(from: items, id: \.id)

        XCTAssertEqual(selectedItems.map(\.id), [1, 3])
    }

    func testDraggingSelectedItemIncludesEntireSelectionInSourceOrder() {
        let items = [
            TestItem(id: 1, value: "first"),
            TestItem(id: 2, value: "second"),
            TestItem(id: 3, value: "third")
        ]
        var selection = ItemSelection<Int>()
        selection.setActive(true)
        selection.selectAll([1, 3])

        let draggedItems = selection.dragItems(startingWith: 3, from: items, id: \.id)

        XCTAssertEqual(draggedItems.map(\.id), [1, 3])
    }

    func testDraggingUnselectedItemIncludesOnlyThatItem() {
        let items = [
            TestItem(id: 1, value: "first"),
            TestItem(id: 2, value: "second"),
            TestItem(id: 3, value: "third")
        ]
        var selection = ItemSelection<Int>()
        selection.setActive(true)
        selection.selectAll([1, 3])

        let draggedItems = selection.dragItems(startingWith: 2, from: items, id: \.id)

        XCTAssertEqual(draggedItems.map(\.id), [2])
    }
}
