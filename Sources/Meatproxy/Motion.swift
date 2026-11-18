import SwiftUI

/// Motion in the HUD (D9: it must feel like a game; tactile-utility: motion confirms what happened). The start-up's
/// timed steps are a deliberate brand moment (the owner's choice); everything else follows real state. Everything
/// stands still when the Mac asks for reduced motion.
enum Motion {
    /// press in, and spring back (the Tuinstra button curve)
    static let pressIn = Animation.easeOut(duration: 0.07)
    static let springBack = Animation.timingCurve(0.2, 1.35, 0.4, 1, duration: 0.18)
    /// things that arrive: a short spring that settles without a wobble
    static let arrive = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// a selection moving between places
    static let slide = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

// MARK: the mark, assembling and stamping

/// The ✓ building itself pixel by pixel in a diagonal sweep, then pressing itself down onto its ledge like a stamp,
/// again and again while `stamping` (the loading screen: the app is busy approving).
struct AnimatedMark: View {
    var stamping: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var scale
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = reduceMotion ? 10 : tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                // the brand mark's geometry: whole device-pixel cells, the grid on a device pixel, centred
                let u = max(1, floor(min(size.width, size.height) * scale / 16)) / scale
                let ox = (((size.width - 16 * u) / 2) * scale).rounded() / scale, oy = (((size.height - 16 * u) / 2) * scale).rounded() / scale
                // assemble: each cell pops in on a diagonal from bottom-left to top-right (≈ 0.75 s in all)
                func appear(_ x: Int, _ y: Int) -> CGFloat {
                    let delay = Double(x + (15 - y)) * 0.028
                    return CGFloat(min(1, max(0, (t - delay) / 0.16)))
                }
                let assembled = t > 0.95
                // the stamp: every 1.6 s after assembling, the face presses down onto the ledge by exactly one cell
                var down = false
                if stamping && assembled {
                    let phase = (t - 0.95).truncatingRemainder(dividingBy: 1.6)
                    down = phase < 0.22
                }
                let face = Set(Brand.checkCells.map { "\($0.0),\($0.1)" })
                let ledge = Brand.checkCells.map { ($0.0, $0.1 + 1) }.filter { !face.contains("\($0.0),\($0.1)") }
                if assembled && !down {
                    for (x, y) in ledge { ctx.fill(Path(CGRect(x: ox + CGFloat(x) * u, y: oy + CGFloat(y) * u, width: u, height: u)), with: .color(.ledge)) }
                }
                for (x, y) in Brand.checkCells {
                    let a = appear(x, y)
                    guard a > 0 else { continue }
                    // a cell grows from its centre in whole device pixels while it appears, then sits exactly on the grid
                    let side = a >= 1 ? u : max(1 / scale, ((u * (0.55 + 0.45 * a)) * scale).rounded() / scale)
                    let cx = ox + (CGFloat(x) + 0.5) * u, cy = oy + (CGFloat(y) + 0.5) * u + (down ? u : 0)
                    let r = CGRect(x: ((cx - side / 2) * scale).rounded() / scale, y: ((cy - side / 2) * scale).rounded() / scale, width: side, height: side)
                    ctx.opacity = Double(a)
                    ctx.fill(Path(r), with: .color(.signal))
                    ctx.opacity = 1
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: the loading screen

/// The whole window while the factory starts: the mark assembles and keeps stamping, TUINSTRA slides in on its tab, the
/// name rises, then the line, and under it the factory's start-up list, one step after another, each stamped with a ✓
/// when it is done. The start-up takes a few seconds on purpose (it should feel like a factory starting, not a window
/// opening); its last step is the real one, the campus being built, and is stamped only when that is really done.
struct LoadingScreen: View {
    /// what the app is really doing; nil once it is done
    let status: String?
    var lockup: Namespace.ID
    /// called once the start-up is over: the last step stamped and a moment to take it in
    var onDone: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var start = Date()
    /// when the real work (the campus) was stamped done, in seconds since the start
    @State private var realDone: TimeInterval?
    /// the real work is done (kept in state: the start-up's clock reads it fresh, a captured `status` would go stale)
    @State private var workDone = false
    private let size: CGFloat = 72

    /// the start-up list: the first steps pace the start-up, the last is the real work
    static let steps = ["Powering the floor", "Waking the CEO agent", "Seating the team", "Locating the human"]
    /// after the real work, the factory's last step: it is stamped, then the screen holds a moment before the world opens
    static let finalStep = "Handing you the rubber stamp"
    /// when each paced step begins; the real step (the campus) is stamped no earlier than its own beat
    static func stepStart(_ k: Int) -> TimeInterval { 1.0 + Double(k) * 0.55 }
    static let finalDelay: TimeInterval = 0.2, finalStamp: TimeInterval = 0.75, hold: TimeInterval = 0.9

    var body: some View {
        let mark = (size * 1.5 / 16).rounded(.down) * 16, cell = mark / 16, gap = size * 0.34
        ZStack {
            Color.ink.ignoresSafeArea()
            VStack(alignment: .leading, spacing: size * 0.22) {
                HStack(alignment: .center, spacing: gap - cell) {
                    AnimatedMark(stamping: true).frame(width: mark, height: mark).padding(.leading, -cell)
                    VStack(alignment: .leading, spacing: size * 0.1) {
                        let tab = max(9, size * 0.62 * 0.22)
                        InterText(text: "TUINSTRA", size: tab, weight: 800, tracking: tab * 0.3, color: .onSignal)
                            .padding(.leading, tab * 0.55).padding(.trailing, tab * 0.25).padding(.vertical, tab * 0.28)
                            .background(Color.signal, in: RoundedRectangle(cornerRadius: 4))
                            .mask(alignment: .leading) { Rectangle().frame(width: shown ? nil : 0).frame(maxWidth: .infinity, alignment: .leading) }
                            .offset(x: shown ? 0 : -12)
                            .animation(reduceMotion ? nil : Motion.arrive.delay(0.55), value: shown)
                        InterText(text: Brand.shortName, size: size * 0.62, weight: 900, tracking: -size * 0.62 * 0.05)
                            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                            .animation(reduceMotion ? nil : Motion.arrive.delay(0.7), value: shown)
                    }
                }
                .matchedGeometryEffect(id: "lockup", in: lockup, anchor: .topLeading)
                VStack(alignment: .leading, spacing: 16) {
                    Brand.productLineText().font(.system(size: max(12, size * 0.25), weight: .semibold))
                        .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
                        .animation(reduceMotion ? nil : Motion.arrive.delay(0.95), value: shown)
                    StartupList(status: status, start: start, realDone: realDone)
                }
                .padding(.leading, mark - cell + gap - cell)
            }
        }
        .onAppear { shown = true; start = Date() }
        .onChange(of: status == nil, initial: true) { _, done in workDone = done }
        .task {
            // the start-up's clock: the real step is stamped when the work is done and its beat has come; then the final
            // step, its stamp, a hold, and done
            let realBeat = Self.stepStart(Self.steps.count + 1)
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start)
                if realDone == nil, workDone, t >= realBeat { realDone = t }
                if let r = realDone, t >= r + Self.finalDelay + Self.finalStamp + Self.hold { onDone(); return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

/// The factory's start-up list: each step appears, works (a blinking caret), and is stamped with a ✓ when the next one
/// starts; the last step is the real status and is stamped when the work is done.
private struct StartupList: View {
    let status: String?
    let start: Date
    let realDone: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { tl in
            let t = tl.date.timeIntervalSince(start)
            let real = LoadingScreen.steps.count
            let steps = LoadingScreen.steps + [(status ?? "Building the campus…").replacingOccurrences(of: "…", with: ""), LoadingScreen.finalStep]
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { k, step in
                    let begun = t >= begins(k, real: real)
                    let done = stamped(k, real: real, at: t)
                    if begun {
                        // each line eases in on the start-up's own clock (no separate transition to cross it)
                        let a = reduceMotion ? 1 : min(1, (t - begins(k, real: real)) / 0.25)
                        HStack(spacing: 10) {
                            ZStack {
                                if done { TickStamp() }
                                else {
                                    Rectangle().fill(Color.signal).frame(width: 7, height: 12)
                                        .opacity(reduceMotion || Int(t / 0.4) % 2 == 0 ? 1 : 0.15)
                                }
                            }
                            .frame(width: 16, height: 16)
                            Text(done ? step : step + "…").font(.system(size: 13))
                                .foregroundStyle(done && k < steps.count - 1 ? Color.muted : Color.inkText)
                        }
                        .opacity(a).offset(y: (1 - a) * 6)
                    }
                }
            }
            // the list's full height from the start, so the lockup above it never moves
            .frame(height: CGFloat(LoadingScreen.steps.count + 2) * 23 - 7, alignment: .top)
        }
    }

    /// when step k begins: the paced steps on their beat, the final step just after the real one is stamped
    private func begins(_ k: Int, real: Int) -> TimeInterval {
        k <= real ? LoadingScreen.stepStart(k) : (realDone.map { $0 + LoadingScreen.finalDelay } ?? .infinity)
    }
    /// whether step k is stamped at time t
    private func stamped(_ k: Int, real: Int, at t: TimeInterval) -> Bool {
        k < real ? t >= LoadingScreen.stepStart(k + 1) : k == real ? realDone != nil : t >= begins(k, real: real) + LoadingScreen.finalStamp
    }
}

// MARK: arriving

/// A HUD part arriving from its own edge, a little after the one before it (`order`), when `shown` turns true.
struct Arrive: ViewModifier {
    var shown: Bool
    var edge: Edge
    var order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let d: CGFloat = shown ? 0 : 28
        content
            .opacity(shown ? 1 : 0)
            .offset(x: edge == .leading ? -d : edge == .trailing ? d : 0, y: edge == .top ? -d : edge == .bottom ? d : 0)
            .animation(reduceMotion ? nil : Motion.arrive.delay(0.06 * Double(order)), value: shown)
    }
}

extension View {
    func arrive(_ shown: Bool, from edge: Edge, order: Int) -> some View { modifier(Arrive(shown: shown, edge: edge, order: order)) }
}

// MARK: the stamp

/// The answer landing on the card: the ✓ (or a cross for no) slams down from large and tilted, with a little dust ring.
struct AnswerStamp: View {
    let yes: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    var body: some View {
        ZStack {
            Circle().stroke(yes ? Color.done : Color.border, lineWidth: 2)
                .scaleEffect(landed ? 1.6 : 0.6).opacity(landed ? 0 : 0.8)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.12), value: landed)
            Group {
                if yes { PixelIcon("check", color: .done, size: 36) } else {   // answered is done: green, not the yellow of what waits
                    PixelIcon("close", color: .inkText, size: 36)
                }
            }
            // tilted only in flight; it lands square, so the pixels stay crisp and the ledge straight below
            .scaleEffect(landed ? 1 : 1.9).rotationEffect(.degrees(landed ? 0 : -14)).opacity(landed ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: landed)
        }
        .frame(width: 46, height: 46)
        .onAppear { landed = true }
    }
}

/// A step stamped done in the start-up list: the 16 pt brand mark (2 px cells) dropping onto its line.
private struct TickStamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    var body: some View {
        BrandMark().frame(width: 16, height: 16)
            .scaleEffect(landed ? 1 : 1.8).opacity(landed ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6), value: landed)
            .onAppear { landed = true }
    }
}
