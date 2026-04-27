// CompatibleBitVectorTests.swift
//
// CompatibleBitVector の単体テスト。
//
// このファイルは Keyboard Extension ターゲットとは別のターゲットに属するため、
// 実装を inline で再定義し、`swift CompatibleBitVectorTests.swift` で直接実行できる。
//
// Xcode でテストを実行する場合:
//   1. sumire-keyboardKeyboard を Unit-Test ターゲットに追加するか、
//   2. このファイルを Keyboard Extension ターゲットにも追加した上で
//      `#if DEBUG` ブロックに wrap する。
//
// Usage (コマンドライン):
//   swift sumire-keyboardTests/CompatibleBitVectorTests.swift

import Foundation

// MARK: - CompatibleBitVector (テスト用 inline コピー)
// ※ MozcArtifacts.swift の実装と完全に同一であること。

private struct CompatibleBitVector {
    let bitCount: Int
    let words: [UInt64]

    private let rank1ByWord: [Int]

    private static let bigBlockBits      = 256
    private static let smallBlockBits    = 8
    private static let smallBlocksPerBig = bigBlockBits / smallBlockBits  // 32

    private let bigBlockRanks:   [Int]
    private let smallBlockRanks: [UInt8]
    let totalOnes: Int

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

    func get(_ index: Int) -> Bool {
        guard index >= 0, index < bitCount else { return false }
        return ((words[index / 64] >> UInt64(index % 64)) & 1) == 1
    }

    func rank1(_ index: Int) -> Int {
        guard index >= 0, bitCount > 0 else { return 0 }
        let clamped   = min(index, bitCount - 1)
        let wordIndex = clamped / 64
        let bitOffset = clamped % 64
        let mask: UInt64 = bitOffset == 63
            ? UInt64.max
            : (UInt64(1) << UInt64(bitOffset + 1)) - 1
        return rank1ByWord[wordIndex] + (words[wordIndex] & mask).nonzeroBitCount
    }

    func rank0(_ index: Int) -> Int {
        guard index >= 0, bitCount > 0 else { return 0 }
        return min(index, bitCount - 1) + 1 - rank1(min(index, bitCount - 1))
    }

    func select1(_ r: Int) -> Int {
        guard r >= 1, r <= totalOnes, bitCount > 0 else { return -1 }
        var lo = 0, hi = bigBlockRanks.count - 1, bigBlock = 0
        while lo <= hi {
            let mid = (lo + hi) >> 1
            if bigBlockRanks[mid] < r { bigBlock = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        let localTarget = r - bigBlockRanks[bigBlock]
        let baseSmall   = bigBlock * Self.smallBlocksPerBig
        let smallCount  = min(Self.smallBlocksPerBig, smallBlockRanks.count - baseSmall)
        var smallBlock  = 0
        while smallBlock < smallCount - 1,
              Int(smallBlockRanks[baseSmall + smallBlock + 1]) < localTarget {
            smallBlock += 1
        }
        let offsetInSmall = localTarget - Int(smallBlockRanks[baseSmall + smallBlock])
        let smallStart    = bigBlock * Self.bigBlockBits + smallBlock * Self.smallBlockBits
        var count = 0
        for off in 0 ..< Self.smallBlockBits {
            let pos = smallStart + off
            if pos >= bitCount { break }
            if get(pos) { count += 1; if count == offsetInSmall { return pos } }
        }
        return -1
    }

    func select0(_ r: Int) -> Int {
        let totalZeros = bitCount - totalOnes
        guard r >= 1, r <= totalZeros, bitCount > 0 else { return -1 }
        var lo = 0, hi = bigBlockRanks.count - 1, bigBlock = 0
        while lo <= hi {
            let mid = (lo + hi) >> 1
            if mid * Self.bigBlockBits - bigBlockRanks[mid] < r { bigBlock = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        let zerosBeforeBlock = bigBlock * Self.bigBlockBits - bigBlockRanks[bigBlock]
        let localTarget      = r - zerosBeforeBlock
        let baseSmall        = bigBlock * Self.smallBlocksPerBig
        let smallCount       = min(Self.smallBlocksPerBig, smallBlockRanks.count - baseSmall)
        var smallBlock = 0
        while smallBlock < smallCount - 1 {
            let next = smallBlock + 1
            if next * Self.smallBlockBits - Int(smallBlockRanks[baseSmall + next]) < localTarget {
                smallBlock += 1
            } else { break }
        }
        let zerosBeforeSmall = smallBlock * Self.smallBlockBits - Int(smallBlockRanks[baseSmall + smallBlock])
        let offsetInSmall    = localTarget - zerosBeforeSmall
        let smallStart       = bigBlock * Self.bigBlockBits + smallBlock * Self.smallBlockBits
        var count = 0
        for off in 0 ..< Self.smallBlockBits {
            let pos = smallStart + off
            if pos >= bitCount { break }
            if !get(pos) { count += 1; if count == offsetInSmall { return pos } }
        }
        return -1
    }

    private static func buildRank1ByWord(_ words: [UInt64]) -> [Int] {
        var rank = [Int](repeating: 0, count: words.count + 1)
        for (i, w) in words.enumerated() { rank[i + 1] = rank[i] + w.nonzeroBitCount }
        return rank
    }

    private static func buildBlockRanks(
        bitCount: Int, words: [UInt64]
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

// MARK: - テストヘルパー

private var passCount = 0
private var failCount = 0

private func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passCount += 1
    } else {
        failCount += 1
        let fileName = (file as NSString).lastPathComponent
        print("❌ FAIL [\(fileName):\(line)] \(message)")
    }
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ msg: String, file: String = #file, line: Int = #line) {
    if lhs == rhs {
        passCount += 1
    } else {
        failCount += 1
        let fileName = (file as NSString).lastPathComponent
        print("❌ FAIL [\(fileName):\(line)] \(msg)  got=\(lhs)  expected=\(rhs)")
    }
}

// MARK: - brute-force 参照実装 (テスト検証用)

private func bruteRank1(_ bits: [Bool], through index: Int) -> Int {
    guard index >= 0 else { return 0 }
    return bits.prefix(index + 1).filter { $0 }.count
}
private func bruteSelect1(_ bits: [Bool], rank r: Int) -> Int {
    var count = 0
    for (i, b) in bits.enumerated() { if b { count += 1; if count == r { return i } } }
    return -1
}
private func bruteSelect0(_ bits: [Bool], rank r: Int) -> Int {
    var count = 0
    for (i, b) in bits.enumerated() { if !b { count += 1; if count == r { return i } } }
    return -1
}

// MARK: - テストケース

private func testSmallGetRank1Rank0() {
    // [1, 0, 1, 1, 0]  → ones at 0,2,3
    let bits: [Bool] = [true, false, true, true, false]
    let bv = CompatibleBitVector(bits: bits)

    expectEqual(bv.get(0), true,  "get(0)")
    expectEqual(bv.get(1), false, "get(1)")
    expectEqual(bv.get(2), true,  "get(2)")
    expectEqual(bv.get(3), true,  "get(3)")
    expectEqual(bv.get(4), false, "get(4)")
    expectEqual(bv.get(5), false, "get(out-of-range)")

    expectEqual(bv.rank1(0), 1, "rank1(0)")
    expectEqual(bv.rank1(1), 1, "rank1(1)")
    expectEqual(bv.rank1(2), 2, "rank1(2)")
    expectEqual(bv.rank1(3), 3, "rank1(3)")
    expectEqual(bv.rank1(4), 3, "rank1(4)")

    expectEqual(bv.rank0(0), 0, "rank0(0)")
    expectEqual(bv.rank0(1), 1, "rank0(1)")
    expectEqual(bv.rank0(4), 2, "rank0(4)")
}

private func testSmallSelect() {
    let bits: [Bool] = [true, false, true, true, false]
    let bv = CompatibleBitVector(bits: bits)

    expectEqual(bv.select1(1), 0, "select1(1)")
    expectEqual(bv.select1(2), 2, "select1(2)")
    expectEqual(bv.select1(3), 3, "select1(3)")
    expectEqual(bv.select1(4), -1, "select1(out-of-range)")
    expectEqual(bv.select1(0), -1, "select1(0) = invalid")

    expectEqual(bv.select0(1), 1, "select0(1)")
    expectEqual(bv.select0(2), 4, "select0(2)")
    expectEqual(bv.select0(3), -1, "select0(out-of-range)")
    expectEqual(bv.select0(0), -1, "select0(0) = invalid")
}

private func testFirstBitOne() {
    // 先頭 bit が 1 のケース
    let bits: [Bool] = [true, false, false, true]
    let bv = CompatibleBitVector(bits: bits)
    expectEqual(bv.get(0), true,  "first=1 get(0)")
    expectEqual(bv.rank1(0), 1,   "first=1 rank1(0)")
    expectEqual(bv.select1(1), 0, "first=1 select1(1)")
}

private func testFirstBitZero() {
    // 先頭 bit が 0 のケース
    let bits: [Bool] = [false, true, false, true]
    let bv = CompatibleBitVector(bits: bits)
    expectEqual(bv.get(0), false, "first=0 get(0)")
    expectEqual(bv.rank1(0), 0,   "first=0 rank1(0)")
    expectEqual(bv.select0(1), 0, "first=0 select0(1)")
}

private func testLastBitOne() {
    let bits: [Bool] = [false, false, false, true]
    let bv = CompatibleBitVector(bits: bits)
    expectEqual(bv.get(3), true,  "last=1 get(3)")
    expectEqual(bv.rank1(3), 1,   "last=1 rank1(3)")
    expectEqual(bv.select1(1), 3, "last=1 select1(1)")
}

private func testLastBitZero() {
    let bits: [Bool] = [true, true, true, false]
    let bv = CompatibleBitVector(bits: bits)
    expectEqual(bv.get(3), false, "last=0 get(3)")
    expectEqual(bv.rank0(3), 1,   "last=0 rank0(3)")
    expectEqual(bv.select0(1), 3, "last=0 select0(1)")
}

private func testAllOnes() {
    // 1 が多いケース
    let bits = [Bool](repeating: true, count: 100)
    let bv = CompatibleBitVector(bits: bits)
    expectEqual(bv.totalOnes, 100,    "allOnes totalOnes")
    expectEqual(bv.rank1(99), 100,    "allOnes rank1(99)")
    expectEqual(bv.rank0(99), 0,      "allOnes rank0(99)")
    expectEqual(bv.select1(100), 99,  "allOnes select1(100)")
    expectEqual(bv.select0(1),   -1,  "allOnes select0(1) = -1")
}

private func testAllZeros() {
    // 0 が多いケース
    let bits = [Bool](repeating: false, count: 100)
    let bv = CompatibleBitVector(bits: bits)
    expectEqual(bv.totalOnes, 0,     "allZeros totalOnes")
    expectEqual(bv.rank1(99), 0,     "allZeros rank1(99)")
    expectEqual(bv.rank0(99), 100,   "allZeros rank0(99)")
    expectEqual(bv.select0(100), 99, "allZeros select0(100)")
    expectEqual(bv.select1(1),   -1, "allZeros select1(1) = -1")
}

private func testCross256Boundary() {
    // 256 bit 境界をまたぐケース: bit 255 と bit 256 に 1 を置く
    var bits = [Bool](repeating: false, count: 512)
    bits[255] = true   // big block 0 の最後
    bits[256] = true   // big block 1 の先頭
    bits[511] = true   // big block 1 の最後
    let bv = CompatibleBitVector(bits: bits)

    expectEqual(bv.get(255), true,  "cross256 get(255)")
    expectEqual(bv.get(256), true,  "cross256 get(256)")
    expectEqual(bv.get(511), true,  "cross256 get(511)")
    expectEqual(bv.rank1(255), 1,   "cross256 rank1(255)")
    expectEqual(bv.rank1(256), 2,   "cross256 rank1(256)")
    expectEqual(bv.rank1(511), 3,   "cross256 rank1(511)")
    expectEqual(bv.select1(1), 255, "cross256 select1(1)")
    expectEqual(bv.select1(2), 256, "cross256 select1(2)")
    expectEqual(bv.select1(3), 511, "cross256 select1(3)")
}

private func testOver512Bits() {
    // 512 bit 以上のケース: 全部 alternating 0/1
    let count = 600
    let bits = (0..<count).map { $0 % 2 == 1 }   // 1,3,5,...が 1
    let bv = CompatibleBitVector(bits: bits)

    // brute-force と突き合わせ
    for i in [0, 1, 63, 64, 255, 256, 511, 512, 599] {
        let expected = bruteRank1(bits, through: i)
        expectEqual(bv.rank1(i), expected, "alternating rank1(\(i))")
    }
    for r in [1, 2, 100, 200, 299, 300] {
        let expected1 = bruteSelect1(bits, rank: r)
        let expected0 = bruteSelect0(bits, rank: r)
        expectEqual(bv.select1(r), expected1, "alternating select1(\(r))")
        expectEqual(bv.select0(r), expected0, "alternating select0(\(r))")
    }
}

private func testInitBitCountWords() {
    // init(bitCount:words:) 経由のケース (MozcArtifactIO が使うパス)
    // bits = [1,0,1,0, 1,1,0,0] → word[0] = 0b00110101 = 0x35 = 53
    let bits: [Bool] = [true,false,true,false, true,true,false,false]
    let bvFromBools = CompatibleBitVector(bits: bits)
    let bvFromWords = CompatibleBitVector(bitCount: 8, words: [UInt64(0x35)])

    for i in 0..<8 {
        expectEqual(bvFromWords.get(i), bvFromBools.get(i), "initWords get(\(i))")
        expectEqual(bvFromWords.rank1(i), bvFromBools.rank1(i), "initWords rank1(\(i))")
        expectEqual(bvFromWords.rank0(i), bvFromBools.rank0(i), "initWords rank0(\(i))")
    }
    expectEqual(bvFromWords.totalOnes, bvFromBools.totalOnes, "initWords totalOnes")
    for r in 1...4 {
        expectEqual(bvFromWords.select1(r), bvFromBools.select1(r), "initWords select1(\(r))")
    }
    for r in 1...4 {
        expectEqual(bvFromWords.select0(r), bvFromBools.select0(r), "initWords select0(\(r))")
    }
}

private func testRandomBitsAgainstBruteForce() {
    // ランダムなビット列でブルートフォースと比較
    var rng = SystemRandomNumberGenerator()
    let count = 700
    let bits = (0..<count).map { _ in Bool.random(using: &rng) }
    let bv = CompatibleBitVector(bits: bits)

    let totalOnes  = bits.filter { $0 }.count
    let totalZeros = bits.filter { !$0 }.count

    // rank の抽出検証
    for i in stride(from: 0, to: count, by: 50) {
        expectEqual(bv.rank1(i), bruteRank1(bits, through: i), "random rank1(\(i))")
    }
    // select1 の検証
    for r in stride(from: 1, through: min(totalOnes, 30), by: 3) {
        expectEqual(bv.select1(r), bruteSelect1(bits, rank: r), "random select1(\(r))")
    }
    // select0 の検証
    for r in stride(from: 1, through: min(totalZeros, 30), by: 3) {
        expectEqual(bv.select0(r), bruteSelect0(bits, rank: r), "random select0(\(r))")
    }
    // 境界外
    expectEqual(bv.select1(totalOnes + 1), -1, "random select1(oob)")
    expectEqual(bv.select0(totalZeros + 1), -1, "random select0(oob)")
}

private func testLOUDSLikePattern() {
    // LOUDS 辞書で典型的な bits = [1,0, 1,0, 1,1,1,0, 0, 1,0, ...]
    // firstChild: select0(rank1(pos)) + 1 のパターン
    let bits: [Bool] = [
        true, false,   // root
        true, false,   // node 1 (leaf)
        true, true, true, false,  // node 2 (3 children)
        false,         // node 3 (leaf)
        true, false,   // node 4 child of node 2
        false,         // node 5 child of node 2
        true, false,   // node 6 child of node 2
    ]
    let bv = CompatibleBitVector(bits: bits)

    // pos=0 (root): rank1(0)=1, select0(1)=1, firstChild = 2
    let r1_0 = bv.rank1(0)
    let s0_r1_0 = bv.select0(r1_0)
    expectEqual(r1_0, 1,  "louds rank1(0)")
    expectEqual(s0_r1_0, 1, "louds select0(1)")
    expectEqual(s0_r1_0 + 1, 2, "louds firstChild(0)")

    // pos=2: rank1(2)=2, select0(2)=3, firstChild = 4
    let r1_2 = bv.rank1(2)
    let s0_r1_2 = bv.select0(r1_2)
    expectEqual(r1_2, 2,  "louds rank1(2)")
    expectEqual(s0_r1_2, 3, "louds select0(2)")
    expectEqual(s0_r1_2 + 1, 4, "louds firstChild(2)")
}

// MARK: - エントリポイント

func runAllTests() {
    print("=== CompatibleBitVector Tests ===\n")

    testSmallGetRank1Rank0()
    testSmallSelect()
    testFirstBitOne()
    testFirstBitZero()
    testLastBitOne()
    testLastBitZero()
    testAllOnes()
    testAllZeros()
    testCross256Boundary()
    testOver512Bits()
    testInitBitCountWords()
    testRandomBitsAgainstBruteForce()
    testLOUDSLikePattern()

    print("\nResult: \(passCount) passed, \(failCount) failed")
    if failCount > 0 {
        print("❌ Some tests FAILED.")
        exit(1)
    } else {
        print("✅ All tests passed.")
    }
}

runAllTests()
