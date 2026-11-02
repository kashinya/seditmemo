import AppKit
import CoreText

/// メモ帳.app/Contents/Resources/Fonts に入れたフォント（build.sh が PC-9800 フォントを入れる）を、
/// このアプリの中だけで使えるようにする。Mac 全体にはインストールしない。
enum EmbeddedFonts {
    static func register() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            _ = CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}

enum AppInfo {
    static var name: String {
        let info = Bundle.main.infoDictionary
        if let name = info?["CFBundleDisplayName"] as? String, !name.isEmpty { return name }
        if let name = info?["CFBundleName"] as? String, !name.isEmpty { return name }
        return "メモ帳"
    }

    static var version: String {
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}

/// Windows のメモ帳がレジストリに覚えてた程度のことだけ覚える（と、ファイルごとのウィンドウの位置と大きさ）。
/// 開いてた文書やウィンドウの中身は保存しない（落ちたとき用の控えは別: Recovery）。
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let fontName = "FontName"
        static let fontSize = "FontSize"
        static let wordWrap = "WordWrap"
        static let statusBar = "StatusBar"
        static let matchCase = "FindMatchCase"
        static let wrapAround = "FindWrapAround"
        static let tabWidth = "TabWidth"
        static let monospaceMode = "MonospaceMode"
        static let legacyAppearance = "Appearance"   // 前の版の［外観］(0: システム, 1: ライト, 2: ダーク)
        static let theme = "Theme"
        static let backgroundOpacity = "BackgroundOpacity"
        static let backgroundImageOpacity = "BackgroundImageOpacity"
        static let classicUI = "ClassicUI"
        static let lineSpacing = "LineSpacingPercent"
        static let seditMode = "SeditMode"
        static let showLineNumbers = "ShowLineNumbers"
        static let showColumnRuler = "ShowColumnRuler"
        static let showCharacterCount = "ShowCharacterCount"
        static let zoomPercent = "ZoomPercent"
        static let hideMacMenuBar = "HideMacMenuBar"   // 前の版の［Mac のメニューバーと Dock を隠す］（もう無い）
        static let defaultProfile = "DefaultViewProfile"
        static let fileProfiles = "FileViewProfiles"
        static let recentFiles = "RecentFiles"
        static let imeLog = "IMELog"
    }

    /// このアプリが覚えてることを全部消して、入れたときの状態に戻す（ファイルごとのウィンドウの位置・背景画像も）。
    /// macOS が置いてるもの（システム設定で付けたこのアプリのキーボードショートカット NSUserKeyEquivalents や、
    /// アプリごとの言語 AppleLanguages など、NS・Apple で始まるもの）は残す
    func resetAll() {
        if let domain = Bundle.main.bundleIdentifier, let stored = defaults.persistentDomain(forName: domain) {
            for key in stored.keys where !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple") {
                defaults.removeObject(forKey: key)
            }
        }
        BackgroundImage.remove()
    }

    private init() {
        defaults.register(defaults: [
            Key.statusBar: true,
            Key.matchCase: false,
            Key.wrapAround: false,
            Key.tabWidth: 8,
            Key.backgroundOpacity: 1.0,
            Key.backgroundImageOpacity: 0.15,
            Key.classicUI: false,
        ])
        migrateLegacyProfile()
    }

    /// 前の版の、全部のウィンドウに効いてた見た目の設定（SeditMode・ShowLineNumbers など）があれば、
    /// 一回だけ初期設定の見た目に移して、古いのは消す（あとで初期設定が読めんでも、古い設定に戻らんように）
    private func migrateLegacyProfile() {
        let legacyKeys = [Key.seditMode, Key.showLineNumbers, Key.showColumnRuler, Key.wordWrap, Key.lineSpacing,
                          Key.zoomPercent, Key.showCharacterCount, Key.monospaceMode, Key.hideMacMenuBar]
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        if defaults.object(forKey: Key.defaultProfile) == nil {
            var profile = ViewProfile.factory
            profile.sedit = defaults.object(forKey: Key.seditMode) as? Bool ?? profile.sedit
            profile.showLineNumbers = defaults.object(forKey: Key.showLineNumbers) as? Bool ?? profile.showLineNumbers
            profile.showColumnRuler = defaults.object(forKey: Key.showColumnRuler) as? Bool ?? profile.showColumnRuler
            profile.wordWrap = defaults.object(forKey: Key.wordWrap) as? Bool ?? profile.wordWrap
            profile.lineSpacingPercent = defaults.object(forKey: Key.lineSpacing) as? Int ?? profile.lineSpacingPercent
            profile.zoomPercent = defaults.object(forKey: Key.zoomPercent) as? Int ?? profile.zoomPercent
            profile.showCharacterCount = defaults.object(forKey: Key.showCharacterCount) as? Bool ?? profile.showCharacterCount
            profile.monospace = defaults.object(forKey: Key.monospaceMode) as? Bool ?? profile.monospace
            defaultProfile = profile.sanitized
        }
        legacyKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    /// アプリに埋め込んだ PC-9800 フォントの PostScript 名
    static let pc98FontName = "PC_9800"

    static var hasPC98Font: Bool {
        return NSFont(name: pc98FontName, size: 16) != nil
    }

    /// 等幅フォントモードのフォント。PC-9800 フォントなら半角:全角がきっちり 1:2（16 ドット）
    static var monospaceFont: NSFont {
        let size: CGFloat = 16
        if let pc98 = NSFont(name: pc98FontName, size: size) { return pc98 }
        if let osaka = osakaMono(size: size) { return osaka }
        if let fixed = NSFont.userFixedPitchFont(ofSize: size) { return fixed }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static var defaultFont: NSFont {
        let size: CGFloat = 13
        // Osaka−等幅が入ってたら半角:全角がきっちり 1:2 になるので優先
        if let osaka = osakaMono(size: size) { return osaka }
        if let fixed = NSFont.userFixedPitchFont(ofSize: size) { return fixed }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Osaka−等幅は、Mac に入ってる（ダウンロード済みの）ときだけ使う。
    /// macOS の「あとから落とせるフォント」なので、入ってないのに名前で引くと、macOS が落としに行って待たされる
    /// （ネットにつながらん Mac では返ってこず、起動が止まる。CI で 20 秒以上返ってこんかった）
    private static let isOsakaMonoInstalled: Bool = {
        let names = (CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? []
        return names.contains("Osaka-Mono")
    }()

    private static func osakaMono(size: CGFloat) -> NSFont? {
        return isOsakaMonoInstalled ? NSFont(name: "Osaka-Mono", size: size) : nil
    }

    var font: NSFont {
        get {
            let size = defaults.double(forKey: Key.fontSize)
            if let name = defaults.string(forKey: Key.fontName), size >= 1,
               let font = NSFont(name: name, size: CGFloat(size)) {
                return font
            }
            return Settings.defaultFont
        }
        set {
            defaults.set(newValue.fontName, forKey: Key.fontName)
            defaults.set(Double(newValue.pointSize), forKey: Key.fontSize)
        }
    }

    /// ［書式］→［行間］の選べる倍率（%）
    static let lineSpacingChoices = [100, 110, 115, 120, 130, 150, 200]

    /// 初期設定の見た目（新しいウィンドウと、まだ見た目を覚えてないファイル）。読めなかったら最初の状態
    var defaultProfile: ViewProfile {
        get {
            if let data = defaults.data(forKey: Key.defaultProfile),
               let profile = try? JSONDecoder().decode(ViewProfile.self, from: data) {
                return profile.sanitized
            }
            return .factory
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.defaultProfile)
            }
        }
    }

    /// ［ファイル］→［最近使ったファイル］（新しい順のパス、10 個まで）
    var recentFiles: [String] {
        get { return defaults.stringArray(forKey: Key.recentFiles) ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: Key.recentFiles) }
    }

    /// 隠し設定: 変換候補の窓の位置を調べるため、IME とのやりとりを ~/Library/Logs/local.memocho.sedit-ime.log に書く
    var imeLog: Bool {
        return defaults.bool(forKey: Key.imeLog)
    }

    var theme: EditorTheme {
        get {
            if let id = defaults.string(forKey: Key.theme), let theme = EditorTheme.named(id) {
                return theme
            }
            switch defaults.integer(forKey: Key.legacyAppearance) {
            case 1: return .light
            case 2: return .dark
            default: return .system
            }
        }
        set { defaults.set(newValue.id, forKey: Key.theme) }
    }

    /// 本文の背景の不透明度（20%〜100%）。100% 未満やと後ろのデスクトップが透ける
    var backgroundOpacity: CGFloat {
        get { return CGFloat(min(1, max(0.2, defaults.double(forKey: Key.backgroundOpacity)))) }
        set { defaults.set(Double(newValue), forKey: Key.backgroundOpacity) }
    }

    /// 背景の画像の濃さ（0%〜80%）
    var backgroundImageOpacity: CGFloat {
        get { return CGFloat(min(0.8, max(0, defaults.double(forKey: Key.backgroundImageOpacity)))) }
        set { defaults.set(Double(newValue), forKey: Key.backgroundImageOpacity) }
    }

    /// ［表示］→［Windows 2000 風］
    var classicUI: Bool {
        get { return defaults.bool(forKey: Key.classicUI) }
        set { defaults.set(newValue, forKey: Key.classicUI) }
    }

    var showStatusBar: Bool {
        get { return defaults.bool(forKey: Key.statusBar) }
        set { defaults.set(newValue, forKey: Key.statusBar) }
    }

    var matchCase: Bool {
        get { return defaults.bool(forKey: Key.matchCase) }
        set { defaults.set(newValue, forKey: Key.matchCase) }
    }

    var wrapAround: Bool {
        get { return defaults.bool(forKey: Key.wrapAround) }
        set { defaults.set(newValue, forKey: Key.wrapAround) }
    }

    /// 隠し設定: defaults write local.memocho.sedit TabWidth -int 4
    var tabWidth: Int {
        let width = defaults.integer(forKey: Key.tabWidth)
        return (1...32).contains(width) ? width : 8
    }
}

/// 見た目。ファイルごとに覚えて、新しいウィンドウは初期設定（Settings.defaultProfile）の見た目で開く。
/// Windows 2000 風の枠・テーマ・背景・ステータスバーなどはアプリ全体の設定（Settings）
struct ViewProfile: Codable, Equatable {
    /// SEDIT 風か（でなければメモ帳）
    var sedit = false
    var showLineNumbers = false
    var showColumnRuler = false
    var wordWrap = false
    var lineSpacingPercent = 100
    var zoomPercent = 100
    var showCharacterCount = false
    /// 等幅フォント（PC-9800）。SEDIT 風はいつも等幅
    var monospace = false

    /// 最初の状態（メモ帳・ルーラーなし・折り返しなし・行間標準・ズーム 100%）
    static let factory = ViewProfile()

    /// 読み込んだ値を、使える範囲に収める
    var sanitized: ViewProfile {
        var profile = self
        if !Settings.lineSpacingChoices.contains(profile.lineSpacingPercent) {
            profile.lineSpacingPercent = 100
        }
        profile.zoomPercent = max(EditorWindowController.minZoom, min(EditorWindowController.maxZoom, profile.zoomPercent))
        return profile
    }

    var lineSpacing: CGFloat {
        return CGFloat(lineSpacingPercent) / 100
    }

    /// 本文のフォント（SEDIT 風か等幅フォントなら PC-9800、でなければフォントパネルで選んだもの）
    var editorFont: NSFont {
        return sedit || monospace ? Settings.monospaceFont : Settings.shared.font
    }
}

extension ViewProfile {
    /// 覚えてない項目は最初の状態で読む（あとで項目を足しても、覚えてた見た目が全部読めなくならんように）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let factory = ViewProfile.factory
        sedit = try container.decodeIfPresent(Bool.self, forKey: .sedit) ?? factory.sedit
        showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? factory.showLineNumbers
        showColumnRuler = try container.decodeIfPresent(Bool.self, forKey: .showColumnRuler) ?? factory.showColumnRuler
        wordWrap = try container.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? factory.wordWrap
        lineSpacingPercent = try container.decodeIfPresent(Int.self, forKey: .lineSpacingPercent) ?? factory.lineSpacingPercent
        zoomPercent = try container.decodeIfPresent(Int.self, forKey: .zoomPercent) ?? factory.zoomPercent
        showCharacterCount = try container.decodeIfPresent(Bool.self, forKey: .showCharacterCount) ?? factory.showCharacterCount
        monospace = try container.decodeIfPresent(Bool.self, forKey: .monospace) ?? factory.monospace
    }
}
