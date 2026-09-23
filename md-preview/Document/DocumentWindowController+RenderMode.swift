//
//  DocumentWindowController+RenderMode.swift
//  md-preview
//
//  Plain-text render mode for `.txt` files. Markdown files always render as
//  Markdown. A `.txt` renders the way the user last chose with View → Render
//  as Markdown, or when they haven't chosen, the way `PlainTextHeuristic`
//  suggests. The choice is re-evaluated on every render (reloads included),
//  so an external edit that adds a heading can flip an unset file to
//  Markdown, while a remembered choice sticks.
//

import Cocoa

extension DocumentWindowController {
    /// Whether the open document is a `.txt` / `.text` file, the only kind
    /// with a render-mode choice.
    var isPlainTextDocument: Bool {
        currentFileURL.map { SupportedDocumentTypes.kind(of: $0) == .plainText } ?? false
    }

    func renderMode(for text: String, fileURL: URL?) -> MarkdownHTML.RenderMode {
        guard let fileURL, SupportedDocumentTypes.kind(of: fileURL) == .plainText else {
            return .markdown
        }
        return RenderModeMemory.mode(for: fileURL) ?? PlainTextHeuristic.suggestedMode(for: text)
    }

    var currentRenderMode: MarkdownHTML.RenderMode {
        renderMode(for: currentMarkdown ?? "", fileURL: currentFileURL)
    }

    /// Available for a loaded `.txt` in preview. Edit mode keeps the mode it
    /// was entered with; switching mid-edit would reload the editor under
    /// the user's cursor.
    var canToggleRenderMode: Bool {
        isPlainTextDocument && currentMarkdown != nil && !isEditing
    }

    /// View → Render as Markdown. Remembers the choice for this file and
    /// re-renders in place, keeping the scroll offset.
    @IBAction func toggleRenderAsMarkdown(_ sender: Any?) {
        guard canToggleRenderMode,
              let url = currentFileURL,
              let text = currentMarkdown else {
            NSSound.beep()
            return
        }
        let newMode: MarkdownHTML.RenderMode = currentRenderMode == .markdown ? .plainText : .markdown
        RenderModeMemory.remember(newMode, for: url)
        if let split = mainSplit {
            split.prepareToScrollAfterNavigation(to: .position(split.previewScrollPosition))
        }
        renderCurrentDocument(text: text, fileURL: url)
    }

    func validateRenderModeMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = isPlainTextDocument && currentRenderMode == .plainText ? .off : .on
        return canToggleRenderMode
    }
}
