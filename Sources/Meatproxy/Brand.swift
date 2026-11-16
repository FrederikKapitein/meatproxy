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

    /// The native About panel: the icon, the name, the story and the line about you.
    @MainActor static func showAbout() {
        let centred = NSMutableParagraphStyle(); centred.alignment = .center
        let credits = NSMutableAttributedString(string: story + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centred])
        credits.append(NSAttributedString(string: userLine, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.labelColor, .paragraphStyle: centred]))
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: name, .credits: credits,
                                                                  .applicationVersion: "Hobby build", .version: ""]
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

/// A Tuinstra button (tactile-utility): a face on a 1 px edge and a solid ledge straight below, plus a faint soft
/// shadow. Pressing moves the face straight down onto its ledge within about 70 ms and holds at least 88 ms, so a quick
/// click still reads; letting go springs back in about 180 ms. Disabled buttons sit flat. Never more than one primary
/// per decision.
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
        let face: Color = kind == .primary ? .signal : kind == .destructive ? .stuck : .raised
        let ledge: Color = kind == .primary ? .ledge : kind == .destructive ? .dangerLedge : .neutralLedge
        configuration.label
            .padding(inset ?? EdgeInsets())
            .foregroundStyle(kind == .neutral ? Color.inkText : Color.onSignal)
            .background(face, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(kind == .neutral ? Color.border : Color.onSignal, lineWidth: 1))
            // the ledge: the same shape, solid, straight below; and the faint soft shadow under it
            .background(RoundedRectangle(cornerRadius: radius).fill(ledge)
                .offset(y: lifted ? depth : 0).opacity(lifted ? 1 : 0))
            .shadow(color: .black.opacity(lifted ? 0.08 : 0), radius: 2.5, y: 3)
            .offset(y: enabled && down ? travel : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { press() } else { release() } }
            // a keyboard shortcut: the same press and release
            .onChange(of: pulse) { _, _ in guard enabled else { return }; press(); release() }
    }
}

/// A lifted input field: a surface on a 1 px edge and a 2 px neutral ledge. It never travels; focus shows a ring.
struct LiftedField: ViewModifier {
    var focused: Bool
    var radius: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .background(Color.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.border, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: radius).fill(Color.neutralLedge).offset(y: 2))
            .shadow(color: .black.opacity(0.08), radius: 2.5, y: 3)
            .overlay(RoundedRectangle(cornerRadius: radius + 3).stroke(Color.inkText, lineWidth: 2).padding(-3).opacity(focused ? 1 : 0))
    }
}

extension View {
    func lifted(focused: Bool, radius: CGFloat = 6) -> some View { modifier(LiftedField(focused: focused, radius: radius)) }
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
                    if let detail { Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.muted) }
                }
                .padding(.leading, mark - cell + gap - cell)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(Brand.name)
    }
}

// MARK: segments

/// A Tuinstra segmented control: a lifted neutral tray (1 px edge, 2 px ledge) in which the current segment is a lifted
/// yellow key (yellow face, ink edge, 3 px yellow-brown ledge), as in Tuinstra's own toggles. The key slides to the
/// segment you pick; the others are quiet.
struct LiftedSegments<ID: Hashable>: View {
    struct Item { var id: ID; var title: String; var icon: String? = nil; var enabled = true; var help: String? = nil }
    let items: [Item]
    let selected: ID
    var mono = false
    var fontSize: CGFloat = 13
    var padding = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
    let pick: (ID) -> Void
    /// the yellow key slides to the segment you pick
    @Namespace private var keySpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { pick(item.id) } label: {
                    HStack(spacing: 6) {
                        if let icon = item.icon { Image(systemName: icon) }
                        Text(item.title).lineLimit(1).fixedSize()
                    }
                    .font(.system(size: fontSize, weight: item.id == selected ? .bold : .semibold, design: mono ? .monospaced : .default))
                    .padding(padding)
                }
                .buttonStyle(SegmentKeyStyle(on: item.id == selected, keySpace: keySpace))
                .disabled(!item.enabled && item.id != selected)
                .help(item.help ?? "")
            }
        }
        .animation(reduceMotion ? nil : Motion.slide, value: selected)
        .padding(.horizontal, 3).padding(.top, 3).padding(.bottom, 6)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.border, lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.neutralLedge).offset(y: 2))
        .shadow(color: .black.opacity(0.08), radius: 2.5, y: 3)
    }
}

private struct SegmentKeyStyle: ButtonStyle {
    let on: Bool
    let keySpace: Namespace.ID
    func makeBody(configuration: Configuration) -> some View { SegmentKey(configuration: configuration, on: on, keySpace: keySpace) }
}

private struct SegmentKey: View {
    let configuration: ButtonStyleConfiguration
    let on: Bool
    let keySpace: Namespace.ID
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    var body: some View {
        let pressed = configuration.isPressed && enabled
        configuration.label
            .foregroundStyle(on ? Color.onSignal : !enabled ? Color.muted.opacity(0.45) : hover ? Color.inkText : Color.muted)
            .background {
                if on {
                    // the key: yellow face, ink edge, its yellow-brown ledge straight below; pressed, it lands on the ledge
                    RoundedRectangle(cornerRadius: 5).fill(Color.signal)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.onSignal, lineWidth: 1))
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.ledge).offset(y: pressed ? 0 : 3))
                        .matchedGeometryEffect(id: "key", in: keySpace)
                } else if hover && enabled {
                    RoundedRectangle(cornerRadius: 5).fill(Color.divider.opacity(0.5))
                }
            }
            .offset(y: pressed ? (on ? (reduceMotion ? 1 : 3) : 1) : 0)
            .animation(reduceMotion ? nil : pressed ? Motion.pressIn : Motion.springBack, value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: 5))
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

/// A Tuinstra switch: a lifted track (1 px edge, 2 px neutral ledge). Off: a neutral track with a light knob on the left.
/// On: a solid Tuinstra-yellow track (the current state) with an ink knob on the right. The knob slides; with reduced
/// motion it jumps. Keeps the switch's accessibility.
struct TactileToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { TactileSwitch(configuration: configuration) }
}

private struct TactileSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let on = configuration.isOn
        // a real button: focusable, Space toggles it, disabled when the switch is; its label is spoken, not drawn
        // (the row around it shows the words)
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Color.signal : Color.raised)
                    .overlay(Capsule().strokeBorder(on ? Color.onSignal : Color.border, lineWidth: 1))
                    .background(Capsule().fill(on ? Color.ledge : Color.neutralLedge).offset(y: 2))
                Circle().fill(on ? Color.onSignal : Color.inkText).frame(width: 14, height: 14).padding(3)
            }
            .frame(width: 38, height: 20)
            .shadow(color: .black.opacity(0.08), radius: 2.5, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : Motion.slide, value: on)
        // to assistive tech it is the system switch, with its label and on/off value
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A keyboard shortcut shown where its action is (tuinstra tactile): a small key with an edge and a 1 pt ledge.
/// On yellow it takes the ink of the yellow key it sits on.
struct KeyCap: View {
    let key: String
    var onYellow = false
    init(_ key: String, onYellow: Bool = false) { self.key = key; self.onYellow = onYellow }
    var body: some View {
        Text(key).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
            .foregroundStyle(onYellow ? Color.onSignal : Color.muted)
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 15)
            .background(RoundedRectangle(cornerRadius: 3).fill(onYellow ? Color.onSignal.opacity(0.08) : Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(onYellow ? Color.onSignal.opacity(0.55) : Color.border.opacity(0.8), lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 3).fill(onYellow ? Color.ledge.opacity(0.5) : Color.neutralLedge).offset(y: 1))
            .accessibilityHidden(true)
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
