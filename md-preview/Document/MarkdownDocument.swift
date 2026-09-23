//
//  MarkdownDocument.swift
//  md-preview
//

import Cocoa
import Synchronization
import UniformTypeIdentifiers

final class MarkdownDocument: NSDocument {

    private nonisolated let markdownStorage = Mutex("")
    private nonisolated let folderStorage = Mutex<URL?>(nil)
    private nonisolated let kindStorage = Mutex<SupportedDocumentTypes.Kind>(.markdown)

    var markdown: String {
        markdownStorage.withLock { $0 }
    }

    /// `.plainText` for `.txt` / `.text`. Both render as Markdown for now
    /// (Phase 2 of docs/plans/txt-file-support.md adds a plain render mode).
    /// Encoding isn't stored: saving re-detects it from disk before writing.
    var kind: SupportedDocumentTypes.Kind {
        kindStorage.withLock { $0 }
    }

    private var folderURL: URL? {
        folderStorage.withLock { $0 }
    }

    override init() {
        super.init()
        hasUndoManager = false
    }

    override nonisolated class var autosavesInPlace: Bool {
        false
    }

    override var isDocumentEdited: Bool {
        false
    }

    override var allowsDocumentSharing: Bool {
        guard let fileURL else { return false }
        return !fileURL.isExistingDirectory
    }

    override func makeWindowControllers() {
        let controller = DocumentWindowController()
        addWindowController(controller)
        if let folderURL {
            controller.display(markdown: "", fileURL: nil)
            controller.openFolder(folderURL)
            return
        }
        if fileURL == nil {
            controller.prepareSidebarForUntitledDocument()
        }
        controller.display(markdown: markdown, fileURL: fileURL)
    }

    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        if url.isExistingDirectory {
            folderStorage.withLock { $0 = url.standardizedFileURL }
            markdownStorage.withLock { $0 = "" }
            return
        }

        let data = try Data(contentsOf: url)
        try read(from: data, ofType: typeName)
        // The extension is more precise than the type name: a document type
        // can be matched through UTI conformance.
        if let kind = SupportedDocumentTypes.kind(of: url) {
            kindStorage.withLock { $0 = kind }
        }
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = SupportedDocumentTypes.decode(data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        folderStorage.withLock { $0 = nil }
        markdownStorage.withLock { $0 = decoded.text }
        kindStorage.withLock { $0 = Self.kind(forTypeName: typeName) }
    }

    /// Maps the Info.plist document type (or a UTI) to a document kind.
    private nonisolated static func kind(forTypeName typeName: String) -> SupportedDocumentTypes.Kind {
        if typeName == "Plain Text Document" { return .plainText }
        if let type = UTType(typeName), type == .plainText { return .plainText }
        return .markdown
    }

    override nonisolated func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.fileWriteNoPermission)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(save(_:)),
             #selector(saveAs(_:)),
             #selector(saveTo(_:)),
             #selector(revertToSaved(_:)):
            return false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    func replaceContents(markdown: String, fileURL: URL) {
        markdownStorage.withLock { $0 = markdown }
        replaceFileURL(fileURL)
    }

    func replaceContents(markdown: String) {
        markdownStorage.withLock { $0 = markdown }
        updateChangeCount(.changeCleared)
    }

    func replaceFileURL(_ fileURL: URL) {
        self.fileURL = fileURL
        if let kind = SupportedDocumentTypes.kind(of: fileURL) {
            kindStorage.withLock { $0 = kind }
        }
        updateChangeCount(.changeCleared)
    }
}
