// Seam B — the exercise resolver. Maps a spoken name to an Exercise in the
// library, with a confidence score, or reports it unresolved with best guesses.
// See specs/v1-voice-logging.md.
//
// Matching (per design): normalise both sides, then score each candidate string
// (name + aliases) as max(edit similarity, token-set similarity). Exact match
// short-circuits to 1.0. score >= 0.85 resolves; the 0.60–0.85 band resolves
// carrying its real (lower) confidence; below 0.60 is unresolved with the top 3
// guesses. No phonetic matching in v1.

import Foundation

private let resolveThreshold = 0.60

/// A fuzzy match at least this strong is treated as confident: strong enough to
/// auto-log a set against (the parser) and to repair a misheard name toward
/// (the post-processor). Matches in `resolveThreshold ..< confidentMatchThreshold`
/// still resolve, but carry their real, lower confidence.
let confidentMatchThreshold = 0.85

public func resolve(_ spokenText: String, in library: ExerciseLibrary) -> ExerciseResolution {
    let needle = normalized(spokenText)
    guard !needle.isEmpty else { return .unresolved(bestGuesses: []) }

    for exercise in library.exercises where candidateStrings(exercise).contains(needle) {
        return .resolved(exercise, confidence: 1.0)
    }

    let ranked = library.exercises
        .map { (exercise: $0, score: bestScore(needle, for: $0)) }
        .sorted(by: ranksAbove)

    guard let best = ranked.first, best.score >= resolveThreshold else {
        return .unresolved(bestGuesses: ranked.prefix(3).map(\.exercise))
    }
    return .resolved(best.exercise, confidence: best.score)
}

// MARK: - Scoring

private func bestScore(_ needle: String, for exercise: Exercise) -> Double {
    candidateStrings(exercise)
        .map { max(editSimilarity(needle, $0), tokenSetSimilarity(needle, $0)) }
        .max() ?? 0
}

private func ranksAbove(
    _ lhs: (exercise: Exercise, score: Double),
    _ rhs: (exercise: Exercise, score: Double)
) -> Bool {
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.exercise.name.count != rhs.exercise.name.count {
        return lhs.exercise.name.count < rhs.exercise.name.count
    }
    return lhs.exercise.name < rhs.exercise.name
}

private func editSimilarity(_ a: String, _ b: String) -> Double {
    let maxLen = max(a.count, b.count)
    guard maxLen > 0 else { return 1 }
    return 1 - Double(levenshtein(a, b)) / Double(maxLen)
}

private func tokenSetSimilarity(_ a: String, _ b: String) -> Double {
    let x = Set(a.split(separator: " "))
    let y = Set(b.split(separator: " "))
    guard !x.isEmpty, !y.isEmpty else { return 0 }
    return Double(x.intersection(y).count) / Double(x.union(y).count)
}

private func levenshtein(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
        current[0] = i
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            current[j] = min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + cost
            )
        }
        swap(&previous, &current)
    }
    return previous[b.count]
}

// MARK: - Normalisation

private func candidateStrings(_ exercise: Exercise) -> [String] {
    ([exercise.name] + exercise.aliases).map(normalized)
}

private func normalized(_ text: String) -> String {
    let mapped = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
    return String(mapped).split(separator: " ").joined(separator: " ")
}
