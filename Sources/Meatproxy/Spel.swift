import SwiftUI
import AppKit
import FactoryCore

// Spel+ (D80): Y · Spel's shapes and type scale on X · Rust's cool neutrals, with X's restraint. One frame with a bevel
// and a plinth, chunky buttons with an under-edge, folder tabs, one card, pixel-crisp icons. The tokens are the kit's
// (assets/ux-spelplus/kit/skit.py).
//
// Type: 11 · 13 · 15 · 19 · 26 (eyebrow, tag, key, meta · body, tab · card title, button · panel title · inspector,
// sheet and Settings title). Radii: 10 for panels, cards, buttons and wells; 6 for tags, keys, chips and small
// controls. Two text levels. Yellow only for the one primary action of a view and for what waits for you; on is green
// with its word, a chosen option white, the selection cyan; warn is amber with a triangle, stuck red with a square.

// MARK: colour

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
    /// behind the world, and the page
    static let ink = Color(hex: 0x121212)
    /// a panel's face, and the top of its bevel
    static let panel = Color(hex: 0x141414)
    static let panelTop = Color(hex: 0x1C1C1C)
    /// the rail behind folder tabs
    static let rail = Color(hex: 0x101010)
    /// a card
    static let surface = Color(hex: 0x1A1A1A)
    /// raised: a card's own raised part, a hover
    static let raised = Color(hex: 0x242424)
    /// recessed: inputs, meters, sockets
    static let well = Color(hex: 0x0E0E0E)
    /// the 2 pt frame and card edge
    static let divider = Color.contrast(0x2C2C2C, increased: 0x6E6E6E)
    /// a control's edge
    static let border = Color.contrast(0x3A3A3A, increased: 0x767676)
    /// the edge of what you type in and of a live ghost button: clear of the dark around it (about 3:1)
    static let inputEdge = Color.contrast(0x5C5C5C, increased: 0x8A8A8A)
    /// the hard shadow under a frame or a button
    static let plinth = Color(hex: 0x050505)
    // two text levels only (X): main and secondary, both at least 4.5:1 on every surface
    static let inkText = Color(hex: 0xF2F2F2)
    static let muted = Color.contrast(0xA3A3A3, increased: 0xC8C8C8)
    // yellow: the one primary action and what waits for you; its gradient top, its edge, its ledge, ink on it
    static let signal = Color(hex: 0xFFD83D)
    static let signalTop = Color(hex: 0xFFE268)
    static let signalEdge = Color(hex: 0xC9A51C)
    static let ledge = Color(hex: 0x8A6D10)
    static let onSignal = Color(hex: 0x141414)
    static let neutralLedge = Color(hex: 0x050505)
    static let dangerLedge = Color(hex: 0x6E1A1A)
    /// a warning: amber, always with a triangle and a word
    static let warn = Color(hex: 0xFF9F43)
    /// busy, and the current phase
    static let working = Color(hex: 0x6EA8FE)
    /// stuck or down: red, always with a square and a word
    static let stuck = Color(hex: 0xFF6B6B)
    /// on, and done
    static let done = Color(hex: 0x4CC38A)
    static let doneEdge = Color(hex: 0x2F8A5E)
    /// the selection, in the world and on its card
    static let selection = Color(hex: 0x4FE0F5)
    /// a chosen option or an active toggle face: white, as in X
    static let lit = Color(hex: 0xF2F2F2)
    static let lit2 = Color(hex: 0xD6D6D6)
    static let litLedge = Color(hex: 0x6E6E6E)
    /// A colour that follows the Mac's Increase contrast (its high-contrast appearance): edges and secondary text step
    /// up there, everything else stays.
    static func contrast(_ normal: UInt32, increased: UInt32) -> Color {
        func ns(_ h: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
        }
        let lo = ns(normal), hi = ns(increased)
        return Color(nsColor: NSColor(name: nil) { a in
            let high = a.bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua])
            return high == .accessibilityHighContrastDarkAqua || high == .accessibilityHighContrastAqua ? hi : lo
        })
    }
    /// a provider's colour lives in the world and its emblem only (E5), never on HUD text
    static func provider(_ p: Provider) -> Color { p == .claude ? Color(hex: 0xE8916B) : Color(hex: 0x6FD3B8) }
    static func state(_ s: SessionState) -> Color {
        switch s { case .working: .working; case .waiting: .signal; case .stuck: .stuck; case .done: .done }
    }
    /// a role's colour: its tag's swatch and its portrait's rim
    static func role(_ r: CastRole) -> Color {
        switch r {
        case .ceo: Color(hex: 0xE9E2D0)
        case .lead: Color(hex: 0x8FA9D6)
        case .pm: Color(hex: 0x2FB0A8)
        case .dev: Color(hex: 0x5B84E8)
        case .tester: Color(hex: 0xE86A92)
        case .designer: Color(hex: 0xFF6AD5)
        case .devops: Color(hex: 0x8F74EA)
        case .researcher: Color(hex: 0x7FA05A)
        case .sales, .marketing: Color(hex: 0x3FAE6A)
        }
    }
}

// MARK: type

extension Font {
    /// 26: the title of an inspector, a sheet or Settings
    static let s26 = Font.system(size: 26, weight: .heavy)
    /// 19: a panel or section title
    static let s19 = Font.system(size: 19, weight: .bold)
    /// 15: a card title, a quest, a button
    static let s15 = Font.system(size: 15, weight: .semibold)
    static let s15b = Font.system(size: 15, weight: .bold)
    /// 13: body text, a tab, a small button
    static let s13 = Font.system(size: 13)
    static let s13m = Font.system(size: 13, weight: .semibold)
    static let s13b = Font.system(size: 13, weight: .bold)
    /// 11: an eyebrow, a tag or a key (bold caps), or a meta line
    static let s11 = Font.system(size: 11, weight: .bold)
    static let s11n = Font.system(size: 11, weight: .medium)
    /// mono only for paths and code
    static let mono = Font.system(size: 13, design: .monospaced)
    static let mono11 = Font.system(size: 11, weight: .medium, design: .monospaced)
}

/// 11 pt bold caps: what something is, above its name.
struct Eyebrow: View {
    let text: String
    var color: Color = .muted
    init(_ text: String, color: Color = .muted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.s11).tracking(0.77).foregroundStyle(color).lineLimit(1)
    }
}

/// A section's head: an optional pixel icon, the eyebrow, and something on the right.
struct SectionHead<Right: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var right: () -> Right
    init(_ title: String, icon: String? = nil, @ViewBuilder right: @escaping () -> Right) { self.title = title; self.icon = icon; self.right = right }
    var body: some View {
        HStack(spacing: 8) {
            if let icon { PixelIcon(icon, color: .muted) }
            Eyebrow(title)
            Spacer(minLength: 0)
            right()
        }
        .frame(minHeight: 20)
    }
}
extension SectionHead where Right == EmptyView {
    init(_ title: String, icon: String? = nil) { self.title = title; self.icon = icon; self.right = { EmptyView() } }
}

// MARK: pixel icons

/// The kit's icons: 9 × 9 cells, drawn crisp at whole points (18 pt is 2 pt a cell).
struct PixelIcon: View {
    let name: String
    var color: Color = .muted
    var size: CGFloat = 18
    init(_ name: String, color: Color = .muted, size: CGFloat = 18) { self.name = name; self.color = color; self.size = size }
    var body: some View {
        Canvas { ctx, sz in
            guard let rows = PixelIcon.cells[name] else { return }
            let u = sz.width / 9
            var p = Path()
            for (y, row) in rows.enumerated() {
                var x = 0
                let cs = Array(row)
                while x < cs.count {
                    if cs[x] == "#" {
                        let s = x
                        while x < cs.count && cs[x] == "#" { x += 1 }
                        p.addRect(CGRect(x: CGFloat(s) * u, y: CGFloat(y) * u, width: CGFloat(x - s) * u, height: u))
                    } else { x += 1 }
                }
            }
            ctx.fill(p, with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static let cells: [String: [String]] = [
        "search": ["..###....", ".#...#...", "#.....#..", "#.....#..", "#.....#..", ".#...#...", "..###.#..", "......##.", ".......##"],
        "gear": ["....#....", ".#.###.#.", "..#####..", ".##...##.", "###...###", ".##...##.", "..#####..", ".#.###.#.", "....#...."],
        "terminal": ["#########", "#########", "#.......#", "#.#.....#", "#..#....#", "#.#.....#", "#....##.#", "#.......#", "#########"],
        "help": ["..####...", ".##..##..", ".....##..", "....##...", "...##....", "...##....", ".........", "...##....", "...##...."],
        "layers": [".........", "....#....", "..##.##..", "##.....##", "..##.##..", "#...#...#", ".##...##.", "...###...", "........."],
        "up": ["....#....", "...###...", "..#####..", ".##.#.##.", "....#....", "....#....", "....#....", "....#....", "........."],
        "close": [".........", ".##...##.", "..##.##..", "...###...", "....#....", "...###...", "..##.##..", ".##...##.", "........."],
        "check": [".........", ".......##", "......##.", ".....##..", "##..##...", ".####....", "..##.....", ".........", "........."],
        "sq": [".........", ".........", "..#####..", "..#####..", "..#####..", "..#####..", "..#####..", ".........", "........."],
        "bang": ["...##....", "...##....", "...##....", "...##....", "...##....", ".........", "...##....", "...##....", "........."],
        "pulse": [".........", "..#......", "..#......", ".#.#..#..", "#..#.#.##", "...#.#...", "....#....", ".........", "........."],
        "play": [".#.......", ".##......", ".###.....", ".####....", ".#####...", ".####....", ".###.....", ".##......", ".#......."],
        "log": [".######..", ".#....#..", ".#.##.#..", ".#....#..", ".#.###.#.", ".#....#..", ".#.##.#..", ".#....#..", ".######.."],
        "server": ["#########", "#.......#", "#.##..#.#", "#########", "#.......#", "#.##..#.#", "#########", "....#....", "..#####.."],
        "lock": ["...###...", "..#...#..", "..#...#..", ".#######.", ".#######.", ".###.###.", ".###.###.", ".#######.", "........."],
        "chev": ["..#......", "..##.....", "...##....", "....##...", "...##....", "..##.....", "..#......", ".........", "........."],
        "chevd": [".........", ".........", "#.......#", "##.....##", ".##...##.", "..##.##..", "...###...", "....#....", "........."],
        "plus": [".........", "....#....", "....#....", "....#....", "#########", "....#....", "....#....", "....#....", "........."],
        "minus": [".........", ".........", ".........", ".........", "#########", ".........", ".........", ".........", "........."],
        "copy": ["...######", "...#....#", "######..#", "#....#..#", "#....#..#", "#....####", "#....#...", "######...", "........."],
        "campus": [".........", "....#....", "..#####..", "#########", ".#######.", "..#####..", "...###...", "....#....", "........."],
        "tower": ["..#####..", "..#.#.#..", "..#####..", "..#.#.#..", "..#####..", "..#.#.#..", "..#####..", "..##.##..", "#########"],
        "floor": [".........", ".........", "#########", "#.#.#.#.#", "#########", "#.#.#.#.#", "#########", ".........", "........."],
        "person": ["...###...", "...###...", "...###...", ".........", "..#####..", ".#######.", ".#######.", ".##...##.", ".##...##."],
        "idea": ["...###...", "..#...#..", ".#.....#.", ".#.....#.", "..#...#..", "...#.#...", "...###...", "...###...", "........."],
        "clock": ["..#####..", ".#.....#.", "#...#...#", "#...#...#", "#...###.#", "#.......#", ".#.....#.", "..#####..", "........."],
        "warn": ["....#....", "...###...", "...#.#...", "..##.##..", "..##.##..", ".#######.", ".###.###.", "#########", "........."],
        "pause": [".........", ".##...##.", ".##...##.", ".##...##.", ".##...##.", ".##...##.", ".##...##.", ".##...##.", "........."],
        "chat": ["#########", "#.......#", "#.#.#.#.#", "#.......#", "#########", ".##......", ".#.......", ".........", "........."],
        "refresh": ["..####.#.", ".#....##.", "#....###.", "#........", "#.......#", "........#", ".###....#", ".##....#.", ".#.####.."],
        "folder": [".........", "###......", "#..#####.", "#.......#", "#.......#", "#.......#", "#.......#", "#########", "........."],
        "file": ["#####....", "#...##...", "#....##..", "#.....#..", "#.....#..", "#.....#..", "#.....#..", "#######..", "........."],
        "key": [".###.....", "#...#....", "#...#####", "#...#.#.#", ".###..#.#", ".........", ".........", ".........", "........."],
        "pebble": [".........", "...###...", ".#######.", "#########", "#########", ".#######.", "...###...", ".........", "........."],
        "scroll": [".#######.", "#.......#", ".#.###.#.", ".#.....#.", ".#.###.#.", ".#.....#.", ".#.##..#.", "#.......#", ".#######."],
        "send": [".........", "#........", "####.....", "#..####..", "#.....###", "#..####..", "####.....", "#........", "........."],
        "map": [".........", "##.###.##", "#.##.##.#", "#..#.#..#", "#..#.#..#", "#..#.#..#", "##.###.##", ".........", "........."],
        "power": ["....#....", ".#..#..#.", "#...#...#", "#...#...#", "#.......#", "#.......#", ".#.....#.", "..#####..", "........."],
        "star": ["....#....", "....#....", "...###...", "#########", ".#######.", "..#####..", "..##.##..", ".##...##.", "........."],
        "dot": [".........", ".........", "...###...", "..#####..", "..#####..", "..#####..", "...###...", ".........", "........."],
        "ring": [".........", ".........", "...###...", "..#...#..", "..#...#..", "..#...#..", "...###...", ".........", "........."],
        "eye": [".........", "..#####..", ".#.....#.", "#..###..#", "#..###..#", ".#.....#.", "..#####..", ".........", "........."],
        "branch": [".##......", ".##...##.", ".#....##.", ".#.....#.", ".#....#..", ".#..##...", ".###.....", ".##......", ".##......"],
        "burst": ["....#....", ".#..#..#.", "..#.#.#..", "...###...", "#########", "...###...", "..#.#.#..", ".#..#..#.", "....#...."],
        "back": ["......#..", ".....##..", "....##...", "...##....", "....##...", ".....##..", "......#..", ".........", "........."],
        "pencil": ["......##.", ".....#..#", "....#..#.", "...#..#..", "..#..#...", ".#..#....", "#..#.....", "##.......", "........."],
        "box": ["....#....", "..##.##..", "##.....##", "#.##.##.#", "#...#...#", "#...#...#", "##..#..##", "..###.#..", "....#...."],
        "moon": ["...####..", "..##.....", ".##......", ".##......", ".##......", ".##......", "..##.....", "...####..", "........."],
        "ship": ["....#....", "...###...", "...###...", "..#####..", "..#####..", ".#######.", "##.###.##", "#..#.#..#", "...#.#..."],
        "hand": ["...#.#...", "..##.##.#", "..##.##.#", "#.##.##.#", "#.#######", "#.#######", ".########", "..######.", "...####.."],
    ]
}

// MARK: frames

/// Y's frame in X's neutrals: a face that lightens to its top (the bevel), a 2 pt edge, a 1 pt light line inside the
/// top, a 4 pt hard plinth straight below, and a soft shadow. Every panel and sheet wears it; it is opaque.
struct SpelFrame: ViewModifier {
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background {
                ZStack(alignment: .top) {
                    Color.panel
                    LinearGradient(colors: [.panelTop, .panel], startPoint: .top, endPoint: .bottom).frame(height: 64)
                }
                .clipShape(shape)
            }
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, radius).padding(.top, 2) }
            .overlay(shape.strokeBorder(Color.divider, lineWidth: 2))
            .background(shape.fill(Color.plinth).offset(y: 4).shadow(color: .black.opacity(0.45), radius: 15, y: 10))
    }
}

/// One card for everything in a panel: a 2 pt edge, radius 10, 12 inside, a 2 pt plinth. A coloured left edge means
/// something: yellow waits for you, amber needs a look, red is stuck; a cyan rim is the selection.
struct SpelCard: ViewModifier {
    var flag: Color? = nil
    var selected = false
    var pad: CGFloat = 12
    var fill: Color = .surface
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        content
            .padding(pad)
            .padding(.leading, flag == nil ? 0 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.horizontal, 10).padding(.top, 2) }
            .overlay(shape.strokeBorder(selected ? Color.selection : Color.divider, lineWidth: 2))
            .overlay {
                if let flag {
                    HStack(spacing: 0) { Rectangle().fill(flag).frame(width: 6); Spacer(minLength: 0) }.clipShape(shape).allowsHitTesting(false)
                }
            }
            .background(shape.fill(Color.plinth).offset(y: 2))
            // the selection's halo: a faint ring just outside the edge (a shadow would blur everything inside)
            .overlay { if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.selection.opacity(contrast == .increased ? 0.7 : 0.3), lineWidth: 2).padding(-3).allowsHitTesting(false) } }
    }
}

/// Recessed: inputs, meters, sockets, the field of a question.
struct SpelWell: ViewModifier {
    var pad: CGFloat = 10
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content.padding(pad)
            .background(shape.fill(Color.well))
            .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.35)).frame(height: 2).padding(.horizontal, radius / 2).padding(.top, 2) }
            .overlay(shape.strokeBorder(Color.divider, lineWidth: 2))
    }
}

extension View {
    func spelFrame(radius: CGFloat = 10) -> some View { modifier(SpelFrame(radius: radius)) }
    func spelCard(flag: Color? = nil, selected: Bool = false, pad: CGFloat = 12, fill: Color = .surface) -> some View {
        modifier(SpelCard(flag: flag, selected: selected, pad: pad, fill: fill))
    }
    func spelWell(pad: CGFloat = 10, radius: CGFloat = 10) -> some View { modifier(SpelWell(pad: pad, radius: radius)) }
    /// a whole panel: 16 inside the frame
    func spelPanel(pad: CGFloat = 16) -> some View { padding(pad).spelFrame() }
}

/// A square well that holds an emblem, an icon or a portrait.
struct Socket<Inner: View>: View {
    var size: CGFloat = 40
    @ViewBuilder var inner: () -> Inner
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        inner()
            .frame(width: size, height: size)
            .background(shape.fill(Color.well))
            .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.35)).frame(height: 2).padding(.horizontal, 5).padding(.top, 2) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.divider, lineWidth: 2))
    }
}

// MARK: buttons

/// The chunky button (Y's shape, X's neutrals): a 2 pt edge and a hard ledge below; pressed, it lands on the ledge.
/// Primary is the one yellow action of a view; secondary everything else; ghost a quiet link-like control; danger a
/// confirmed removal. Disabled is flat and grey on a solid edge, with no ledge, so it never looks pressable (a dashed edge
/// means "not yet" or an empty slot, nothing else); its label stays readable (E9). m is 34 high, s 28, l 40.
struct SpelButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    enum Size { case s, m, l }
    var kind: Kind = .secondary
    var size: Size = .m
    /// a square button: an icon alone
    var square = false
    /// stretch to the width it is given
    var wide = false
    var pulse: Int = 0
    func makeBody(configuration: Configuration) -> some View {
        SpelButtonBody(configuration: configuration, kind: kind, size: size, square: square, wide: wide, pulse: pulse)
    }
}

private struct SpelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: SpelButtonStyle.Kind
    let size: SpelButtonStyle.Size
    let square: Bool
    let wide: Bool
    let pulse: Int
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var down = false
    @State private var token = 0

    var body: some View {
        let h: CGFloat = size == .s ? 28 : size == .m ? 34 : 40
        let r: CGFloat = size == .s ? 6 : 10
        let font: Font = size == .s ? .s13b : .s15b
        let depth: CGFloat = kind == .ghost ? 0 : size == .s ? 2 : 3
        let pressed = (configuration.isPressed || down) && enabled
        let travel: CGFloat = pressed ? (reduceMotion ? min(depth, 1) : depth) : 0
        configuration.label
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : (size == .s ? 10 : 12))
            .frame(minWidth: square ? h : nil, maxWidth: wide ? .infinity : nil)
            .frame(width: square ? h : nil, height: h)
            .foregroundStyle(ink)
            .background(face(r))
            .overlay(edge(r))
            .background(RoundedRectangle(cornerRadius: r).fill(ledgeColor).offset(y: enabled && !pressed ? depth : 0).opacity(enabled ? 1 : 0))
            .offset(y: travel)
            .contentShape(RoundedRectangle(cornerRadius: r))
            .onHover { hover = $0 }
            .animation(reduceMotion ? nil : pressed ? Motion.pressIn : Motion.springBack, value: pressed)
            .onChange(of: pulse) { _, _ in
                guard enabled else { return }
                token += 1; let mine = token; down = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { if mine == token { down = false } }
            }
    }

    private var ink: Color {
        if !enabled { return .muted }
        switch kind { case .primary: return .onSignal; case .ghost: return hover ? .inkText : .muted; case .danger: return .onSignal; case .secondary: return .inkText }
    }
    private var ledgeColor: Color {
        switch kind { case .primary: return .ledge; case .danger: return .dangerLedge; default: return .plinth }
    }
    @ViewBuilder private func face(_ r: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: r)
        if !enabled { shape.fill(Color.surface) }
        else {
            switch kind {
            case .primary: shape.fill(LinearGradient(colors: [hover ? Color(hex: 0xFFE987) : .signalTop, .signal], startPoint: .top, endPoint: .bottom))
            case .danger: shape.fill(Color.stuck)
            case .ghost: shape.fill(hover ? Color.raised.opacity(0.6) : Color.clear)
            case .secondary: shape.fill(LinearGradient(colors: [hover ? Color(hex: 0x3B3B3B) : Color(hex: 0x333333), Color(hex: 0x292929)], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1).padding(.horizontal, r).padding(.top, 2) }
            }
        }
    }
    @ViewBuilder private func edge(_ r: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: r)
        if !enabled { shape.strokeBorder(Color.divider, lineWidth: 2) }
        else {
            switch kind {
            case .primary: shape.strokeBorder(Color.signalEdge, lineWidth: 2)
            case .danger: shape.strokeBorder(Color(hex: 0xB23A3A), lineWidth: 2)
            case .ghost: shape.strokeBorder(Color.inputEdge, lineWidth: 2)
            case .secondary: shape.strokeBorder(Color.border, lineWidth: 2)
            }
        }
    }
}

/// What sits in a button: a pixel icon, a label and its key, in that order (C8). Any of the three may be left out.
struct SpelLabel: View {
    var icon: String? = nil
    var title: String? = nil
    var key: String? = nil
    var onYellow = false
    var iconColor: Color? = nil
    init(_ title: String? = nil, icon: String? = nil, key: String? = nil, onYellow: Bool = false, iconColor: Color? = nil) {
        self.title = title; self.icon = icon; self.key = key; self.onYellow = onYellow; self.iconColor = iconColor
    }
    var body: some View {
        HStack(spacing: 8) {
            if let icon { PixelIcon(icon, color: iconColor ?? (onYellow ? .onSignal : .muted)) }
            if let title { Text(title) }
            if let key { KeyCap(key, onYellow: onYellow) }
        }
        .accessibilityHint(key.map(KeyCap.spoken) ?? "")
    }
}

// MARK: small parts

/// A tag: 20 high, 11 pt caps, a 1.5 pt edge. Neutral is quiet; a tone carries its colour and, for a warning or a
/// stop, its shape.
struct Tag: View {
    enum Tone { case neutral, warn, stuck, done, work, quest, sel }
    let text: String
    var tone: Tone = .neutral
    var icon: String? = nil
    init(_ text: String, tone: Tone = .neutral, icon: String? = nil) { self.text = text; self.tone = tone; self.icon = icon }
    var color: Color {
        switch tone { case .neutral: .muted; case .warn: .warn; case .stuck: .stuck; case .done: .done; case .work: .working; case .quest: .signal; case .sel: .selection }
    }
    var body: some View {
        let c = color
        let ic = icon ?? (tone == .warn ? "warn" : tone == .stuck ? "sq" : nil)
        HStack(spacing: 4) {
            if let ic { PixelIcon(ic, color: c, size: 9) }
            Text(text.uppercased()).font(.s11).tracking(0.7).lineLimit(1).fixedSize()
        }
        .foregroundStyle(c)
        .padding(.horizontal, 7).frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 6).fill(tone == .neutral ? Color.white.opacity(0.03) : c.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tone == .neutral ? Color.border : c, lineWidth: 1.5))
    }
}

/// A role as a tag: its swatch and its name.
struct RoleTag: View {
    let role: CastRole
    var label: String? = nil
    var body: some View {
        let c = Color.role(role)
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
            Text((label ?? role.label).uppercased()).font(.s11).tracking(0.7).lineLimit(1).fixedSize()
        }
        .foregroundStyle(Color.inkText)
        .padding(.leading, 5).padding(.trailing, 7).frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 6).fill(c.opacity(0.18)))
    }
}

/// The yellow quest count: only ever "this many wait for you".
struct QuestBadge: View {
    let count: Int
    var small = false
    var body: some View {
        let h: CGFloat = small ? 18 : 20
        Text("\(count)").font(.system(size: 11, weight: .heavy).monospacedDigit())
            .foregroundStyle(Color.onSignal)
            .padding(.horizontal, small ? 5 : 6).frame(minWidth: h, minHeight: h, maxHeight: h)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.signal))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.ledge).offset(y: 2))
            .accessibilityLabel("\(count) waiting for you")
    }
}

/// The quest marker: a yellow diamond with a dark glyph ("!" a decision, "?" a chat, a rack for the Server room).
struct QuestMarker: View {
    var glyph: String = "bang"
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.signal)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.ledge).offset(y: 2))
                .frame(width: size - 6, height: size - 6).rotationEffect(.degrees(45))
            PixelIcon(glyph, color: .onSignal, size: size < 26 ? 9 : 18)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A count of what something holds, quiet: "4", "WORKSTREAMS · 4" lives in the tab, never as a badge on it.
struct Pips: View {
    let count: Int
    let current: Int
    var done = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { k in
                let shape = RoundedRectangle(cornerRadius: 3)
                Group {
                    if k < done { shape.fill(Color.done).overlay(shape.strokeBorder(Color.doneEdge, lineWidth: 2)) }
                    else if k == current { shape.fill(Color.lit).overlay(shape.strokeBorder(Color.white, lineWidth: 2)) }
                    else { shape.strokeBorder(Color.muted, style: StrokeStyle(lineWidth: 2, dash: [3, 2])) }
                }
                .frame(width: 22, height: 10)
            }
        }
        .accessibilityElement().accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// A labelled meter: the value, and a striped bar in a well. Amber past `warnAt`.
struct Meter: View {
    let label: String
    let value: String
    let fraction: Double
    var warnAt: Double = 2
    var body: some View {
        let over = fraction >= warnAt
        let c: Color = over ? .warn : .done
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.s13).foregroundStyle(Color.muted)
                Spacer(minLength: 6)
                Text(value).font(.s13m.monospacedDigit()).foregroundStyle(over ? Color.warn : Color.inkText).lineLimit(1)
            }
            GeometryReader { g in
                let w = max(4, (g.size.width - 4) * min(max(fraction, 0), 1))
                Canvas { ctx, sz in
                    var x: CGFloat = 0
                    while x < sz.width {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: min(6, sz.width - x), height: sz.height)), with: .color(c))
                        ctx.fill(Path(CGRect(x: x + 6, y: 0, width: min(2, max(0, sz.width - x - 6)), height: sz.height)), with: .color(c.opacity(0.75)))
                        x += 8
                    }
                }
                .frame(width: w, height: 8).padding(2)
            }
            .frame(height: 12)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.well))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.divider, lineWidth: 2))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A workstream's road (E9): done is a filled green node with a tick, the current phase a filled blue node with a
/// bold label, what is ahead a dashed outline; every label stays readable.
struct PhaseTrack: View {
    let phases: [String]
    /// the index of the current phase; phases.count when all are done
    let current: Int
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(phases.enumerated()), id: \.offset) { k, p in
                VStack(spacing: 4) {
                    node(k)
                    Text(p.uppercased()).font(.system(size: 11, weight: k == current ? .heavy : .semibold)).tracking(0.6)
                        .foregroundStyle(k == current ? Color.inkText : Color.muted).lineLimit(1).fixedSize()
                }
                .frame(width: 44)
                if k < phases.count - 1 {
                    Group {
                        if k < current { Rectangle().fill(Color.done) }
                        else { Line().stroke(Color.muted, style: StrokeStyle(lineWidth: 2, dash: [3, 3])) }
                    }
                    .frame(height: 2).frame(minWidth: 6).padding(.top, 8)
                }
            }
        }
        .accessibilityElement().accessibilityLabel(current < phases.count ? "In \(phases[current])" : "Done")
    }
    @ViewBuilder private func node(_ k: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        if k < current {
            shape.fill(Color.done).overlay(shape.strokeBorder(Color.doneEdge, lineWidth: 2))
                .overlay(PixelIcon("check", color: Color(hex: 0x0B2A1A), size: 9)).frame(width: 18, height: 18)
        } else if k == current {
            shape.fill(Color.working).overlay(shape.strokeBorder(Color(hex: 0xCFE0FF), lineWidth: 2))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.working.opacity(0.3)).padding(-3)).frame(width: 18, height: 18)
        } else {
            shape.strokeBorder(Color.muted, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 18, height: 18)
        }
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
    }
}

// MARK: folder tabs

/// Folder tabs (Y): the active one is a raised card tab joined to the body below it; the rest sit on the rail. A tab
/// carries a yellow badge only for what waits for you (C10); how much a tab holds is said inside it.
struct FolderTabs<ID: Hashable>: View {
    struct Item { var id: ID; var title: String; var badge: Int = 0; var help: String? = nil }
    let items: [Item]
    let selected: ID
    var stretch = true
    let pick: (ID) -> Void
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                FolderTab(item: item, on: item.id == selected, stretch: stretch) { pick(item.id) }
            }
            if !stretch { Spacer(minLength: 0) }
        }
        .frame(height: 36, alignment: .bottom)
        .accessibilityElement(children: .contain)
    }
}

private struct FolderTab<ID: Hashable>: View {
    let item: FolderTabs<ID>.Item
    let on: Bool
    let stretch: Bool
    let pick: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: pick) {
            HStack(spacing: 5) {
                Text(item.title).font(.system(size: 13, weight: on ? .bold : .semibold)).lineLimit(1).fixedSize()
                if item.badge > 0 { QuestBadge(count: item.badge, small: true) }
            }
            .foregroundStyle(on || hover ? Color.inkText : Color.muted)
            .padding(.horizontal, stretch ? 8 : 14)
            .frame(maxWidth: stretch ? .infinity : nil)
            .frame(height: on ? 36 : 30)
            .background(TabShape().fill(on ? Color.surface : Color.rail))
            .overlay(TabShape().stroke(Color.divider, lineWidth: 2).padding(.horizontal, 1).padding(.top, 1))
            .padding(.bottom, on ? 0 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .zIndex(on ? 2 : 0)
        .help(item.help ?? "")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badge) waiting for you" : item.title)
    }
}

/// A folder tab's outline: rounded on top, open at the bottom.
struct TabShape: Shape {
    var radius: CGFloat = 10
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// The body under folder tabs: one card, square at its top left.
struct TabBody: ViewModifier {
    var pad: CGFloat = 12
    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 10)
        content.padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.surface))
            .overlay(shape.strokeBorder(Color.divider, lineWidth: 2))
    }
}

extension View {
    func tabBody(pad: CGFloat = 12) -> some View { modifier(TabBody(pad: pad)) }
}

/// Tabs on their body: the tabs overlap the body's top edge by its 2 pt, so the active tab joins it.
struct TabbedBox<ID: Hashable, Content: View>: View {
    let items: [FolderTabs<ID>.Item]
    let selected: ID
    var stretch = true
    let pick: (ID) -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: -2) {
            FolderTabs(items: items, selected: selected, stretch: stretch, pick: pick).zIndex(1)
            content().tabBody()
        }
    }
}

// MARK: the inspector's head

/// An inspector's head: a crest in a socket, the eyebrow, the name at 26, and the close button.
struct InspectorHead<Crest: View>: View {
    let eyebrow: String
    let title: String
    var marker = false
    var titleLines = 2
    let close: () -> Void
    var closeHelp = "Close (Esc)"
    @ViewBuilder var crest: () -> Crest
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            crest()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if marker { QuestMarker(size: 18) }
                    Eyebrow(eyebrow)
                }
                Text(title).font(.s26).foregroundStyle(Color.inkText).lineLimit(titleLines).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            CloseButton(action: close, help: closeHelp)
        }
    }
}

/// The one way to close a panel: a small square button with a cross (Esc does the same).
struct CloseButton: View {
    let action: () -> Void
    var help = "Close (Esc)"
    var body: some View {
        Button(action: action) { PixelIcon("close", color: .inkText) }
            .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: true))
            .help(help).accessibilityLabel("Close")
    }
}

/// A portrait from the cast in its socket, rimmed in its role's colour.
struct Portrait: View {
    let image: CGImage?
    let role: CastRole
    var size: CGFloat = 56
    var body: some View {
        let c = Color.role(role), shape = RoundedRectangle(cornerRadius: 10)
        ZStack(alignment: .bottom) {
            RadialGradient(colors: [c.opacity(0.4), Color.surface], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: size * 0.75)
            if let image { Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit().padding(.top, size * 0.08) }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(c.opacity(0.7), lineWidth: 2))
        .accessibilityHidden(true)
    }
}

/// A row of a settings or inspector card: a title and one line under it on the left, the control on the right.
struct FieldRow<Control: View>: View {
    let title: String
    var text: String? = nil
    var disabled = false
    @ViewBuilder var control: () -> Control
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // a row that cannot be used yet is dimmed, its line saying why
                Text(title).font(.s15).foregroundStyle(disabled ? Color.muted : Color.inkText)
                if let text, !text.isEmpty { Text(text).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            control().opacity(disabled ? 0.45 : 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// Hairline between the rows of one card.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.divider).frame(height: 2) }
}

/// A group of rows in one card, its name above it.
struct RowCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionHead(title, icon: icon) }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .spelCard(pad: 0)
        }
    }
}
