import SwiftUI
import AppKit

/// Tuinstra Meatproxy (D45): the brand in the app. The mark is a 16 × 16 pixel checkmark, a Tuinstra Yes button you
/// press: a yellow face on a solid yellow-brown ledge straight below it. Controls follow the Tuinstra tactile rules:
/// lifted on a 1 px edge and a solid ledge (primary 3 px, neutral 2 px) with a faint soft shadow; a pressed button
/// travels straight down onto its ledge and springs back. Neutrals are the Tuinstra charcoal Dark.
enum Brand {
    static let name = "Tuinstra Meatproxy"
    static let shortName = "Meatproxy"
    /// describes the product: the app, the lockup
    static let productLine = "Approved by a human. Reviewed by nobody."
    /// describes the user: About, stickers
    static let userLine = "Still needed. Legally."
    /// the product line as the brand sets it: the first sentence in Text, the second in Secondary
    static func productLineText(_ line: String = productLine) -> Text {
        let parts = line.components(separatedBy: ". ")
        guard parts.count == 2 else { return Text(line).foregroundColor(.muted) }
        return Text(parts[0] + ". ").foregroundColor(.inkText) + Text(parts[1]).foregroundColor(.muted)
    }
    static let story = "Tuinstra Meatproxy watches your Dark Software Factories while they plan, build, test and ship without you. A CEO agent runs the floor. Developer, tester, designer, devops and product agents do the work. You answer yes or no. Five yeses in a row and the CEO asks to turn the lights off. You remain the proxy. Somebody still has to sign."

    static let emptyState = "Nothing needs you. The factories are fine without you. Try not to read into it."
    /// The Needs-you counter: "1 needs you ›", "3 need you ›", "99+ need you. They can wait."
    static func counter(_ n: Int) -> String {
        n == 0 ? "Nothing needs you" : n == 1 ? "1 needs you ›" : n > 99 ? "99+ need you. They can wait." : "\(n) need you ›"
    }

    /// The checkmark: the same 16 × 16 cells as every brand asset (assets/brand-explore/v2/a-checkmark/gen.py).
    static let check: [String] = [
        "................",
        "................",
        "............###.",
        "...........####.",
        "..........####..",
        ".........####...",
        ".##.....####....",
        ".###...####.....",
        ".####.####......",
        "..#######.......",
        "...#####........",
        "....###.........",
        ".....#..........",
        "................",
        "................",
        "................",
    ]
    static let checkCells: [(Int, Int)] = check.enumerated().flatMap { y, row in row.enumerated().compactMap { x, c in c == "#" ? (x, y) : nil } }

    /// The app icon, as the Dock shows it.
    static var appIcon: NSImage? { AppResources.bundle.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Brand").flatMap(NSImage.init(contentsOf:)) }

    /// The build's version (scripts/make-app.sh writes it into the bundle); a bare `swift build` is "dev".
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    /// The native About panel: the icon, the name, the story, its version and the line about you.
    @MainActor static func showAbout() {
        let centred = NSMutableParagraphStyle(); centred.alignment = .center
        let credits = NSMutableAttributedString(string: story + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centred])
        credits.append(NSAttributedString(string: userLine, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.labelColor, .paragraphStyle: centred]))
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: name, .credits: credits,
                                                                  .applicationVersion: "Hobby build \(version)", .version: ""]
        if let appIcon { options[.applicationIcon] = appIcon }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: the mark

/// The ✓ drawn from its cells: yellow face, the ledge one cell straight below, and (on light or busy backgrounds) a thin
/// ink outline round both. `ledge: false` gives the one-colour mark.
struct BrandMark: View {
    var face: Color = .signal
    var ledge: Bool = true
    var outline: Bool = false
    @Environment(\.displayScale) private var scale
    var body: some View {
        Canvas { ctx, size in
            // square pixels only: a cell is a whole number of device pixels, and the grid starts on a device pixel; the
            // face and ledge span x 1…14, y 2…13 of the 16-cell grid, so centring the grid centres the mark
            let u = max(1, floor(min(size.width, size.height) * scale / 16)) / scale
            let ox = (((size.width - 16 * u) / 2) * scale).rounded() / scale, oy = (((size.height - 16 * u) / 2) * scale).rounded() / scale
            let face = Set(Brand.checkCells.map { "\($0.0),\($0.1)" })
            let below = Brand.checkCells.map { ($0.0, $0.1 + 1) }.filter { !face.contains("\($0.0),\($0.1)") }
            /// cells merged into horizontal runs, as the brand's generator draws them (no seams between cells)
            func runs(_ cells: [(Int, Int)], inset t: CGFloat = 0) -> Path {
                var p = Path()
                for y in Set(cells.map(\.1)).sorted() {
                    let xs = cells.filter { $0.1 == y }.map(\.0).sorted()
                    var start = xs[0], prev = xs[0]
                    for x in xs.dropFirst() + [Int.max] {
                        if x == prev + 1 { prev = x; continue }
                        p.addRect(CGRect(x: ox + CGFloat(start) * u - t, y: oy + CGFloat(y) * u - t, width: CGFloat(prev - start + 1) * u + 2 * t, height: u + 2 * t))
                        start = x; prev = x
                    }
                }
                return p
            }
            if outline { ctx.fill(runs(Brand.checkCells + below, inset: (u * 0.22 * scale).rounded() / scale), with: .color(.onSignal)) }
            if ledge { ctx.fill(runs(below), with: .color(.ledge)) }
            ctx.fill(runs(Brand.checkCells), with: .color(self.face))
        }
        .accessibilityHidden(true)
    }
}

// MARK: tactile controls

/// A Tuinstra button in the Spel+ shape (D80): a 2 pt edge and a hard ledge straight below. Pressing moves the face
/// down onto its ledge within about 70 ms and holds at least 88 ms, so a quick click still reads; letting go springs
/// back in about 180 ms. Disabled buttons sit flat with a dashed edge and keep a readable label (E9). Never more than
/// one primary per view.
struct TactileButtonStyle: ButtonStyle {
    /// primary: the one yellow action; neutral: everything else; destructive: a confirmed removal, in semantic red
    enum Kind { case primary, neutral, destructive }
    var kind: Kind = .neutral
    var radius: CGFloat = 6
    /// padding round the label, for buttons whose label is plain text
    var inset: EdgeInsets? = nil
    /// bump it when the button's keyboard shortcut fires: the key then shows the same press as a click
    var pulse: Int = 0
    func makeBody(configuration: Configuration) -> some View { TactileBody(configuration: configuration, kind: kind, radius: radius, inset: inset, pulse: pulse) }
}

private struct TactileBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TactileButtonStyle.Kind
    let radius: CGFloat
    let inset: EdgeInsets?
    let pulse: Int
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false
    @State private var hover = false
    @State private var since = Date.distantPast
    /// the latest press: a release scheduled by an earlier one is dropped
    @State private var token = 0

    private func press() {
        token += 1
        since = Date()
        withAnimation(reduceMotion ? nil : Motion.pressIn) { down = true }
    }
    private func release() {
        let mine = token, wait = max(0, 0.088 - Date().timeIntervalSince(since))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            guard mine == token else { return }
            withAnimation(reduceMotion ? nil : Motion.springBack) { down = false }
        }
    }

    var body: some View {
        // with reduced motion the face moves at most a pixel and nothing springs
        let depth: CGFloat = kind == .neutral ? 2 : 3, travel = reduceMotion ? min(depth, 1) : depth
        let lifted = enabled && !down
        let shape = RoundedRectangle(cornerRadius: radius)
        let ink: Color = !enabled ? .muted : kind == .neutral ? .inkText : .onSignal
        let edge: Color = kind == .primary ? .signalEdge : kind == .destructive ? Color(hex: 0xB23A3A) : .border
        let ledge: Color = kind == .primary ? .ledge : kind == .destructive ? .dangerLedge : .plinth
        let top: Color = kind == .primary ? (hover ? Color(hex: 0xFFE987) : .signalTop) : kind == .destructive ? .stuck : (hover ? Color(hex: 0x3B3B3B) : Color(hex: 0x333333))
        let bottom: Color = kind == .primary ? .signal : kind == .destructive ? .stuck : Color(hex: 0x292929)
        let faceStyle: AnyShapeStyle = enabled ? AnyShapeStyle(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.clear)
        return configuration.label
            .padding(inset ?? EdgeInsets())
            .foregroundStyle(ink)
            .background(shape.fill(faceStyle))
            .overlay(alignment: .top) {
                if enabled && kind == .neutral { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1).padding(.horizontal, radius).padding(.top, 2) }
            }
            .overlay {
                if enabled { shape.strokeBorder(edge, lineWidth: 2) }
                else { shape.strokeBorder(Color.border, style: StrokeStyle(lineWidth: 2, dash: [4, 3])) }
            }
            // the ledge: the same shape, solid, straight below
            .background(shape.fill(ledge).offset(y: lifted ? depth : 0).opacity(lifted ? 1 : 0))
            .offset(y: enabled && down ? travel : 0)
            .contentShape(shape)
            .onHover { hover = $0 }
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { press() } else { release() } }
            // a keyboard shortcut: the same press and release
            .onChange(of: pulse) { _, _ in guard enabled else { return }; press(); release() }
    }
}

/// An input field (Spel+): recessed in a well with a 2 pt control edge; focus shows a white edge.
struct LiftedField: ViewModifier {
    var focused: Bool
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return content
            .background(shape.fill(Color.well))
            .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.35)).frame(height: 2).padding(.horizontal, radius / 2).padding(.top, 2) }
            .overlay(shape.strokeBorder(focused ? Color.inkText : Color.inputEdge, lineWidth: 2))
    }
}

extension View {
    func lifted(focused: Bool, radius: CGFloat = 10) -> some View { modifier(LiftedField(focused: focused, radius: radius)) }
}

// MARK: type

extension Brand {
    /// Registers the bundled Inter (OFL, Brand/fonts) for this process; the wordmark is set in it (D45).
    static func registerFonts() {
        guard let url = AppResources.bundle.url(forResource: "InterVariable", withExtension: "woff2", subdirectory: "Brand/fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// Inter set at an exact weight on its variable `wght` axis and drawn with Core Text. SwiftUI's own text drops the
/// variation of a registered variable font and falls back to its default instance (Regular), so the wordmark draws itself.
struct InterText: View {
    let text: String
    let size: CGFloat
    let weight: CGFloat
    /// letter-spacing in points (the brand sets Meatproxy at -0.05 em and TUINSTRA at 0.3 em)
    var tracking: CGFloat = 0
    var color: Color = .inkText

    private var line: CTLine {
        let base = CTFontCreateWithName("InterVariable" as CFString, size, nil)
        let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
                                                            [kCTFontVariationAttribute: [0x77676874: weight]] as CFDictionary)   // 'wght'
        // (CTFontCreateCopyWithAttributes drops the variation below Inter's 14 pt optical size; this keeps it)
        let font = CTFontCreateWithFontDescriptor(desc, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking, .foregroundColor: NSColor(color)]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    }

    var body: some View {
        let line = self.line
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        // the trailing kern after the last letter is not part of the word
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading)) - max(0, tracking)
        Canvas { ctx, _ in
            ctx.withCGContext { cg in
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: ascent)
                cg.scaleBy(x: 1, y: -1)
                CTLineDraw(line, cg)
            }
        }
        .frame(width: ceil(width), height: ceil(ascent + descent))
        .accessibilityLabel(text)
    }
}

// MARK: the lockup

/// The lockup (D45): the mark as tall as the name block, TUINSTRA on a yellow tab above Meatproxy in Inter Black, and
/// below them, in the text column, optionally the product line and a detail (what the app is doing).
struct BrandLockup: View {
    /// the type scale: Meatproxy is 0.62 × size, the TUINSTRA tab 0.3 × size
    var size: CGFloat = 30
    var line: String? = nil
    var detail: String? = nil
    var body: some View {
        // the mark on whole 1 pt-or-larger cells (a multiple of 16), its face starting on the gutter: the grid's empty
        // first column hangs outside
        let mark = max(16, (size * 1.5 / 16).rounded(.down) * 16), cell = mark / 16, gap = size * 0.34
        VStack(alignment: .leading, spacing: size * 0.22) {
            HStack(alignment: .center, spacing: gap - cell) {
                BrandMark().frame(width: mark, height: mark).padding(.leading, -cell)
                VStack(alignment: .leading, spacing: size * 0.1) {
                    // the brand book's proportions: the tab about a fifth of the name, never under 9 pt; 4 pt corners
                    let name = size * 0.62, tab = max(9, name * 0.22)
                    InterText(text: "TUINSTRA", size: tab, weight: 800, tracking: tab * 0.3, color: .onSignal)
                        .padding(.leading, tab * 0.55).padding(.trailing, tab * 0.25).padding(.vertical, tab * 0.28)
                        .background(Color.signal, in: RoundedRectangle(cornerRadius: 4))
                    InterText(text: Brand.shortName, size: name, weight: 900, tracking: -name * 0.05)
                }
            }
            if line != nil || detail != nil {
                VStack(alignment: .leading, spacing: size * 0.3) {
                    if let line { Brand.productLineText(line).font(.system(size: max(12, size * 0.25), weight: .semibold)) }
                    if let detail { Text(detail).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.muted) }
                }
                .padding(.leading, mark - cell + gap - cell)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(Brand.name)
    }
}

// MARK: segments

/// A segmented choice (Spel+): a well with chunky keys; the chosen one is lit white on its ledge, never yellow (E1).
/// The key slides to the segment you pick; the others are quiet. A segment that cannot be picked keeps its readable
/// label with a dashed edge (E9). Two sizes, as SpelButton (UX review 26 Nov, Henk): s has 22 pt keys in a 28 pt well
/// (radius 6), m 28 pt keys in a 34 pt well (radius 10); both 13 pt labels.
struct LiftedSegments<ID: Hashable>: View {
    struct Item { var id: ID; var title: String; var icon: String? = nil; var enabled = true; var help: String? = nil }
    enum Size { case s, m }
    let items: [Item]
    let selected: ID
    var size: Size = .m
    var mono = false
    /// stretch the segments to the width they are given
    var fill = false
    let pick: (ID) -> Void
    @Namespace private var keySpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let key: CGFloat = size == .s ? 22 : 28, well: CGFloat = size == .s ? 6 : 10
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let on = item.id == selected
                Button { pick(item.id) } label: {
                    HStack(spacing: 6) {
                        if let icon = item.icon { PixelIcon(icon, color: on ? .onSignal : .muted) }
                        Text(item.title).lineLimit(1).fixedSize()
                    }
                    .font(.spel(13, weight: on ? .bold : .semibold, design: mono ? .monospaced : .default))
                    .padding(.horizontal, size == .s ? 8 : 12)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .frame(height: key)
                }
                .buttonStyle(SegmentKeyStyle(on: on, radius: size == .s ? 4 : 6, keySpace: keySpace))
                .disabled(!item.enabled && !on)
                .help(item.help ?? "")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : Motion.slide, value: selected)
        // 2 above the keys, 4 below (their 2 pt ledge and 2 of well): 28 or 34 in all
        .padding(.horizontal, 2).padding(.top, 2).padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: well).fill(Color.well))
        .overlay(RoundedRectangle(cornerRadius: well).strokeBorder(Color.divider, lineWidth: 2))
    }
}

private struct SegmentKeyStyle: ButtonStyle {
    let on: Bool
    let radius: CGFloat
    let keySpace: Namespace.ID
    func makeBody(configuration: Configuration) -> some View { SegmentKey(configuration: configuration, on: on, radius: radius, keySpace: keySpace) }
}

private struct SegmentKey: View {
    let configuration: ButtonStyleConfiguration
    let on: Bool
    let radius: CGFloat
    let keySpace: Namespace.ID
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    var body: some View {
        let pressed = configuration.isPressed && enabled
        let ink: Color = on ? Color.onSignal : hover && enabled ? Color.inkText : Color.muted
        let shape = RoundedRectangle(cornerRadius: radius)
        return configuration.label
            .foregroundStyle(ink)
            .background {
                if on {
                    // the key: a white face and edge, its grey ledge straight below; pressed, it lands on the ledge
                    shape.fill(LinearGradient(colors: [.lit, .lit2], startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(Color.white, lineWidth: 2))
                        .background(shape.fill(Color.litLedge).offset(y: pressed ? 0 : 2))
                        .matchedGeometryEffect(id: "key", in: keySpace)
                } else if !enabled {
                    shape.strokeBorder(Color.border, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                } else if hover {
                    shape.fill(Color.raised)
                }
            }
            .offset(y: pressed ? (on ? (reduceMotion ? 1 : 2) : 1) : 0)
            .animation(reduceMotion ? nil : pressed ? Motion.pressIn : Motion.springBack, value: pressed)
            .contentShape(shape)
            .onHover { hover = $0 }
    }
}

/// A card you can click (a quest in Needs you, a workstream, a session): Tuinstra dense cards stay flat and give about
/// 1 px of press feedback instead of a raised button.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 1 : 0)
            .animation(configuration.isPressed ? .easeOut(duration: 0.07) : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: switches

/// A switch (Spel+, E1): on is green with the word ON, never yellow; off a recessed track with OFF. A white square knob
/// slides; with reduced motion it jumps. A switch that is fixed has a dashed edge and keeps its word. It keeps the
/// system switch's accessibility.
struct TactileToggleStyle: ToggleStyle {
    /// the word beside the track (ON / OFF)
    var word = true
    func makeBody(configuration: Configuration) -> some View { TactileSwitch(configuration: configuration, word: word) }
}

private struct TactileSwitch: View {
    let configuration: ToggleStyleConfiguration
    let word: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let on = configuration.isOn
        let shape = RoundedRectangle(cornerRadius: 6)
        // a real button: focusable, Space toggles it, disabled when the switch is; its label is spoken, not drawn
        // (the row around it shows the words)
        return Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                if word {
                    Text(on ? "ON" : "OFF").font(.s11).tracking(0.7).foregroundStyle(on ? Color.done : Color.muted).frame(width: 28, alignment: .trailing)
                }
                ZStack(alignment: on ? .trailing : .leading) {
                    shape.fill(on ? Color.done : Color.well)
                        .overlay {
                            if enabled { shape.strokeBorder(on ? Color.doneEdge : Color.border, lineWidth: 2) }
                            else { shape.strokeBorder(Color.border, style: StrokeStyle(lineWidth: 2, dash: [3, 2])) }
                        }
                    RoundedRectangle(cornerRadius: 4).fill(Color.inkText)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: 0xBDBDBD), lineWidth: 2))
                        .frame(width: 18, height: 18).padding(.horizontal, 3)
                }
                .frame(width: 44, height: 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : Motion.slide, value: on)
        // to assistive tech it is the system switch, with its label and on/off value
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A keyboard shortcut shown where its action is (Spel+): a small recessed key with a thicker bottom edge.
/// On yellow it takes the ink of the yellow button it sits on.
struct KeyCap: View {
    let key: String
    var onYellow = false
    init(_ key: String, onYellow: Bool = false) { self.key = key; self.onYellow = onYellow }
    var body: some View {
        // the colours first: in one expression this takes the compiler too long to type-check
        let ink: Color = onYellow ? Color.onSignal : Color.muted
        let face: Color = onYellow ? Color.onSignal.opacity(0.12) : Color.well
        let edge: Color = onYellow ? Color.onSignal.opacity(0.45) : Color.border
        let shape = RoundedRectangle(cornerRadius: 6)
        return Text(key).font(.spel(11, weight: .semibold)).lineLimit(1).fixedSize()
            .foregroundStyle(ink)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18, maxHeight: 18)
            .background(shape.fill(face))
            .overlay(shape.strokeBorder(edge, lineWidth: 1.5))
            .background(shape.fill(edge).offset(y: 1.5))
            .padding(.bottom, 1.5)
            .accessibilityHidden(true)
    }

    /// The cap hides itself from VoiceOver: what it shows goes into its button's hint instead ("Shortcut: Command K").
    static func spoken(_ key: String) -> String {
        let names: [(String, String)] = [("⌘", "Command "), ("⇧", "Shift "), ("⌥", "Option "), ("⌃", "Control "), ("↩", "Return"),
                                          ("esc", "Escape"), ("↑", "Up Arrow"), ("↓", "Down Arrow"), ("?", "Question Mark"),
                                          ("+", "Plus"), ("−", "Minus"), (",", "Comma")]
        var s = key.replacingOccurrences(of: " ", with: " or ")   // "1 2": either key
        for (k, v) in names { s = s.replacingOccurrences(of: k, with: v) }
        return "Shortcut: " + s.trimmingCharacters(in: .whitespaces)
    }
}

/// The app's resources: inside Meatproxy.app they sit in Contents/Resources (scripts/make-app.sh); in a bare build,
/// where SwiftPM put them.
enum AppResources {
    static let bundle: Bundle = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Meatproxy_Meatproxy.bundle"), let b = Bundle(url: r) { return b }
        return Bundle.module
    }()
}

/// A project's own logo (D55), small and rounded; nothing when it has none (the name says it then).
struct ProjectLogoView: View {
    let path: String?
    var size: CGFloat = 18
    private static let cache = NSCache<NSString, NSImage>()
    var body: some View {
        if let path, let img = Self.image(path) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
                .accessibilityHidden(true)
        }
    }
    static func image(_ path: String) -> NSImage? {
        if let i = cache.object(forKey: path as NSString) { return i }
        guard let i = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(i, forKey: path as NSString)
        return i
    }
}
