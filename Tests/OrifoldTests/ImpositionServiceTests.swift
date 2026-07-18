import XCTest
@testable import Orifold

final class ImpositionServiceTests: XCTestCase {
    func testBookletPadsToMultipleOfFour() {
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 1).count, 4)   // 3 blanks
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 5).count, 8)
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 4).count, 4)
    }
    func testBookletFourPageSignatureOrder() {
        // 4 pages (0..3): outer sheet back = [3,0], inner = [1,2]
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 4), [3, 0, 1, 2])
    }
    func testBookletBlanksAreMinusOne() {
        // 2 pages -> padded to 4: pages 0,1 real; slots 2,3 blank
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 2), [-1, 0, 1, -1])
    }
    func testEveryRealPageAppearsExactlyOnce() {
        for n in 1...16 {
            let order = ImpositionService.bookletPageOrder(pageCount: n)
            let reals = order.filter { $0 >= 0 }.sorted()
            XCTAssertEqual(reals, Array(0..<n), "n=\(n)")
        }
    }
    func testNUpSheetCount() {
        XCTAssertEqual(ImpositionService.nUpSheetCount(pageCount: 5, perSheet: 4), 2)
        XCTAssertEqual(ImpositionService.nUpSheetCount(pageCount: 4, perSheet: 2), 2)
    }
}
