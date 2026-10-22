import Combine
import Foundation
import XCTest
@testable import Orifold

@MainActor
final class WorkspaceCommandRoutingTests: XCTestCase {
    private let commands: [Notification.Name] = [
        .orifoldToggleReaderMode,
        .orifoldToggleTableOfContents,
        .orifoldRequestDiscardClose,
        .orifoldRequestTranslation,
        .orifoldPrint,
        .orifoldPrintNUp,
        .orifoldCreateCommentFromSelection,
        .orifoldZoomIn,
        .orifoldZoomOut,
        .orifoldZoomFit,
        .orifoldZoomActualSize,
        .orifoldShowShortcuts,
    ]

    func testCommandsReachOnlyTheirTargetWorkspaceAfterFocusChanges() {
        let center = NotificationCenter()
        let first = WorkspaceViewModel(document: WorkspaceDocument())
        let second = WorkspaceViewModel(document: WorkspaceDocument())

        for command in commands {
            var firstCount = 0
            var secondCount = 0
            let firstReceiver = center.publisher(for: command, object: first).sink { _ in firstCount += 1 }
            let secondReceiver = center.publisher(for: command, object: second).sink { _ in secondCount += 1 }

            center.postWorkspaceCommand(command, to: first)
            XCTAssertEqual(firstCount, 1, command.rawValue)
            XCTAssertEqual(secondCount, 0, command.rawValue)

            center.postWorkspaceCommand(command, to: second)
            XCTAssertEqual(firstCount, 1, command.rawValue)
            XCTAssertEqual(secondCount, 1, command.rawValue)
            withExtendedLifetime((firstReceiver, secondReceiver)) {}
        }
    }

    func testMissingFocusedWorkspaceDoesNotBroadcast() {
        let center = NotificationCenter()
        for command in commands {
            var received = false
            let receiver = center.publisher(for: command).sink { _ in received = true }
            center.postWorkspaceCommand(command, to: nil)
            XCTAssertFalse(received, command.rawValue)
            withExtendedLifetime(receiver) {}
        }
    }

    func testViewModelZoomCommandsReachOnlyTheirOriginWorkspace() {
        let first = WorkspaceViewModel(document: WorkspaceDocument())
        let second = WorkspaceViewModel(document: WorkspaceDocument())
        let zoomCommands: [(Notification.Name, (WorkspaceViewModel) -> Void)] = [
            (.orifoldZoomIn, { $0.zoomIn() }),
            (.orifoldZoomOut, { $0.zoomOut() }),
            (.orifoldZoomFit, { $0.zoomFit() }),
            (.orifoldZoomActualSize, { $0.zoomActualSize() }),
        ]

        for (command, invoke) in zoomCommands {
            var firstCount = 0
            var secondCount = 0
            let firstReceiver = NotificationCenter.default.publisher(for: command, object: first)
                .sink { _ in firstCount += 1 }
            let secondReceiver = NotificationCenter.default.publisher(for: command, object: second)
                .sink { _ in secondCount += 1 }

            invoke(first)
            XCTAssertEqual(firstCount, 1, command.rawValue)
            XCTAssertEqual(secondCount, 0, command.rawValue)

            invoke(second)
            XCTAssertEqual(firstCount, 1, command.rawValue)
            XCTAssertEqual(secondCount, 1, command.rawValue)
            withExtendedLifetime((firstReceiver, secondReceiver)) {}
        }
    }

    func testWorkspaceReceiversIgnoreUnscopedCommands() {
        let center = NotificationCenter()
        let workspace = WorkspaceViewModel(document: WorkspaceDocument())
        for command in commands {
            var received = false
            let receiver = center.publisher(for: command, object: workspace).sink { _ in received = true }
            center.post(name: command, object: nil)
            XCTAssertFalse(received, command.rawValue)
            withExtendedLifetime(receiver) {}
        }
    }
}
