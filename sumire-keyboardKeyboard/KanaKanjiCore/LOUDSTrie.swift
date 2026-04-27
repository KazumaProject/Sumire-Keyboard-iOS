import Foundation

// LOUDSBitVector: LOUDSTrie 専用 bit vector。
// CompatibleBitVector と同じ block-based 設計で zeroPositions を廃止。
struct LOUDSBitVector: Sendable {
    let bitCount: Int

    private let words: [UInt64]
    private let rank1ByWord: [Int]

    // Block-based select0 index
    private static let bigBlockBits      = 256
    private static let smallBlockBits    = 8
    private static let smallBlocksPerBig = bigBlockBits / smallBlockBits  // 32

    private let bigBlockRanks:   [Int]
    private let smallBlockRanks: [UInt8]
    private let totalOnes: Int

    init(bits: [Bool]) {
        let count = bits.count
        self.bitCount = count

        var ws = [UInt64](repeating: 0, count: (count + 63) / 64)
        for (i, b) in bits.enumerated() where b {
            ws[i / 64] |= UInt64(1) << UInt64(i % 64)
        }
        self.words = ws
        self.rank1ByWord = Self.buildRank1ByWord(ws)
        let (big, small, total) = Self.buildBlockRanks(bitCount: count, words: ws)
        self.bigBlockRanks   = big
        self.smallBlockRanks = small
        self.totalOnes       = total
    }

    init(bitCount: Int, words: [UInt64]) {
        self.bitCount = bitCount
        self.words    = words
        self.rank1ByWord = Self.buildRank1ByWord(words)
        let (big, small, total) = Self.buildBlockRanks(bitCount: bitCount, words: words)
        self.bigBlockRanks   = big
        self.smallBlockRanks = small
        self.totalOnes       = total
    }

    var packedWords: [UInt64] { words }

    var zeroCount: Int { bitCount - totalOnes }

    func rank1(through index: Int) -> Int {
        guard index >= 0, bitCount > 0 else { return 0 }
        let clamped   = min(index, bitCount - 1)
        let wordIndex = clamped / 64
        let bitOffset = clamped % 64
        let mask: UInt64 = bitOffset == 63
            ? UInt64.max
            : (UInt64(1) << UInt64(bitOffset + 1)) - 1
        return rank1ByWord[wordIndex] + (words[wordIndex] & mask).nonzeroBitCount
    }

    func select0(_ oneBasedRank: Int) -> Int? {
        let totalZeros = bitCount - totalOnes
        guard oneBasedRank >= 1, oneBasedRank <= totalZeros, bitCount > 0 else { return nil }

        // 1. big block 二分探索
        var lo = 0, hi = bigBlockRanks.count - 1, bigBlock = 0
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let zerosBefore = mid * Self.bigBlockBits - bigBlockRanks[mid]
            if zerosBefore < oneBasedRank { bigBlock = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }

        // 2. small block 線形探索
        let zerosBeforeBlock = bigBlock * Self.bigBlockBits - bigBlockRanks[bigBlock]
        let localTarget      = oneBasedRank - zerosBeforeBlock
        let baseSmall        = bigBlock * Self.smallBlocksPerBig
        let smallCount       = min(Self.smallBlocksPerBig, smallBlockRanks.count - baseSmall)
        var smallBlock = 0
        while smallBlock < smallCount - 1 {
            let next = smallBlock + 1
            let zerosBeforeNext = next * Self.smallBlockBits - Int(smallBlockRanks[baseSmall + next])
            if zerosBeforeNext < localTarget { smallBlock += 1 } else { break }
        }

        // 3. small block 内ビット走査
        let zerosBeforeSmall = smallBlock * Self.smallBlockBits - Int(smallBlockRanks[baseSmall + smallBlock])
        let offsetInSmall    = localTarget - zerosBeforeSmall
        let smallStart       = bigBlock * Self.bigBlockBits + smallBlock * Self.smallBlockBits
        var count = 0
        for off in 0 ..< Self.smallBlockBits {
            let pos = smallStart + off
            if pos >= bitCount { break }
            if ((words[pos / 64] >> UInt64(pos % 64)) & 1) == 0 {
                count += 1
                if count == offsetInSmall { return pos }
            }
        }
        return nil
    }

    // MARK: Private helpers

    private static func buildRank1ByWord(_ words: [UInt64]) -> [Int] {
        var rank = [Int](repeating: 0, count: words.count + 1)
        for (i, w) in words.enumerated() { rank[i + 1] = rank[i] + w.nonzeroBitCount }
        return rank
    }

    private static func buildBlockRanks(
        bitCount: Int,
        words: [UInt64]
    ) -> (bigBlockRanks: [Int], smallBlockRanks: [UInt8], totalOnes: Int) {
        let bigCount   = max(1, (bitCount + bigBlockBits  - 1) / bigBlockBits)
        let smallCount = bigCount * smallBlocksPerBig
        var bigRanks   = [Int](repeating: 0,   count: bigCount)
        var smallRanks = [UInt8](repeating: 0, count: smallCount)
        var ones = 0
        for bigIdx in 0 ..< bigCount {
            bigRanks[bigIdx] = ones
            let bigStart = bigIdx * bigBlockBits
            for smallIdx in 0 ..< smallBlocksPerBig {
                let gSmall     = bigIdx * smallBlocksPerBig + smallIdx
                let smallStart = bigStart + smallIdx * smallBlockBits
                smallRanks[gSmall] = UInt8(ones - bigRanks[bigIdx])
                guard smallStart < bitCount else { continue }
                let smallEnd    = min(smallStart + smallBlockBits, bitCount)
                let bitsInBlock = smallEnd - smallStart
                let wordIdx     = smallStart / 64
                let bitOffset   = smallStart % 64
                let extracted   = UInt8((words[wordIdx] >> UInt64(bitOffset)) & 0xFF)
                let masked: UInt8 = bitsInBlock == 8
                    ? extracted
                    : extracted & UInt8((1 << bitsInBlock) - 1)
                ones += masked.nonzeroBitCount
            }
        }
        return (bigRanks, smallRanks, ones)
    }
}

/// 濁点 / 半濁点 / 小書き文字などの「入力で省略されがちなしるし」を吸収するための
/// 文字バリエーション表。C++ 版 `LOUDSReaderUtf16::getCharVariations` と同じ対応を持つ。
///
/// 非対称であることに注意: 入力 `か` に対しては `[か, が]` を返すが、
/// 入力 `が` に対しては `[が]` しか返さない (= 入力が "lean" で辞書が "rich" のケースだけ吸収する)。
enum KanaVariations {
    private static let pairs: [(Character, [Character])] = [
        ("か", ["か", "が"]),
        ("き", ["き", "ぎ"]),
        ("く", ["く", "ぐ"]),
        ("け", ["け", "げ"]),
        ("こ", ["こ", "ご"]),

        ("さ", ["さ", "ざ"]),
        ("し", ["し", "じ"]),
        ("す", ["す", "ず"]),
        ("せ", ["せ", "ぜ"]),
        ("そ", ["そ", "ぞ"]),

        ("た", ["た", "だ"]),
        ("ち", ["ち", "ぢ"]),
        ("つ", ["つ", "づ", "っ"]),
        ("て", ["て", "で"]),
        ("と", ["と", "ど"]),

        ("は", ["は", "ば", "ぱ"]),
        ("ひ", ["ひ", "び", "ぴ"]),
        ("ふ", ["ふ", "ぶ", "ぷ"]),
        ("へ", ["へ", "べ", "ぺ"]),
        ("ほ", ["ほ", "ぼ", "ぽ"]),

        ("や", ["や", "ゃ"]),
        ("ゆ", ["ゆ", "ゅ"]),
        ("よ", ["よ", "ょ"]),

        ("あ", ["あ", "ぁ"]),
        ("い", ["い", "ぃ"]),
        ("う", ["う", "ぅ"]),
        ("え", ["え", "ぇ"]),
        ("お", ["お", "ぉ"])
    ]

    private static let byCharacter: [Character: [Character]] = Dictionary(
        uniqueKeysWithValues: pairs
    )

    private static let byCodeUnit: [UInt16: [UInt16]] = {
        var result: [UInt16: [UInt16]] = [:]
        for (key, values) in pairs {
            guard let keyUnit = key.utf16.first else {
                continue
            }
            let valueUnits = values.compactMap { $0.utf16.first }
            result[keyUnit] = valueUnits
        }
        return result
    }()

    /// 指定された文字に対する置換候補を返す。常に最初の要素は自分自身。
    static func variations(for character: Character) -> [Character] {
        byCharacter[character] ?? [character]
    }

    /// UTF-16 code unit 単位の置換候補を返す (artifact backend 用)。
    static func variations(for codeUnit: UInt16) -> [UInt16] {
        byCodeUnit[codeUnit] ?? [codeUnit]
    }
}

struct LOUDSTrie<Value: Sendable>: Sendable {
    struct PrefixMatch: Sendable {
        let length: Int
        let value: Value
    }

    /// omission-aware search の結果。
    /// `replaceCount` は C++ 版と同じく「置換が必要だった文字数」を指す。
    struct OmissionMatch: Sendable {
        let length: Int
        let replaceCount: Int
        let value: Value
    }

    private final class BuildNode {
        var value: Value?
        var children: [Character: BuildNode] = [:]
    }

    let bitVector: LOUDSBitVector
    let labels: [Character]

    private let values: [Value?]

    var nodeCount: Int {
        values.count
    }

    init(_ pairs: [(key: String, value: Value)]) {
        let root = BuildNode()

        for pair in pairs {
            var node = root
            for character in pair.key {
                if let child = node.children[character] {
                    node = child
                } else {
                    let child = BuildNode()
                    node.children[character] = child
                    node = child
                }
            }
            node.value = pair.value
        }

        var bits: [Bool] = []
        var labels: [Character] = []
        var values: [Value?] = []

        var queue = [root]
        var index = 0

        while index < queue.count {
            let node = queue[index]
            values.append(node.value)

            let children = node.children.sorted {
                String($0.key) < String($1.key)
            }

            for (label, child) in children {
                bits.append(true)
                labels.append(label)
                queue.append(child)
            }
            bits.append(false)

            index += 1
        }

        self.bitVector = LOUDSBitVector(bits: bits)
        self.labels = labels
        self.values = values
    }

    init(bitCount: Int, words: [UInt64], labels: [Character], values: [Value?]) {
        self.bitVector = LOUDSBitVector(bitCount: bitCount, words: words)
        self.labels = labels
        self.values = values
    }

    var packedWords: [UInt64] {
        bitVector.packedWords
    }

    var optionalValues: [Value?] {
        values
    }

    func value(for key: String) -> Value? {
        guard let nodeIndex = nodeIndex(for: key) else {
            return nil
        }
        return values[nodeIndex]
    }

    func commonPrefixSearch(in characters: [Character], from start: Int) -> [PrefixMatch] {
        guard start < characters.count else {
            return []
        }

        var nodeIndex = 0
        var matches: [PrefixMatch] = []

        for index in start..<characters.count {
            guard let childIndex = child(of: nodeIndex, matching: characters[index]) else {
                break
            }

            nodeIndex = childIndex
            if let value = values[nodeIndex] {
                matches.append(PrefixMatch(length: index - start + 1, value: value))
            }
        }

        return matches
    }

    func predictiveSearch(prefix: String, limit: Int = .max) -> [(key: String, value: Value)] {
        guard limit > 0, let startNode = nodeIndex(for: prefix) else {
            return []
        }

        var results: [(key: String, value: Value)] = []
        var stack: [(nodeIndex: Int, key: String)] = [(startNode, prefix)]

        while let current = stack.popLast() {
            if let value = values[current.nodeIndex] {
                results.append((current.key, value))
                if results.count >= limit {
                    break
                }
            }

            let childIndices = children(of: current.nodeIndex).reversed()
            for childIndex in childIndices {
                let label = labels[childIndex - 1]
                stack.append((childIndex, current.key + String(label)))
            }
        }

        return results
    }

    func predictiveSearch(
        prefix: String,
        matching requiredPrefix: String,
        limit: Int = .max,
        maxKeyLength: Int? = nil
    ) -> [(key: String, value: Value)] {
        guard limit > 0,
              requiredPrefix.isEmpty == false,
              let startNode = nodeIndex(for: prefix),
              Self.isCompatiblePrefix(prefix, requiredPrefix: requiredPrefix),
              maxKeyLength.map({ prefix.count <= $0 }) ?? true else {
            return []
        }

        var results: [(key: String, value: Value)] = []
        var stack: [(nodeIndex: Int, key: String)] = [(startNode, prefix)]

        while let current = stack.popLast() {
            guard Self.isCompatiblePrefix(current.key, requiredPrefix: requiredPrefix),
                  maxKeyLength.map({ current.key.count <= $0 }) ?? true else {
                continue
            }

            if current.key.hasPrefix(requiredPrefix), let value = values[current.nodeIndex] {
                results.append((current.key, value))
                if results.count >= limit {
                    break
                }
            }

            let childIndices = children(of: current.nodeIndex).reversed()
            for childIndex in childIndices {
                let label = labels[childIndex - 1]
                let key = current.key + String(label)
                if Self.isCompatiblePrefix(key, requiredPrefix: requiredPrefix),
                   maxKeyLength.map({ key.count <= $0 }) ?? true {
                    stack.append((childIndex, key))
                }
            }
        }

        return results
    }

    private static func isCompatiblePrefix(_ key: String, requiredPrefix: String) -> Bool {
        if key.count <= requiredPrefix.count {
            return requiredPrefix.hasPrefix(key)
        }
        return key.hasPrefix(requiredPrefix)
    }

    /// 濁点 / 半濁点 / 小書きなどの揺れを吸収した common prefix search。
    ///
    /// C++ 版 `LOUDSReaderUtf16::commonPrefixSearchWithOmission` の移植。
    /// 入力文字列の各文字について `KanaVariations.variations(for:)` で置換候補を試し、
    /// トライ上でノードに着地するたびに leaf を matches に拾い集める。
    /// 同じ yomi (= 同じ node index) に複数経路で到達した場合は `replaceCount`
    /// が最小のものを採用する。
    func commonPrefixSearchWithOmission(
        in characters: [Character],
        from start: Int
    ) -> [OmissionMatch] {
        guard start <= characters.count else {
            return []
        }

        // node index → 最良の (length, replaceCount)
        var resultsByNode: [Int: (length: Int, replaceCount: Int, value: Value)] = [:]

        recursiveOmissionSearch(
            characters: characters,
            startIndex: start,
            strIndex: start,
            currentNodeIndex: 0,
            replaceCount: 0,
            results: &resultsByNode
        )

        return resultsByNode.values.map { tuple in
            OmissionMatch(length: tuple.length, replaceCount: tuple.replaceCount, value: tuple.value)
        }
    }

    private func recursiveOmissionSearch(
        characters: [Character],
        startIndex: Int,
        strIndex: Int,
        currentNodeIndex: Int,
        replaceCount: Int,
        results: inout [Int: (length: Int, replaceCount: Int, value: Value)]
    ) {
        if currentNodeIndex != 0, let value = values[currentNodeIndex] {
            let length = strIndex - startIndex
            if let existing = results[currentNodeIndex] {
                if replaceCount < existing.replaceCount {
                    results[currentNodeIndex] = (length, replaceCount, value)
                }
            } else {
                results[currentNodeIndex] = (length, replaceCount, value)
            }
        }

        guard strIndex < characters.count else {
            return
        }

        let ch = characters[strIndex]
        for variant in KanaVariations.variations(for: ch) {
            guard let childIndex = child(of: currentNodeIndex, matching: variant) else {
                continue
            }
            let replaced = (variant != ch) ? 1 : 0
            recursiveOmissionSearch(
                characters: characters,
                startIndex: startIndex,
                strIndex: strIndex + 1,
                currentNodeIndex: childIndex,
                replaceCount: replaceCount + replaced,
                results: &results
            )
        }
    }

    private func nodeIndex(for key: String) -> Int? {
        var nodeIndex = 0
        for character in key {
            guard let childIndex = child(of: nodeIndex, matching: character) else {
                return nil
            }
            nodeIndex = childIndex
        }
        return nodeIndex
    }

    private func child(of nodeIndex: Int, matching label: Character) -> Int? {
        let children = self.children(of: nodeIndex)
        guard !children.isEmpty else {
            return nil
        }

        let target = String(label)
        var lower = children.startIndex
        var upper = children.endIndex

        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let childIndex = children[middle]
            let childLabel = String(labels[childIndex - 1])

            if childLabel == target {
                return childIndex
            } else if childLabel < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        return nil
    }

    private func children(of nodeIndex: Int) -> [Int] {
        guard nodeIndex >= 0,
              nodeIndex < values.count,
              let currentZero = bitVector.select0(nodeIndex + 1) else {
            return []
        }

        let previousZero = nodeIndex == 0 ? -1 : (bitVector.select0(nodeIndex) ?? -1)
        let firstBit = previousZero + 1
        guard firstBit < currentZero else {
            return []
        }

        let firstChild = bitVector.rank1(through: firstBit)
        let lastChild = bitVector.rank1(through: currentZero - 1)
        guard firstChild <= lastChild else {
            return []
        }

        return Array(firstChild...lastChild)
    }
}
