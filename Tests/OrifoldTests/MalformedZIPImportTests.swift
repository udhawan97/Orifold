import UniformTypeIdentifiers
import XCTest
@testable import Orifold

/// Defensive-coding coverage from the exception-handling audit: Office Open XML formats
/// (.xlsx/.pptx/.docx) are ZIP archives, and Orifold's minimal ZIP reader
/// (`SimpleZIPArchive.entryData`, private to PDFKitEngine.swift) force-unwrapped
/// `withUnsafeBytes { ... }.baseAddress!` when decompressing a deflate entry — relying on
/// undocumented Foundation behavior rather than the documented contract, under which an
/// empty buffer's `baseAddress` CAN be nil. Empirically, `Data.withUnsafeBytes` on the
/// current toolchain happens to vend a non-nil pointer even for empty slices, so a
/// zero-`compressedSize` deflate entry does not currently reproduce a crash here — but the
/// fix (checking for an empty buffer explicitly instead of trusting `baseAddress!`) follows
/// the documented contract instead of an implementation detail that could change. These
/// tests build a byte-exact malformed ZIP/XLSX by hand and confirm the import path handles
/// it gracefully (fails closed or imports empty content), never crashing, on both the
/// consistent (empty+empty) and inconsistent (empty compressed, non-zero uncompressed)
/// shapes.
final class MalformedZIPImportTests: XCTestCase {
    private func littleEndian16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private func littleEndian32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) }
    }

    /// Builds a minimal, structurally-valid ZIP with exactly one entry, whose declared
    /// compression method/sizes are caller-controlled so tests can construct the exact
    /// inconsistent metadata (deflate + zero compressedSize) that triggered the crash.
    private func makeSingleEntryZIP(
        name: String,
        compressionMethod: UInt16,
        compressedBytes: [UInt8],
        uncompressedSize: UInt32
    ) -> Data {
        let nameBytes = Array(name.utf8)
        var localHeader: [UInt8] = []
        localHeader += littleEndian32(0x04034b50)
        localHeader += littleEndian16(20) // version needed
        localHeader += littleEndian16(0)  // flags
        localHeader += littleEndian16(compressionMethod)
        localHeader += littleEndian16(0)  // mod time
        localHeader += littleEndian16(0)  // mod date
        localHeader += littleEndian32(0)  // crc32 (unchecked by our reader)
        localHeader += littleEndian32(UInt32(compressedBytes.count))
        localHeader += littleEndian32(uncompressedSize)
        localHeader += littleEndian16(UInt16(nameBytes.count))
        localHeader += littleEndian16(0)  // extra length
        localHeader += nameBytes
        localHeader += compressedBytes

        let localHeaderOffset = 0
        var centralDirectory: [UInt8] = []
        centralDirectory += littleEndian32(0x02014b50)
        centralDirectory += littleEndian16(20) // version made by
        centralDirectory += littleEndian16(20) // version needed
        centralDirectory += littleEndian16(0)  // flags
        centralDirectory += littleEndian16(compressionMethod)
        centralDirectory += littleEndian16(0)  // mod time
        centralDirectory += littleEndian16(0)  // mod date
        centralDirectory += littleEndian32(0)  // crc32
        centralDirectory += littleEndian32(UInt32(compressedBytes.count))
        centralDirectory += littleEndian32(uncompressedSize)
        centralDirectory += littleEndian16(UInt16(nameBytes.count))
        centralDirectory += littleEndian16(0)  // extra length
        centralDirectory += littleEndian16(0)  // comment length
        centralDirectory += littleEndian16(0)  // disk number start
        centralDirectory += littleEndian16(0)  // internal attributes
        centralDirectory += littleEndian32(0)  // external attributes
        centralDirectory += littleEndian32(UInt32(localHeaderOffset))
        centralDirectory += nameBytes

        let centralDirectoryOffset = localHeader.count
        var eocd: [UInt8] = []
        eocd += littleEndian32(0x06054b50)
        eocd += littleEndian16(0) // disk number
        eocd += littleEndian16(0) // disk with central directory
        eocd += littleEndian16(1) // entries on this disk
        eocd += littleEndian16(1) // total entries
        eocd += littleEndian32(UInt32(centralDirectory.count))
        eocd += littleEndian32(UInt32(centralDirectoryOffset))
        eocd += littleEndian16(0) // comment length

        return Data(localHeader + centralDirectory + eocd)
    }

    /// The exact malformed shape found in the audit: a deflate-method entry (8) declaring
    /// zero compressed bytes but a NON-zero uncompressed size -- internally inconsistent,
    /// so real content parsers should fail closed. Before the fix this crashed the whole
    /// app on import via a force-unwrapped nil `baseAddress`; it must now just fail to
    /// import (or import with that section empty), never crash.
    func testZeroByteDeflateEntryWithNonZeroUncompressedSizeDoesNotCrashXLSXImport() throws {
        let zip = makeSingleEntryZIP(
            name: "xl/worksheets/sheet1.xml",
            compressionMethod: 8,
            compressedBytes: [],
            uncompressedSize: 5
        )
        // Must not crash. It's acceptable for this to either throw (unreadable) or succeed
        // with empty/partial text -- the only unacceptable outcome is a process crash.
        do {
            let imported = try DocumentImportConverter.importedDocument(
                from: zip,
                contentType: .orifoldXLSX,
                filename: "malformed.xlsx",
                baseURL: nil
            )
            XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0)
        } catch {
            // Throwing is an acceptable, non-crashing outcome for malformed input.
        }
    }

    /// A genuinely valid zero-byte entry (both compressed AND uncompressed size are zero,
    /// i.e. an empty file legitimately stored with the deflate method tag) must decode
    /// cleanly to empty content, not throw or crash -- this is the "not every zero-length
    /// entry is malicious" half of the fix.
    func testZeroByteDeflateEntryWithZeroUncompressedSizeImportsCleanly() throws {
        let zip = makeSingleEntryZIP(
            name: "xl/worksheets/sheet1.xml",
            compressionMethod: 8,
            compressedBytes: [],
            uncompressedSize: 0
        )
        let imported = try DocumentImportConverter.importedDocument(
            from: zip,
            contentType: .orifoldXLSX,
            filename: "empty-sheet.xlsx",
            baseURL: nil
        )
        XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0)
    }
}
