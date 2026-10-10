import Foundation

enum VocabularyEntriesTests {
    static func run() {
        testEntriesKeepVariantsTogether()
        testTermsDropVariantsAndDuplicates()
        testVariantsAreReplacedAsWholeWords()
        testSeparatorsInsideVariantsAreFlexible()
    }

    private static func testEntriesKeepVariantsTogether() {
        TestSupport.expectEqual(
            VocabularyEntries.entries(in: "Kubernetes, Synthwave (Sin Wave, Cinq Wave)\nstaging; deploy"),
            [
                VocabularyEntries.Entry(term: "Kubernetes", variants: []),
                VocabularyEntries.Entry(term: "Synthwave", variants: ["Sin Wave", "Cinq Wave"]),
                VocabularyEntries.Entry(term: "staging", variants: []),
                VocabularyEntries.Entry(term: "deploy", variants: [])
            ]
        )
    }

    private static func testTermsDropVariantsAndDuplicates() {
        TestSupport.expectEqual(
            VocabularyEntries.terms(in: "Synthwave (SinWave), webhook, Webhook"),
            ["Synthwave", "webhook"]
        )
    }

    private static func testVariantsAreReplacedAsWholeWords() {
        let vocabulary = "Synthwave (SinWave, Sin-Wave)"
        TestSupport.expectEqual(
            VocabularyEntries.applyingCorrections(
                to: "Sur sinwave, tu as le studio. SinWaves reste.",
                vocabulary: vocabulary
            ),
            "Sur Synthwave, tu as le studio. SinWaves reste."
        )
        TestSupport.expectEqual(
            VocabularyEntries.applyingCorrections(to: "Rien à corriger.", vocabulary: "Synthwave"),
            "Rien à corriger."
        )
    }

    private static func testSeparatorsInsideVariantsAreFlexible() {
        TestSupport.expectEqual(
            VocabularyEntries.applyingCorrections(
                to: "Sin Wave, sin-wave et Sin\u{2011}Wave.",
                vocabulary: "Synthwave (Sin Wave)"
            ),
            "Synthwave, Synthwave et Synthwave."
        )
    }
}
