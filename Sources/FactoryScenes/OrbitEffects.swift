import SpriteKit
import simd

/// The Engine room's black hole on the GPU (D26): the same picture as orbit-gen.js holeSprite (shadow, photon ring, the
/// near and far disk, both lensed arcs, beaming and the soft glow), but per frame, so the disk can turn and it stays sharp
/// at any zoom. The disk's streaks come from the generator as a table (phase across, radius down), the node's texture.
/// The quad is 9.4 × 5.8 shadow radii round the hole, like the sprite.
@MainActor
final class HoleShading {
    static let quad = CGSize(width: 9.4, height: 5.8)

    let shader: SKShader
    private let spin = SKUniform(name: "u_spin", float: 0)
    private let k = SKUniform(name: "u_k", float: 1)
    private let pa = SKUniform(name: "u_pa", vectorFloat2: vector_float2(1, 0))
    private let geo = SKUniform(name: "u_geo", vectorFloat4: vector_float4(0.2, 1.5, 3.5, 30))
    private let fx = SKUniform(name: "u_fx", vectorFloat2: vector_float2(1, 1))

    /// pa in degrees, sy the disk's squash, inner and outer its edges in shadow radii (all from the generator's look).
    init(pa deg: CGFloat, sy: CGFloat, inner: CGFloat, outer: CGFloat) {
        shader = SKShader(source: Self.source)
        shader.uniforms = [spin, k, pa, geo, fx]
        let a = Float(deg * .pi / 180)
        pa.vectorFloat2Value = vector_float2(cos(a), sin(a))
        geo.vectorFloat4Value = vector_float4(Float(sy), Float(inner), Float(outer), 30)
    }

    /// spin: the disk's phase (radians, decreasing turns it the way the beaming says); k: how bright (0.6 + 0.4 × activity);
    /// rp: the shadow radius in device pixels; ring and glow: slow breathing multipliers near 1.
    func set(spin s: CGFloat, k kk: CGFloat, rp: CGFloat, ring: CGFloat, glow: CGFloat) {
        spin.floatValue = Float(s); k.floatValue = Float(kk)
        var g = geo.vectorFloat4Value; g.w = Float(max(1, rp)); geo.vectorFloat4Value = g
        fx.vectorFloat2Value = vector_float2(Float(ring), Float(glow))
    }

    static let source = """
    float hss(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
    vec3 hramp(float T) {
        if (T <= 0.0) return vec3(0.0);
        if (T <= 0.08) return mix(vec3(0.0), vec3(22.0, 16.0, 38.0) / 255.0, T / 0.08);
        if (T <= 0.18) return mix(vec3(22.0, 16.0, 38.0), vec3(52.0, 44.0, 82.0), (T - 0.08) / 0.10) / 255.0;
        if (T <= 0.38) return mix(vec3(52.0, 44.0, 82.0), vec3(110.0, 99.0, 152.0), (T - 0.18) / 0.20) / 255.0;
        if (T <= 0.66) return mix(vec3(110.0, 99.0, 152.0), vec3(180.0, 171.0, 208.0), (T - 0.38) / 0.28) / 255.0;
        if (T <= 0.95) return mix(vec3(180.0, 171.0, 208.0), vec3(232.0, 226.0, 246.0), (T - 0.66) / 0.29) / 255.0;
        if (T <= 1.5) return mix(vec3(232.0, 226.0, 246.0), vec3(255.0, 252.0, 255.0), (T - 0.95) / 0.55) / 255.0;
        return vec3(255.0, 252.0, 255.0) / 255.0;
    }
    void main() {
        // (uniforms are only visible in main in SpriteKit's Metal translation, so the disk lookup lives here)
        float sy = u_geo.x, inner = u_geo.y, outer = u_geo.z, rp = u_geo.w, span = outer - inner;
        float cp = u_pa.x, sp = u_pa.y;
        float ringW = max(0.011, 0.75 / rp);
        vec2 uv = v_tex_coord;
        vec3 acc = vec3(0.0); float aacc = 0.0;
        for (int n = 0; n < 4; n++) {
            float ox = (float(n - (n / 2) * 2) - 0.5) * 0.5 / rp, oy = (float(n / 2) - 0.5) * 0.5 / rp;
            float X0 = (uv.x - 0.5) * 9.4 + ox, Y0 = (0.5 - uv.y) * 5.8 + oy;
            float x = X0 * cp + Y0 * sp, y = -X0 * sp + Y0 * cp, r = length(vec2(x, y));
            if (r > 1.95 && length(vec2(x, y / sy)) >= outer) continue;
            // up to three looks at the disk: straight on (far half behind the shadow, near half in front), and one lensed arc
            float Dy = y / sy, rho = length(vec2(x, Dy)), ph = atan(Dy, x);
            float r0 = -1.0, p0 = 0.0, w0 = 0.0, r1 = -1.0, p1 = 0.0, w1 = 0.0;
            bool front = Dy >= 0.0;
            if (rho > inner && rho < outer) {
                if (!front) { if (r > 1.0) { r0 = rho; p0 = ph; w0 = 1.0; } }
                else { r0 = rho; p0 = ph; w0 = 1.0 + 0.25 * hss(0.0, 0.5, Dy / rho); }
            }
            if (r > 1.0) {
                float ang = atan(y, x);
                if (y < 0.0) { float w = hss(0.02, 0.38, -y / r), rl = inner + (r - 1.06) / (span * 0.34) * span; if (w > 0.0 && rl > inner && rl < outer) { r1 = rl; p1 = ang; w1 = w * 0.95; } }
                else { float w = hss(0.12, 0.55, y / r), rl = inner + (r - 1.03) / (span * 0.1) * span; if (w > 0.0 && rl > inner && rl < outer) { r1 = rl; p1 = -ang; w1 = w * 0.5; } }
            }
            // the gap inside the disk, beside the shadow: the disk's inner edge fades into it softly, down to dark at the
            // shadow's edge, so no hard black band sticks out of the shadow
            float gapK = 0.0;
            if (r0 < 0.0 && r > 1.0 && rho > 1.0 && rho <= inner) {
                gapK = pow(hss(1.0, inner, rho), 1.6) * hss(1.0, 1.18, r);
                if (gapK > 0.0) { r0 = inner + 0.0001; p0 = ph; w0 = gapK; }
            }
            float T = 0.0, Tf = 0.0;
            for (int e = 0; e < 2; e++) {
                float dr0 = e == 0 ? r0 : r1, dp = e == 0 ? p0 : p1, dw = e == 0 ? w0 : w1;
                float u = (dr0 - inner) / span;
                if (dw <= 0.0 || u <= 0.0 || u >= 1.0) continue;
                // the direct view's inner edge is soft only where it passes over the shadow; beside it the gap carries on
                float edge = e == 0 ? max(hss(0.0, 0.035, u), hss(1.0, 1.18, r)) : hss(0.0, 0.035, u);
                float prof = edge * pow(inner / dr0, 2.3) * (1.0 - hss(0.5, 1.0, u));
                float pp = fract((dp - u_spin * pow(inner / dr0, 1.5)) / 6.28318530718);
                float gv = texture2D(u_texture, vec2((pp * 640.0 + 0.5) / 640.0, 1.0 - (u * 79.0 + 0.5) / 80.0)).r * 1.2;
                float beam = pow(1.0 - 0.42 * cos(dp), 2.1) / 1.35;
                float v = prof * beam * (0.35 + 0.95 * gv) * u_k * dw;
                if (e == 0 && front) Tf += v; else T += v;
            }
            float dr = (r - 1.012) / ringW;
            float pr = exp(-dr * dr) * (0.62 + 0.38 * (-x / max(r, 0.000001))) * 0.95 * u_k * u_fx.x;
            float shadow = clamp((1.0 - r) * rp * 2.0 + 0.5, 0.0, 1.0);
            vec3 c = hramp(T);
            float a = clamp(max(c.r, max(c.g, c.b)) * 1.2, 0.0, 1.0);
            vec3 q = c * (1.0 - shadow);
            a = shadow + a * (1.0 - shadow);
            q += hramp(Tf) + hramp(pr * 1.15);
            a = max(a, clamp(max(q.r, max(q.g, q.b)) * 1.2, 0.0, 1.0));
            acc += q; aacc += a;
        }
        float A = aacc / 4.0;
        vec3 col = min(acc / 4.0, vec3(A));
        // the glow under it all: the disk's light scattered in the gas, flattened along the disk
        float X = (v_tex_coord.x - 0.5) * 9.4, Y = (0.5 - v_tex_coord.y) * 5.8;
        float gx = X * cp + Y * sp, gy = (-X * sp + Y * cp) / 0.58, gt = clamp((length(vec2(gx, gy)) - 0.8) / 3.8, 0.0, 1.0);
        float ga = (gt < 0.35 ? mix(0.2, 0.07, gt / 0.35) : mix(0.07, 0.0, (gt - 0.35) / 0.65)) * u_k * u_fx.y;
        vec3 gc = vec3(143.0, 128.0, 196.0) / 255.0 * ga;
        gl_FragColor = vec4(col + gc * (1.0 - A), A + ga * (1.0 - A));
    }
    """
}

extension SKView {
    /// Whether SpriteKit is drawing frames right now: not paused, its window on screen and that screen's display awake.
    /// A sleeping display or a hidden window runs no display link, so a scene's update, its SKActions and a transition
    /// would wait until it wakes; whatever must finish now (a flight, a hover, a scene change) should then happen at once.
    /// Only a first guess: frames were seen to stop with this still true, so what must finish also needs a watchdog.
    var drawsFrames: Bool {
        guard !isPaused, let w = window, w.isVisible else { return false }
        #if os(macOS)
        guard w.occlusionState.contains(.visible) else { return false }
        let id = (w.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        return CGDisplayIsAsleep(id) == 0
        #else
        return true
        #endif
    }
}
