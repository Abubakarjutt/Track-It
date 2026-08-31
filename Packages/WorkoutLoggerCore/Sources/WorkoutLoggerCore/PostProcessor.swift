// Seam 2 — the STT post-processor. Takes the on-device recogniser's n-best
// hypotheses (best-first) and produces one corrected transcript for the parser.
// Pure and synchronous: no Speech framework, no I/O. See specs/v1-voice-logging.md.
//
// Steps, in order: pick the best hypothesis, split off the leading exercise-name
// span, bias that span toward the library, and coerce spoken number words to
// digits in what's left. Splitting first keeps a name-embedded number word (the
// "one" in "one arm row") out of the coercion.

public func postProcess(_ hypotheses: [String], library: ExerciseLibrary) -> String {
    let tokens = bestHypothesis(hypotheses, library: library)
        .split(separator: " ").map(String.init)
    let (name, rest) = splitNameSpan(tokens, library: library)
    return (biasExerciseName(name, library: library) + coerceNumberWords(rest))
        .joined(separator: " ")
}

// MARK: - Hypothesis selection

/// Picks the hypothesis whose leading name span resolves best against the
/// library. Strict improvement wins, so ties keep the recogniser's own ordering;
/// with no library match every hypothesis scores 0 and the first is kept.
private func bestHypothesis(_ hypotheses: [String], library: ExerciseLibrary) -> String {
    guard var chosen = hypotheses.first else { return "" }
    var chosenScore = nameConfidence(chosen, library: library)
    for hypothesis in hypotheses.dropFirst() {
        let score = nameConfidence(hypothesis, library: library)
        if score > chosenScore {
            chosen = hypothesis
            chosenScore = score
        }
    }
    return chosen
}

private func nameConfidence(_ hypothesis: String, library: ExerciseLibrary) -> Double {
    let tokens = hypothesis.split(separator: " ").map(String.init)
    let (name, _) = splitNameSpan(tokens, library: library)
    guard !name.isEmpty,
          case .resolved(_, let confidence) = resolve(name.joined(separator: " "), in: library)
    else { return 0 }
    return confidence
}

// MARK: - Exercise-name span

// Tokens that mark the end of a leading exercise-name span.
private let nameStopWords: Set<String> = [
    "for", "warmup", "plus", "assisted", "dropset", "drop", "minus", "superset",
]

/// Splits the leading exercise-name span from the rest. Preferred span: the
/// longest leading run of non-digit, non-stopword tokens that resolves
/// confidently against the library (so "one arm row" stays whole). Failing that,
/// the span stops at the first spoken-number token, leaving "two twenty five" and
/// the like for number coercion.
private func splitNameSpan(
    _ tokens: [String], library: ExerciseLibrary
) -> (name: [String], rest: [String]) {
    func split(at end: Int) -> ([String], [String]) {
        (Array(tokens[..<end]), Array(tokens[end...]))
    }

    let greedyEnd = tokens.prefix {
        Int($0) == nil && !nameStopWords.contains($0.lowercased())
    }.count
    if greedyEnd > 0,
       case .resolved(_, let confidence) =
        resolve(tokens[..<greedyEnd].joined(separator: " "), in: library),
       confidence >= confidentMatchThreshold {
        return split(at: greedyEnd)
    }

    let plainEnd = tokens.prefix {
        Int($0) == nil && !nameStopWords.contains($0.lowercased()) && !isNumberToken($0)
    }.count
    return split(at: plainEnd)
}

/// Rewrites the name span to an exercise's canonical name when the resolver
/// matches it strongly but not exactly (`confidentMatchThreshold ..< 1.0`) — a
/// mishearing worth repairing. An exact match (1.0) is already right; a weak one
/// is left for the parser to flag.
private func biasExerciseName(_ name: [String], library: ExerciseLibrary) -> [String] {
    guard !name.isEmpty,
          case .resolved(let exercise, let confidence) =
            resolve(name.joined(separator: " "), in: library),
          (confidentMatchThreshold ..< 1.0).contains(confidence)
    else { return name }

    return exercise.name.lowercased().split(separator: " ").map(String.init)
}

// MARK: - Number-word coercion

private let numberWords: [String: Int] = [
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
    "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
]

/// Collapses each maximal run of spoken-number tokens into a single digit string,
/// leaving every other token untouched. A run that matches no known shape falls
/// back to per-token replacement so nothing regresses.
private func coerceNumberWords(_ words: [String]) -> [String] {
    var out: [String] = []
    var i = 0
    while i < words.count {
        guard isNumberToken(words[i]) else {
            out.append(words[i]); i += 1
            continue
        }
        var run: [String] = []
        while i < words.count, isNumberToken(words[i]) {
            run.append(words[i]); i += 1
        }
        if let value = interpretNumberRun(run) {
            out.append(String(value))
        } else {
            out.append(contentsOf: run.map { numberWords[$0.lowercased()].map(String.init) ?? $0 })
        }
    }
    return out
}

private func isNumberToken(_ word: String) -> Bool {
    let lower = word.lowercased()
    return numberWords[lower] != nil || lower == "hundred" || lower == "oh" || lower == "o"
}

private func isRoundTen(_ n: Int) -> Bool { n >= 20 && n <= 90 && n % 10 == 0 }

/// Interprets a run of spoken-number tokens the way lifters actually say gym
/// numbers. Returns `nil` if the run is not a shape we recognise.
///
///   two twenty five      → 225   (leading digit is hundreds; then tens + ones)
///   one thirty five      → 135
///   twenty five          → 25
///   one oh five          → 105
///   one hundred          → 100
///   two hundred twenty   → 220
private func interpretNumberRun(_ run: [String]) -> Int? {
    let tokens = run.map { $0.lowercased() }
    func value(_ token: String) -> Int {
        (token == "oh" || token == "o") ? 0 : (numberWords[token] ?? 0)
    }

    if let hundred = tokens.firstIndex(of: "hundred") {
        let before = tokens[..<hundred].map(value).reduce(0, +)
        let after = tokens[(hundred + 1)...].map(value).reduce(0, +)
        return (before == 0 ? 1 : before) * 100 + after
    }

    let values = tokens.map(value)
    switch values.count {
    case 1:
        return values[0]
    case 2:
        if (1...9).contains(values[0]), (10...99).contains(values[1]) {
            return values[0] * 100 + values[1]
        }
        if isRoundTen(values[0]), (1...9).contains(values[1]) {
            return values[0] + values[1]
        }
        return nil
    case 3:
        if (1...9).contains(values[0]), isRoundTen(values[1]), (1...9).contains(values[2]) {
            return values[0] * 100 + values[1] + values[2]
        }
        if (1...9).contains(values[0]), tokens[1] == "oh" || tokens[1] == "o", (1...9).contains(values[2]) {
            return values[0] * 100 + values[2]
        }
        return nil
    default:
        return nil
    }
}
