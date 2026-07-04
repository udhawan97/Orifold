import CoreGraphics
import Foundation
import PDFKit

enum PDFEncryptionService {
    private static let maxVerifiedTextBytes = 128 * 1024 * 1024

    static func encryptedData(from pdfData: Data, options: PDFEncryptionOptions) throws -> Data {
        try validate(options)
        guard let sourcePDF = PDFDocument(data: pdfData) else {
            throw PDFEncryptionError.cannotOpenSourcePDF
        }
        let shouldVerifyText = pdfData.count <= maxVerifiedTextBytes
        let expectedPageStrings = shouldVerifyText ? pageStrings(in: sourcePDF) : nil
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-encrypted-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let writeOptions: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: options.userPassword,
            .ownerPasswordOption: options.ownerPassword,
            PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsPrinting as String): options.allowsPrinting,
            PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsCopying as String): options.allowsCopying,
            PDFDocumentWriteOption(rawValue: kCGPDFContextEncryptionKeyLength as String): 128
        ]

        guard sourcePDF.write(to: tempURL, withOptions: writeOptions) else {
            throw PDFEncryptionError.writeFailed
        }
        let encrypted = try Data(contentsOf: tempURL)
        try validateEncryptedData(encrypted, options: options, expectedPageStrings: expectedPageStrings)
        return encrypted
    }

    static func validate(_ options: PDFEncryptionOptions) throws {
        guard !options.userPassword.isEmpty else {
            throw PDFEncryptionError.emptyUserPassword
        }
        guard !options.ownerPassword.isEmpty else {
            throw PDFEncryptionError.emptyOwnerPassword
        }
        guard options.ownerPassword != options.userPassword else {
            throw PDFEncryptionError.matchingOwnerAndUserPasswords
        }
    }

    static func validateEncryptedData(_ data: Data,
                                      options: PDFEncryptionOptions,
                                      expectedText: String? = nil,
                                      expectedPageStrings: [String]? = nil) throws {
        guard let encryptedPDF = PDFDocument(data: data) else {
            throw PDFEncryptionError.unreadableEncryptedOutput
        }
        guard encryptedPDF.isLocked else {
            throw PDFEncryptionError.unprotectedOutput
        }
        guard encryptedPDF.unlock(withPassword: options.userPassword) else {
            throw PDFEncryptionError.unlockFailed
        }
        guard encryptedPDF.allowsPrinting == options.allowsPrinting,
              encryptedPDF.allowsCopying == options.allowsCopying else {
            throw PDFEncryptionError.permissionsMismatch
        }
        if let expectedPageStrings {
            guard encryptedPDF.pageCount == expectedPageStrings.count else {
                throw PDFEncryptionError.textChanged
            }
            for pageIndex in 0..<encryptedPDF.pageCount {
                guard normalizedText(encryptedPDF.page(at: pageIndex)?.string ?? "") == normalizedText(expectedPageStrings[pageIndex]) else {
                    throw PDFEncryptionError.textChanged
                }
            }
        } else if let expectedText, normalizedText(encryptedPDF.string ?? "") != normalizedText(expectedText) {
            throw PDFEncryptionError.textChanged
        }
    }

    private static func pageStrings(in document: PDFDocument) -> [String] {
        (0..<document.pageCount).map { pageIndex in
            document.page(at: pageIndex)?.string ?? ""
        }
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
