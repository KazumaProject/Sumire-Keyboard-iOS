import Foundation

// MARK: - CompatibleBitVector
//
// Block-based succinct bit vector (Kotlin SuccinctBitVector 移植版)。
//
// メモリ構造:
//   words          : 元の bit 列を 64-bit word に詰めたもの (辞書ファイル由来、変更不可)
//   rank1ByWord    : word 単位の prefix popcount — rank1() を O(1) で処理するため
//   bigBlockRanks  : bigBlockBits(=256) 単位の prefix popcount — select の二分探索用
//   smallBlockRanks: smallBlockBits(=8) 単位の差分 popcount — big block 内線形探索用
//                    値は big block 先頭からの相対 1-bit 数なので UInt8 に収まる (最大 248)
//   totalOnes      : 全 1-bit 数
//
// 旧実装の zeroPositions / onePositions ([Int] × bitCount 個) を廃止し、
// Keyboard Extension の辞書ロード時メモリを大幅に削減する。
struct CompatibleBitVector: Sendable {
    let bitCount: Int
    let words: [UInt64]

    // word-level prefix popcount: rank1ByWord[i] = ones in words[0..<i]
    private let rank1ByWord: [Int]

    // block-based index for select
    private static let bigBlockBits     = 256
    private static let smallBlockBits   = 8
    private static let smallBlocksPerBig = bigBlockBits / smallBlockBits  // 32

    /// bigBlockRanks[i] = 1-bit count in bits [0, i * bigBlockBits)  (absolute)
    private let bigBlockRanks: [Int]
    /// smallBlockRanks[bigIdx * smallBlocksPerBig + smallIdx] =
    ///   1-bit count in bits [bigStart, bigStart + smallIdx * smallBlockBits)
    ///   relative to big block start → fits in UInt8 (max value = 31 * 8 = 248)
    private let smallBlockRanks: [UInt8]
    /// Total number of 1-bits in the entire vector
    let totalOnes: Int

    // MARK: init(bits:)

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

    // MARK: init(bitCount:words:)  ← MozcArtifactIO.readBitVector が使う。変更不可。

    init(bitCount: Int, words: [UInt64]) {
        self.bitCount = bitCount
        self.words    = words
        self.rank1ByWord = Self.buildRank1ByWord(words)
        let (big, small, total) = Self.buildBlockRanks(bitCount: bitCount, words: words)
        self.bigBlockRanks   = big
        self.smallBlockRanks = small
        self.totalOnes       = total
    }

    // MARK: Public API

    /// bits[index] を返す。範囲外は false。
    func get(_ index: Int) -> Bool {
        guard index >= 0, index < bitCount else { return false }
        return ((words[index / 64] >> UInt64(index % 64)) & 1) == 1
    }

    /// bits[0...index] の 1-bit 数を返す。
    func rank1(_ index: Int) -> Int {
        guard index >= 0, bitCount > 0 else { return 0 }
        let clamped    = min(index, bitCount - 1)
        let wordIndex  = clamped / 64
        let bitOffset  = clamped % 64
        let mask: UInt64 = bitOffset == 63
            ? UInt64.max
            : (UInt64(1) << UInt64(bitOffset + 1)) - 1
        return rank1ByWord[wordIndex] + (words[wordIndex] & mask).nonzeroBitCount
    }

    /// bits[0...index] の 0-bit 数を返す。
    func rank0(_ index: Int) -> Int {
        guard index >= 0, bitCount > 0 else { return 0 }
        let clamped = min(index, bitCount - 1)
        return clamped + 1 - rank1(clamped)
    }

    /// `oneBasedRank` 番目 (1-origin) の 1-bit の位置 (0-origin) を返す。
    /// 見つからなければ -1。
    func select1(_ oneBasedRank: Int) -> Int {
        guard oneBasedRank >= 1, oneBasedRank <= totalOnes, bitCount > 0 else { return -1 }

        // 1. big block を二分探索
        var lo = 0
        var hi = bigBlockRanks.count - 1
        var bigBlock = 0
        while lo <= hi {
            let mid = (lo + hi) >> 1
            if bigBlockRanks[mid] < oneBasedRank {
                bigBlock = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        // 2. big block 内の small block を線形探索
        let localTarget  = oneBasedRank - bigBlockRanks[bigBlock]
        let baseSmall    = bigBlock * Self.smallBlocksPerBig
        let smallCount   = min(Self.smallBlocksPerBig, smallBlockRanks.count - baseSmall)
        var smallBlock   = 0
        while smallBlock < smallCount - 1,
              Int(smallBlockRanks[baseSmall + smallBlock + 1]) < localTarget {
            smallBlock += 1
        }

        // 3. small block 内をビット走査 (最大 8 bit)
        let offsetInSmall = localTarget - Int(smallBlockRanks[baseSmall + smallBlock])
        let smallStart    = bigBlock * Self.bigBlockBits + smallBlock * Self.smallBlockBits
        var count = 0
        for off in 0 ..< Self.smallBlockBits {
            let pos = smallStart + off
            if pos >= bitCount { break }
            if get(pos) {
                count += 1
                if count == offsetInSmall { return pos }
            }
        }
        return -1
    }

    /// `oneBasedRank` 番目 (1-origin) の 0-bit の位置 (0-origin) を返す。
    /// 見つからなければ -1。
    func select0(_ oneBasedRank: Int) -> Int {
        let totalZeros = bitCount - totalOnes
        guard oneBasedRank >= 1, oneBasedRank <= totalZeros, bitCount > 0 else { return -1 }

        // 1. big block を二分探索 (zeros before block i = i*bigBlockBits - bigBlockRanks[i])
        var lo = 0
        var hi = bigBlockRanks.count - 1
        var bigBlock = 0
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let zerosBefore = mid * Self.bigBlockBits - bigBlockRanks[mid]
            if zerosBefore < oneBasedRank {
                bigBlock = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        // 2. big block 内の small block を線形探索
        let zerosBeforeBlock = bigBlock * Self.bigBlockBits - bigBlockRanks[bigBlock]
        let localTarget      = oneBasedRank - zerosBeforeBlock
        let baseSmall        = bigBlock * Self.smallBlocksPerBig
        let smallCount       = min(Self.smallBlocksPerBig, smallBlockRanks.count - baseSmall)
        var smallBlock = 0
        while smallBlock < smallCount - 1 {
            let nextSmall      = smallBlock + 1
            let onesBeforeNext = Int(smallBlockRanks[baseSmall + nextSmall])
            let zerosBeforeNext = nextSmall * Self.smallBlockBits - onesBeforeNext
            if zerosBeforeNext < localTarget {
                smallBlock += 1
            } else {
                break
            }
        }

        // 3. small block 内をビット走査 (最大 8 bit)
        let onesBeforeSmall  = Int(smallBlockRanks[baseSmall + smallBlock])
        let zerosBeforeSmall = smallBlock * Self.smallBlockBits - onesBeforeSmall
        let offsetInSmall    = localTarget - zerosBeforeSmall
        let smallStart       = bigBlock * Self.bigBlockBits + smallBlock * Self.smallBlockBits
        var count = 0
        for off in 0 ..< Self.smallBlockBits {
            let pos = smallStart + off
            if pos >= bitCount { break }
            if !get(pos) {
                count += 1
                if count == offsetInSmall { return pos }
            }
        }
        return -1
    }

    // MARK: Private helpers

    /// words の word-level prefix popcount 配列を構築する。
    /// rank1ByWord[i] = ones in words[0..<i]  (size = words.count + 1)
    private static func buildRank1ByWord(_ words: [UInt64]) -> [Int] {
        var rank = [Int](repeating: 0, count: words.count + 1)
        for (i, word) in words.enumerated() {
            rank[i + 1] = rank[i] + word.nonzeroBitCount
        }
        return rank
    }

    /// block-based の補助データを構築する。
    /// 一時的な位置配列 ([Int]) を作らず、直接 bigBlockRanks / smallBlockRanks を埋める。
    private static func buildBlockRanks(
        bitCount: Int,
        words: [UInt64]
    ) -> (bigBlockRanks: [Int], smallBlockRanks: [UInt8], totalOnes: Int) {
        let bigCount   = max(1, (bitCount + bigBlockBits  - 1) / bigBlockBits)
        let smallCount = bigCount * smallBlocksPerBig

        var bigRanks   = [Int](repeating: 0,    count: bigCount)
        var smallRanks = [UInt8](repeating: 0,  count: smallCount)
        var ones = 0

        for bigIdx in 0 ..< bigCount {
            bigRanks[bigIdx] = ones
            let bigStart = bigIdx * bigBlockBits

            for smallIdx in 0 ..< smallBlocksPerBig {
                let globalSmall = bigIdx * smallBlocksPerBig + smallIdx
                let smallStart  = bigStart + smallIdx * smallBlockBits

                // small block 先頭時点での big block 内相対 ones を記録
                smallRanks[globalSmall] = UInt8(ones - bigRanks[bigIdx])

                guard smallStart < bitCount else { continue }

                // smallBlockBits(8) は 64 の約数なので small block は必ず 1 word 内に収まる。
                let smallEnd     = min(smallStart + smallBlockBits, bitCount)
                let bitsInBlock  = smallEnd - smallStart
                let wordIdx      = smallStart / 64
                let bitOffset    = smallStart % 64
                // 当該 small block に対応する 8bit を取り出す
                let extracted    = UInt8((words[wordIdx] >> UInt64(bitOffset)) & 0xFF)
                let masked: UInt8 = bitsInBlock == 8
                    ? extracted
                    : extracted & UInt8((1 << bitsInBlock) - 1)
                ones += masked.nonzeroBitCount
            }
        }

        return (bigRanks, smallRanks, ones)
    }
}

struct CompatibleLOUDS: Sendable {
    let lbs: CompatibleBitVector
    let isLeaf: CompatibleBitVector
    let labels: [UInt16]
    let termIds: [Int32]?

    func firstChild(_ pos: Int) -> Int {
        let r1 = lbs.rank1(pos)
        guard r1 > 0 else {
            return -1
        }
        let y = lbs.select0(r1) + 1
        guard y >= 0, y < lbs.bitCount else {
            return -1
        }
        return lbs.get(y) ? y : -1
    }

    func traverse(_ pos: Int, _ codeUnit: UInt16) -> Int {
        var child = firstChild(pos)
        while child >= 0, child < lbs.bitCount, lbs.get(child) {
            let labelIndex = lbs.rank1(child)
            if labelIndex >= 0, labelIndex < labels.count, labels[labelIndex] == codeUnit {
                return child
            }
            child += 1
        }
        return -1
    }

    func commonPrefixSearchTermIds(_ codeUnits: [UInt16]) -> [(yomi: String, termId: Int)] {
        var resultUnits: [UInt16] = []
        var results: [(String, Int)] = []
        var node = 0

        for codeUnit in codeUnits {
            node = traverse(node, codeUnit)
            if node < 0 {
                break
            }

            let index = lbs.rank1(node)
            guard index >= 0, index < labels.count else {
                break
            }
            resultUnits.append(labels[index])

            if node < isLeaf.bitCount, isLeaf.get(node) {
                let nodeId = lbs.rank1(node) - 1
                if let termIds, nodeId >= 0, nodeId < termIds.count, termIds[nodeId] >= 0 {
                    let yomi = String(decoding: resultUnits, as: UTF16.self)
                    results.append((yomi, Int(termIds[nodeId])))
                }
            }
        }

        return results
    }

    /// 接頭辞 `codeUnits` で始まるすべての yomi を列挙する。
    /// C++ 版 `LOUDSReaderUtf16::predictiveSearch` の移植。
    func predictiveSearchTermIds(_ codeUnits: [UInt16]) -> [(yomi: String, termId: Int)] {
        var node = 0
        var built: [UInt16] = []
        built.reserveCapacity(codeUnits.count)

        for unit in codeUnits {
            node = traverse(node, unit)
            if node < 0 {
                return []
            }
            let idx = lbs.rank1(node)
            guard idx >= 0, idx < labels.count else {
                return []
            }
            built.append(labels[idx])
        }

        var out: [(String, Int)] = []
        collectTerms(pos: node, built: &built, out: &out)
        return out
    }

    func predictiveSearchTermIds(
        _ codeUnits: [UInt16],
        matching requiredPrefix: [UInt16],
        limit: Int,
        maxYomiLength: Int? = nil
    ) -> [(yomi: String, termId: Int)] {
        guard limit > 0,
              requiredPrefix.isEmpty == false,
              isCompatiblePrefix(codeUnits, requiredPrefix: requiredPrefix),
              maxYomiLength.map({ codeUnits.count <= $0 }) ?? true else {
            return []
        }

        var node = 0
        var built: [UInt16] = []
        built.reserveCapacity(codeUnits.count)

        for unit in codeUnits {
            node = traverse(node, unit)
            if node < 0 {
                return []
            }
            let idx = lbs.rank1(node)
            guard idx >= 0, idx < labels.count else {
                return []
            }
            built.append(labels[idx])
        }

        var out: [(String, Int)] = []
        collectTerms(
            pos: node,
            built: &built,
            requiredPrefix: requiredPrefix,
            maxYomiLength: maxYomiLength,
            limit: limit,
            out: &out
        )
        return out
    }

    private func collectTerms(
        pos: Int,
        built: inout [UInt16],
        out: inout [(String, Int)]
    ) {
        guard pos >= 0, pos < lbs.bitCount else {
            return
        }

        if pos < isLeaf.bitCount, isLeaf.get(pos) {
            let nodeId = lbs.rank1(pos) - 1
            if let termIds, nodeId >= 0, nodeId < termIds.count, termIds[nodeId] >= 0 {
                let yomi = String(decoding: built, as: UTF16.self)
                out.append((yomi, Int(termIds[nodeId])))
            }
        }

        var child = firstChild(pos)
        while child >= 0, child < lbs.bitCount, lbs.get(child) {
            let labelIndex = lbs.rank1(child)
            guard labelIndex >= 0, labelIndex < labels.count else {
                break
            }
            built.append(labels[labelIndex])
            collectTerms(pos: child, built: &built, out: &out)
            built.removeLast()
            child += 1
        }
    }

    private func collectTerms(
        pos: Int,
        built: inout [UInt16],
        requiredPrefix: [UInt16],
        maxYomiLength: Int?,
        limit: Int,
        out: inout [(String, Int)]
    ) {
        guard out.count < limit,
              pos >= 0,
              pos < lbs.bitCount,
              isCompatiblePrefix(built, requiredPrefix: requiredPrefix),
              maxYomiLength.map({ built.count <= $0 }) ?? true else {
            return
        }

        if built.starts(with: requiredPrefix),
           pos < isLeaf.bitCount,
           isLeaf.get(pos) {
            let nodeId = lbs.rank1(pos) - 1
            if let termIds, nodeId >= 0, nodeId < termIds.count, termIds[nodeId] >= 0 {
                let yomi = String(decoding: built, as: UTF16.self)
                out.append((yomi, Int(termIds[nodeId])))
                if out.count >= limit {
                    return
                }
            }
        }

        var child = firstChild(pos)
        while out.count < limit, child >= 0, child < lbs.bitCount, lbs.get(child) {
            let labelIndex = lbs.rank1(child)
            guard labelIndex >= 0, labelIndex < labels.count else {
                break
            }
            built.append(labels[labelIndex])
            collectTerms(
                pos: child,
                built: &built,
                requiredPrefix: requiredPrefix,
                maxYomiLength: maxYomiLength,
                limit: limit,
                out: &out
            )
            built.removeLast()
            child += 1
        }
    }

    private func isCompatiblePrefix(_ key: [UInt16], requiredPrefix: [UInt16]) -> Bool {
        if key.count <= requiredPrefix.count {
            return requiredPrefix.starts(with: key)
        }
        return key.starts(with: requiredPrefix)
    }

    /// 濁点/半濁点/小書きなどの置換を許容する common prefix search。
    /// C++ 版 `LOUDSReaderUtf16::commonPrefixSearchWithOmission` の移植。
    /// 返り値は termId でデデュプ済みで、同じ termId に複数経路で到達した場合は
    /// `replaceCount` の最小値を採用する。
    func commonPrefixSearchWithOmissionTermIds(
        _ codeUnits: [UInt16]
    ) -> [(yomi: String, termId: Int, replaceCount: Int)] {
        var resultByTerm: [Int: (yomi: String, replaceCount: Int)] = [:]
        var built: [UInt16] = []
        built.reserveCapacity(codeUnits.count)

        omissionRecursive(
            codeUnits: codeUnits,
            strIndex: 0,
            node: 0,
            built: &built,
            replaceCount: 0,
            results: &resultByTerm
        )

        return resultByTerm.map { ($0.value.yomi, $0.key, $0.value.replaceCount) }
    }

    private func omissionRecursive(
        codeUnits: [UInt16],
        strIndex: Int,
        node: Int,
        built: inout [UInt16],
        replaceCount: Int,
        results: inout [Int: (yomi: String, replaceCount: Int)]
    ) {
        if node < 0 || node >= lbs.bitCount {
            return
        }

        if node != 0, node < isLeaf.bitCount, isLeaf.get(node) {
            let nodeId = lbs.rank1(node) - 1
            if let termIds, nodeId >= 0, nodeId < termIds.count, termIds[nodeId] >= 0 {
                let termId = Int(termIds[nodeId])
                let yomi = String(decoding: built, as: UTF16.self)
                if let existing = results[termId] {
                    if replaceCount < existing.replaceCount {
                        results[termId] = (yomi, replaceCount)
                    }
                } else {
                    results[termId] = (yomi, replaceCount)
                }
            }
        }

        guard strIndex < codeUnits.count else {
            return
        }

        let ch = codeUnits[strIndex]
        for variant in KanaVariations.variations(for: ch) {
            let next = traverse(node, variant)
            guard next >= 0 else {
                continue
            }
            let replaced = (variant != ch) ? 1 : 0
            built.append(variant)
            omissionRecursive(
                codeUnits: codeUnits,
                strIndex: strIndex + 1,
                node: next,
                built: &built,
                replaceCount: replaceCount + replaced,
                results: &results
            )
            built.removeLast()
        }
    }

    func getLetter(nodeIndex: Int) -> String {
        guard nodeIndex >= 0, nodeIndex < lbs.bitCount else {
            return ""
        }

        var units: [UInt16] = []
        var current = nodeIndex

        while true {
            let nodeId = lbs.rank1(current)
            guard nodeId >= 0, nodeId < labels.count else {
                break
            }

            let codeUnit = labels[nodeId]
            if codeUnit != 0x20 {
                units.append(codeUnit)
            }

            if nodeId == 0 {
                break
            }

            let r0 = lbs.rank0(current)
            current = lbs.select1(r0)
            if current < 0 {
                break
            }
        }

        return String(decoding: units.reversed(), as: UTF16.self)
    }

    func getNodeIndex(_ text: String) -> Int {
        search(index: 2, chars: Array(text.utf16), offset: 0)
    }

    private func search(index: Int, chars: [UInt16], offset: Int) -> Int {
        var current = index
        guard !chars.isEmpty, current >= 0 else {
            return -1
        }

        while current < lbs.bitCount, lbs.get(current) {
            if offset >= chars.count {
                return current
            }

            let labelIndex = lbs.rank1(current)
            guard labelIndex >= 0, labelIndex < labels.count else {
                return -1
            }

            if chars[offset] == labels[labelIndex] {
                if offset + 1 == chars.count {
                    return current
                }

                let next = lbs.select0(labelIndex) + 1
                guard next >= 0 else {
                    return -1
                }
                return search(index: next, chars: chars, offset: offset + 1)
            }

            current += 1
        }

        return -1
    }
}

struct TokenEntry: Sendable {
    let posIndex: UInt16
    let wordCost: Int16
    let nodeIndex: Int32
}

struct CompatibleTokenArray: Sendable {
    static let hiraganaSentinel = Int32(-1)
    static let katakanaSentinel = Int32(-2)

    let posIndex: [UInt16]
    let wordCost: [Int16]
    let nodeIndex: [Int32]
    let postingsBits: CompatibleBitVector

    func tokens(forTermId termId: Int) -> [TokenEntry] {
        let p0 = postingsBits.select0(termId + 1)
        let p1 = postingsBits.select0(termId + 2)
        guard p0 >= 0, p1 >= 0 else {
            return []
        }

        let begin = postingsBits.rank1(p0)
        let end = postingsBits.rank1(p1)
        guard begin <= end else {
            return []
        }

        return (begin..<end).map {
            TokenEntry(posIndex: posIndex[$0], wordCost: wordCost[$0], nodeIndex: nodeIndex[$0])
        }
    }
}

struct CompatiblePosTable: Sendable {
    let leftIds: [Int16]
    let rightIds: [Int16]

    func ids(for index: UInt16) -> (left: Int, right: Int) {
        let i = Int(index)
        guard i < leftIds.count, i < rightIds.count else {
            return (0, 0)
        }
        return (Int(leftIds[i]), Int(rightIds[i]))
    }
}

struct MozcArtifactDictionary: Sendable {
    let yomiTerm: CompatibleLOUDS
    let tango: CompatibleLOUDS
    let tokens: CompatibleTokenArray
    let posTable: CompatiblePosTable

    /// `suffix` から始まる入力に対して、与えられた `mode` で yomi 候補を集める。
    /// 既存呼び出しとの互換のため `mode = .commonPrefix` の場合は
    /// 旧来の common prefix のみの挙動と等価になるようデフォルト値を保っている。
    func prefixMatches(
        _ input: String,
        mode: YomiSearchMode = .commonPrefix,
        predictivePrefixLength: Int = 1
    ) -> [MozcDictionary.PrefixMatch] {
        let codeUnits = Array(input.utf16)
        let remaining = codeUnits.count

        // termId -> (yomi, length[UTF-16], penalty)
        var collected: [Int: (yomi: String, length: Int, penalty: Int)] = [:]
        collected.reserveCapacity(64)

        // (A) common prefix search は常に実施
        for hit in yomiTerm.commonPrefixSearchTermIds(codeUnits) {
            let length = hit.yomi.utf16.count
            if let existing = collected[hit.termId] {
                if 0 < existing.penalty {
                    collected[hit.termId] = (hit.yomi, length, 0)
                }
            } else {
                collected[hit.termId] = (hit.yomi, length, 0)
            }
        }

        // (B) predictive search
        if mode.includesPredictive, remaining > 0 {
            let k = max(1, min(predictivePrefixLength, remaining))
            let prefix = Array(codeUnits.prefix(k))
            for hit in yomiTerm.predictiveSearchTermIds(prefix) {
                let length = hit.yomi.utf16.count
                guard length <= remaining else {
                    continue
                }
                if collected[hit.termId] == nil {
                    collected[hit.termId] = (hit.yomi, length, 0)
                }
            }
        }

        // (C) omission-aware search
        if mode.includesOmission {
            for hit in yomiTerm.commonPrefixSearchWithOmissionTermIds(codeUnits) {
                let length = hit.yomi.utf16.count
                guard length <= remaining else {
                    continue
                }
                let penalty = hit.replaceCount
                if let existing = collected[hit.termId] {
                    if penalty < existing.penalty {
                        collected[hit.termId] = (existing.yomi, existing.length, penalty)
                    }
                } else {
                    collected[hit.termId] = (hit.yomi, length, penalty)
                }
            }
        }

        return collected.map { (termId, value) -> MozcDictionary.PrefixMatch in
            let entries = buildEntries(forTermId: termId, yomi: value.yomi)
            // length はグラフ構築時の endPosition 計算に使われるため、
            // Character 単位に揃える (ひらがなでは UTF-16 単位数と一致する)。
            return MozcDictionary.PrefixMatch(
                length: value.yomi.count,
                entries: entries,
                penalty: value.penalty
            )
        }
    }

    private func buildEntries(forTermId termId: Int, yomi: String) -> [DictionaryEntry] {
        tokens.tokens(forTermId: termId).map { token -> DictionaryEntry in
            let ids = posTable.ids(for: token.posIndex)
            let surface: String
            if token.nodeIndex == CompatibleTokenArray.hiraganaSentinel {
                surface = yomi
            } else if token.nodeIndex == CompatibleTokenArray.katakanaSentinel {
                surface = hiraganaToKatakana(yomi)
            } else {
                surface = tango.getLetter(nodeIndex: Int(token.nodeIndex))
            }
            return DictionaryEntry(
                yomi: yomi,
                leftId: ids.left,
                rightId: ids.right,
                cost: Int(token.wordCost),
                surface: surface
            )
        }.sorted {
            if $0.cost != $1.cost {
                return $0.cost < $1.cost
            }
            return $0.surface < $1.surface
        }
    }

    private func hiraganaToKatakana(_ value: String) -> String {
        let units = value.utf16.map { unit -> UInt16 in
            if (0x3041...0x3096).contains(unit) || (0x309D...0x309F).contains(unit) {
                return unit + 0x60
            }
            return unit
        }
        return String(decoding: units, as: UTF16.self)
    }

    func predictiveEntries(
        for input: String,
        predictivePrefixLength: Int = 1,
        limit: Int = 50,
        maxYomiLength: Int? = nil
    ) -> [DictionaryEntry] {
        let codeUnits = Array(input.utf16)
        guard limit > 0, codeUnits.isEmpty == false else {
            return []
        }

        let k = max(1, min(predictivePrefixLength, codeUnits.count))
        let prefix = Array(codeUnits.prefix(k))
        let yomiLimit = max(limit, 200)
        let hits = yomiTerm.predictiveSearchTermIds(
            prefix,
            matching: codeUnits,
            limit: yomiLimit,
            maxYomiLength: maxYomiLength
        )

        var entries: [DictionaryEntry] = []
        entries.reserveCapacity(limit * 2)
        for hit in hits {
            entries.append(contentsOf: buildEntries(forTermId: hit.termId, yomi: hit.yomi))
        }
        return MozcDictionary.sortedPredictiveEntries(entries).prefix(limit).map { $0 }
    }
}
