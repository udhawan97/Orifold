import CQPDF
import Foundation

extension QPDFService {
    /// Extracts AcroForm signature dictionaries without reserializing the PDF. The returned
    /// byte ranges and binary `/Contents` strings are copied while qpdf owns the handles, so
    /// the validation layer can perform byte-exact checks after this call returns.
    static func signatureDictionaries(in data: Data) -> [QPDFSignatureDictionary] {
        withQPDF(data, description: "signature-dictionaries") { qpdf in
            let root = qpdf_get_root(qpdf)
            guard hasKey(qpdf, root, "/AcroForm") else { return [] }
            let form = qpdf_oh_get_key(qpdf, root, "/AcroForm")
            guard hasKey(qpdf, form, "/Fields") else { return [] }

            var state = SignatureCollectionState()
            collectSignatures(
                from: qpdf_oh_get_key(qpdf, form, "/Fields"),
                inheritedFieldType: nil,
                in: qpdf,
                state: &state,
                depth: 0
            )
            return state.signatures
        } ?? []
    }

    private struct SignatureCollectionState {
        var signatures: [QPDFSignatureDictionary] = []
        var visitedFields = Set<String>()
        var visitedSignatures = Set<String>()
    }

    private static func collectSignatures(
        from fields: qpdf_oh,
        inheritedFieldType: String?,
        in qpdf: qpdf_data,
        state: inout SignatureCollectionState,
        depth: Int
    ) {
        guard depth < 64, qpdf_oh_is_array(qpdf, fields) != QPDF_FALSE else { return }
        let count = qpdf_oh_get_array_n_items(qpdf, fields)
        guard count > 0 else { return }
        for index in 0..<count {
            let field = qpdf_oh_get_array_item(qpdf, fields, index)
            if let identity = signatureIndirectIdentity(field, in: qpdf),
               !state.visitedFields.insert(identity).inserted {
                continue
            }

            let fieldType = hasKey(qpdf, field, "/FT")
                ? signatureNameValue(qpdf, qpdf_oh_get_key(qpdf, field, "/FT"))
                : inheritedFieldType
            if hasKey(qpdf, field, "/V") {
                let value = qpdf_oh_get_key(qpdf, field, "/V")
                if fieldType == "Sig" || hasKey(qpdf, value, "/ByteRange"),
                   let signature = signatureDictionary(value, field: field, in: qpdf),
                   state.visitedSignatures.insert(signature.id).inserted {
                    state.signatures.append(signature)
                }
            }

            if hasKey(qpdf, field, "/Kids") {
                collectSignatures(
                    from: qpdf_oh_get_key(qpdf, field, "/Kids"),
                    inheritedFieldType: fieldType,
                    in: qpdf,
                    state: &state,
                    depth: depth + 1
                )
            }
        }
    }

    private static func signatureDictionary(_ dictionary: qpdf_oh,
                                            field: qpdf_oh,
                                            in qpdf: qpdf_data) -> QPDFSignatureDictionary? {
        guard qpdf_oh_is_dictionary(qpdf, dictionary) != QPDF_FALSE else { return nil }
        let objectIdentity = signatureIndirectIdentity(dictionary, in: qpdf)
            ?? signatureIndirectIdentity(field, in: qpdf)
            ?? "direct-signature-\(qpdf_oh_get_object_id(qpdf, field))"
        return QPDFSignatureDictionary(
            id: objectIdentity,
            byteRange: signatureByteRange(
                qpdf,
                hasKey(qpdf, dictionary, "/ByteRange")
                    ? qpdf_oh_get_key(qpdf, dictionary, "/ByteRange")
                    : qpdf_oh()
            ),
            contents: hasKey(qpdf, dictionary, "/Contents")
                ? signatureBinaryValue(qpdf, qpdf_oh_get_key(qpdf, dictionary, "/Contents"))
                : nil,
            signerName: hasKey(qpdf, dictionary, "/Name")
                ? signatureUTF8Value(qpdf, qpdf_oh_get_key(qpdf, dictionary, "/Name"))
                : nil,
            signingTime: hasKey(qpdf, dictionary, "/M")
                ? signatureUTF8Value(qpdf, qpdf_oh_get_key(qpdf, dictionary, "/M")).flatMap(pdfDate)
                : nil
        )
    }

    private static func signatureIndirectIdentity(_ object: qpdf_oh,
                                                  in qpdf: qpdf_data) -> String? {
        let objectID = qpdf_oh_get_object_id(qpdf, object)
        guard objectID > 0 else { return nil }
        return "\(objectID)-\(qpdf_oh_get_generation(qpdf, object))"
    }

    private static func signatureByteRange(_ qpdf: qpdf_data,
                                           _ array: qpdf_oh) -> SignatureByteRange? {
        guard qpdf_oh_is_array(qpdf, array) != QPDF_FALSE,
              qpdf_oh_get_array_n_items(qpdf, array) == 4 else { return nil }
        var values: [Int] = []
        values.reserveCapacity(4)
        for index in 0..<4 {
            let item = qpdf_oh_get_array_item(qpdf, array, numericCast(index))
            guard qpdf_oh_is_integer(qpdf, item) != QPDF_FALSE,
                  let value = Int(exactly: qpdf_oh_get_int_value(qpdf, item)),
                  value >= 0 else { return nil }
            values.append(value)
        }
        return SignatureByteRange(
            beforeOffset: values[0],
            beforeLength: values[1],
            afterOffset: values[2],
            afterLength: values[3]
        )
    }

    private static func signatureBinaryValue(_ qpdf: qpdf_data, _ object: qpdf_oh) -> Data? {
        var raw: UnsafePointer<CChar>?
        var length = 0
        guard qpdf_oh_get_value_as_string(qpdf, object, &raw, &length) == QPDF_TRUE,
              let raw, length > 0 else { return nil }
        return raw.withMemoryRebound(to: UInt8.self, capacity: length) {
            Data(bytes: $0, count: length)
        }
    }

    private static func signatureUTF8Value(_ qpdf: qpdf_data, _ object: qpdf_oh) -> String? {
        var raw: UnsafePointer<CChar>?
        var length = 0
        guard qpdf_oh_get_value_as_utf8(qpdf, object, &raw, &length) == QPDF_TRUE,
              let raw, length > 0 else { return nil }
        return raw.withMemoryRebound(to: UInt8.self, capacity: length) {
            String(bytes: UnsafeBufferPointer(start: $0, count: length), encoding: .utf8)
        }
    }

    private static func signatureNameValue(_ qpdf: qpdf_data, _ object: qpdf_oh) -> String? {
        var raw: UnsafePointer<CChar>?
        var length = 0
        guard qpdf_oh_get_value_as_name(qpdf, object, &raw, &length) == QPDF_TRUE,
              let raw, length > 0 else { return nil }
        guard var value = raw.withMemoryRebound(to: UInt8.self, capacity: length, {
            String(bytes: UnsafeBufferPointer(start: $0, count: length), encoding: .utf8)
        }) else { return nil }
        if value.hasPrefix("/") { value.removeFirst() }
        return value.isEmpty ? nil : value
    }

    private static func pdfDate(_ value: String) -> Date? {
        var raw = value
        if raw.hasPrefix("D:") { raw.removeFirst(2) }
        guard raw.count >= 14 else { return nil }
        let timestamp = String(raw.prefix(14))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        guard var date = formatter.date(from: timestamp) else { return nil }

        let suffix = raw.dropFirst(14)
        if let sign = suffix.first, sign == "+" || sign == "-" {
            let digits = suffix.dropFirst().filter(\.isNumber)
            if digits.count >= 4,
               let hours = Int(digits.prefix(2)),
               let minutes = Int(digits.dropFirst(2).prefix(2)) {
                let offset = TimeInterval((hours * 60 + minutes) * 60)
                date.addTimeInterval(sign == "+" ? -offset : offset)
            }
        }
        return date
    }
}
