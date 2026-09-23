//
//  MarkdownDocumentController.swift
//  md-preview
//

import Cocoa
import UniformTypeIdentifiers

final class MarkdownDocumentController: NSDocumentController {
    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?
    ) async -> Int {
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.message = NSLocalizedString(
            "Choose a Markdown file or folder",
            comment: "Open panel prompt"
        )
        SupportedDocumentOpenPanelFilter.configure(openPanel)
        return await super.beginOpenPanel(openPanel, forTypes: inTypes)
    }

    /// The app-level Open command (Command-O with no document window key).
    /// `NSDocumentController`'s default opens each selected URL through
    /// `openDocument(withContentsOf:)` independently, so two selected folders
    /// would each replace the root and the second would win. Run the panel
    /// and dispatch the whole selection through one batch instead, so every
    /// folder mounts and files still open per the tab policy.
    @IBAction override func openDocument(_ sender: Any?) {
        Task { @MainActor in
            let panel = NSOpenPanel()
            let response = await beginOpenPanel(panel, forTypes: nil)
            guard response == NSApplication.ModalResponse.OK.rawValue,
                  !panel.urls.isEmpty,
                  let appDelegate = NSApp.delegate as? AppDelegate else { return }
            appDelegate.openResolvedURLs(panel.urls)
        }
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        if url.isExistingDirectory,
           let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openFolder(url)
            completionHandler(nil, false, nil)
            return
        }

        super.openDocument(
            withContentsOf: url,
            display: displayDocument,
            completionHandler: completionHandler
        )
    }

    override func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        let document = try super.openUntitledDocumentAndDisplay(displayDocument)
        if displayDocument {
            (document.windowControllers.first as? DocumentWindowController)?
                .enterEditMode(autofocus: true)
        }
        return document
    }
}
