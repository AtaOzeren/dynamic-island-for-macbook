/// One pixel of art, placed over a frame: how a blink or a bark is drawn on a
/// pose without copying the whole frame. The transparent key erases.
struct PetArtPixel {
    let column: Int
    let row: Int
    let key: Character
}

/// How a pet's frames are put together from shared blocks.
///
/// Frames share blocks wherever the pet holds part of itself still — the head
/// over a changing body, the body under a changing face — so a pose is drawn
/// once and every frame that holds it reads the same rows. A pet's art type
/// adopts this for the operations that combine them.
protocol PetArtComposer {
    /// Pixels across every frame, which is what an empty row spans.
    static var artWidth: Int { get }
}

extension PetArtComposer {
    typealias ArtPixel = PetArtPixel

    static func painting(_ rows: [String], _ pixels: [ArtPixel]) -> [String] {
        var grid = rows.map(Array.init)
        for pixel in pixels where grid.indices.contains(pixel.row) && grid[pixel.row].indices.contains(pixel.column) {
            grid[pixel.row][pixel.column] = pixel.key
        }
        return grid.map { String($0) }
    }

    /// `overlay`'s drawn pixels laid over `rows`, its top left at `column`,
    /// `row`: something the pet carries or wears, over the pose that carries it.
    static func stamping(_ overlay: [String], onto rows: [String], column: Int, row: Int) -> [String] {
        var pixels: [ArtPixel] = []
        for (rowOffset, line) in overlay.enumerated() {
            for (columnOffset, key) in line.enumerated() where key != PetSpriteSheet.transparentKey {
                pixels.append(ArtPixel(column: column + columnOffset, row: row + rowOffset, key: key))
            }
        }
        return painting(rows, pixels)
    }

    /// The same pose with what is drawn in `columns` of the top `topRows` rows
    /// a row lower: a nod, a chin dropped in thought, a swallow.
    static func lowering(_ rows: [String], columns: Range<Int>, topRows: Int) -> [String] {
        var grid = rows.map(Array.init)
        let head = grid.prefix(topRows).map { Array($0[columns]) }
        for row in 0..<topRows {
            for column in columns {
                grid[row][column] = PetSpriteSheet.transparentKey
            }
        }
        for (row, line) in head.enumerated() {
            for (offset, key) in line.enumerated() where key != PetSpriteSheet.transparentKey {
                grid[row + 1][columns.lowerBound + offset] = key
            }
        }
        return grid.map { String($0) }
    }

    /// Rows moved sideways by `columns` — negative is left — with what they
    /// leave behind empty.
    static func shifting(_ rows: [String], by columns: Int) -> [String] {
        let gap = String(repeating: PetSpriteSheet.transparentKey, count: abs(columns))
        return rows.map { row in
            columns < 0 ? String(row.dropFirst(-columns)) + gap : gap + String(row.dropLast(columns))
        }
    }

    static func emptyRows(_ count: Int) -> [String] {
        Array(repeating: String(repeating: PetSpriteSheet.transparentKey, count: artWidth), count: count)
    }
}
