/* The Orbit generator, in the Starfield style (D18, D42): a stable id always makes the same body, like
   BlockyCast.person makes the same person. Galaxy = provider, solar system / star = project, planet = session,
   moon = sub-agent (D6), plus the Engine room's black hole (D26) and the wormhole of a project at two providers (D16).

   The look follows the prototype's Starfield skin and the game it is named after: minimal and clinical, grounded in
   reality. Stars, planets and moons are lit spheres with procedural textures, rendered per pixel on a canvas, in
   muted colours; the night side is nearly black; the sun is white-hot with a soft bloom and a thin lens streak;
   orbits are hairlines in one gently tilted plane over a faint survey grid; labels are monospace caps tags.

   A plain script (no imports). Browser only for the bodies (they need a canvas):
     OrbitGen.planet(sessionId, {state, role, kind}) · moon(subAgentId, {type, finished, depth}) · star(projectId, {state, activity})
       → a look with .paint(ctx, x, y, r, o), .sprite(r, o) → {canvas, w, h} and .svg(r, o) → an <image> plus its marker
     OrbitGen.galaxy · blackHole · infra · wormhole → the same, rendered per pixel too
     OrbitGen.paintSystem(ctx, sys, o) → one solar system: survey grid, orbits, sun, planets, moons and tags
     OrbitGen.mark(ctx, x, y, r, state, o) / markSVG(state, r, o) → the state marker on its own
   r is the base radius in CSS px; the look's own scale multiplies it (gas giants are bigger than rocks).
   o: {state: working|waiting|stuck|done, light: angle toward the light (radians), spin, selected, t (ms), dpr, mark}
   State reads over any look as a hairline hexagon round the body: dashed yellow #FFD83D = waits for you,
   red #ff4a4a = stuck, cyan = selected; a done body dims. */
(function () {
  const TAU = Math.PI * 2;
  const WAIT = "#FFD83D", STUCK = "#ff4a4a", NIGHT = "#06050f", INK = "#0b0816", CYAN = "#4fe0f5";
  const f = v => (+v).toFixed(2);
  const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const toHex = c => "#" + c.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")).join("");
  const mix = (a, b, t) => { const A = hex(a), B = hex(b); return toHex(A.map((v, i) => v + (B[i] - v) * t)); };
  const shade = (h, k) => toHex(hex(h).map(v => v * k));
  const tint = (h, k) => mix(h, "#ffffff", k);
  const dim = h => { const c = hex(h), l = .3 * c[0] + .59 * c[1] + .11 * c[2]; return toHex([0, 1, 2].map(i => (l * .42 + 30 + (i === 2 ? 10 : 0)) * .9 + c[i] * .08)); };

  /* the same hashed RNG as the blocky cast */
  const rnd = seed => { let x = 2166136261; for (const c of String(seed)) x = Math.imul(x ^ c.charCodeAt(0), 16777619); return () => ((x = Math.imul(x ^ (x >>> 15), 2246822507) ^ Math.imul(x ^ (x >>> 13), 3266489909)) >>> 0) / 4294967296; };
  const pick = (r, a) => a[Math.floor(r() * a.length)];
  const pickW = (r, w) => { const e = Object.entries(w), t = e.reduce((s, x) => s + x[1], 0); let u = r() * t; for (const [k, v] of e) if ((u -= v) < 0) return k; return e[0][0]; };
  const between = (r, a, b) => a + (b - a) * r();
  const count = (r, a, b) => a + Math.floor(r() * (b - a + 1));
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));

  /* ---------- noise: value noise on the sphere, so textures have no seam ---------- */
  function hash3(i, j, k, s) { let h = (i * 374761393 + j * 668265263 + k * 1274126177 + s * 982451653) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); return ((h ^ (h >>> 16)) >>> 0) / 4294967295; }
  function vnoise(x, y, z, s) {
    const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z), xf = x - xi, yf = y - yi, zf = z - zi;
    const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf), w = zf * zf * (3 - 2 * zf);
    const c000 = hash3(xi, yi, zi, s), c100 = hash3(xi + 1, yi, zi, s), c010 = hash3(xi, yi + 1, zi, s), c110 = hash3(xi + 1, yi + 1, zi, s);
    const c001 = hash3(xi, yi, zi + 1, s), c101 = hash3(xi + 1, yi, zi + 1, s), c011 = hash3(xi, yi + 1, zi + 1, s), c111 = hash3(xi + 1, yi + 1, zi + 1, s);
    const a = c000 + (c100 - c000) * u, b = c010 + (c110 - c010) * u, c = c001 + (c101 - c001) * u, d = c011 + (c111 - c011) * u;
    const e = a + (b - a) * v, g = c + (d - c) * v;
    return e + (g - e) * w;
  }
  function fbm(x, y, z, s, oct = 5) { let a = .5, fr = 1, t = 0, n = 0; for (let o = 0; o < oct; o++) { t += a * vnoise(x * fr, y * fr, z * fr, s + o * 17); n += a; a *= .5; fr *= 2.03; } return t / n; }
  const C3 = h => hex(h);
  const M3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  const SS = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t); };

  /* ---------- textures: an equirectangular map of colour, emission and cloud, made once per body ---------- */
  const TEX = new Map();
  function texture(key, res, fn) {
    const k = key + "@" + res;
    if (TEX.has(k)) return TEX.get(k);
    const tw = 192 * res, th = 96 * res, col = new Float32Array(tw * th * 3), emi = new Float32Array(tw * th), cld = new Float32Array(tw * th);
    for (let y = 0; y < th; y++) {
      const lat = (y / (th - 1) - .5) * Math.PI, cl = Math.cos(lat), py = Math.sin(lat);
      for (let x = 0; x < tw; x++) {
        const lon = x / tw * TAU, px = cl * Math.cos(lon), pz = cl * Math.sin(lon), i = y * tw + x;
        const [c, e = 0, cd = 0] = fn(px, py, pz);
        col[i * 3] = c[0]; col[i * 3 + 1] = c[1]; col[i * 3 + 2] = c[2]; emi[i] = e; cld[i] = clamp(cd);
      }
    }
    const t = {col, emi, cld, tw, th};
    TEX.set(k, t);
    return t;
  }

  /* ---------- the sphere: per pixel, lit by one light; the night side nearly black, a thin atmosphere on the rim ---------- */
  const hasDOM = typeof document !== "undefined";
  const newCanvas = (w, h) => { const c = document.createElement("canvas"); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; };
  const lightVec = (a, up = .55) => { const v = [Math.cos(a), Math.sin(a), up], n = Math.hypot(...v); return v.map(x => x / n); };
  // o: {L, spin, cspin, tilt, atm:[r,g,b], atmK, dim, emissive, limb, emiCol:[r,g,b]}
  function sphereCanvas(rp, tex, o) {
    const D = Math.ceil(rp * 2) + 2, c = newCanvas(D, D), x = c.getContext("2d"), img = x.createImageData(D, D), d = img.data;
    const [lx, ly, lz] = o.L || lightVec(-2.25), ct = Math.cos(o.tilt || 0), st = Math.sin(o.tilt || 0), spin = o.spin || 0, cspin = o.cspin ?? spin * 1.4;
    const atm = o.atm || [150, 165, 180], atmK = o.atmK ?? 1, dm = o.dim ?? 1, emCol = o.emiCol || [255, 120, 30], limb = o.limb ?? .32;
    const {col, emi, cld, tw, th} = tex, smooth = rp > 20;
    for (let py = 0; py < D; py++) for (let px = 0; px < D; px++) {
      const k = py * D + px, dx = (px + .5 - D / 2) / rp, dy = (py + .5 - D / 2) / rp, r2 = dx * dx + dy * dy;
      const al = clamp(rp * (1 - Math.sqrt(r2)) + .5);
      if (al <= 0) continue;
      const z = Math.sqrt(Math.max(0, 1 - r2));
      const tx = dx * ct - dy * st, ty = dx * st + dy * ct;
      let u = (Math.atan2(tx, z) + spin) / TAU; u -= Math.floor(u);
      const vf = clamp((Math.asin(clamp(ty, -1, 1)) / Math.PI + .5) * (th - 1), 0, th - 1);
      let r, g, b, e;
      if (smooth) {
        const fx = u * tw - .5, x0 = Math.floor(fx), fu = fx - x0, xa = ((x0 % tw) + tw) % tw, xb = (xa + 1) % tw;
        const y0 = Math.floor(vf), fv = vf - y0, ya = y0 * tw, yb = Math.min(th - 1, y0 + 1) * tw;
        const w00 = (1 - fu) * (1 - fv), w10 = fu * (1 - fv), w01 = (1 - fu) * fv, w11 = fu * fv, i00 = (ya + xa) * 3, i10 = (ya + xb) * 3, i01 = (yb + xa) * 3, i11 = (yb + xb) * 3;
        r = col[i00] * w00 + col[i10] * w10 + col[i01] * w01 + col[i11] * w11;
        g = col[i00 + 1] * w00 + col[i10 + 1] * w10 + col[i01 + 1] * w01 + col[i11 + 1] * w11;
        b = col[i00 + 2] * w00 + col[i10 + 2] * w10 + col[i01 + 2] * w01 + col[i11 + 2] * w11;
        e = emi[ya + xa] * w00 + emi[ya + xb] * w10 + emi[yb + xa] * w01 + emi[yb + xb] * w11;
      } else { const ti = Math.round(vf) * tw + Math.floor(u * tw) % tw; r = col[ti * 3]; g = col[ti * 3 + 1]; b = col[ti * 3 + 2]; e = emi[ti]; }
      if (o.emissive) {
        // a star: limb darkening, no night side
        const lm = limb + (1 - limb) * Math.pow(z, .45);
        d[k * 4] = Math.min(255, r * lm); d[k * 4 + 1] = Math.min(255, g * lm); d[k * 4 + 2] = Math.min(255, b * lm); d[k * 4 + 3] = 255 * al;
        continue;
      }
      const nd = dx * lx + dy * ly + z * lz, diff = Math.max(0, nd);
      // a soft terminator, then near-black: the light of one sun
      const lit = (.035 + 1.0 * Math.pow(SS(-.06, .5, nd) * .35 + diff * .65, .85)) * dm;
      r *= lit; g *= lit; b *= lit;
      let cu = (Math.atan2(tx, z) + cspin) / TAU; cu -= Math.floor(cu);
      const cv = cld[Math.round(vf) * tw + Math.floor(cu * tw) % tw];
      if (cv) { const cl = cv * (.04 + .95 * Math.pow(diff, .7)) * dm; r += (245 - r) * cl * .92; g += (245 - g) * cl * .92; b += (242 - b) * cl * .92; }
      if (e) { const ee = e * (.55 + .45 * (1 - diff)); r += emCol[0] * ee; g += emCol[1] * ee; b += emCol[2] * ee; }
      // the atmosphere: a thin bright rim on the lit side
      const rim = Math.pow(1 - z, 3.2) * (.15 + .95 * Math.max(0, nd + .25)) * .6 * atmK;
      r += atm[0] * rim; g += atm[1] * rim; b += atm[2] * rim;
      d[k * 4] = r > 255 ? 255 : r; d[k * 4 + 1] = g > 255 ? 255 : g; d[k * 4 + 2] = b > 255 ? 255 : b; d[k * 4 + 3] = 255 * al;
    }
    x.putImageData(img, 0, 0);
    return c;
  }

  /* ---------- state: a hairline hexagon round the body, as on a survey map ---------- */
  const hexPts = (x, y, r) => Array.from({length: 6}, (_, i) => { const a = Math.PI / 6 + i * Math.PI / 3; return [x + r * Math.cos(a), y + r * Math.sin(a)]; });
  function mark(ctx, x, y, r, st, o = {}) {
    const t = o.t ?? (typeof performance !== "undefined" ? performance.now() : 0), lw = o.lw || 1, sel = o.selected;
    if (st !== "waiting" && st !== "stuck" && !sel) return;
    const path = rr => { ctx.beginPath(); hexPts(x, y, rr).forEach(([px, py], i) => i ? ctx.lineTo(px, py) : ctx.moveTo(px, py)); ctx.closePath(); };
    ctx.save(); ctx.lineWidth = lw;
    if (st === "waiting") {
      const a = o.still ? .85 : .55 + .35 * Math.sin(t / 900);
      ctx.strokeStyle = `rgba(255,210,63,${a.toFixed(2)})`; ctx.setLineDash([4 * lw, 3 * lw]); path(r); ctx.stroke(); ctx.setLineDash([]);
      ctx.strokeStyle = "rgba(255,210,63,.22)"; path(r + 4 * lw); ctx.stroke();
    } else if (st === "stuck") {
      const a = o.still ? .9 : .55 + .35 * Math.sin(t / 500);
      ctx.strokeStyle = `rgba(255,74,74,${a.toFixed(2)})`; path(r); ctx.stroke();
      ctx.strokeStyle = "rgba(255,74,74,.3)"; path(r + 4 * lw); ctx.stroke();
      // a small caps flag on the upper right corner
      const [fx, fy] = hexPts(x, y, r)[5]; ctx.fillStyle = "#ff4a4a"; ctx.fillRect(fx + 2 * lw, fy - 9 * lw, 9 * lw, 9 * lw);
      ctx.fillStyle = "#1a0606"; ctx.fillRect(fx + 5.9 * lw, fy - 7.6 * lw, 1.4 * lw, 4 * lw); ctx.fillRect(fx + 5.9 * lw, fy - 2.6 * lw, 1.4 * lw, 1.3 * lw);
    }
    if (sel) { ctx.shadowColor = CYAN; ctx.shadowBlur = 8; ctx.strokeStyle = CYAN; path(r + (st === "waiting" || st === "stuck" ? 8 * lw : 0)); ctx.stroke(); }
    ctx.restore();
  }
  function markSVG(st, r, o = {}) {
    if (st !== "waiting" && st !== "stuck" && !o.selected) return "";
    const lw = o.lw || 1, P = rr => hexPts(0, 0, rr).map(p => f(p[0]) + "," + f(p[1])).join(" ");
    let s = "";
    if (st === "waiting") s += `<polygon points="${P(r)}" fill="none" stroke="${WAIT}" stroke-width="${lw}" stroke-dasharray="${4 * lw} ${3 * lw}" opacity=".85">${o.animate ? `<animate attributeName="opacity" values=".9;.35;.9" dur="1.8s" repeatCount="indefinite"/>` : ""}</polygon><polygon points="${P(r + 4 * lw)}" fill="none" stroke="${WAIT}" stroke-width="${lw}" opacity=".22"/>`;
    if (st === "stuck") { const [fx, fy] = hexPts(0, 0, r)[5]; s += `<polygon points="${P(r)}" fill="none" stroke="${STUCK}" stroke-width="${lw}" opacity=".9">${o.animate ? `<animate attributeName="opacity" values=".95;.45;.95" dur="1s" repeatCount="indefinite"/>` : ""}</polygon><polygon points="${P(r + 4 * lw)}" fill="none" stroke="${STUCK}" stroke-width="${lw}" opacity=".3"/><rect x="${f(fx + 2 * lw)}" y="${f(fy - 9 * lw)}" width="${9 * lw}" height="${9 * lw}" fill="${STUCK}"/><rect x="${f(fx + 5.9 * lw)}" y="${f(fy - 7.6 * lw)}" width="${f(1.4 * lw)}" height="${4 * lw}" fill="#1a0606"/><rect x="${f(fx + 5.9 * lw)}" y="${f(fy - 2.6 * lw)}" width="${f(1.4 * lw)}" height="${f(1.3 * lw)}" fill="#1a0606"/>`; }
    if (o.selected) s += `<polygon points="${P(r + (st === "waiting" || st === "stuck" ? 8 * lw : 0))}" fill="none" stroke="${CYAN}" stroke-width="${lw}"/>`;
    return s;
  }

  /* ---------- sprites: a body drawn once per size, light and spin, then reused ---------- */
  const SPR = new Map();
  // kept by count and by pixels (a body that spins is a new sprite per step and light), the least recently used going first
  let SPR_PX = 0;
  const SPR_MAX_PX = 40e6;
  function sprite(key, w, h, draw) {
    if (SPR.has(key)) { const s = SPR.get(key); SPR.delete(key); SPR.set(key, s); return s; }
    const c = newCanvas(w, h); draw(c.getContext("2d"));
    const s = {canvas: c, w: c.width, h: c.height, url: null};
    SPR_PX += s.w * s.h;
    while (SPR.size && (SPR.size > 900 || SPR_PX > SPR_MAX_PX)) { const k = SPR.keys().next().value; SPR_PX -= SPR.get(k).w * SPR.get(k).h; SPR.delete(k); }
    SPR.set(key, s);
    return s;
  }
  const q = (v, step) => Math.round(v / step) * step;
  const bucketR = px => Math.pow(2, Math.ceil(Math.log2(Math.max(1.5, px)) * 3) / 3);
  let uid = 0;

  /* ---------- planets: six landscapes in muted, realistic palettes; the session's role leans the landscape ---------- */
  const PAL = {
    rocky: [
      {name: "dust", a: "#cdab80", b: "#a7835c", c: "#6e5640", d: "#e0caa8", atm: [215, 185, 145], banded: true},
      {name: "basalt", a: "#9b958c", b: "#55514c", c: "#2f2d2a", d: "#c4beb3", atm: [150, 150, 150]},
      {name: "rust", a: "#b07656", b: "#7c4c38", c: "#4c3226", d: "#d0a688", atm: [205, 150, 120], banded: true},
      {name: "ash", a: "#8d8780", b: "#5e5954", c: "#34312e", d: "#b4ada3", atm: [165, 165, 165]}
    ],
    gas: [
      {name: "umber", bands: ["#bcb6a6", "#7f8c95", "#dcd4c0"], storm: "#a07a5a", atm: [150, 165, 180]},
      {name: "ochre", bands: ["#cdb084", "#8e6e4c", "#e8dabe"], storm: "#7a4a2e", atm: [205, 180, 140]},
      {name: "slate", bands: ["#a2b6ba", "#5f7a84", "#d6e0e2"], storm: "#3f5a66", atm: [150, 180, 200]},
      {name: "sienna", bands: ["#c89e7e", "#7a5444", "#ead6c2"], storm: "#6a3a2a", atm: [205, 165, 140]}
    ],
    ice: [
      {name: "rime", lo: "#aeb9be", hi: "#eef1f0", crack: "#6f8794", atm: [190, 210, 225]},
      {name: "glacier", lo: "#9fb2c2", hi: "#e6eef4", crack: "#56738a", atm: [175, 205, 230]},
      {name: "frost", lo: "#b6b4bf", hi: "#f0eff2", crack: "#7a768c", atm: [200, 200, 220]}
    ],
    lava: [
      {name: "basalt", lo: "#1b1918", hi: "#3e3631", glow: [216, 104, 42], atm: [210, 110, 70]},
      {name: "cinder", lo: "#211816", hi: "#4a3428", glow: [232, 128, 52], atm: [220, 130, 80]}
    ],
    ocean: [
      {name: "deep", lo: "#0d1c2b", hi: "#335c78", l1: "#6b6a55", l2: "#8b8466", atm: [110, 160, 210]},
      {name: "teal", lo: "#0b2226", hi: "#2f6a6e", l1: "#6a6650", l2: "#8a8262", atm: [110, 180, 190]}
    ],
    jungle: [
      {name: "temperate", s1: "#132535", s2: "#2f5466", l1: "#59613f", l2: "#8a7a5c", atm: [120, 160, 200]},
      {name: "verdant", s1: "#10222e", s2: "#2a4d5e", l1: "#3f5a34", l2: "#6f7a4a", atm: [120, 170, 190]},
      {name: "arid", s1: "#16262e", s2: "#355262", l1: "#7a6a48", l2: "#a08a64", atm: [170, 170, 170]}
    ]
  };
  const KINDS = Object.keys(PAL);
  const ROLE_KINDS = {
    dev:        {rocky: 3, jungle: 3, ocean: 2, gas: 1, ice: 1, lava: 1},
    designer:   {jungle: 3, gas: 3, ocean: 2, ice: 1},
    tester:     {ice: 4, rocky: 2, ocean: 1},
    devops:     {lava: 4, rocky: 2, gas: 1},
    pm:         {gas: 4, ocean: 2, jungle: 1},
    researcher: {ocean: 3, ice: 2, jungle: 2},
    ceo:        {gas: 3, jungle: 2, ocean: 2},
    sales:      {ocean: 3, gas: 2, jungle: 2},
    marketing:  {jungle: 3, gas: 3, lava: 1}
  };
  const SCALE = {rocky: [.72, .92], gas: [1.2, 1.45], ice: [.82, 1.02], lava: [.72, .9], ocean: [.95, 1.1], jungle: [.95, 1.1]};
  const RINGP = {gas: .45, ice: .25, rocky: .15, lava: .06, ocean: .08, jungle: .08};
  // each texture gets the point on the unit sphere, the palette, the look (seed, frequency, storm) and the brightness jitter
  const TEXF = {
    rocky(px, py, pz, P, L) {
      const k = 1.8 * L.freq, s = L.seed, h = fbm(px * k + 5, py * k + 5, pz * k + 5, s);
      let c = P.banded ? M3(M3(C3(P.a), C3(P.b), Math.sin(py * 6 + h * 4) * .5 + .5), C3(P.c), Math.max(0, h - .55) * 1.8) : M3(C3(P.b), C3(P.a), SS(.3, .72, h));
      c = M3(c, C3(P.c), SS(.56, .7, fbm(px * 3.2 + 1, py * 3.2, pz * 3.2, s + 3, 4)) * .5);
      const cr = fbm(px * 10, py * 10, pz * 10, s + 9, 4);
      if (cr > .66) c = M3(c, C3(P.c), .45); else if (cr < .3) c = M3(c, C3(P.d), .3);
      return [c.map(v => v * L.bright)];
    },
    gas(px, py, pz, P, L) {
      const s = L.seed, w = fbm(px * 2, py * 2, pz * 2, s, 4), b = Math.sin(py * 12 * L.freq + w * 4);
      let c = M3(M3(C3(P.bands[0]), C3(P.bands[1]), b * .5 + .5), C3(P.bands[2]), Math.max(0, Math.sin(py * 4 + 1 + L.freq)) * .35);
      c = c.map(v => v * (.93 + .14 * fbm(px * 7, py * 18, pz * 7, s + 5, 3)));
      if (L.storm) {
        let sx = Math.atan2(pz, px) - L.storm.lon; sx -= Math.round(sx / TAU) * TAU;
        const sy = py - L.storm.lat, dd = sx * sx * 1.6 + sy * sy * 40;
        c = M3(c, C3(P.storm), (1 - SS(.015, .06, dd)) * .65);
      }
      return [c.map(v => v * L.bright)];
    },
    ice(px, py, pz, P, L) {
      const s = L.seed, k = 1.8 * L.freq, h = fbm(px * k + 5, py * k + 5, pz * k + 5, s);
      let c = M3(C3(P.lo), C3(P.hi), h);
      const cr = Math.abs(fbm(px * 3 + 9, py * 3, pz * 3, s + 3) - .5);
      if (cr < .03) c = M3(C3(P.crack), c, cr / .03);
      if (h < .38) c = M3(M3(C3(P.lo), C3(P.crack), .35), c, h / .38);
      return [c.map(v => v * L.bright), 0, Math.max(0, fbm(px * 4, py * 6, pz * 4, s + 50) - .62) * 1.6];
    },
    lava(px, py, pz, P, L) {
      const s = L.seed, k = 1.8 * L.freq, h = fbm(px * k + 5, py * k + 5, pz * k + 5, s);
      let c = M3(C3(P.lo), C3(P.hi), h), e = 0;
      const cr = Math.abs(fbm(px * 2.6 * L.freq + 3, py * 2.6 * L.freq, pz * 2.6 * L.freq, s + 11) - .5);
      if (cr < .035) { e = (1 - cr / .035) * .75; c = M3(c, P.glow, e); }
      if (h > .7) { const p2 = SS(.7, .8, h) * .5; e = Math.max(e, p2); c = M3(c, P.glow, p2); }
      return [c, e];
    },
    ocean(px, py, pz, P, L) {
      const s = L.seed, k = 1.8 * L.freq, h = fbm(px * k + 5, py * k + 5, pz * k + 5, s);
      let c = M3(C3(P.lo), C3(P.hi), Math.pow(h, 1.3));
      if (h > .72) c = M3(C3(P.l1), C3(P.l2), (h - .72) * 3);
      if (Math.abs(py) > .9) c = M3(c, [232, 236, 236], Math.min(1, (Math.abs(py) - .9) * 10));
      return [c.map(v => v * L.bright), 0, Math.max(0, fbm(px * 3.4 + 4, py * 4.5 + 4, pz * 3.4 + 4, s + 77) - .5) * 2.6];
    },
    jungle(px, py, pz, P, L) {
      const s = L.seed, k = 1.8 * L.freq, h = fbm(px * k + 5, py * k + 5, pz * k + 5, s);
      let c = h < .52 ? M3(C3(P.s1), C3(P.s2), Math.pow(h / .52, 2)) : M3(C3(P.l1), C3(P.l2), (h - .52) * 2.2);
      const capT = .8 + (fbm(px * 4 + 7, py * 4, pz * 4, s + 61, 3) - .5) * .4;
      if (Math.abs(py) > capT) c = M3(c, [230, 232, 230], Math.min(1, (Math.abs(py) - capT) * 14));
      return [c.map(v => v * L.bright), 0, Math.max(0, fbm(px * 3 + 1, py * 5 + 1, pz * 3 + 1, s + 99) - .53) * 2.6];
    }
  };
  // a ring system: thin warm bands with gaps, like the prototype's; back half before the planet, front half after
  function makeRing(r) {
    const inner = between(r, 1.36, 1.5), outer = inner + between(r, .38, .62), bands = [];
    for (let x = inner; x < outer;) { const w = between(r, .04, .11); if (r() > .2) bands.push({f: x + w / 2, w, a: +between(r, .18, .58).toFixed(2)}); x += w + (r() < .25 ? between(r, .02, .06) : 0); }
    return {inner, outer, bands, rot: between(r, -.5, .5), k: between(r, .24, .34), col: pick(r, [[214, 200, 172], [205, 196, 180], [196, 186, 170]])};
  }
  function ringHalf(ctx, cx, cy, Rp, ring, half, alphaK) {
    for (const b of ring.bands) {
      const rr = Rp * b.f;
      ctx.strokeStyle = `rgba(${ring.col.join(",")},${(b.a * alphaK * (half === "back" ? .72 : 1)).toFixed(3)})`; ctx.lineWidth = Math.max(.6, Rp * b.w);
      ctx.beginPath(); ctx.ellipse(cx, cy, rr, rr * ring.k, ring.rot, half === "back" ? Math.PI : 0, half === "back" ? TAU : Math.PI); ctx.stroke();
    }
  }
  function lookOf(L, R, o) { const sc = (o.dpr || 1) * (o.ss || 1); return {sc, Rp: R * L.scale * sc}; }
  function bodySprite(L, R, o, extra) {
    const {sc, Rp} = lookOf(L, R, o), done = (o.state || L.state) === "done" || o.finished;
    const la = o.light ?? -2.25, spin = (L.spin + (o.spin || 0)), key = `${L.body}:${L.id}:${Rp.toFixed(1)}:${q(la, .26)}:${q(spin, .04)}:${done ? 1 : 0}`;
    const half = Math.ceil(Rp * (L.ring ? L.ring.outer * 1.04 : 1.5)) + 3;
    return sprite(key, half * 2, half * 2, ctx => {
      const cx = half, cy = half, res = Rp * (o.ss || 1) > 70 ? 2 : 1, tex = L.tex(res);
      // a thin atmosphere halo: it hugs the limb and is gone well inside the state hexagon round the body (whose flats
      // clear the disc by 4 pt), so the band between body and hexagon stays the sky's own black, never a slate fill
      if (L.atm) { const g = ctx.createRadialGradient(cx, cy, Rp * .96, cx, cy, Rp * 1.14), a = (done ? .05 : .14) * (L.atmK ?? 1); g.addColorStop(0, `rgba(${L.atm.join(",")},${a})`); g.addColorStop(.35, `rgba(${L.atm.join(",")},${(a * .35).toFixed(4)})`); g.addColorStop(1, `rgba(${L.atm.join(",")},0)`); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy, Rp * 1.14, 0, TAU); ctx.fill(); }
      if (L.ring) ringHalf(ctx, cx, cy, Rp, L.ring, "back", done ? .5 : 1);
      const sph = sphereCanvas(Rp, tex, {L: lightVec(q(la, .26), .5), spin: q(spin, .04), tilt: L.tilt, atm: L.atm, atmK: done ? .3 : (L.atmK ?? 1), dim: done ? .55 : 1, emiCol: L.emiCol});
      ctx.drawImage(sph, cx - sph.width / 2, cy - sph.height / 2);
      if (L.ring) ringHalf(ctx, cx, cy, Rp, L.ring, "front", done ? .5 : 1);
      if (extra) extra(ctx, cx, cy, Rp);
    });
  }
  function attach(L, defaults, markR) {
    L.sprite = (R = 30, o = {}) => bodySprite(L, R, {...defaults, ...o});
    L.paint = (ctx, x, y, R = 30, o = {}) => {
      const oo = {...defaults, ...o}, sc = (oo.dpr || 1) * (oo.ss || 1), Rs = oo.bucket ? bucketR(R * L.scale * sc) / (L.scale * sc) : R, s = L.sprite(Rs, oo), k = R / Rs / sc;
      ctx.drawImage(s.canvas, x - s.w * k / 2, y - s.h * k / 2, s.w * k, s.h * k);
      if (oo.mark !== false) mark(ctx, x, y, markR(R), oo.state, oo);
    };
    L.svg = (R = 30, o = {}) => {
      const oo = {dpr: 2, ...defaults, ...o}, s = L.sprite(R, oo), sc = (oo.dpr || 1) * (oo.ss || 1), w = s.w / sc, h = s.h / sc;
      if (!s.url) s.url = s.canvas.toDataURL("image/png");
      return `<g class="og-${L.body}"><image href="${s.url}" x="${f(-w / 2)}" y="${f(-h / 2)}" width="${f(w)}" height="${f(h)}"/>${oo.mark === false ? "" : markSVG(oo.state, markR(R), oo)}</g>`;
    };
    return L;
  }
  function planet(sessionId, opts = {}) {
    const r = rnd("planet:" + sessionId), kind = opts.kind && PAL[opts.kind] ? opts.kind : pickW(r, ROLE_KINDS[opts.role] || Object.fromEntries(KINDS.map(k => [k, 1])));
    const P = pick(r, PAL[kind]), sc = SCALE[kind];
    const L = {id: sessionId, body: "planet", kind, palette: P.name, role: opts.role || null, state: opts.state || "working", seed: Math.floor(r() * 1e6), freq: between(r, .8, 1.25), bright: between(r, .9, 1.08),
      tilt: between(r, -.4, .4), spin: r() * TAU, scale: between(r, sc[0], sc[1]), atm: P.atm, emiCol: kind === "lava" ? P.glow : null};
    if (kind === "gas" && r() < .6) L.storm = {lon: r() * TAU, lat: between(r, -.45, .45)};
    if (r() < RINGP[kind]) L.ring = makeRing(r);
    L.extent = L.scale * (L.ring ? L.ring.outer : 1.3);
    L.tex = res => texture("planet:" + sessionId, res, (px, py, pz) => TEXF[kind](px, py, pz, P, L));
    return attach(L, {state: opts.state}, R => R * L.scale + 8);
  }

  /* ---------- moons: the sub-agent's type picks the rock ---------- */
  const MOON_TYPES = {
    explore:  {label: "Explore", lo: "#55524d", hi: "#aaa59c", dark: "#3e3b37", atm: [150, 150, 150]},
    plan:     {label: "Plan", lo: "#7e8a92", hi: "#d4dadc", dark: "#5e6c76", atm: [170, 190, 205], icy: true},
    general:  {label: "General", lo: "#5e5448", hi: "#b6a68e", dark: "#463c32", atm: [190, 170, 140]},
    review:   {label: "Review", lo: "#5c4236", hi: "#ac876f", dark: "#3e2a22", atm: [190, 140, 120]},
    test:     {label: "Test", lo: "#556058", hi: "#b4bcb0", dark: "#3c463e", atm: [160, 190, 170]},
    build:    {label: "Build", lo: "#2a2624", hi: "#5c524b", dark: "#1c1816", atm: [200, 120, 80], seams: [222, 110, 44]},
    research: {label: "Research", lo: "#565642", hi: "#a8a486", dark: "#3c3c2c", atm: [170, 170, 130]},
    design:   {label: "Design", lo: "#5a5464", hi: "#b0a8bc", dark: "#403a4a", atm: [175, 160, 200]},
    backup:   {label: "Backup", lo: "#6a667a", hi: "#cbc7d8", dark: "#4a4658", atm: [190, 180, 220], icy: true}
  };
  const MOON_MATCH = [[/research|doc|web|guide|read/i, "research"], [/build|deploy|devops|\bci\b|infra|ops/i, "build"], [/explor|^search|scan|find/i, "explore"], [/plan|architect/i, "plan"], [/review|audit|critic|secur/i, "review"], [/test|qa\b|verif|check|lint/i, "test"], [/design|\bui\b|ux|style/i, "design"], [/backup/i, "backup"], [/general|default|task|worker/i, "general"]];
  function moonType(type, r) { if (type && MOON_TYPES[type]) return type; for (const [re, k] of MOON_MATCH) if (re.test(type || "")) return k; return pick(r, Object.keys(MOON_TYPES).filter(k => k !== "backup")); }
  function moon(subAgentId, opts = {}) {
    const r = rnd("moon:" + subAgentId), type = moonType(opts.type, rnd("type:" + (opts.type || subAgentId))), P = MOON_TYPES[type];
    const L = {id: subAgentId, body: "moon", type, kind: type, label: P.label, seed: Math.floor(r() * 1e6), freq: between(r, .85, 1.3), tilt: between(r, -.4, .4), spin: r() * TAU,
      scale: between(r, .85, 1.1) * Math.pow(.72, opts.depth || 0), atm: P.atm, atmK: .6, emiCol: P.seams, state: opts.finished ? "done" : opts.state};
    L.extent = L.scale * 1.3;
    L.tex = res => texture("moon:" + subAgentId, res, (px, py, pz) => {
      const s = L.seed, k = 2.2 * L.freq, h = fbm(px * k + 3, py * k + 3, pz * k + 3, s);
      let c = M3(C3(P.lo), C3(P.hi), h), e = 0;
      c = M3(c, C3(P.dark), SS(.58, .7, fbm(px * 3, py * 3, pz * 3, s + 5, 4)) * .55);
      const cr = fbm(px * 9, py * 9, pz * 9, s + 13, 4);
      if (cr > .68) c = M3(c, C3(P.dark), .45); else if (cr < .28) c = M3(c, C3(P.hi), .3);
      if (P.icy) { const cc = Math.abs(fbm(px * 3 + 9, py * 3, pz * 3, s + 3) - .5); if (cc < .025) c = M3(C3(P.dark), c, cc / .025); }
      if (P.seams) { const cc = Math.abs(fbm(px * 2.8 + 3, py * 2.8, pz * 2.8, s + 11) - .5); if (cc < .03) { e = (1 - cc / .03) * .6; c = M3(c, P.seams, e); } }
      return [c, e];
    });
    return attach(L, {state: L.state}, R => R * L.scale + 5);
  }

  /* ---------- stars: a project's sun; class sets the colour, size the scale; white-hot, a soft bloom, a thin lens streak ---------- */
  const STAR_CLASSES = {
    M: {label: "red", lo: "#e0683a", mid: "#b8482a", hi: "#ffd2b0", glow: "#ffb48c"},
    K: {label: "orange", lo: "#f59a48", mid: "#d8702a", hi: "#ffeacc", glow: "#ffd6aa"},
    G: {label: "yellow", lo: "#ffb45c", mid: "#f08a2c", hi: "#fff7e4", glow: "#ffeccd"},
    F: {label: "white", lo: "#efc48e", mid: "#e0a060", hi: "#fffaf0", glow: "#fff4e2"},
    A: {label: "blue-white", lo: "#b4c4ec", mid: "#8ea2dc", hi: "#f8faff", glow: "#e4ecff"},
    B: {label: "blue", lo: "#8aa2e8", mid: "#6a80d0", hi: "#eef2ff", glow: "#c8d7ff"}
  };
  const STAR_SIZES = {dwarf: .62, main: .9, giant: 1.25, supergiant: 1.6};
  const SIZE_W = {M: {dwarf: 4, main: 1, giant: 1.2, supergiant: .6}, K: {dwarf: 1, main: 3, giant: 1.3}, G: {dwarf: 1, main: 4, giant: .7}, F: {main: 3, giant: 1}, A: {main: 2, giant: 1.2, supergiant: .5}, B: {main: 1, giant: 1.4, supergiant: 1}};
  const starTex = (key, cls, L) => res => texture(key, res, (px, py, pz) => {
    const c = STAR_CLASSES[cls], s = L.seed, g = fbm(px * 11, py * 11, pz * 11, s, 4) * .7 + fbm(px * 28, py * 28, pz * 28, s + 7, 2) * .3, lanes = Math.abs(fbm(px * 9 + 3, py * 9, pz * 9, s + 4, 3) - .5);
    let col = M3(C3(c.lo), C3(c.hi), SS(.22, .86, g));
    if (lanes < .045) col = M3(C3(c.mid), col, lanes / .045 * .6 + .4);
    if (L.spots) { const sp = fbm(px * 3.5, py * 3.5, pz * 3.5, s + 21, 4); col = M3(col, C3(c.mid).map(v => v * .45), SS(.7, .78, sp) * .85); }
    return [col, 1];
  });
  function star(projectId, opts = {}) {
    const r = rnd("star:" + projectId), cls = pickW(r, {M: 2.4, K: 2.4, G: 2.4, F: 2, A: 2, B: 1.6}), size = pickW(r, SIZE_W[cls]);
    const L = {id: projectId, body: "star", cls, label: STAR_CLASSES[cls].label, size, scale: STAR_SIZES[size] * between(r, .92, 1.08), seed: Math.floor(r() * 1e6), tilt: between(r, -.3, .3), spin: r() * TAU, streak: between(r, .85, 1.15)};
    L.spots = "MKG".includes(cls) && r() < .6;
    if (r() < .18) { const cc = pickW(r, {M: 3, K: 2, G: 1, A: 1, B: 1}); L.companion = {cls: cc, ang: between(r, -2.6, -.5), dist: between(r, 1.75, 2.25), size: between(r, .22, .3), seed: Math.floor(r() * 1e6)}; }
    L.tex = starTex("star:" + projectId, cls, L);
    if (L.companion) L.companion.tex = starTex("star:" + projectId + ":b", L.companion.cls, L.companion);
    L.extent = L.scale * 2;
    L.bloom = R => R * L.scale * Math.min(11.5, 3.5 + 220 / Math.max(1, R * L.scale));
    L.sprite = (R = 24, o = {}) => starSprite(L, R, {state: opts.state, activity: opts.activity, ...o});
    L.paint = (ctx, x, y, R = 24, o = {}) => {
      const oo = {state: opts.state, activity: opts.activity, ...o}, sc = (oo.dpr || 1) * (oo.ss || 1), Rs = oo.bucket ? bucketR(R * L.scale * sc) / (L.scale * sc) : R, s = L.sprite(Rs, oo), k = R / Rs / sc;
      ctx.save(); ctx.globalCompositeOperation = "lighter"; ctx.drawImage(s.canvas, x - s.w * k / 2, y - s.h * k / 2, s.w * k, s.h * k); ctx.restore();
      if (oo.mark !== false) mark(ctx, x, y, R * L.scale * 1.9 + 4, oo.state, oo);
    };
    L.svg = (R = 24, o = {}) => {
      const oo = {dpr: 2, state: opts.state, activity: opts.activity, ...o}, s = L.sprite(R, oo), sc = (oo.dpr || 1) * (oo.ss || 1), w = s.w / sc, h = s.h / sc;
      if (!s.url) s.url = s.canvas.toDataURL("image/png");
      return `<g class="og-star"><image href="${s.url}" x="${f(-w / 2)}" y="${f(-h / 2)}" width="${f(w)}" height="${f(h)}" style="mix-blend-mode:screen"/>${oo.mark === false ? "" : markSVG(oo.state, R * L.scale * 1.9 + 4, oo)}</g>`;
    };
    return L;
  }
  function starSprite(L, R, o) {
    const sc = (o.dpr || 1) * (o.ss || 1), Rp = R * L.scale * sc, act = clamp(o.activity ?? 1), k = .35 + .65 * act, bk = o.bloom ?? 1, sk = o.streak ?? 1;
    const B = L.bloom(R) * sc * bk, hw = Math.ceil(Math.max(B, B * 1.15 * L.streak * sk)) + 2, hh = Math.ceil(B) + 2, key = `star:${L.id}:${Rp.toFixed(1)}:${k.toFixed(2)}:${bk}:${sk}:${q(o.spin || 0, .04)}`;
    return sprite(key, hw * 2, hh * 2, ctx => {
      const cx = hw, cy = hh, c = STAR_CLASSES[L.cls], gl = C3(c.glow).join(",");
      ctx.globalCompositeOperation = "lighter";
      // bloom: a wide soft glow that fades fast
      const bl = ctx.createRadialGradient(cx, cy, 0, cx, cy, B); bl.addColorStop(0, `rgba(${gl},${(.55 * k).toFixed(3)})`); bl.addColorStop(.07, `rgba(${gl},${(.3 * k).toFixed(3)})`); bl.addColorStop(.22, `rgba(${gl},${(.09 * k).toFixed(3)})`); bl.addColorStop(1, `rgba(${gl},0)`);
      ctx.fillStyle = bl; ctx.fillRect(cx - B, cy - B, B * 2, B * 2);
      // the lens streak: one hairline through the star, and a faint band round it
      const SL = B * 1.15 * L.streak * sk, st = ctx.createLinearGradient(cx - SL, 0, cx + SL, 0); st.addColorStop(0, `rgba(${gl},0)`); st.addColorStop(.5, `rgba(${gl},${(.34 * k).toFixed(3)})`); st.addColorStop(1, `rgba(${gl},0)`);
      ctx.fillStyle = st; ctx.fillRect(cx - SL, cy - Math.max(.6, Rp * .028), SL * 2, Math.max(1.2, Rp * .056));
      const S2 = SL * .6, st2 = ctx.createLinearGradient(cx - S2, 0, cx + S2, 0); st2.addColorStop(0, `rgba(${gl},0)`); st2.addColorStop(.5, `rgba(${gl},${(.06 * k).toFixed(3)})`); st2.addColorStop(1, `rgba(${gl},0)`);
      ctx.fillStyle = st2; ctx.fillRect(cx - S2, cy - Rp * .23, S2 * 2, Rp * .46);
      ctx.globalCompositeOperation = "source-over";
      const sph = sphereCanvas(Rp, L.tex(Rp > 70 ? 2 : 1), {emissive: true, limb: .32, spin: L.spin + (o.spin || 0), tilt: L.tilt});
      ctx.drawImage(sph, cx - sph.width / 2, cy - sph.height / 2);
      ctx.globalCompositeOperation = "lighter";
      // the corona, hugging the disc
      const co = ctx.createRadialGradient(cx, cy, Rp * .92, cx, cy, Rp * 1.9); co.addColorStop(0, `rgba(${gl},${(.5 * k).toFixed(3)})`); co.addColorStop(.25, `rgba(${gl},${(.16 * k).toFixed(3)})`); co.addColorStop(1, `rgba(${gl},0)`);
      ctx.fillStyle = co; ctx.beginPath(); ctx.arc(cx, cy, Rp * 1.9, 0, TAU); ctx.fill();
      if (L.companion) {
        const m = L.companion, cc = STAR_CLASSES[m.cls], r2 = Rp * m.size, x2 = cx + Math.cos(m.ang) * Rp * m.dist, y2 = cy + Math.sin(m.ang) * Rp * m.dist, g2 = C3(cc.glow).join(",");
        const b2 = ctx.createRadialGradient(x2, y2, 0, x2, y2, r2 * 6); b2.addColorStop(0, `rgba(${g2},${(.5 * k).toFixed(3)})`); b2.addColorStop(.12, `rgba(${g2},${(.22 * k).toFixed(3)})`); b2.addColorStop(1, `rgba(${g2},0)`);
        ctx.fillStyle = b2; ctx.fillRect(x2 - r2 * 6, y2 - r2 * 6, r2 * 12, r2 * 12);
        ctx.globalCompositeOperation = "source-over";
        const s2 = sphereCanvas(Math.max(1, r2), m.tex(1), {emissive: true, limb: .35});
        ctx.drawImage(s2, x2 - s2.width / 2, y2 - s2.height / 2);
      }
    });
  }

  /* ---------- a solar system: the survey grid, hairline orbits in one tilted plane, the sun, planets, moons, tags ---------- */
  const MONO = `"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace`;
  const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];
  // a light caps tag next to a body, joined to it by a hairline leader (as in the prototype's Starfield skin)
  function tag(ctx, x, y, r, o) {
    const sc = o.scale || 1, th = 14 * sc, pad = 5 * sc; let side = o.side || "right";
    ctx.save(); ctx.textAlign = "left"; ctx.letterSpacing = `${sc}px`;
    ctx.font = `500 ${10 * sc}px ${MONO}`; const nameW = ctx.measureText(o.name).width;
    ctx.font = `700 ${9 * sc}px ${MONO}`; const numW = o.num ? ctx.measureText(o.num).width + pad * 2 : 0;
    ctx.font = `400 ${9 * sc}px ${MONO}`; const subW = o.sub ? ctx.measureText(o.sub).width + pad * 2 : 0;
    const topW = numW + nameW + pad * 2, gap = (o.gap ?? 10) * sc, vw = ctx.canvas.width / (o.dpr || 1), boxW = Math.max(topW, subW);
    // flip to the other side when the tag would leave the canvas (unless a layout already chose the side)
    if (!o.fixed) { if (side === "left" && x - r - gap - boxW < 2) side = "right"; else if (side === "right" && x + r + gap + boxW > vw - 2) side = "left"; }
    const bx = side === "right" ? x + r + gap : side === "left" ? x - r - gap - topW : x - topW / 2, by = side === "below" ? y + r + gap : side === "above" ? y - r - gap - th - (o.sub ? 13 * sc : 0) : y - th / 2;
    if (o.measure) { ctx.restore(); const sx = side === "left" ? bx + topW - boxW : bx; return {x: Math.min(bx, sx), y: by, w: boxW, h: th + (o.sub ? 13 * sc + 2 : 0)}; }
    const ax = Math.max(bx, Math.min(bx + topW, x)), ay = Math.max(by, Math.min(by + th, y)), dx = ax - x, dy = ay - y, dl = Math.hypot(dx, dy) || 1;
    ctx.globalAlpha *= o.alpha ?? 1;
    if (dl > r + 2) { ctx.strokeStyle = "rgba(235,232,225,.45)"; ctx.lineWidth = o.lw || 1; ctx.beginPath(); ctx.moveTo(x + dx / dl * (r + 2), y + dy / dl * (r + 2)); ctx.lineTo(ax, ay); ctx.stroke(); }
    ctx.textBaseline = "middle"; ctx.textAlign = "left";
    ctx.fillStyle = o.selected ? "#f2f0ea" : "#d6d3cb"; ctx.fillRect(bx, by, topW, th);
    if (o.num) { ctx.fillStyle = o.numColor || "#3a3936"; ctx.fillRect(bx, by, numW, th); ctx.font = `700 ${9 * sc}px ${MONO}`; ctx.fillStyle = o.numInk || "#e6e3dc"; ctx.fillText(o.num, bx + pad, by + th / 2 + .5); }
    ctx.font = `500 ${10 * sc}px ${MONO}`; ctx.fillStyle = "#141413"; ctx.fillText(o.name, bx + numW + pad, by + th / 2 + .5);
    if (o.sub) { const sx = side === "left" ? bx + topW - subW : bx; ctx.fillStyle = "rgba(10,10,9,.72)"; ctx.fillRect(sx, by + th + 1, subW, 12 * sc + 2); ctx.font = `400 ${9 * sc}px ${MONO}`; ctx.fillStyle = o.subColor || "#9c988f"; ctx.fillText(o.sub, sx + pad, by + th + 1 + 6 * sc + 1.5); }
    ctx.restore();
  }
  // sys: {x, y, K, grid: [r0, r1, step], star, starR, planets: [{look, rx, a, r, state, name, num, sub, selected, moons: [{look, d, a, r}]}]}
  function paintSystem(ctx, sys, o = {}) {
    const {x, y} = sys, K = sys.K ?? .46, lw = o.lw || 1, t = o.t ?? 0, PL = sys.planets || [];
    const maxR = Math.max(sys.starR * 3, ...PL.map(p => p.rx));
    const [g0, g1, gs] = sys.grid || [sys.starR * 2.2, maxR * 1.22, 15];
    const half = (rx, h, cx = x, cy = y, k = K) => { ctx.beginPath(); ctx.ellipse(cx, cy, rx, rx * k, 0, h === "back" ? Math.PI : 0, h === "back" ? TAU : Math.PI); };
    const grid = h => {
      ctx.save(); ctx.lineWidth = lw * .8; ctx.strokeStyle = "rgba(235,232,225,.05)";
      for (let rr = g0; rr <= g1; rr += gs) { half(rr, h); ctx.stroke(); }
      ctx.strokeStyle = "rgba(235,232,225,.035)"; ctx.beginPath();
      for (let i = 0; i < 12; i++) { const a = i * Math.PI / 6 + Math.PI / 12, sy = Math.sin(a); if ((h === "back") !== (sy < 0)) continue; ctx.moveTo(x + Math.cos(a) * g0, y + sy * g0 * K); ctx.lineTo(x + Math.cos(a) * g1, y + sy * g1 * K); }
      ctx.stroke(); ctx.restore();
    };
    const orbits = h => {
      ctx.save(); ctx.lineWidth = lw;
      for (const p of PL) { ctx.strokeStyle = p.selected ? `rgba(79,224,245,${h === "back" ? .45 : .7})` : p.state === "waiting" ? `rgba(255,210,63,${h === "back" ? .22 : .38})` : `rgba(235,232,225,${h === "back" ? .17 : .3})`; half(p.rx, h); ctx.stroke(); }
      ctx.restore();
    };
    const at = p => ({px: x + Math.cos(p.a) * p.rx, py: y + Math.sin(p.a) * p.rx * K, back: Math.sin(p.a) < 0});
    const body = p => {
      const {px, py} = at(p), light = Math.atan2(y - py, x - px), R = p.r, pr = R * p.look.scale, ms = p.moons || [];
      const mpos = m => ({mx: px + Math.cos(m.a) * m.d, my: py + Math.sin(m.a) * m.d * .46, mb: Math.sin(m.a) < 0});
      ctx.save(); ctx.lineWidth = lw; ctx.strokeStyle = "rgba(235,232,225,.08)"; for (const m of ms) { half(m.d, "back", px, py, .46); ctx.stroke(); } ctx.restore();
      for (const m of ms) { const {mx, my, mb} = mpos(m); if (mb) m.look.paint(ctx, mx, my, m.r, {...o, light, mark: true}); }
      p.look.paint(ctx, px, py, R, {...o, light, state: p.state, selected: p.selected});
      ctx.save(); ctx.lineWidth = lw; ctx.strokeStyle = "rgba(235,232,225,.14)"; for (const m of ms) { half(m.d, "front", px, py, .46); ctx.stroke(); } ctx.restore();
      for (const m of ms) { const {mx, my, mb} = mpos(m); if (!mb) m.look.paint(ctx, mx, my, m.r, {...o, light, mark: true}); }
      p._at = {px, py, pr};
    };
    grid("back"); orbits("back");
    PL.filter(p => at(p).back).forEach(body);
    if (sys.star) sys.star.paint(ctx, x, y, sys.starR, {...o, state: sys.starState});
    grid("front"); orbits("front");
    PL.filter(p => !at(p).back).forEach(body);
    if (o.tags !== false) {
      const vw = ctx.canvas.width / (o.dpr || 1), vh = ctx.canvas.height / (o.dpr || 1), placed = [];
      // bodies are obstacles too, so a tag never covers a planet or the sun
      const obstacles = PL.filter(p => p._at).map(p => ({x: p._at.px - p._at.pr - 2, y: p._at.py - p._at.pr - 2, w: p._at.pr * 2 + 4, h: p._at.pr * 2 + 4}));
      const sr = sys.starR * (sys.star ? sys.star.scale : 1); obstacles.push({x: x - sr - 4, y: y - sr - 4, w: sr * 2 + 8, h: sr * 2 + 8});
      const hit = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      const place = (bx, by, r, oo, sides) => {
        let best = null, bestScore = 1e9;
        for (const side of sides) {
          const box = tag(ctx, bx, by, r, {...oo, side, fixed: true, measure: true});
          let score = sides.indexOf(side) * 3;
          if (box.x < 2 || box.y < 2 || box.x + box.w > vw - 2 || box.y + box.h > vh - 2) score += 100;
          for (const q of placed) if (hit(box, q)) score += 200;
          for (const q of obstacles) if (hit(box, q)) score += 60;
          if (score < bestScore) { bestScore = score; best = {side, box}; }
        }
        placed.push(best.box); tag(ctx, bx, by, r, {...oo, side: best.side, fixed: true});
      };
      if (sys.starTag) place(x, y, sr + 4, {...sys.starTag, gap: 16, lw, dpr: o.dpr, scale: sys.tagScale || 1}, [sys.starTag.side || "below", "above", "right", "left"]);
      const rank = p => (p.selected ? 0 : p.state === "waiting" ? 1 : p.state === "stuck" ? 2 : p.state === "done" ? 4 : 3);
      for (const p of PL.filter(p => p.name && p._at).sort((a, b) => rank(a) - rank(b))) {
        const out = p._at.px >= x ? "right" : "left";
        place(p._at.px, p._at.py, p._at.pr + 9, {name: p.name.toUpperCase(), num: p.num, sub: p.sub, lw, dpr: o.dpr, scale: sys.tagScale || 1,
          numColor: p.state === "stuck" ? "#7a2a24" : p.state === "waiting" ? "#6b5a1a" : "#3a3936", numInk: p.state === "waiting" ? WAIT : "#e6e3dc",
          subColor: p.state === "waiting" ? WAIT : p.state === "stuck" ? "#f08a80" : p.state === "done" ? "#6f6c66" : "#9c988f", selected: p.selected, alpha: p.state === "done" ? .7 : 1},
          p.side ? [p.side] : [out, out === "right" ? "left" : "right", "below", "above"]);
      }
    }
  }

  /* ---------- galaxies: a provider, by shape; its projects sit on it as solar systems ----------
     galaxy(providerId, {color, shape, state}) → look + .paint(ctx, x, y, r, o) + .sprite(r, o) + .svg(r, o) + .slot(i) → [x, y] for the i-th project at r = 1.
     Known providers keep the board's colours (Claude coral, ChatGPT mint); others get a seeded hue. */
  const GAL_SHAPES = {spiral: 4, barred: 3, elliptical: 1.3, ring: 1, irregular: 1.1};
  const GAL_HUES = ["#8ab4ff", "#b49cff", "#6fd3b8", "#e8916b", "#ff9ac8", "#ffd27a", "#7ad7ff"];
  const PROVIDER_COLORS = [[/claude|anthropic/i, "#e8916b"], [/chatgpt|codex|openai|gpt/i, "#6fd3b8"], [/gemini|google/i, "#8ab4ff"]];
  const gauss = r => Math.sqrt(-2 * Math.log(1 - r())) * Math.cos(TAU * r());
  function galaxy(providerId, opts = {}) {
    const r = rnd("galaxy:" + providerId), shape = opts.shape && GAL_SHAPES[opts.shape] ? opts.shape : pickW(r, GAL_SHAPES);
    const color = opts.color || (PROVIDER_COLORS.find(([re]) => re.test(providerId)) || [])[1] || pick(r, GAL_HUES);
    const L = {id: providerId, body: "galaxy", shape, color, core: pick(r, [STAR_CLASSES.G.glow, STAR_CLASSES.F.glow, STAR_CLASSES.K.glow]), pa: between(r, -60, 60), incl: between(r, .2, 1),
      arms: shape === "spiral" ? count(r, 2, 4) : shape === "barred" ? 2 : 0, twist: between(r, 2.8, 4.8) * (r() < .5 ? -1 : 1), bar: shape === "barred" ? between(r, .22, .36) : 0,
      ringR: between(r, .58, .78), q: shape === "elliptical" ? between(r, .55, .9) : 1, coreR: shape === "elliptical" ? between(r, .45, .6) : between(r, .2, .3), dots: [], knots: [], clumps: []};
    const t0 = L.bar || .07;
    // a point on arm a at t in 0..1: from the core (or the bar's end) out to the rim, winding by twist
    const arm = (a, t) => { const phi = a * TAU / L.arms + L.twist * t, rho = t0 + t * (.96 - t0); return [Math.cos(phi) * rho, Math.sin(phi) * rho]; };
    const armNormal = (a, t) => { const p = arm(a, t), q = arm(a, Math.min(1, t + .01)), dx = q[0] - p[0], dy = q[1] - p[1], m = Math.hypot(dx, dy) || 1; return [-dy / m, dx / m]; };
    L.arm = arm;
    const cols = ["#ffffff", "#ffffff", color, tint(color, .5), STAR_CLASSES.A.glow, STAR_CLASSES.F.glow];
    const dot = (x, y, col, s = between(r, .4, 1.4), op = +between(r, .25, .95).toFixed(2)) => L.dots.push([x, y, s, col, op]);
    if (shape === "irregular") for (let k = count(r, 4, 7); k--;) L.clumps.push([gauss(r) * .3, gauss(r) * .3, between(r, .1, .22)]);
    for (let k = 0; k < 1100; k++) {
      const u = r();
      if (shape === "elliptical") { const rho = Math.abs(gauss(r)) * .36, ph = r() * TAU; dot(Math.cos(ph) * rho, Math.sin(ph) * rho * L.q, rho < .2 ? L.core : pick(r, [L.core, "#ffffff", tint(color, .6)])); }
      else if (shape === "irregular") { const c = pick(r, L.clumps); dot(c[0] + gauss(r) * c[2], c[1] + gauss(r) * c[2], pick(r, cols)); }
      else if (u < .14) { const rho = Math.abs(gauss(r)) * .11, ph = r() * TAU; dot(Math.cos(ph) * rho, Math.sin(ph) * rho, L.core); }
      else if (shape === "ring" && u < .78) { const rho = L.ringR + gauss(r) * .035, ph = r() * TAU; dot(Math.cos(ph) * rho, Math.sin(ph) * rho, pick(r, cols)); }
      else if (shape === "barred" && u < .26) dot(between(r, -L.bar, L.bar), gauss(r) * .03, pick(r, [L.core, "#ffffff"]));
      else if (shape !== "ring" && u < .8) { const a = Math.floor(r() * L.arms), t = Math.pow(r(), .85), p = arm(a, t), n = armNormal(a, t), s = gauss(r) * (.025 + .07 * t); dot(p[0] + n[0] * s, p[1] + n[1] * s, pick(r, cols)); }
      else { const rho = Math.min(1, Math.abs(gauss(r)) * .42), ph = r() * TAU; dot(Math.cos(ph) * rho, Math.sin(ph) * rho, pick(r, cols), between(r, .3, .9), +between(r, .15, .5).toFixed(2)); }
    }
    // star-forming knots: small bright clouds along the arms, the ring or the clumps
    const knotCols = [STAR_CLASSES.B.glow, STAR_CLASSES.A.glow, STAR_CLASSES.M.glow, tint(color, .3)];
    if (shape !== "elliptical") for (let k = count(r, 8, 18); k--;) {
      let p;
      if (shape === "ring") { const ph = r() * TAU; p = [Math.cos(ph) * L.ringR, Math.sin(ph) * L.ringR]; }
      else if (shape === "irregular") { const c = pick(r, L.clumps); p = [c[0] + gauss(r) * c[2] * .7, c[1] + gauss(r) * c[2] * .7]; }
      else { const a = Math.floor(r() * L.arms), t = between(r, .2, .9), n = armNormal(a, t), s = gauss(r) * .02; p = arm(a, t); p = [p[0] + n[0] * s, p[1] + n[1] * s]; }
      L.knots.push([p[0], p[1], between(r, .01, .026), pick(r, knotCols)]);
    }
    L.extent = 1.05;
    // where the i-th project sits: spread over the arms, never on the core
    L.slot = i => {
      const g = (i * .618034 + .17) % 1; let p;
      if (L.arms) { const a = i % L.arms, j = Math.floor(i / L.arms), t = .3 + ((j * .618034 + a * .31 + .17) % 1) * .6; p = arm(a, t); }
      else if (shape === "ring") { const ph = i * 2.39996 + .4; p = [Math.cos(ph) * L.ringR, Math.sin(ph) * L.ringR]; }
      else if (shape === "irregular") { const c = L.clumps[i % L.clumps.length], ph = g * TAU; p = [c[0] + Math.cos(ph) * c[2] * .8, c[1] + Math.sin(ph) * c[2] * .8]; }
      else { const ph = i * 2.39996 + .4, rho = .25 + g * .45; p = [Math.cos(ph) * rho, Math.sin(ph) * rho * L.q]; }
      const a = L.pa * Math.PI / 180, y = p[1] * Math.cos(L.incl);
      return [p[0] * Math.cos(a) - y * Math.sin(a), p[0] * Math.sin(a) + y * Math.cos(a)];
    };
    L.seed = Math.floor(rnd("galaxy-tex:" + providerId)() * 1e6);
    return attachGalaxy(L, opts);
  }
  /* the galaxy, rendered per pixel: the disk face on (old light in the bulge, young light and star clouds on the arms, dark
     dust lanes on their inner edge, pink and blue star-forming knots), then tilted; the bulge is drawn after the tilt, so it stays
     round. Muted: the provider colour tints the young light, the core stays a warm white. Additive light, like the stars. */
  const GPLANE = new Map();
  function galaxyPlane(L, N, done) {
    const key = `${L.id}:${N}:${done ? 1 : 0}`;
    if (GPLANE.has(key)) return GPLANE.get(key);
    const c = newCanvas(N, N), x = c.getContext("2d"), img = x.createImageData(N, N), d = img.data, S = L.seed, E = 1.1;
    const arms = L.arms, tw = L.twist, sg = Math.sign(tw) || 1, t0 = L.bar || .07, shape = L.shape, ell = shape === "elliptical";
    const young = hex(mix(tint(L.color, .3), "#d8dde6", .38)), old = hex(mix(L.core, "#f2e6d2", .4)), gas = hex(mix(L.color, "#ffffff", .15)), dust = [.55, .62, .75];
    const pink = hex(mix(STAR_CLASSES.M.glow, "#ff8fb0", .5)), blue = hex(STAR_CLASSES.B.glow);
    for (let py = 0; py < N; py++) for (let px = 0; px < N; px++) {
      const u = ((px + .5) / N * 2 - 1) * E, v = ((py + .5) / N * 2 - 1) * E, rho = Math.hypot(u, v);
      if (rho > 1.08 && !ell) continue;
      const phi = Math.atan2(v, u), n1 = fbm(u * 4.2 + 9, v * 4.2, 3.1, S, 4), n2 = fbm(u * 13, v * 13, 7.7, S + 5, 3), n3 = vnoise(u * 46, v * 46, 1.3, S + 9);
      let R = 0, G = 0, B = 0, lane = 0;
      const add = (col, k) => { R += col[0] * k; G += col[1] * k; B += col[2] * k; };
      if (ell) {
        const re = Math.hypot(u, v / L.q), I = Math.exp(-Math.pow(re / (L.coreR * .5), .5) * 2.6) * (.92 + .16 * n1) * (1 - SS(.55, 1.05, re));
        add(old, I * 3.2);
      } else {
        const disk = Math.exp(-rho / .3) * (1 - SS(.72, 1.06, rho)), t = (rho - t0) / (.96 - t0);
        add(old, disk * .45 * (.75 + .5 * n1)); add(young, disk * .12 * (.6 + .8 * n2));
        if (arms) {
          const env = SS(-.04, .12, t) * (1 - SS(.72, 1.06, t)), ph = arms * (phi - tw * t), w = .5 + .5 * Math.cos(ph);
          const arm = (.6 * Math.pow(w, 12) + .4 * Math.pow(w, 3)) * env, clumps = .45 + .9 * SS(.3, .8, n1) * (.55 + .9 * SS(.35, .75, n2));
          add(young, arm * (.9 - .45 * t) * clumps * (.65 + .7 * n3));
          add(gas, arm * .18 * SS(.55, .85, n2));
          lane = Math.pow(.5 + .5 * Math.cos(ph - .5 * sg), 9) * env * (.5 + .8 * n2) * (1 - .4 * t);
        }
        if (shape === "ring") { const rg = Math.exp(-Math.pow((rho - L.ringR) / .055, 2)), lens = Math.exp(-Math.pow(rho / .35, 2)) * .25; add(young, rg * (.4 + 1.1 * SS(.3, .8, n1)) * (.8 + .4 * n3)); add(old, lens); lane = Math.exp(-Math.pow((rho - L.ringR + .07) / .025, 2)) * .7 * n2; }
        if (shape === "irregular") {
          let k = 0; for (const [cx, cy, cr] of L.clumps) k += Math.exp(-((u - cx) ** 2 + (v - cy) ** 2) / (cr * cr * 1.4));
          add(young, Math.min(1.4, k) * (.25 + 1.2 * SS(.35, .85, n1)) * (.7 + .6 * n3)); add(old, Math.min(1, k) * .12);
          lane = SS(.62, .8, n2) * Math.min(1, k) * .7;
        }
        if (L.bar) add(old, Math.exp(-Math.pow(Math.abs(u) / (L.bar * 1.05), 2.6) - Math.pow(v / .085, 2)) * .5 * (.85 + .3 * n2));
      }
      // dust takes light away, most from the young light it sits in
      const ab = clamp(lane * .95);
      R *= 1 - ab * dust[0]; G *= 1 - ab * dust[1]; B *= 1 - ab * dust[2];
      const tone = k => 255 * (1 - Math.exp(-k / 255 * 1.6));
      R = tone(R); G = tone(G); B = tone(B);
      if (done) { const l = (R + G + B) / 3; R = (R * .3 + l * .7) * .55; G = (G * .3 + l * .7) * .55; B = (B * .3 + l * .7) * .6; }
      const a = clamp(Math.max(R, G, B) / 255 * 1.15);
      if (a < .004) continue;
      const i = (py * N + px) * 4; d[i] = Math.min(255, R / a); d[i + 1] = Math.min(255, G / a); d[i + 2] = Math.min(255, B / a); d[i + 3] = 255 * a;
    }
    x.putImageData(img, 0, 0);
    // star-forming knots and the brightest single stars, small and soft, in the plane
    if (!ell) {
      x.globalCompositeOperation = "lighter";
      const P = q => (q / E * .5 + .5) * N;
      L.knots.forEach(([kx, ky, ks], j) => {
        const col = (j % 3 ? blue : pink).join(","), r = Math.max(1, ks * N / E * .55), g = x.createRadialGradient(P(kx), P(ky), 0, P(kx), P(ky), r);
        g.addColorStop(0, `rgba(${col},${done ? .15 : .55})`); g.addColorStop(1, `rgba(${col},0)`); x.fillStyle = g; x.fillRect(P(kx) - r, P(ky) - r, r * 2, r * 2);
      });
      const n = Math.min(L.dots.length, Math.round(N * .18));
      for (let k = 0; k < n; k++) {
        const [dx, dy, sz, , op] = L.dots[k];
        if (op < .7) continue;
        x.fillStyle = `rgba(235,236,240,${(done ? .2 : .5) * op})`; x.fillRect(P(dx), P(dy), Math.max(.8, sz * N / 900), Math.max(.8, sz * N / 900));
      }
    }
    if (GPLANE.size > 24) GPLANE.delete(GPLANE.keys().next().value);
    GPLANE.set(key, c);
    return c;
  }
  /* o.layer splits the galaxy for an app that turns it (all light adds up, so the layers can be drawn in any order):
     "plane" is the disk face on (arms, dust, bar, knots, bright stars), 2.2 R square, to be tilted and turned by the app;
     "static" is what does not turn: the halo and the bulge, already in the galaxy's own tilt. */
  function galaxySprite(L, R, o) {
    const sc = (o.dpr || 1) * (o.ss || 1), Rp = R * sc, done = o.state === "done", layer = o.layer || "all";
    const N = Math.min(1024, Math.pow(2, Math.ceil(Math.log2(Math.max(32, Rp * 2.2)))));
    if (layer === "plane") {
      const hp = Math.ceil(Rp * 1.1);
      return sprite(`galaxy-plane:${L.id}:${Rp.toFixed(1)}:${done ? 1 : 0}`, hp * 2, hp * 2, ctx => { ctx.imageSmoothingQuality = "high"; ctx.drawImage(galaxyPlane(L, N, done), 0, 0, hp * 2, hp * 2); });
    }
    const half = Math.ceil(Rp * 1.25) + 2, key = `galaxy:${L.id}:${Rp.toFixed(1)}:${done ? 1 : 0}:${layer}`;
    return sprite(key, half * 2, half * 2, ctx => {
      const plane = layer === "static" ? null : galaxyPlane(L, N, done), sy = Math.cos(L.incl), E = 1.1, cc = C3(L.color).join(","), co = C3(L.core).join(",");
      ctx.globalCompositeOperation = "lighter";
      // a faint halo in the provider's colour
      const h = ctx.createRadialGradient(half, half, 0, half, half, Rp * 1.2); h.addColorStop(0, `rgba(${cc},${done ? .03 : .09})`); h.addColorStop(.5, `rgba(${cc},${done ? .015 : .035})`); h.addColorStop(1, `rgba(${cc},0)`);
      ctx.fillStyle = h; ctx.fillRect(0, 0, half * 2, half * 2);
      if (plane) { ctx.save(); ctx.translate(half, half); ctx.rotate(L.pa * Math.PI / 180); ctx.scale(1, sy); ctx.imageSmoothingQuality = "high"; ctx.drawImage(plane, -Rp * E, -Rp * E, Rp * E * 2, Rp * E * 2); ctx.restore(); }
      // the bulge, after the tilt: rounder than the disk
      if (L.shape !== "elliptical") {
        ctx.save(); ctx.translate(half, half); ctx.rotate(L.pa * Math.PI / 180); ctx.scale(1, (1 + sy) / 2);
        const br = Rp * L.coreR * .9, g = ctx.createRadialGradient(0, 0, 0, 0, 0, br), k = done ? .35 : 1;
        g.addColorStop(0, `rgba(255,250,240,${.9 * k})`); g.addColorStop(.06, `rgba(${co},${.6 * k})`); g.addColorStop(.25, `rgba(${co},${.22 * k})`); g.addColorStop(.6, `rgba(${co},${.06 * k})`); g.addColorStop(1, `rgba(${co},0)`);
        ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, br, 0, TAU); ctx.fill(); ctx.restore();
      }
    });
  }
  function attachGalaxy(L, opts) {
    const def = o => ({state: opts.state, ...o});
    L.sprite = (R = 120, o = {}) => galaxySprite(L, R, def(o));
    L.paint = (ctx, x, y, R = 120, o = {}) => {
      const oo = def(o), sc = (oo.dpr || 1) * (oo.ss || 1), Rs = Math.min(480 / sc, oo.bucket ? Math.pow(2, Math.ceil(Math.log2(Math.max(8, R * sc)))) / sc : R), s = L.sprite(Rs, oo), k = R / Rs / sc;
      ctx.save(); ctx.globalCompositeOperation = "lighter"; ctx.drawImage(s.canvas, x - s.w * k / 2, y - s.h * k / 2, s.w * k, s.h * k); ctx.restore();
      if (oo.bucket && !L._warm && typeof requestIdleCallback !== "undefined") {
        L._warm = true;
        const ahead = px => { if (px > 480) return; requestIdleCallback(() => { L.sprite(px / sc, oo); ahead(px * 2); }, {timeout: 5000}); };
        ahead(Math.min(480, Rs * sc * 2));
      }
    };
    L.svg = (R = 120, o = {}) => {
      const oo = {dpr: 2, ...def(o)}, s = L.sprite(R, oo), sc = (oo.dpr || 1) * (oo.ss || 1), w = s.w / sc, h = s.h / sc;
      if (!s.url) s.url = s.canvas.toDataURL("image/png");
      return `<g class="og-galaxy"><image href="${s.url}" x="${f(-w / 2)}" y="${f(-h / 2)}" width="${f(w)}" height="${f(h)}" style="mix-blend-mode:screen"/></g>`;
    };
    return L;
  }

  /* ---------- the Engine room: one supermassive black hole at the top of Orbit, violet and always on (D23, D26) ----------
     blackHole(id, {state, activity}) → look + .paint(ctx, x, y, r, o) + .sprite(r, o) + .svg(r, o) + .slot(i, n) → [x, y] at r = 1.
     Rendered per pixel like the planets: a black shadow, a thin photon ring, a thin accretion disk seen almost edge on with
     turbulent streaks, the far side of the disk bent over the top of the shadow (and faintly under it) by lensing, and the side
     turning toward us brighter (beaming). Muted lilac and dusky violet, white-hot only at the inner edge.
     r is the radius of the shadow; the disk reaches about 3.6 r. A warning hangs a small yellow beacon above the hole (red when
     down), like the beacon on the datacenter roof; it shows even with mark: false, as it is part of the picture.
     infra(itemId, {kind, state}) → look + .paint/.sprite/.svg. kind: server (a pulsar), deploy (a comet falling in),
     backup (an icy moonlet). state: ok | warning | down | done. A warning reads like waiting, down like stuck. */
  const HOLE = {hot: "#fbf8ff", lilac: "#d9d0ef", violet: "#a495cf", deep: "#5f528e", glow: "#8f80c4"};
  // temperature → light: none, dusky violet, muted lilac, then white-hot (it adds up, so no light is black)
  const HRAMP = [[0, [0, 0, 0]], [.08, [22, 16, 38]], [.18, [52, 44, 82]], [.38, [110, 99, 152]], [.66, [180, 171, 208]], [.95, [232, 226, 246]], [1.5, [255, 252, 255]]];
  function hramp(T) {
    if (T <= 0) return [0, 0, 0];
    for (let i = 1; i < HRAMP.length; i++) if (T <= HRAMP[i][0]) { const [a, ca] = HRAMP[i - 1], [b, cb] = HRAMP[i]; return M3(ca, cb, (T - a) / (b - a)); }
    return HRAMP[HRAMP.length - 1][1];
  }
  function blackHole(id = "engine-room", opts = {}) {
    const r = rnd("hole:" + id);
    const L = {id, body: "hole", pa: between(r, -8, 8), sy: between(r, .17, .22), inner: between(r, 1.45, 1.6), outer: between(r, 3.3, 3.7), seed: Math.floor(r() * 1e6), spin: r() * TAU, state: opts.state};
    L.extent = L.outer;
    // the disk as a polar table (radius × angle), made once: streaks long along the orbit, thin across it
    L.disk = () => {
      if (L._disk) return L._disk;
      const nR = 80, nP = 640, g = new Float32Array(nR * nP), s = L.seed;
      for (let i = 0; i < nR; i++) {
        const rho = L.inner + (L.outer - L.inner) * i / (nR - 1);
        for (let j = 0; j < nP; j++) {
          const ph = j / nP * TAU, c = Math.cos(ph), sn = Math.sin(ph);
          const a = fbm(rho * 5.5, c * 1.4, sn * 1.4, s, 4), b = fbm(rho * 15, c * 3.2, sn * 3.2, s + 9, 3), ring = Math.sin(rho * 34 + a * 10);
          g[i * nP + j] = clamp(.5 + 1.15 * (a - .5) + .55 * (b - .5) + .14 * ring, 0, 1.2);
        }
      }
      return (L._disk = {g, nR, nP});
    };
    // the same table as a greyscale image (phase across, radius down, value / 1.2), for an app that turns the disk on the GPU
    L.diskCanvas = () => {
      if (L._diskC) return L._diskC;
      const {g, nR, nP} = L.disk(), c = newCanvas(nP, nR), x = c.getContext("2d"), img = x.createImageData(nP, nR), d = img.data;
      for (let k = 0; k < nR * nP; k++) { const v = Math.round(clamp(g[k] / 1.2) * 255); d[k * 4] = d[k * 4 + 1] = d[k * 4 + 2] = v; d[k * 4 + 3] = 255; }
      x.putImageData(img, 0, 0);
      return (L._diskC = c);
    };
    // infra circles on wide flat orbits outside the disk, spread round the hole
    L.slot = (i, n = 6) => { const side = i % 2, j = Math.floor(i / 2), m = Math.ceil(n / 2), a = (side ? Math.PI : 0) + (m > 1 ? (j / (m - 1) - .5) * 2.1 : 0) * (side ? -1 : 1), d = 4.6 + (j % 2) * 1.2, x = Math.cos(a) * d, y = Math.sin(a) * d * .42, p = L.pa * Math.PI / 180; return [x * Math.cos(p) - y * Math.sin(p), x * Math.sin(p) + y * Math.cos(p)]; };
    // the beacon sits above the hole, in the hole's own frame
    const beaconAt = R => { const p = L.pa * Math.PI / 180, d = R * 2.45; return [Math.sin(p) * d, -Math.cos(p) * d]; };
    const beaconR = R => Math.max(5, Math.min(12, R * .2));
    const def = o => ({state: opts.state, activity: opts.activity, ...o});
    L.sprite = (R = 30, o = {}) => holeSprite(L, R, def(o));
    L.paint = (ctx, x, y, R = 30, o = {}) => {
      // rendered per pixel, so a zoom renders it once per octave and it stops growing at a 256 px shadow (scaled up past that)
      const oo = def(o), sc = (oo.dpr || 1) * (oo.ss || 1), Rs = Math.min(256 / sc, oo.bucket ? Math.pow(2, Math.ceil(Math.log2(Math.max(4, R * sc)))) / sc : R), s = L.sprite(Rs, oo), k = R / Rs / sc;
      ctx.drawImage(s.canvas, x - s.w * k / 2, y - s.h * k / 2, s.w * k, s.h * k);
      // while the browser is idle, render the larger octaves ahead, so zooming in never waits on one
      if (oo.bucket && !L._warm && typeof requestIdleCallback !== "undefined") {
        L._warm = true;
        const ahead = px => { if (px > 256) return; requestIdleCallback(() => { L.sprite(px / sc, oo); ahead(px * 2); }, {timeout: 4000}); };
        ahead(Math.min(256, Rs * sc * 2));
      }
      if ((oo.state === "waiting" || oo.state === "stuck") && oo.beacon !== false) {
        const [bx, by] = beaconAt(R), col = oo.state === "stuck" ? "255,74,74" : "255,210,63", br = Math.max(1.4, Math.min(3.2, R * .05));
        ctx.save(); ctx.globalCompositeOperation = "lighter";
        const g = ctx.createRadialGradient(x + bx, y + by, 0, x + bx, y + by, br * 5); g.addColorStop(0, `rgba(${col},.55)`); g.addColorStop(1, `rgba(${col},0)`);
        ctx.fillStyle = g; ctx.fillRect(x + bx - br * 5, y + by - br * 5, br * 10, br * 10); ctx.restore();
        ctx.fillStyle = `rgb(${col})`; ctx.beginPath(); ctx.arc(x + bx, y + by, br, 0, TAU); ctx.fill();
        mark(ctx, x + bx, y + by, beaconR(R), oo.state, {...oo, selected: false});
      }
      if (oo.mark !== false && oo.selected) mark(ctx, x, y, R * 1.25 + 6, null, oo);
    };
    L.svg = (R = 30, o = {}) => {
      const oo = {dpr: 2, ...def(o)}, s = L.sprite(R, oo), sc = (oo.dpr || 1) * (oo.ss || 1), w = s.w / sc, h = s.h / sc;
      if (!s.url) s.url = s.canvas.toDataURL("image/png");
      let b = "";
      if (oo.state === "waiting" || oo.state === "stuck") {
        const [bx, by] = beaconAt(R), col = oo.state === "stuck" ? STUCK : WAIT, br = Math.max(1.4, Math.min(3.2, R * .05));
        b = `<g transform="translate(${f(bx)} ${f(by)})"><circle r="${f(br * 4)}" fill="${col}" opacity=".16"/><circle r="${f(br)}" fill="${col}"/>${markSVG(oo.state, beaconR(R), oo)}</g>`;
      }
      return `<g class="og-hole"><image href="${s.url}" x="${f(-w / 2)}" y="${f(-h / 2)}" width="${f(w)}" height="${f(h)}"/>${b}</g>`;
    };
    return L;
  }
  function holeSprite(L, R, o) {
    const sc = (o.dpr || 1) * (o.ss || 1), Rp = R * sc, act = clamp(o.activity ?? 1), k = .6 + .4 * act, spin = q(L.spin + (o.spin || 0), .02);
    const hw = Math.ceil(Rp * 4.7) + 2, hh = Math.ceil(Rp * 2.9) + 2, key = `hole:${L.id}:${Rp.toFixed(1)}:${k.toFixed(2)}:${spin}`;
    return sprite(key, hw * 2, hh * 2, ctx => {
      const cx = hw, cy = hh, gl = C3(HOLE.glow).join(",");
      // a faint glow, flattened along the disk: the light of the disk scattered in the gas round it
      ctx.save(); ctx.translate(cx, cy); ctx.rotate(L.pa * Math.PI / 180); ctx.scale(1, .58);
      const g = ctx.createRadialGradient(0, 0, Rp * .8, 0, 0, Rp * 4.6); g.addColorStop(0, `rgba(${gl},${(.2 * k).toFixed(3)})`); g.addColorStop(.35, `rgba(${gl},${(.07 * k).toFixed(3)})`); g.addColorStop(1, `rgba(${gl},0)`);
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, Rp * 4.6, 0, TAU); ctx.fill(); ctx.restore();
      const W = hw * 2, H = hh * 2, img = ctx.createImageData(W, H), d = img.data, {g: tab, nR, nP} = L.disk();
      const pa = L.pa * Math.PI / 180, cp = Math.cos(pa), sp = Math.sin(pa), sy = L.sy, inner = L.inner, outer = L.outer, span = outer - inner;
      const ringW = Math.max(.011, .75 / Rp), ss = Rp < 40 ? 2 : 1, inv = 1 / ss;
      // the disk's light at radius rho and angle ph (0 = right, π/2 = toward us): streaks, a falling profile, beaming
      const disk = (rho, ph, soft = 0) => {
        const u = (rho - inner) / span;
        if (u <= 0 || u >= 1) return 0;
        const prof = Math.max(SS(0, .035, u), soft) * Math.pow(inner / rho, 2.3) * (1 - SS(.5, 1, u));
        let pp = (ph - spin * Math.pow(inner / rho, 1.5)) / TAU; pp -= Math.floor(pp);
        const fi = u * (nR - 1), i0 = Math.min(nR - 2, Math.floor(fi)), fr = fi - i0, fj = pp * nP, j0 = Math.floor(fj) % nP, j1 = (j0 + 1) % nP, fc = fj - Math.floor(fj);
        const gv = (tab[i0 * nP + j0] * (1 - fc) + tab[i0 * nP + j1] * fc) * (1 - fr) + (tab[(i0 + 1) * nP + j0] * (1 - fc) + tab[(i0 + 1) * nP + j1] * fc) * fr;
        const beam = Math.pow(1 - .42 * Math.cos(ph), 2.1) / 1.35;
        return prof * beam * (.35 + .95 * gv) * k;
      };
      for (let py = 0; py < H; py++) for (let px = 0; px < W; px++) {
        let er = 0, eg = 0, eb = 0, ea = 0;
        for (let sy2 = 0; sy2 < ss; sy2++) for (let sx2 = 0; sx2 < ss; sx2++) {
          const X0 = (px + (sx2 + .5) * inv - cx) / Rp, Y0 = (py + (sy2 + .5) * inv - cy) / Rp;
          // into the hole's frame (the disk lies along x)
          const x = X0 * cp + Y0 * sp, y = -X0 * sp + Y0 * cp, r = Math.hypot(x, y);
          // most of the sprite is empty sky: past the lensed arc and outside the disk there is nothing to add
          if (r > 1.95 && Math.hypot(x, y / sy) >= outer) continue;
          let T = 0, Tf = 0;
          // the disk straight on: the far half hides behind the shadow, the near half crosses in front of it
          const Dy = y / sy, rho = Math.hypot(x, Dy), ph = Math.atan2(Dy, x);
          // beside the shadow the inner edge does not stop hard: it fades into the gap, down to dark at the shadow's edge
          const soft = SS(1, 1.18, r);
          if (rho > inner && rho < outer) { if (Dy < 0) { if (r > 1) T += disk(rho, ph, soft); } else Tf += disk(rho, ph, soft) * (1 + .25 * SS(0, .5, Dy / rho)); }
          else if (rho > 1 && rho <= inner && r > 1) T += disk(inner + 1e-4, ph, 1) * Math.pow(SS(1, inner, rho), 1.6) * soft;
          if (r > 1) {
            const ang = Math.atan2(y, x);
            // the far side of the disk, bent over the top of the shadow: a bright arc hugging it
            if (y < 0) { const w = SS(.02, .38, -y / r), rl = inner + (r - 1.06) / (span * .34) * span; if (w > 0 && rl > inner && rl < outer) T += disk(rl, ang) * w * .95; }
            // and faintly under it
            else { const w = SS(.12, .55, y / r), rl = inner + (r - 1.03) / (span * .1) * span; if (w > 0 && rl > inner && rl < outer) T += disk(rl, -ang) * w * .5; }
          }
          // the photon ring: one hairline of light right on the edge of the shadow, brighter on the side turning toward us
          const pr = Math.exp(-Math.pow((r - 1.012) / ringW, 2)) * (.62 + .38 * (-x / Math.max(r, 1e-6))) * .95 * k;
          const shadow = clamp((1 - r) * Rp * ss + .5);
          // light adds up (premultiplied): the far side first, the shadow over it, then the ring and the near side
          const c = hramp(T); let a = clamp(Math.max(c[0], c[1], c[2]) / 255 * 1.2), pr0 = c[0], pg0 = c[1], pb0 = c[2];
          pr0 *= 1 - shadow; pg0 *= 1 - shadow; pb0 *= 1 - shadow; a = shadow + a * (1 - shadow);
          const add = hramp(Tf), ring = hramp(pr * 1.15);
          pr0 += add[0] + ring[0]; pg0 += add[1] + ring[1]; pb0 += add[2] + ring[2];
          a = Math.max(a, clamp(Math.max(pr0, pg0, pb0) / 255 * 1.2));
          er += pr0; eg += pg0; eb += pb0; ea += a;
        }
        const n = ss * ss, A = ea / n;
        if (A <= .002) continue;
        const i = (py * W + px) * 4;
        d[i] = Math.min(255, er / n / A); d[i + 1] = Math.min(255, eg / n / A); d[i + 2] = Math.min(255, eb / n / A); d[i + 3] = 255 * Math.min(1, A);
      }
      const c2 = newCanvas(W, H); c2.getContext("2d").putImageData(img, 0, 0); ctx.drawImage(c2, 0, 0);
    });
  }

  /* infra round the hole, in the same light as everything else: a pulsar is a tiny white-violet star with two thin beams,
     a deploy a comet (a small dark nucleus in a bright coma, its faint tail pointing away from the hole), a backup an icy moonlet */
  const INFRA_STATE = {ok: "working", warning: "waiting", down: "stuck", done: "done"};
  const pulsarTex = id => res => texture("pulsar:" + id, res, (px, py, pz) => { const g = fbm(px * 9, py * 9, pz * 9, 77, 3); return [M3([200, 190, 236], [255, 252, 255], SS(.3, .8, g)), 1]; });
  const nucleusTex = id => res => texture("nucleus:" + id, res, (px, py, pz) => { const g = fbm(px * 4, py * 4, pz * 4, 91, 5); return [M3([58, 54, 52], [128, 122, 116], SS(.3, .75, g)), 0]; });
  function infra(itemId, opts = {}) {
    const r = rnd("infra:" + itemId), kind = ["server", "deploy", "backup"].includes(opts.kind) ? opts.kind : pick(r, ["server", "deploy", "backup"]);
    const L = {id: itemId, body: "infra", kind, beam: between(r, -1.2, 1.2), state: INFRA_STATE[opts.state] || "working", seed: Math.floor(r() * 1e6), spin: r() * TAU};
    if (kind === "backup") { L.moon = moon(itemId, {type: "backup"}); L.extent = 1.6; }
    else L.extent = kind === "deploy" ? 6 : 4.4;
    const def = o => ({state: L.state, ...o}), markR = R => R * (kind === "backup" ? 1 : .75) + 4;
    L.sprite = (R = 6, o = {}) => kind === "backup" ? L.moon.sprite(R, def(o)) : infraSprite(L, R, def(o));
    L.paint = (ctx, x, y, R = 6, o = {}) => {
      const oo = def(o);
      if (kind === "backup") return L.moon.paint(ctx, x, y, R, oo);
      const sc = (oo.dpr || 1) * (oo.ss || 1), Rs = Math.min(160 / sc, oo.bucket ? bucketR(R * sc) / sc : R), s = L.sprite(Rs, oo), k = R / Rs / sc;
      ctx.save(); ctx.globalCompositeOperation = "lighter"; ctx.drawImage(s.canvas, x - s.w * k / 2, y - s.h * k / 2, s.w * k, s.h * k); ctx.restore();
      if (oo.mark !== false) mark(ctx, x, y, markR(R), oo.state, oo);
    };
    L.svg = (R = 6, o = {}) => {
      const oo = {dpr: 2, ...def(o)};
      if (kind === "backup") return L.moon.svg(R, oo);
      const s = L.sprite(R, oo), sc = (oo.dpr || 1) * (oo.ss || 1), w = s.w / sc, h = s.h / sc;
      if (!s.url) s.url = s.canvas.toDataURL("image/png");
      return `<g class="og-infra"><image href="${s.url}" x="${f(-w / 2)}" y="${f(-h / 2)}" width="${f(w)}" height="${f(h)}" style="mix-blend-mode:screen"/>${oo.mark === false ? "" : markSVG(oo.state, markR(R), oo)}</g>`;
    };
    return L;
  }
  function infraSprite(L, R, o) {
    const sc = (o.dpr || 1) * (o.ss || 1), Rp = R * sc, done = o.state === "done", k = done ? .35 : 1;
    const ang = L.kind === "server" ? L.beam + (o.spin || 0) : (o.tail ?? -2.4);
    const half = Math.ceil(Rp * (L.kind === "server" ? 4.6 : 6.2)) + 2, key = `infra:${L.kind}:${L.id}:${Rp.toFixed(1)}:${q(ang, .05)}:${done ? 1 : 0}`;
    return sprite(key, half * 2, half * 2, ctx => {
      const cx = half, cy = half, ca = Math.cos(ang), sa = Math.sin(ang), gl = C3(HOLE.glow).join(","), li = C3(HOLE.lilac).join(",");
      ctx.globalCompositeOperation = "lighter";
      if (L.kind === "server") {
        const core = Math.max(1.2, Rp * .42);
        const b = ctx.createRadialGradient(cx, cy, 0, cx, cy, Rp * 2.6); b.addColorStop(0, `rgba(${gl},${(.5 * k).toFixed(3)})`); b.addColorStop(.18, `rgba(${gl},${(.16 * k).toFixed(3)})`); b.addColorStop(1, `rgba(${gl},0)`);
        ctx.fillStyle = b; ctx.fillRect(cx - Rp * 2.6, cy - Rp * 2.6, Rp * 5.2, Rp * 5.2);
        // two thin beams, fading out: a hairline core in a soft band, like the sun's lens streak
        if (!done) {
          ctx.save(); ctx.translate(cx, cy); ctx.rotate(ang);
          const len = Rp * 4.4, bg = ctx.createLinearGradient(-len, 0, len, 0); bg.addColorStop(0, `rgba(${li},0)`); bg.addColorStop(.5, `rgba(${li},.5)`); bg.addColorStop(1, `rgba(${li},0)`);
          ctx.fillStyle = bg; ctx.fillRect(-len, -Math.max(.5, Rp * .045), len * 2, Math.max(1, Rp * .09));
          const wb = ctx.createLinearGradient(-len * .7, 0, len * .7, 0); wb.addColorStop(0, `rgba(${gl},0)`); wb.addColorStop(.5, `rgba(${gl},.14)`); wb.addColorStop(1, `rgba(${gl},0)`);
          ctx.fillStyle = wb; ctx.beginPath(); ctx.moveTo(-len * .7, 0); ctx.lineTo(0, -Rp * .32); ctx.lineTo(len * .7, 0); ctx.lineTo(0, Rp * .32); ctx.closePath(); ctx.fill();
          ctx.restore();
        }
        ctx.globalCompositeOperation = "source-over";
        const s = sphereCanvas(core, pulsarTex(L.id)(1), {emissive: true, limb: .5, spin: L.spin});
        ctx.globalAlpha = done ? .5 : 1; ctx.drawImage(s, cx - s.width / 2, cy - s.height / 2); ctx.globalAlpha = 1;
      } else {
        // the tail: a long faint fan of dust and a straighter, thinner ion tail, both away from the hole
        const len = Rp * 6;
        for (const [wid, a0, l] of [[.9, .2, 1], [.35, .32, .92]]) {
          ctx.save(); ctx.translate(cx, cy); ctx.rotate(ang);
          const tg = ctx.createLinearGradient(0, 0, len * l, 0); tg.addColorStop(0, `rgba(${li},${(a0 * k).toFixed(3)})`); tg.addColorStop(.35, `rgba(${gl},${(a0 * .45 * k).toFixed(3)})`); tg.addColorStop(1, `rgba(${gl},0)`);
          ctx.fillStyle = tg; ctx.beginPath(); ctx.moveTo(0, -Rp * .5); ctx.quadraticCurveTo(len * l * .5, -Rp * wid * 1.2, len * l, -Rp * wid * 1.6); ctx.lineTo(len * l, Rp * wid * .9); ctx.quadraticCurveTo(len * l * .5, Rp * wid * .5, 0, Rp * .5); ctx.closePath(); ctx.fill();
          ctx.restore();
        }
        // the coma, then the nucleus inside it
        const cm = ctx.createRadialGradient(cx, cy, 0, cx, cy, Rp * 1.9); cm.addColorStop(0, `rgba(${li},${(.75 * k).toFixed(3)})`); cm.addColorStop(.3, `rgba(${gl},${(.25 * k).toFixed(3)})`); cm.addColorStop(1, `rgba(${gl},0)`);
        ctx.fillStyle = cm; ctx.beginPath(); ctx.arc(cx, cy, Rp * 1.9, 0, TAU); ctx.fill();
        ctx.globalCompositeOperation = "source-over";
        const s = sphereCanvas(Math.max(1, Rp * .38), nucleusTex(L.id)(1), {L: lightVec(ang + Math.PI, .5), atmK: 0, dim: done ? .5 : 1});
        ctx.drawImage(s, cx - s.width / 2, cy - s.height / 2);
      }
    });
  }

  /* ---------- wormholes: one project worked on at two providers (D16) ----------
     wormhole(projectId, {colors: [a, b], state}) → look + .paint/.sprite/.svg(r, o) for one mouth + .link(x1, y1, x2, y2, o) for the bridge.
     A mouth is rendered per pixel like the black hole: a sphere that works as a lens. Inside it you see the other end's sky,
     squeezed toward the rim (a faint nebula in the other provider's colour, its stars and a far galaxy); on the rim a thin
     bright ring; just outside it a few stars of this side drawn out into arcs, and a faint haze in this provider's colour.
     o.side = 0 is provider a's end, 1 provider b's end. The same project id gives the same sky at both ends. */
  function wormhole(projectId, opts = {}) {
    const r = rnd("wormhole:" + projectId), cols = opts.colors || ["#e8916b", "#6fd3b8"];
    const L = {id: projectId, body: "wormhole", colors: cols, rot: r() * TAU, bend: between(r, .18, .32) * (r() < .5 ? -1 : 1), seed: Math.floor(r() * 1e6), gal: [between(r, -1.6, 1.6), between(r, -1.6, 1.6), between(r, .25, .45)]};
    L.extent = 1.7;
    const def = o => ({state: opts.state, ...o}), markR = R => R * 1.25 + 3;
    L.sprite = (R = 12, o = {}) => wormSprite(L, R, def(o));
    L.paint = (ctx, x, y, R = 12, o = {}) => {
      const oo = def(o), sc = (oo.dpr || 1) * (oo.ss || 1), Rs = Math.min(200 / sc, oo.bucket ? Math.pow(2, Math.ceil(Math.log2(Math.max(4, R * sc)))) / sc : R), s = L.sprite(Rs, oo), k = R / Rs / sc;
      ctx.drawImage(s.canvas, x - s.w * k / 2, y - s.h * k / 2, s.w * k, s.h * k);
      if (oo.mark !== false) mark(ctx, x, y, markR(R), oo.state, oo);
    };
    L.svg = (R = 12, o = {}) => {
      const oo = {dpr: 2, ...def(o)}, s = L.sprite(R, oo), sc = (oo.dpr || 1) * (oo.ss || 1), w = s.w / sc, h = s.h / sc;
      if (!s.url) s.url = s.canvas.toDataURL("image/png");
      return `<g class="og-wormhole"><image href="${s.url}" x="${f(-w / 2)}" y="${f(-h / 2)}" width="${f(w)}" height="${f(h)}"/>${oo.mark === false ? "" : markSVG(oo.state, markR(R), oo)}</g>`;
    };
    L.link = (x1, y1, x2, y2, o = {}) => renderWormLink(L, x1, y1, x2, y2, def(o));
    return L;
  }
  function wormSprite(L, R, o) {
    const sc = (o.dpr || 1) * (o.ss || 1), Rp = R * sc, side = o.side ? 1 : 0, done = o.state === "done", sp = q(o.spin || 0, .02);
    const half = Math.ceil(Rp * 1.75) + 2, key = `worm:${L.id}:${L.colors.join("")}:${Rp.toFixed(1)}:${side}:${done ? 1 : 0}:${sp}`;
    return sprite(key, half * 2, half * 2, ctx => {
      const near = C3(L.colors[side]), far = C3(L.colors[1 - side]), W = half * 2, img = ctx.createImageData(W, W), d = img.data, S = L.seed + side * 101;
      const mute = c => M3(c, [205, 205, 210], .25), farM = mute(far), nearM = mute(near), rimC = M3(M3(farM, nearM, .65), [255, 255, 255], .3), k = done ? .4 : 1;
      const ss = Rp < 30 ? 2 : 1, inv = 1 / ss, ringW = Math.max(.018, .7 / Rp), [gx, gy, gs] = L.gal;
      // the other end's sky at a point (sx, sy) of the far side: nebula, stars, a far galaxy
      const sky = (sx, sy, pix) => {
        const n = fbm(sx * .9 + 5, sy * .9, 2.2, S + 31, 4), n2 = fbm(sx * 2.6, sy * 2.6, 6.1, S + 37, 3);
        const nb = (.18 + .82 * SS(.3, .82, n)) * (.55 + .7 * n2) * .85;
        let R2 = 10 + farM[0] * nb, G2 = 10 + farM[1] * nb, B2 = 14 + farM[2] * nb;
        const cx = Math.floor(sx * 3), cy = Math.floor(sy * 3), h = hash3(cx, cy, 0, S), sz = Math.max(.05, pix * .9);
        if (h > .55) { const ox = (cx + hash3(cx, cy, 1, S)) / 3, oy = (cy + hash3(cx, cy, 2, S)) / 3, dd = Math.hypot(sx - ox, sy - oy), b = Math.exp(-Math.pow(dd / sz, 2)) * Math.pow((h - .55) / .45, 2) * 255 * Math.min(1, .06 / sz + .3); R2 += b; G2 += b; B2 += b * 1.02; }
        const gd = Math.hypot((sx - gx) / gs, (sy - gy) / (gs * .45)), gb = Math.exp(-gd * gd * 1.6) * 150 + Math.exp(-gd * gd * 26) * 230;
        R2 += gb * (.6 + .4 * farM[0] / 255); G2 += gb * (.6 + .4 * farM[1] / 255); B2 += gb * (.6 + .4 * farM[2] / 255);
        return [R2, G2, B2];
      };
      for (let py = 0; py < W; py++) for (let px = 0; px < W; px++) {
        let er = 0, eg = 0, eb = 0, ea = 0;
        for (let j = 0; j < ss; j++) for (let i = 0; i < ss; i++) {
          const x = (px + (i + .5) * inv - half) / Rp, y = (py + (j + .5) * inv - half) / Rp, r = Math.hypot(x, y);
          if (r > 1.72) continue;
          const th = Math.atan2(y, x) + L.rot + sp;
          let cr = 0, cg = 0, cb = 0, a = 0;
          if (r < 1) {
            // through the lens: the whole other sky, squeezed toward the rim
            const z = Math.sqrt(Math.max(0, 1 - r * r)), s = r / (z + .1), s2 = (r + 1 / Rp) / (Math.sqrt(Math.max(0, 1 - (r + 1 / Rp) ** 2)) + .1);
            const c = sky(Math.cos(th) * s * 1.6, Math.sin(th) * s * 1.6, (s2 - s) * 1.6);
            const shade = .7 + .5 * Math.pow(r, 5);
            cr = c[0] * shade; cg = c[1] * shade; cb = c[2] * shade;
            a = clamp((1 - r) * Rp * ss + .5);
          }
          // the rim: a thin ring of light where the two skies meet, and a fainter second one just outside
          const ring = Math.exp(-Math.pow((r - 1) / ringW, 2)) * .95 + Math.exp(-Math.pow((r - 1.09) / (ringW * 1.6), 2)) * .22;
          // this side's stars drawn out into short arcs round the mouth, and a faint haze
          let arcs = 0;
          if (r > 1.02) {
            const u = (th / TAU + 1) * 70, v = (r - 1) * 16, cu = Math.floor(u), cv = Math.floor(v), h = hash3(cu, cv, 3, S + 11);
            if (h > .86 && cv < 8) { const dv = v - cv - .5, du = u - cu - .5; arcs = Math.exp(-Math.pow(dv / .09, 2) - Math.pow(du / (.25 + .35 / (r - .9)), 2)) * (h - .86) / .14 * 1.4; }
          }
          const haze = Math.exp(-(r - 1) / .3) * (r > 1 ? .42 : 0);
          const add = [rimC[0] * ring + 235 * arcs + nearM[0] * haze, rimC[1] * ring + 235 * arcs + nearM[1] * haze, rimC[2] * ring + 240 * arcs + nearM[2] * haze];
          cr = cr * k + add[0] * k; cg = cg * k + add[1] * k; cb = cb * k + add[2] * k;
          a = Math.max(a, clamp(Math.max(cr, cg, cb) / 255 * 1.2));
          er += cr; eg += cg; eb += cb; ea += a;
        }
        const n = ss * ss, A = ea / n;
        if (A <= .003) continue;
        const ii = (py * W + px) * 4;
        d[ii] = Math.min(255, er / n / A); d[ii + 1] = Math.min(255, eg / n / A); d[ii + 2] = Math.min(255, eb / n / A); d[ii + 3] = 255 * Math.min(1, A);
      }
      ctx.putImageData(img, 0, 0);
    });
  }
  // the bridge: a hairline from one mouth to the other, dashed like a survey route, the colour turning from one provider to the other
  function renderWormLink(L, x1, y1, x2, y2, o) {
    const id = "og" + (++uid), done = o.state === "done", C = c => done ? dim(c) : mix(c, "#cfcfd4", .3), dx = x2 - x1, dy = y2 - y1, d = Math.hypot(dx, dy) || 1;
    const cx = (x1 + x2) / 2 - dy / d * d * L.bend, cy = (y1 + y2) / 2 + dx / d * d * L.bend;
    const path = `M${f(x1)},${f(y1)}Q${f(cx)},${f(cy)} ${f(x2)},${f(y2)}`;
    const defs = `<linearGradient id="${id}t" gradientUnits="userSpaceOnUse" x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}"><stop offset="0" stop-color="${C(L.colors[0])}"/><stop offset="1" stop-color="${C(L.colors[1])}"/></linearGradient>`;
    let s = `<path d="${path}" fill="none" stroke="url(#${id}t)" stroke-width="3" opacity=".07"/><path d="${path}" fill="none" stroke="url(#${id}t)" stroke-width="1" stroke-dasharray="2 5" opacity="${done ? .4 : .75}">${o.animate ? `<animate attributeName="stroke-dashoffset" values="0;-14" dur="1.6s" repeatCount="indefinite"/>` : ""}</path>`;
    // one small light on its way through
    const t = (.42 + (o.phase || 0)) % 1, u = 1 - t, px = u * u * x1 + 2 * u * t * cx + t * t * x2, py = u * u * y1 + 2 * u * t * cy + t * t * y2;
    if (!done) s += `<circle cx="${f(px)}" cy="${f(py)}" r="3.5" fill="#ffffff" opacity=".08"/><circle cx="${f(px)}" cy="${f(py)}" r="1.1" fill="#f4f4f6" opacity=".9"/>`;
    return `<g class="og-wormlink"><defs>${defs}</defs>${s}</g>`;
  }

  // a whole system drawn once on a canvas and handed back as an SVG <image> (w × h CSS px, origin top left)
  function systemSVG(sys, w, h, o = {}) {
    const dpr = o.dpr || 2, c = newCanvas(w * dpr, h * dpr), ctx = c.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); paintSystem(ctx, sys, {...o, dpr});
    return `<image href="${c.toDataURL("image/png")}" x="0" y="0" width="${w}" height="${h}"/>`;
  }
  /* the Starfield sky: warm grey space, a faint dust band, fine stars and a vignette (prototype skin) */
  function paintSky(ctx, w, h, seed = 31, o = {}) {
    const base = ctx.createRadialGradient(w * .6, h * .5, 50, w * .6, h * .5, Math.max(w, h) * .75); base.addColorStop(0, "#161514"); base.addColorStop(1, "#0a0a0a");
    ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
    let s = seed; const rr = () => (s = (s * 16807) % 2147483647) / 2147483647;
    for (let i = 0; i < Math.round(26 * w * h / 1e6) + 8; i++) {
      const u = rr(), x = -100 + u * (w + 200), y = h * .9 - u * h * .75 + (rr() - .5) * 220, r = 80 + rr() * 220;
      const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, `rgba(${110 + rr() * 30 | 0},${98 + rr() * 20 | 0},${86 + rr() * 16 | 0},${(.035 + rr() * .03).toFixed(3)})`); g.addColorStop(1, "rgba(100,90,80,0)");
      ctx.fillStyle = g; ctx.fillRect(x - r, y - r, r * 2, r * 2);
    }
    for (let n = 0; n < Math.round(650 * w * h / 1e6); n++) {
      const x = rr() * w, y = rr() * h, m = rr();
      ctx.fillStyle = `rgba(${m > .7 ? "235,228,215" : "205,205,205"},${(.12 + Math.pow(rr(), 2) * .55).toFixed(2)})`;
      ctx.beginPath(); ctx.arc(x, y, m > .985 ? 1.1 : .35 + rr() * .35, 0, TAU); ctx.fill();
    }
    if (o.vignette !== false) { const vg = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * .45, w / 2, h / 2, Math.max(w, h) * .8); vg.addColorStop(0, "rgba(0,0,0,0)"); vg.addColorStop(1, "rgba(0,0,0,.5)"); ctx.fillStyle = vg; ctx.fillRect(0, 0, w, h); }
  }
  function skySVG(w, h, seed, o = {}) { const dpr = o.dpr || 1, c = newCanvas(w * dpr, h * dpr), ctx = c.getContext("2d"); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); paintSky(ctx, w, h, seed, o); return `<image href="${c.toDataURL("image/jpeg", .92)}" x="0" y="0" width="${w}" height="${h}"/>`; }

  window.OrbitGen = {systemSVG, paintSky, skySVG, star, planet, moon, galaxy, blackHole, infra, wormhole, paintSystem, tag, mark, markSVG, ROMAN, MONO,
    KINDS, PAL, ROLE_KINDS, MOON_TYPES, STAR_CLASSES, STAR_SIZES, GAL_SHAPES, STATE: {waiting: WAIT, stuck: STUCK}};
})();
