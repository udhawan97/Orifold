import PDFKit
import XCTest
@testable import Orifold

/// What `PDFOutlineReader` does with outline nodes it cannot use.
///
/// A node is unresolvable when its label is blank or its destination points at a page the
/// document no longer contains. Such a node is not drawn, but its children may be perfectly
/// good, so they are *promoted* to the level the dropped node would have occupied.
///
/// Promotion is the reason this file exists. It re-descends at the SAME display depth by
/// design, which means `maximumDepth` cannot advance along a run of unresolvable nodes; and
/// because nothing is emitted for them, `maximumNodeCount` cannot advance either. Both of
/// those caps measure what the walk *emits*, and an unresolvable node emits nothing while
/// still costing work — so bounding it takes caps that measure the walk itself:
/// `maximumTraversalDepth` for how deep it goes, `maximumTraversalSteps` for how much it
/// does. The last two tests here are one per axis, deep and wide.
final class PDFOutlinePromotionTests: XCTestCase {

    func testPromotesChildrenOfAnUnresolvableNodeToTheDepthItWouldHaveOccupied() throws {
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 4,
            outline: [
                .init(title: "Chapter", page: 0, children: [
                    .init(title: "   ", page: 1, children: [
                        .init(title: "Promoted A", page: 2),
                        .init(title: "Promoted B", page: 3)
                    ])
                ])
            ]
        )

        let nodes = PDFOutlineReader.nodes(in: pdf)

        // The blank node is never drawn, so its children must occupy the row it would
        // have taken. Indenting them under a parent that was dropped would leave the tree
        // claiming a level the user cannot see.
        XCTAssertEqual(nodes.map(\.title), ["Chapter", "Promoted A", "Promoted B"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 1])
        // "Chapter" still has emitted descendants, so its disclosure control stays.
        XCTAssertEqual(nodes.map(\.hasChildren), [true, false, false])
    }

    func testPromotesThroughAChainOfUnresolvableNodesWellInsideTheTraversalCap() throws {
        // Promotion may skip many levels in a row, so a bookmark buried under a chain
        // shorter than the cap must still surface — at depth 0, since none of the nodes
        // above it were drawn. Guards the cap against being set so tight that it swallows
        // recoverable bookmarks.
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 1,
            outline: [
                OutlineFixturePDFBuilder.unresolvableChain(
                    wrappers: PDFOutlineReader.maximumTraversalDepth / 2,
                    around: "Buried"
                )
            ]
        )

        let nodes = PDFOutlineReader.nodes(in: pdf)

        XCTAssertEqual(nodes.map(\.title), ["Buried"])
        XCTAssertEqual(nodes.map(\.depth), [0])
    }

    func testStopsWalkingAChainOfUnresolvableNodesThatOutrunsTheTraversalCap() throws {
        // Reaching the bookmark at the bottom is the failure: it can only be reached by
        // recursing once per wrapper, which is exactly the unbounded descent the cap
        // exists to stop.
        //
        // PDFKit really will hand over a chain like this. It materialises each level as a
        // distinct PDFOutline on demand and only refuses to re-enter a node already on the
        // path it is walking, so it truncates genuine `/Outlines` cycles but passes deep
        // finite nesting straight through, tens of thousands of levels deep.
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(
            pageCount: 1,
            outline: [
                OutlineFixturePDFBuilder.unresolvableChain(
                    wrappers: PDFOutlineReader.maximumTraversalDepth + 50,
                    around: "Buried"
                )
            ]
        )

        let nodes = PDFOutlineReader.nodes(in: pdf)

        XCTAssertTrue(
            nodes.isEmpty,
            "traversal must stop inside the chain rather than recurse to the bookmark below it"
        )
    }

    func testStopsWalkingAWideFanOutOfUnresolvableSiblings() throws {
        // The same blind spot on the other axis. `maximumNodeCount` counts what was
        // emitted, so a run of siblings that all fail to resolve advances it by nothing
        // and is iterated in full. No depth cap can help here — this tree is one level
        // deep and still unbounded.
        //
        // The resolvable bookmark sits at the far end, so emitting it is proof the whole
        // fan-out was walked.
        let overBudget = PDFOutlineReader.maximumTraversalSteps + 50
        var outline = (0..<overBudget).map { _ in OutlineFixturePDFBuilder.Spec(title: "", page: 0) }
        outline.append(OutlineFixturePDFBuilder.Spec(title: "Last", page: 0))
        let pdf = OutlineFixturePDFBuilder.outlinedPDF(pageCount: 1, outline: outline)

        let nodes = PDFOutlineReader.nodes(in: pdf)

        XCTAssertTrue(
            nodes.isEmpty,
            "traversal must stop inside the fan-out rather than examine every sibling to reach the end"
        )
    }
}
