//
//  SupportedDocumentOpenPanelFilter.swift
//  md-preview
//
//  Narrows an open panel to the documents the app actually supports.
//  `allowedContentTypes` includes `public.plain-text` for `.txt`, but source
//  code, logs, and CSV all conform to it, so the panel alone would enable
//  them. This delegate keeps folders selectable and disables every file that
//  isn't Markdown or `.txt` / `.text`.
//

import Cocoa

final class SupportedDocumentOpenPanelFilter: NSObject, NSOpenSavePanelDelegate {
    /// Panels hold their delegate weakly; the shared instance outlives them.
    static let shared = SupportedDocumentOpenPanelFilter()

    static func configure(_ panel: NSOpenPanel) {
        panel.allowedContentTypes = SupportedDocumentTypes.openPanelContentTypes
        panel.delegate = shared
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        url.hasDirectoryPath || url.isExistingDirectory || SupportedDocumentTypes.isOpenable(url)
    }
}
