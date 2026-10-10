import AppKit

// MARK: - Add Vocabulary Extension

@MainActor
extension AppState {
    /// Reads the text currently selected in the frontmost app and returns the
    /// terms that adding it would actually contribute to the vocabulary, or
    /// nil once it has explained on the overlay why there are none.
    ///
    /// It reads the selection through the same Accessibility call the context
    /// service uses, so it works wherever the app exposes a selection, and it
    /// never guesses — only what you selected is considered.
    ///
    /// Feedback goes to the overlay, next to where the user is writing. The
    /// menu bar checkmark alone is invisible in practice: the user is looking
    /// at the text they just corrected, not at the top of the screen.
    func vocabularyTermsFromSelection() -> String? {
        guard let selectedText = contextService.collectSelectionSnapshot().selectedText,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            overlayManager.showError("Select a word first")
            return nil
        }

        guard let terms = newVocabularyTerms(in: selectedText) else {
            overlayManager.showNotice("Already in vocabulary")
            return nil
        }

        return terms
    }

    /// Adds the current selection to the vocabulary straight away, for the
    /// menu item — clicking it is already the confirmation. The shortcut goes
    /// through `AppState.requestVocabularyConfirmation()` instead, because a
    /// single modifier key is far too easy to hit by accident.
    @discardableResult
    func addSelectionToVocabulary() -> String? {
        guard let terms = vocabularyTermsFromSelection() else { return nil }
        return commitVocabularyTerms(terms)
    }

    /// Writes already-vetted terms into the vocabulary and confirms it on
    /// screen.
    @discardableResult
    func commitVocabularyTerms(_ terms: String) -> String? {
        guard let added = addWordsToVocabulary(terms) else {
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

    /// The terms in `text` that are not in the vocabulary yet, joined the way
    /// they would be written into it. Nil when `text` adds nothing.
    func newVocabularyTerms(in text: String) -> String? {
        let entriesToAdd = VocabularyEntries.entries(in: text)
        guard !entriesToAdd.isEmpty else { return nil }

        // Compare terms only, so "Higgsfield" is already covered by an
        // existing "Higgsfield (XField)" entry.
        var knownTerms = Set(VocabularyEntries.terms(in: self.customVocabulary).map { $0.lowercased() })
        let newEntries = entriesToAdd.filter { knownTerms.insert($0.term.lowercased()).inserted }

        guard !newEntries.isEmpty else { return nil }
        return newEntries.map(\.written).joined(separator: ", ")
    }

    /// Appends the unique, non-empty terms found in `text` to the custom
    /// vocabulary. Returns the terms actually added, or nil when there is
    /// nothing new to add.
    @discardableResult
    func addWordsToVocabulary(_ text: String) -> String? {
        guard let newWordsString = newVocabularyTerms(in: text) else { return nil }

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
