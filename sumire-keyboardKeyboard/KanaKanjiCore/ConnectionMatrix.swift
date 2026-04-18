import Foundation

public struct ConnectionMatrix: Sendable {
    private enum Storage: Sendable {
        case costs([Int])
        case bigEndianInt16Data(Data)
    }

    private let dimension: Int
    private let storage: Storage

    public init(costs: [Int]) throws {
        guard !costs.isEmpty else {
            self.dimension = 0
            self.storage = .costs([])
            return
        }

        let root = Int(Double(costs.count).squareRoot().rounded())
        guard root > 0, root * root == costs.count else {
            throw KanaKanjiError.connectionMatrixIsNotSquare(URL(fileURLWithPath: "<memory>"), count: costs.count)
        }

        self.dimension = root
        self.storage = .costs(costs)
    }

    private init(bigEndianInt16Data data: Data, dimension: Int) {
        self.dimension = dimension
        self.storage = .bigEndianInt16Data(data)
    }

    public static func loadText(
        _ fileURL: URL,
        skipFirstLine: Bool = true
    ) throws -> ConnectionMatrix {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KanaKanjiError.dictionaryNotFound(fileURL)
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if skipFirstLine, !lines.isEmpty {
            lines.removeFirst()
        }

        var values: [Int] = []
        values.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            guard let value = Int(trimmed) else {
                continue
            }
            values.append(value)
        }

        guard !values.isEmpty else {
            throw KanaKanjiError.connectionMatrixIsEmpty(fileURL)
        }

        let root = Int(Double(values.count).squareRoot().rounded())
        guard root > 0, root * root == values.count else {
            throw KanaKanjiError.connectionMatrixIsNotSquare(fileURL, count: values.count)
        }

        return try ConnectionMatrix(costs: values)
    }

    public static func loadBinaryBigEndianInt16(_ fileURL: URL) throws -> ConnectionMatrix {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KanaKanjiError.dictionaryNotFound(fileURL)
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let valueCount = data.count / 2

        guard valueCount > 0 else {
            throw KanaKanjiError.connectionMatrixIsEmpty(fileURL)
        }

        let root = Int(Double(valueCount).squareRoot().rounded())
        guard data.count.isMultiple(of: 2), root > 0, root * root == valueCount else {
            throw KanaKanjiError.connectionMatrixIsNotSquare(fileURL, count: valueCount)
        }

        return ConnectionMatrix(bigEndianInt16Data: data, dimension: root)
    }

    public func cost(previousLeftId: Int, currentRightId: Int) -> Int {
        guard dimension > 0,
              previousLeftId >= 0,
              currentRightId >= 0,
              previousLeftId < dimension,
              currentRightId < dimension else {
            return 0
        }

        let valueIndex = previousLeftId * dimension + currentRightId

        switch storage {
        case let .costs(costs):
            guard valueIndex < costs.count else {
                return 0
            }
            return costs[valueIndex]
        case let .bigEndianInt16Data(data):
            let byteOffset = valueIndex * 2
            guard byteOffset + 1 < data.count else {
                return 0
            }

            let firstIndex = data.index(data.startIndex, offsetBy: byteOffset)
            let secondIndex = data.index(after: firstIndex)
            let raw = UInt16(data[firstIndex]) << 8 | UInt16(data[secondIndex])
            return Int(Int16(bitPattern: raw))
        }
    }
}
