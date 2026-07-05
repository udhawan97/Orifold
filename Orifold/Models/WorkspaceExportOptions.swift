import Foundation

struct WorkspaceExportOptions: Equatable {
    var encryption: PDFEncryptionOptions?
    var lockFormAnswers: Bool
    var compressionPreset: PDFCompressionPreset?
    var embedsEditableWorkspaceState: Bool
    var sanitization: PDFSanitizationOptions?

    init(encryption: PDFEncryptionOptions? = nil,
         lockFormAnswers: Bool = false,
         compressionPreset: PDFCompressionPreset? = nil,
         embedsEditableWorkspaceState: Bool = false,
         sanitization: PDFSanitizationOptions? = nil) {
        self.encryption = encryption
        self.lockFormAnswers = lockFormAnswers
        self.compressionPreset = compressionPreset
        self.embedsEditableWorkspaceState = embedsEditableWorkspaceState
        self.sanitization = sanitization
    }
}

struct PDFSanitizationOptions: Equatable {
    var removesMetadata: Bool

    init(removesMetadata: Bool = false) {
        self.removesMetadata = removesMetadata
    }
}

enum PDFSanitizationError: Error, Equatable {
    case sanitizationFailed

    var userMessage: String {
        switch self {
        case .sanitizationFailed:
            return L10n.string("error.sanitization.failed")
        }
    }
}

enum PDFCompressionPreset: String, CaseIterable, Identifiable, Equatable {
    case balanced
    case small

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: return L10n.string("pdfCompressionPreset.balanced.label")
        case .small: return L10n.string("pdfCompressionPreset.small.label")
        }
    }

    var dpiCap: Int {
        switch self {
        case .balanced: return 150
        case .small: return 100
        }
    }

    var jpegQuality: Double {
        switch self {
        case .balanced: return 0.7
        case .small: return 0.5
        }
    }
}

struct PDFCompressionResult: Equatable {
    var data: Data
    var originalByteCount: Int
    var compressedByteCount: Int

    var percentSmaller: Int {
        guard originalByteCount > 0 else { return 0 }
        let reduction = 1.0 - (Double(compressedByteCount) / Double(originalByteCount))
        return max(0, Int((reduction * 100).rounded()))
    }
}

enum PDFCompressionError: LocalizedError, Equatable {
    case invalidPDF
    case writeFailed
    case validationFailed
    case textChanged
    case grewLarger
    case cancelled
    case pdfiumRewriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return L10n.string("error.compression.invalidPDF")
        case .writeFailed:
            return L10n.string("error.compression.writeFailed")
        case .validationFailed:
            return L10n.string("error.compression.validationFailed")
        case .textChanged:
            return L10n.string("error.compression.textChanged")
        case .grewLarger:
            return L10n.string("error.compression.grewLarger")
        case .cancelled:
            return L10n.string("error.compression.cancelled")
        case .pdfiumRewriteFailed:
            return L10n.string("error.compression.pdfiumRewriteFailed")
        }
    }
}

struct PDFEncryptionOptions: Codable, Equatable {
    var userPassword: String
    var ownerPassword: String
    var allowsPrinting: Bool
    var allowsCopying: Bool

    init(userPassword: String,
         ownerPassword: String,
         allowsPrinting: Bool = true,
         allowsCopying: Bool = true) {
        self.userPassword = userPassword
        self.ownerPassword = ownerPassword
        self.allowsPrinting = allowsPrinting
        self.allowsCopying = allowsCopying
    }
}

enum PDFEncryptionError: Error, Equatable {
    case emptyUserPassword
    case emptyOwnerPassword
    case matchingOwnerAndUserPasswords
    case digitalSignatureConflict
    case cannotOpenSourcePDF
    case writeFailed
    case unprotectedOutput
    case unreadableEncryptedOutput
    case unlockFailed
    case permissionsMismatch
    case textChanged

    var userMessage: String {
        switch self {
        case .emptyUserPassword:
            return L10n.string("error.encryption.emptyUserPassword")
        case .emptyOwnerPassword:
            return L10n.string("error.encryption.emptyOwnerPassword")
        case .matchingOwnerAndUserPasswords:
            return L10n.string("error.encryption.matchingOwnerAndUserPasswords")
        case .digitalSignatureConflict:
            return L10n.string("error.encryption.digitalSignatureConflict")
        case .cannotOpenSourcePDF:
            return L10n.string("error.encryption.cannotOpenSourcePDF")
        case .writeFailed:
            return L10n.string("error.encryption.writeFailed")
        case .unprotectedOutput:
            return L10n.string("error.encryption.unprotectedOutput")
        case .unreadableEncryptedOutput:
            return L10n.string("error.encryption.unreadableEncryptedOutput")
        case .unlockFailed:
            return L10n.string("error.encryption.unlockFailed")
        case .permissionsMismatch:
            return L10n.string("error.encryption.permissionsMismatch")
        case .textChanged:
            return L10n.string("error.encryption.textChanged")
        }
    }
}
