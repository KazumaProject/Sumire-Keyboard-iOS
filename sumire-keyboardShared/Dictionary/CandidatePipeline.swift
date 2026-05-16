import Foundation

enum CandidateSourceKind: Hashable, Sendable {
    case systemMain
    case systemAuxiliary
    case systemSingleKanji
    case systemEnglish
    case learning
    case user
    case fallback
    case direct
}

extension CandidateSourceKind {
    static let systemDisplayOrder: [CandidateSourceKind] = [
        .systemMain,
        .systemAuxiliary,
        .systemSingleKanji,
        .systemEnglish,
        .fallback,
        .direct
    ]
}

struct CandidateLexicalInfo: Hashable, Sendable {
    let score: Int
    let leftId: Int
    let rightId: Int
}

struct CandidateDedupKey: Hashable, Sendable {
    let reading: String
    let word: String
}

struct Candidate: Hashable, Sendable {
    let reading: String
    let word: String
    let consumedReadingLength: Int
    let sourceKind: CandidateSourceKind
    let lexicalInfo: CandidateLexicalInfo?

    var dedupKey: CandidateDedupKey {
        CandidateDedupKey(reading: reading, word: word)
    }
}

protocol CandidateSource: Sendable {
    var kind: CandidateSourceKind { get }
    func searchExact(reading: String, limit: Int) -> [Candidate]
    func searchCommonPrefix(inputReading: String, limit: Int) -> [Candidate]
    func searchPredictive(prefix: String, limit: Int) -> [Candidate]
}

enum CandidateScoreStrategy: Hashable, Sendable {
    case max
    case sourceWeighted([CandidateSourceKind: Int])
    case customNamed(String)
}

struct CandidateMergePolicy: Hashable, Sendable {
    let sourcePriority: [CandidateSourceKind]
    let scoreStrategy: CandidateScoreStrategy
    let totalLimit: Int
    let includesAuxiliaryCandidates: Bool

    func dedupKey(for candidate: Candidate) -> CandidateDedupKey {
        candidate.dedupKey
    }

    func sourcePriorityRank(for kind: CandidateSourceKind) -> Int {
        sourcePriority.firstIndex(of: kind) ?? sourcePriority.count
    }
}

struct CandidatePipeline: Sendable {
    let sources: [any CandidateSource]
    let mergePolicy: CandidateMergePolicy

    func candidates(for inputReading: String, limit: Int) -> [Candidate] {
        let effectiveLimit = min(max(limit, 0), max(mergePolicy.totalLimit, 0))
        guard inputReading.isEmpty == false, effectiveLimit > 0 else {
            return []
        }

        var collected: [Candidate] = []
        collected.reserveCapacity(effectiveLimit)

        for source in sources {
            if source.kind == .systemAuxiliary, mergePolicy.includesAuxiliaryCandidates == false {
                continue
            }

            let remainingLimit = max(effectiveLimit - collected.count, 1)
            collected.append(contentsOf: source.searchExact(reading: inputReading, limit: remainingLimit))

            if source.kind != .systemMain,
               source.kind != .systemEnglish,
               source.kind != .fallback,
               source.kind != .direct {
                collected.append(contentsOf: source.searchCommonPrefix(inputReading: inputReading, limit: remainingLimit))
                collected.append(contentsOf: source.searchPredictive(prefix: inputReading, limit: remainingLimit))
            }
        }

        return merge(collected).prefix(effectiveLimit).map { $0 }
    }

    private func merge(_ candidates: [Candidate]) -> [Candidate] {
        var bestByKey: [CandidateDedupKey: Candidate] = [:]
        var firstIndexByKey: [CandidateDedupKey: Int] = [:]

        for (index, candidate) in candidates.enumerated() {
            let key = mergePolicy.dedupKey(for: candidate)
            if let current = bestByKey[key] {
                if shouldReplace(current: current, with: candidate) {
                    bestByKey[key] = candidate
                }
            } else {
                bestByKey[key] = candidate
                firstIndexByKey[key] = index
            }
        }

        return bestByKey.values.sorted { lhs, rhs in
            let lhsRank = mergePolicy.sourcePriorityRank(for: lhs.sourceKind)
            let rhsRank = mergePolicy.sourcePriorityRank(for: rhs.sourceKind)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let lhsScore = effectiveScore(for: lhs)
            let rhsScore = effectiveScore(for: rhs)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            let lhsIndex = firstIndexByKey[mergePolicy.dedupKey(for: lhs)] ?? Int.max
            let rhsIndex = firstIndexByKey[mergePolicy.dedupKey(for: rhs)] ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }

            return lhs.word < rhs.word
        }
    }

    private func shouldReplace(current: Candidate, with candidate: Candidate) -> Bool {
        let currentRank = mergePolicy.sourcePriorityRank(for: current.sourceKind)
        let candidateRank = mergePolicy.sourcePriorityRank(for: candidate.sourceKind)
        if currentRank != candidateRank {
            return candidateRank < currentRank
        }

        guard current.sourceKind == candidate.sourceKind else {
            return false
        }

        return effectiveScore(for: candidate) < effectiveScore(for: current)
    }

    private func effectiveScore(for candidate: Candidate) -> Int {
        let baseScore = candidate.lexicalInfo?.score ?? 0
        switch mergePolicy.scoreStrategy {
        case .max:
            return baseScore
        case .sourceWeighted(let weights):
            return baseScore + (weights[candidate.sourceKind] ?? 0)
        case .customNamed:
            return baseScore
        }
    }
}
