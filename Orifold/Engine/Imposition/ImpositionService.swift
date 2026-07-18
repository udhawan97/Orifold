// Pure page-order math for imposition. Deliberately free of PDFium/Foundation imports so it stays
// a fast, deterministic unit — the PDFium byte-level work lives in `PDFImpositionEngine`.

/// How exported pages are laid out onto physical sheets.
enum ImpositionLayout: Equatable {
    /// Saddle-stitch booklet: 2-up, auto-padded to a multiple of 4, folio page order.
    case booklet
    /// Sequential grid, `rows` x `cols` source pages per output sheet (2x1, 2x2, 3x3, …).
    case nUp(rows: Int, cols: Int)
}

enum ImpositionService {
    /// 0-indexed source page order for a saddle-stitch booklet, padded to a multiple of 4.
    /// `-1` marks an intentional blank. Per physical side the order is [last, first], then
    /// [second, second-last], walking inward — so a folded, stapled stack reads front-to-back.
    static func bookletPageOrder(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let padded = ((pageCount + 3) / 4) * 4        // ceil(n/4) * 4
        var order: [Int] = []
        order.reserveCapacity(padded)
        var left = padded - 1
        var right = 0
        while right < left {
            order.append(left)        // outer side, verso
            order.append(right)       // outer side, recto
            order.append(right + 1)   // inner side, verso
            order.append(left - 1)    // inner side, recto
            left -= 2
            right += 2
        }
        // Padding slots (indices past the real page count) become intentional blanks.
        return order.map { $0 >= pageCount ? -1 : $0 }
    }

    /// Number of output sheets an N-up grid needs, i.e. ceil(pageCount / perSheet).
    static func nUpSheetCount(pageCount: Int, perSheet: Int) -> Int {
        guard perSheet > 0, pageCount > 0 else { return 0 }
        return (pageCount + perSheet - 1) / perSheet
    }
}
