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
            return "Orifold could not sanitize this PDF. Export without \"Sanitize for sharing,\" or try again."
        }
    }
}

enum PDFCompressionPreset: String, CaseIterable, Identifiable, Equatable {
    case balanced
    case small

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .small: return "Small"
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
            return "Orifold could not read this PDF for file-size reduction. Reopen the document and try again."
        case .writeFailed:
            return "Orifold could not create the reduced PDF. Check the destination and try again."
        case .validationFailed:
            return "Orifold could not verify the reduced PDF. Try exporting without reducing file size."
        case .textChanged:
            return "Orifold could not verify the reduced PDF text. Try exporting without reducing file size."
        case .grewLarger:
            return "This PDF is already optimized. The reduced copy would not be smaller."
        case .cancelled:
            return "File-size reduction was cancelled. No file was written."
        case .pdfiumRewriteFailed:
            return "Orifold could not safely rewrite the images in this PDF. Try exporting without reducing file size."
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
            return "Password is missing. Enter a password before exporting the protected PDF."
        case .emptyOwnerPassword:
            return "Orifold could not prepare password protection. Try exporting again."
        case .matchingOwnerAndUserPasswords:
            return "Orifold could not apply PDF permissions because the owner and user passwords matched. Try exporting again."
        case .digitalSignatureConflict:
            return "Password protection is unavailable because this PDF has a digital signature. Remove the signature, or export without password protection."
        case .cannotOpenSourcePDF:
            return "Orifold could not open the final PDF for password protection. Export without password protection, or try again."
        case .writeFailed:
            return "Orifold could not write the protected PDF. Check the destination and try again."
        case .unprotectedOutput:
            return "Orifold could not verify password protection. Try exporting again."
        case .unreadableEncryptedOutput:
            return "Orifold could not verify the protected PDF. Try exporting again."
        case .unlockFailed:
            return "Orifold could not unlock the protected PDF during verification. Try exporting again."
        case .permissionsMismatch:
            return "Orifold could not verify the protected PDF permissions. Try exporting again."
        case .textChanged:
            return "Orifold could not verify the protected PDF text. Try exporting again."
        }
    }
}
