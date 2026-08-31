import AppKit

// MARK: - Add Vocabulary Extension

@MainActor
extension AppState {
    /// Adds the text currently selected in the frontmost app to the user's
    /// custom vocabulary, and flashes the menu bar checkmark on success.
    ///
    /// This is the shortcut-driven path: correct a mis-transcribed word by
    /// hand, select it, press the shortcut. It reads the selection through the
    /// same Accessibility call the context service uses, so it works wherever
    /// the app exposes a selection, and it never guesses — only what you
    /// selected is added.
    @discardableResult
    func addSelectionToVocabulary() -> String? {
        // Feedback goes to the overlay, next to the cursor. The menu bar
        // checkmark alone is invisible in practice: the user is looking at the
        // text they just corrected, not at the top of the screen.
        guard let selectedText = contextService.collectSelectionSnapshot().selectedText,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            overlayManager.showError("Select a word first")
            return nil
        }

        guard let added = addWordsToVocabulary(selectedText) else {
            overlayManager.showNotice("Already in vocabulary")
            return nil
        }

        VocabularyNotificationManager.shared.flashCheckmark()
        overlayManager.showNotice("Added: \(added)")
        return added
    }

    /// Pastes a word (or words) from the macOS pasteboard into the user's custom vocabulary.
    /// Returns the pasted text if successful, or nil otherwise.
    @discardableResult
    func pasteWordToVocabulary() -> String? {
        guard let pastedString = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        return addWordsToVocabulary(pastedString)
    }

    /// Appends the unique, non-empty terms found in `text` to the custom
    /// vocabulary. Returns the terms actually added, or nil when there is
    /// nothing new to add.
    @discardableResult
    func addWordsToVocabulary(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Clean and prepare the new word(s)
        let wordsToAdd = text
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !wordsToAdd.isEmpty else { return nil }

        // Parse current vocabulary list to avoid adding exact duplicates
        let currentWordsList = self.customVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let currentWordsSet = Set(currentWordsList.map { $0.lowercased() })

        let newUniqueWords = wordsToAdd.filter { !currentWordsSet.contains($0.lowercased()) }

        guard !newUniqueWords.isEmpty else { return nil }

        let newWordsString = newUniqueWords.joined(separator: ", ")

        // Append unique words to existing vocabulary
        // We trim the block as a whole to safely append, but not the individual words themselves
        var currentVocab = self.customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentVocab.isEmpty {
            if !currentVocab.hasSuffix(",") {
                currentVocab += ","
            }
            currentVocab += "\n\(newWordsString)"
        } else {
            currentVocab = newWordsString
        }

        // Save back to the published state
        self.customVocabulary = currentVocab
        return newWordsString
    }
}
