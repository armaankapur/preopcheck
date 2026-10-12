//
//  PageAnalysis.swift
//  PreOpCheck
//
//  The scanner's decision step, on its own: recognised text lines in, four
//  answers out. Which lines are PARC drugs (green), which are drugs PARC has
//  nothing on (red), which identify the patient (blur), and which sit in an
//  allergy section (ignored). Nothing here knows about the camera or the
//  screen, so the same code runs on a live frame, on the Simulator's sample
//  page, and on fixture images in the tests.
//
//  Coordinates are Vision's: normalised, y pointing up.
//

import CoreGraphics
import Foundation
import Vision

/// One recognised line with a box per word, so markers can sit on the
/// matched words rather than the whole line.
struct RecognizedLine {
    let text: String
    let box: CGRect
    let tokens: [OCRToken]

    var scanned: ScannedLine { ScannedLine(text: text, box: box) }
}

struct PageAnalysis {

    /// A box to draw, keyed so the scanner can glide the same marker between
    /// frames. Green keys are drug ids; red keys are "red:" + ingredient.
    struct Marker: Equatable {
        let key: String
        let box: CGRect
    }

    /// PARC drugs seen on this page, strongest match per drug. The scanner
    /// feeds these to its stability tracker.
    let matches: [DrugMatch]
    let green: [Marker]
    let red: [Marker]
    /// Lines to blur. Never a line that carries a drug.
    let redactions: [CGRect]

    // MARK: From Vision

    /// Builds lines from Vision's observations. The only place Vision types
    /// are touched; the tests use it on fixture images.
    static func lines(from observations: [VNRecognizedTextObservation]) -> [RecognizedLine] {
        observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let tokens = candidate.string.split(separator: " ").map { word -> OCRToken in
                let range = word.startIndex..<word.endIndex
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? obs.boundingBox
                return OCRToken(text: String(word), box: box, ocrConfidence: candidate.confidence)
            }
            return RecognizedLine(text: candidate.string, box: obs.boundingBox, tokens: tokens)
        }
    }

    // MARK: Analysis

    /// `roi` is the guide box in Vision space; lines outside it are not
    /// matched, though they still count for the privacy blur.
    static func analyze(_ lines: [RecognizedLine],
                        roi: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> PageAnalysis {
        let allLines = lines.map(\.scanned)
        // Allergy-style sections, worked out from the lines in the guide box.
        let excludedBands = SectionExclusion.bands(in: allLines.filter { roi.intersects($0.box) })

        var frameMatches: [String: DrugMatch] = [:]
        var greenBoxes: [String: CGRect] = [:]          // drug id -> marker box
        var unlisted: [(ingredient: String, box: CGRect)] = []

        // Lines that already carry a marker, used to recognise the detail
        // line printed under a drug name ("acetaminophen 500 mg tablet") so
        // it is not marked a second time. `lastPlainLine` is the most recent
        // line with no drug on it: when a title misreads and only its detail
        // line is recognised, the marker is promoted onto that title line.
        var markedLines: [CGRect] = []
        var lastPlainLine: CGRect?
        var seenUnlisted = Set<String>()

        // Privacy: lines that identify the patient, judged across the whole
        // page so a header above the guide box counts too. Any that turn out
        // to carry a drug are dropped from this list afterwards.
        let identityLines = PatientIdentity.identityLines(in: allLines)

        // Top of the page first, so "first seen" means "the title line";
        // within a row, left to right, so a name is seen before its brand.
        for line in readingOrder(lines) {
            guard roi.intersects(line.box) else { continue }

            // Skip the allergy heading and the section under it.
            if SectionExclusion.isExcluded(line.box, by: excludedBands) { continue }

            let matches = DrugMatcher.shared.match(line.tokens)
            for match in matches {
                if let existing = frameMatches[match.id] {
                    frameMatches[match.id] = match.matchKind > existing.matchKind ? match : existing
                } else {
                    frameMatches[match.id] = match
                }
                // First line wins (the title), and the box grows to take in
                // a bracketed brand right after the name.
                if greenBoxes[match.id] == nil {
                    greenBoxes[match.id] = titleBox(hitBoxes: match.boxes, in: line.tokens)
                }
            }
            // A line with a PARC match is done: its brand in brackets, or any
            // other word on it, never gets a red box of its own.
            if !matches.isEmpty {
                markedLines.append(line.box)
                continue
            }

            // Red: a known drug (per the lexicon) that PARC has nothing on.
            // One box per line covering name and brand together. A drug whose
            // ingredient was already marked higher up (the detail line under
            // "Vitamin D3" says "cholecalciferol") is skipped.
            // The FDA list has products called "Allergies" and "Full", so a
            // hit only counts on a line that looks like a medication entry.
            let hits = unlistedDrugHits(in: line.tokens)
                .filter { !seenUnlisted.contains($0.ingredient) }
            guard !hits.isEmpty,
                  MedicationLineCues.hasMedicationContext(text: line.text, box: line.box, in: allLines)
            else {
                lastPlainLine = line.box
                continue
            }

            let isDetail = MedicationLineCues.looksLikeDetailLine(line.text)
            var box = titleBox(hitBoxes: hits.map(\.box), in: line.tokens)
            if isDetail {
                if MedicationLineCues.isDirectlyBelow(line.box, markedLines) {
                    continue            // detail line of a drug already marked
                }
                if let title = lastPlainLine,
                   MedicationLineCues.isDirectlyBelow(line.box, [title]) {
                    box = title         // title misread: mark the title line instead
                }
            }

            hits.forEach { seenUnlisted.insert($0.ingredient) }
            unlisted.append((hits[0].ingredient, box))
            markedLines.append(line.box)
        }

        // Non-drug text is never retained. Only box positions leave here,
        // for drawing; the words themselves are discarded.
        return PageAnalysis(
            matches: Array(frameMatches.values),
            green: greenBoxes.map { Marker(key: $0.key, box: absorbBrandCell($0.value, in: allLines)) },
            red: unlisted.map { Marker(key: "red:" + $0.ingredient, box: absorbBrandCell($0.box, in: allLines)) },
            redactions: identityLines.filter { line in !markedLines.contains { $0.intersects(line) } }
        )
    }

    // MARK: Helpers

    /// Rows from the top of the page down; within a row, left to right.
    /// Recognition returns table cells as separate boxes in no fixed order.
    private static func readingOrder(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        var rows: [[RecognizedLine]] = []
        for line in lines.sorted(by: { $0.box.maxY > $1.box.maxY }) {
            if let last = rows.indices.last, rows[last][0].box.sharesRow(with: line.box) {
                rows[last].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// When recognition splits "(Tylenol)" into its own cell beside the
    /// name, the marker grows to take it in, so the whole entry is boxed.
    private static func absorbBrandCell(_ box: CGRect, in lines: [ScannedLine]) -> CGRect {
        guard let brand = lines.first(where: { line in
            line.text.hasPrefix("(")
                && line.box.sharesRow(with: box)
                && line.box.minX >= box.maxX - box.height * 0.3
                && line.box.minX - box.maxX < box.height * 1.5
        }) else { return box }
        return box.union(brand.box)
    }

    /// Phrases on one line that the drug lexicon knows, with their ingredient
    /// key and box. Tries multi-word names first, longest span wins. Returns
    /// nothing while no lexicon is bundled.
    private static func unlistedDrugHits(in tokens: [OCRToken]) -> [(ingredient: String, box: CGRect)] {
        let lexicon = DrugLexicon.shared
        guard !lexicon.isEmpty, !tokens.isEmpty else { return [] }

        let norms = tokens.map { DrugMatcher.normalize($0.text) }
        var consumed = Set<Int>()
        var hits: [(ingredient: String, box: CGRect)] = []

        for span in stride(from: min(lexicon.maxWords, tokens.count), through: 1, by: -1) {
            for start in 0...(tokens.count - span) {
                let range = start..<(start + span)
                if range.contains(where: { consumed.contains($0) }) { continue }
                let phrase = norms[range].filter { !$0.isEmpty }.joined(separator: " ")
                guard phrase.count >= 4, let ingredient = lexicon.ingredient(for: phrase) else { continue }
                let union = tokens[range].dropFirst().reduce(tokens[start].box) { $0.union($1.box) }
                hits.append((ingredient, union))
                range.forEach { consumed.insert($0) }
            }
        }
        return hits
    }

    /// The marker box for a drug on one line: the words that matched, any
    /// release-form tag after them ("HFA", "ER"), and a bracketed brand name
    /// after that, so "Albuterol HFA (ProAir HFA)" is boxed as one even when
    /// the brand is in neither list.
    private static func titleBox(hitBoxes: [CGRect], in tokens: [OCRToken]) -> CGRect {
        guard var box = hitBoxes.first else { return .zero }
        hitBoxes.dropFirst().forEach { box = box.union($0) }

        // A two-word match ("metoprolol succinate") comes back as one box
        // covering both words, so look for overlap rather than equality.
        guard let last = tokens.lastIndex(where: { token in hitBoxes.contains { $0.intersects(token.box) } })
        else { return box }

        var i = last + 1
        while i < tokens.count, MedicationLineCues.isFormulationTag(tokens[i].text) {
            box = box.union(tokens[i].box)
            i += 1
        }
        guard i < tokens.count, tokens[i].text.hasPrefix("(") else { return box }
        // Up to four words of brand; a table border can stick to the closing
        // bracket ("HFA)|"), so look for the bracket anywhere in the word.
        let end = min(tokens.count, i + 4)
        while i < end {
            box = box.union(tokens[i].box)
            if tokens[i].text.contains(")") { break }
            i += 1
        }
        return box
    }
}
