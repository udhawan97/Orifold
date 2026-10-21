import Foundation
import XCTest

/// Independently serialized qpdf outputs update the second trailer /ID using the
/// current time. Ignore only that hex value; retain the original ID and every
/// other byte so preservation assertions still detect content or catalog drift.
func pdfIgnoringUpdatedDocumentID(_ data: Data) throws -> Data {
    let trailer = try XCTUnwrap(data.range(of: Data("trailer".utf8), options: .backwards))
    // Fixture trailers must be ASCII, making UTF-16 regex offsets byte offsets.
    let tail = try XCTUnwrap(String(data: data[trailer.lowerBound...], encoding: .ascii))
    let pattern = try NSRegularExpression(pattern: #"/ID\s*\[\s*<[0-9a-fA-F]+>\s*<([0-9a-fA-F]+)>\s*\]"#)
    let match = try XCTUnwrap(pattern.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)))
    let value = match.range(at: 1)
    var result = data
    result.replaceSubrange((trailer.lowerBound + value.location)..<(trailer.lowerBound + value.location + value.length),
                           with: repeatElement(UInt8(ascii: "0"), count: value.length))
    return result
}
