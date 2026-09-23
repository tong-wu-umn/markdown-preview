//
//  PlainTextFontSetting.swift
//  md-preview
//
//  The face used when a `.txt` file renders as plain text. Defaults to
//  monospaced, which keeps ASCII tables and art aligned the way a text editor
//  shows them. The alternative is the reader's document font. Kept free of
//  AppKit so the SPM helper tests can exercise it.
//

import Foundation

enum PlainTextFontSetting {
    static let defaultsKey = "MarkdownPreview.plainTextFont"

    static var current: MarkdownHTML.PlainTextFont {
        get { read(from: .standard) }
        set { write(newValue, to: .standard) }
    }

    static func read(from defaults: UserDefaults?) -> MarkdownHTML.PlainTextFont {
        defaults?.string(forKey: defaultsKey)
            .flatMap(MarkdownHTML.PlainTextFont.init(rawValue:)) ?? .monospaced
    }

    static func write(_ font: MarkdownHTML.PlainTextFont, to defaults: UserDefaults?) {
        defaults?.set(font.rawValue, forKey: defaultsKey)
    }
}
