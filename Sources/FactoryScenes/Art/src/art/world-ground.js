/* Ground and buildings for the campus (Spel+, D80), from the world artist's ground.js and build.js, painted by
   world-kit.js: a tile map (void, grass, road, walk, path, plaza, water, …) painted by a layout, turned into a heightfield
   with kerbs and banks, an island underside of stepped rock columns with strata, roots and vines; doors with steps and a
   canopy, roof gear, and facades with depth (recessed windows, sills, lintels). */
(function () {
  const K = window.WorldKit, Pr = window.Props, P = K.P, shade = K.shade, tint = K.tint, rnd = Pr.rnd;
  const G = {}, Bd = {};

  G.map = function (NI, NJ) {
    const m = {NI, NJ, t: [], meta: []};
    for (let i = 0; i < NI; i++) { m.t[i] = []; m.meta[i] = []; for (let j = 0; j < NJ; j++) { m.t[i][j] = "void"; m.meta[i][j] = {}; } }
    m.get = (i, j) => (i >= 0 && j >= 0 && i < NI && j < NJ) ? m.t[i][j] : "void";
    m.set = (i, j, v, meta) => { if (i >= 0 && j >= 0 && i < NI && j < NJ) { m.t[i][j] = v; if (meta) Object.assign(m.meta[i][j], meta); } };
    m.rect = (i0, j0, i1, j1, v, meta, onlyOn) => { for (let i = Math.floor(i0); i < i1; i++) for (let j = Math.floor(j0); j < j1; j++) if (!onlyOn || onlyOn.includes(m.get(i, j))) m.set(i, j, v, meta ? (typeof meta === "function" ? meta(i, j) : meta) : null); };
    m.disc = (ci, cj, ri, rj, v, onlyOn) => { for (let i = Math.floor(ci - ri - 1); i <= ci + ri + 1; i++) for (let j = Math.floor(cj - rj - 1); j <= cj + rj + 1; j++) { const a = (i + .5 - ci) / ri, b = (j + .5 - cj) / rj; if (a * a + b * b <= 1 && (!onlyOn || onlyOn.includes(m.get(i, j)))) m.set(i, j, v); } };
    m.each = fn => { for (let i = 0; i < NI; i++) for (let j = 0; j < NJ; j++) fn(i, j, m.t[i][j], m.meta[i][j]); };
    return m;
  };
  /* an island shape: a rounded rectangle with a wobbly coast */
  G.island = function (m, o = {}) {
    const {NI, NJ} = m, r = o.round || 6, wob = o.wobble || 0, rr = rnd("isl" + NI);
    const noise = []; for (let k = 0; k < 400; k++) noise.push(rr());
    m.each((i, j) => {
      const ci = Math.min(i + .5, NI - i - .5), cj = Math.min(j + .5, NJ - j - .5);
      let inside = true;
      if (ci < r && cj < r) inside = Math.hypot(r - ci, r - cj) <= r;
      const n = wob ? Math.floor(noise[(i * 7 + j * 13) % 400] * wob) : 0;
      if (Math.min(ci, cj) < n + .5) inside = false;
      if (o.cut && o.cut(i, j)) inside = false;
      if (inside) m.set(i, j, "grass");
    });
  };
  /* a road along i or j with walks either side; ends: an array of 'loop' etc. handled by the layout */
  G.road = function (m, axis, at, from, to, o = {}) {
    const rw = o.rw || 4, sw = o.sw || 2;
    for (let a = from; a < to; a++) for (let k = -sw; k < rw + sw; k++) {
      const [i, j] = axis === "i" ? [a, at + k] : [at + k, a];
      if (m.get(i, j) === "void" && !o.overVoid) continue;
      if (k < 0 || k >= rw) { if (m.get(i, j) !== "road") m.set(i, j, "walk"); }
      else m.set(i, j, "road", {axis, k, rw, a});
    }
  };
  G.crossing = function (m, axis, at, a0, rw = 4) { // zebra across a road running along `axis`, at road start `at`, over tiles a0..a0+1
    for (let k = 0; k < rw; k++) for (let a = a0; a < a0 + 2; a++) { const [i, j] = axis === "i" ? [a, at + k] : [at + k, a]; if (m.get(i, j) === "road") m.meta[i][j].zebra = axis; }
  };

  /* the terrain from the map, with a theme of colours */
  G.terrain = function (W, m, th) {
    const r = rnd("terr" + m.NI);
    const H = {grass: 1, walk: 1.6, road: -1.4, path: 1.15, plaza: 1.8, water: -5, soil: 1.2, lot: 1.3, court: 1.7, deck: 2.2, yard: 1.6, sand: 1};
    W.terrain(m.NI, m.NJ, (i, j) => {
      const t = m.t[i][j], mt = m.meta[i][j];
      if (t === "void") return null;
      const deco = [];
      let c, side, kerb;
      if (t === "grass") {
        c = (i * 7 + j * 3) % 5 ? th.grass[0] : th.grass[1];
        if ((i * 13 + j * 7) % 3 === 0) deco.push([i + .2 + r() * .5, j + .2 + r() * .5, 0, 0, th.grassDark || shade(c, .92)]);
        if ((i * 31 + j * 17) % 13 === 0) { const a = i + .25 + r() * .5, b = j + .25 + r() * .5; deco.push([a, b, a + .1, b + .1, th.flowers[(i + j) % th.flowers.length]]); }
        deco.forEach(d => { if (d[2] === 0) { d[2] = d[0] + .14; d[3] = d[1] + .08; } });
      } else if (t === "walk") {
        c = th.walk; kerb = th.kerb; side = th.kerbSide || "#8e8678";
        deco.push([i, j, i + .025, j + 1, th.joint], [i, j, i + 1, j + .025, th.joint]);
        if ((i * 5 + j * 3) % 7 === 0) deco.push([i + .5, j, i + .525, j + 1, th.joint]);
      } else if (t === "road") {
        c = th.road;
        const ax = mt.axis, k = mt.k, rw = mt.rw;
        if (mt.zebra) {
          // stripes parallel to the road, across it
          for (let q = 0; q < 2; q++) { const s = .1 + q * .5; if (mt.zebra === "i") deco.push([i + .05, j + s, i + .95, j + s + .26, th.line]); else deco.push([i + s, j + .05, i + s + .26, j + .95, th.line]); }
        } else if (!mt.junction) {
          if (k === rw / 2 - 1 || k === rw / 2) { // centre line on the edge between the two middle lanes
            const dash = (mt.a % 3) !== 2;
            if (dash) { if (ax === "i") deco.push(k === rw / 2 - 1 ? [i + .1, j + .94, i + .9, j + 1, th.line] : [i + .1, j, i + .9, j + .06, th.line]); else deco.push(k === rw / 2 - 1 ? [i + .94, j + .1, i + 1, j + .9, th.line] : [i, j + .1, i + .06, j + .9, th.line]); }
          }
          if ((i * 17 + j * 5) % 11 === 0) deco.push([i + .3, j + .4, i + .42, j + .5, shade(th.road, .9)]);
        }
        if (mt.arrow) deco.push(...mt.arrow);
      } else if (t === "path") {
        c = th.path; side = shade(th.path, .9);
        if ((i * 11 + j * 7) % 3 === 0) deco.push([i + .3, j + .2, i + .4, j + .3, shade(th.path, .86)], [i + .7, j + .6, i + .78, j + .68, tint(th.path, .2)]);
      } else if (t === "plaza") {
        c = (i + j) % 2 ? th.plaza[0] : th.plaza[1]; kerb = th.kerb;
        if (mt.inlay) c = mt.inlay;
        deco.push([i, j, i + .02, j + 1, shade(c, .9)], [i, j, i + 1, j + .02, shade(c, .9)]);
      } else if (t === "water") { c = th.waterBed || "#2a4a5a"; side = th.bank || "#6a5a4a"; }
      else if (t === "soil") { c = "#5a3e2a"; for (let q = 0; q < 3; q++) deco.push([i + .1, j + .15 + q * .3, i + .9, j + .2 + q * .3, "#4a3222"]); }
      else if (t === "lot") { c = th.lot || "#b49a72"; deco.push([i + .2, j + .3, i + .3, j + .4, shade(c, .85)]); }
      else if (t === "court") { c = mt.c || th.court || "#c97a5a"; }
      else if (t === "deck") { c = th.deck || "#a8743a"; deco.push([i, j + .24, i + 1, j + .27, shade(c, .8)], [i, j + .49, i + 1, j + .52, shade(c, .8)], [i, j + .74, i + 1, j + .77, shade(c, .8)]); }
      else if (t === "yard") { c = (i + j) % 2 ? th.yard[0] : th.yard[1]; deco.push([i, j, i + .02, j + 1, shade(c, .85)], [i, j, i + 1, j + .02, shade(c, .85)]); }
      else if (t === "sand") { c = th.sand || "#e2cf9a"; }
      const h = mt.h != null ? mt.h : H[t];
      if (t !== "water" && (m.get(i, j + 1) === "water" || m.get(i + 1, j) === "water")) side = th.bank || "#7a6248";
      // where grass meets the island edge it has a lip; the edge itself is earth with a few stones
      const hsh = (i * 73 + j * 151) % 97, ed = [];
      if (hsh % 3 === 0) ed.push([.1 + (hsh % 7) * .1, -4 - (hsh % 5), .3 + (hsh % 7) * .1, -2.6 - (hsh % 3), "#6e4c30"]);
      if (hsh % 4 === 1) ed.push([.05 + (hsh % 5) * .15, -9 - (hsh % 4), .2 + (hsh % 5) * .15, -7 - (hsh % 3), "#a07a52"]);
      if (hsh % 5 === 2) ed.push([.3 + (hsh % 4) * .1, -6, .38 + (hsh % 4) * .1, -5.2, "#8a8076"]);
      return {h, c, side: side || shade(c, .9), kerb, deco, edge: th.edge, lip: th.grass[0], edgeDecoF: ed, edgeDecoR: ed};
    }, {base: -12});
  };

  /* the underside: columns that hang deeper towards the middle, rock strata, roots */
  G.underside = function (W, m, th, o = {}) {
    const {NI, NJ} = m, dist = [], q = [];
    for (let i = 0; i < NI; i++) { dist[i] = []; for (let j = 0; j < NJ; j++) { dist[i][j] = m.t[i][j] === "void" ? -1 : 1e9; } }
    for (let i = 0; i < NI; i++) for (let j = 0; j < NJ; j++) if (dist[i][j] > 0) { const edge = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([a, b]) => m.get(i + a, j + b) === "void"); if (edge) { dist[i][j] = 0; q.push([i, j]); } }
    while (q.length) { const [i, j] = q.shift(); for (const [a, b] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const x = i + a, y = j + b; if (x >= 0 && y >= 0 && x < NI && y < NJ && dist[x][y] > dist[i][j] + 1) { dist[x][y] = dist[i][j] + 1; q.push([x, y]); } } }
    const r = rnd("und" + NI), cols = [], crystals = [];
    const maxD = o.maxD || 260, step = o.step || 6;
    for (let i = 0; i < NI; i++) for (let j = 0; j < NJ; j++) {
      const dd = dist[i][j];
      if (dd < 0) continue;
      let d = 12 + (o.lin ? dd * o.lin : Math.sqrt(dd) * (o.k || 34)) + r() * 16;
      for (const [ci, cj, cr, ch] of o.spikes || []) { const e = Math.hypot(i - ci, j - cj); if (e < cr) d += ch * (1 - e / cr) * (1 - e / cr); }
      d = Math.min(maxD, Math.round(d / step) * step);
      const extra = []; const c = {}; 
      if (dd <= 1 && r() < .2) { const f2 = m.get(i, j + 1) === "void" ? "front" : "right", base0 = (f2 === "front" ? i : j); let a = base0 + .15 + r() * .6, z = -12; const segs = 2 + Math.floor(r() * 3), col = ["#5e3e28", "#6e4a30", "#4e3420"][Math.floor(r() * 3)];
        for (let q = 0; q < segs; q++) { const L = 3 + r() * 7, w = .05 + r() * .06; extra.push({f: f2, r: [a, z - L, a + w, z, col]}); z -= L; a = Math.min(base0 + .9, Math.max(base0 + .05, a + (r() < .5 ? -.08 : .08))); } }
      if (o.vines && dd <= 1 && r() < .3) { const a = (m.get(i, j + 1) === "void" ? i : j) + .15 + r() * .6, L = 18 + r() * 34, f2 = m.get(i, j + 1) === "void" ? "front" : "right"; extra.push({f: f2, r: [a, -12 - L, a + .07, -10, o.vines]}); for (let q = 6; q < L; q += 7) extra.push({f: f2, r: [a - .06, -12 - q, a + .13, -12 - q + 2, q % 14 ? o.vines : "!#ff8ac8"]}); }
      if (r() < .12) { const a = .2 + r() * .5, zz = -24 - r() * Math.max(10, d - 30); extra.push({f: "front", r: [i + a, zz, i + a + .22, zz + 2.4, th.stone || "#7a6a78"]}); }
      cols.push({i, j, d, extra});
    }
    W.underside(cols, th.strata, -12);
    return dist;
  };

  /* a small floating islet: grass top, a stepped rock underside; its ops, back to front */
  G.islet = function (ci, cj, z, rad, th, dress) {
    const W = new K.World();
    const n = Math.ceil(rad) + 1, ii = Math.floor(ci - n), jj = Math.floor(cj - n);
    const mask = (i, j) => Math.hypot(i + .5 - ci, (j + .5 - cj) * 1.1) <= rad;
    const cols = [];
    for (let i = ii; i < ci + n; i++) for (let j = jj; j < cj + n; j++) if (mask(i, j)) { const e = rad - Math.hypot(i + .5 - ci, (j + .5 - cj) * 1.1); cols.push({i, j, d: Math.round((14 + e * 42 + ((i * 7 + j * 3) % 3) * 6) / 6) * 6}); }
    W.underside(cols, th.strata.map(([zz, c]) => [zz + z, c]), z - 10);
    W.terrain(2 * n + 2, 2 * n + 2, (i, j) => (mask(i, j)) ? {h: z, c: (i + j) % 3 ? th.grass[0] : th.grass[1], edge: th.edge, lip: th.grass[0]} : null, {base: z - 10, i0: ii, j0: jj});
    if (dress) dress(W);
    const ops = [...W.under, ...W.base];
    for (const it of K.World.sortItems(W.items)) for (const q of it.ops) ops.push(q);
    return {ops, halos: W.halos};
  };

  /* a door on the front (+y) or right (+x) face of a box: a recessed double door, steps and a canopy */
  Bd.door = function (W, face, a, at, z, o = {}) {
    // a: centre along the face; at: the face plane (j1 for front, i1 for right)
    const w = o.w || 1.3, h = o.h || 36, col = o.col || "#2a2433", glass = o.glass || "#9fd0ff", can = o.canopy || "#2a2433";
    if (face === "front") {
      W.box(a - w / 2 - .12, at - .06, z, a + w / 2 + .12, at + .02, z + h + 3, col, {deco: {front: [[a - w / 2, z + 1, a - .03, z + h, "!" + glass], [a + .03, z + 1, a + w / 2, z + h, "!" + glass], [a - .2, z + 15, a - .1, z + 18, "#c9a46a"], [a + .1, z + 15, a + .2, z + 18, "#c9a46a"], [a - w / 2, z + h * .55, a + w / 2, z + h * .55 + .8, col]]}});
      if (o.steps !== false) W.box(a - w / 2 - .3, at, z, a + w / 2 + .3, at + .5, z + 1.6, o.step || "#c9c0b0");
      if (o.canopy !== false) W.box(a - w / 2 - .4, at, z + h + 4, a + w / 2 + .4, at + (o.depth || 1.1), z + h + 6.6, can, {deco: {front: o.canText ? [] : [[a - w / 2 - .4, z + h + 4, a + w / 2 + .4, z + h + 4.8, shade(can, .8)]]}, text: o.canText ? [{f: "front", a, z: z + h + 4.5, t: o.canText, s: 2.2, c: o.canInk || "!#fff3d6", wt: 700, font: o.font, ls: .3}] : []});
      if (o.lamps !== false) for (const s of [-1, 1]) { const x = a + s * (w / 2 + .45); W.box(x - .1, at, z + 26, x + .1, at + .18, z + 31, "#ffe2a8", {deco: {front: [[x - .1, z + 26, x + .1, z + 26.8, "#2a2433"]]}}); W.halo(x, at + .2, z + 28.5, 9, "#ffd9a0", .6); }
      W.pool(a, at + .9, z, 46, o.light || "#ffd9a0", .55);
    } else {
      W.box(at - .02, a - w / 2 - .12, z, at + .06, a + w / 2 + .12, z + h + 3, col, {deco: {right: [[a - w / 2, z + 1, a - .03, z + h, "!" + glass], [a + .03, z + 1, a + w / 2, z + h, "!" + glass], [a - .2, z + 15, a - .1, z + 18, "#c9a46a"], [a + .1, z + 15, a + .2, z + 18, "#c9a46a"], [a - w / 2, z + h * .55, a + w / 2, z + h * .55 + .8, col]]}});
      if (o.steps !== false) W.box(at, a - w / 2 - .3, z, at + .5, a + w / 2 + .3, z + 1.6, o.step || "#c9c0b0");
      if (o.canopy !== false) W.box(at, a - w / 2 - .4, z + h + 4, at + (o.depth || 1.1), a + w / 2 + .4, z + h + 6.6, can, {deco: {right: [[a - w / 2 - .4, z + h + 4, a + w / 2 + .4, z + h + 4.8, shade(can, .8)]]}, text: o.canText ? [{f: "right", a, z: z + h + 4.5, t: o.canText, s: 2.2, c: o.canInk || "!#fff3d6", wt: 700, font: o.font}] : []});
      if (o.lamps !== false) for (const s of [-1, 1]) { const y = a + s * (w / 2 + .45); W.box(at, y - .1, z + 26, at + .18, y + .1, z + 31, "#ffe2a8", {deco: {right: [[y - .1, z + 26, y + .1, z + 26.8, "#2a2433"]]}}); W.halo(at + .2, y, z + 28.5, 9, "#ffd9a0", .6); }
      W.pool(at + .9, a, z, 46, o.light || "#ffd9a0", .55);
    }
  };

  /* roof gear: AC units, a water tank, a vent */
  Bd.ac = (W, i, j, z) => { W.box(i, j, z, i + 1, j + .8, z + 7, "#9aa3b4", {deco: {top: [[i + .2, j + .15, i + .8, j + .65, "#5d6178"]], front: [[i + .1, z + 1, i + .9, z + 1.5, "#7a8090"], [i + .1, z + 3, i + .9, z + 3.5, "#7a8090"], [i + .1, z + 5, i + .9, z + 5.5, "#7a8090"]]}}); };
  Bd.tank = (W, i, j, z) => { for (const [a, b] of [[i, j], [i + .9, j], [i, j + .9], [i + .9, j + .9]]) W.box(a, b, z, a + .1, b + .1, z + 9, "#5a4a3a"); W.box(i - .05, j - .05, z + 9, i + 1.05, j + 1.05, z + 22, "#8a6a4a", {deco: {front: [[i - .05, z + 12, i + 1.05, z + 12.8, "#5a4a3a"], [i - .05, z + 18, i + 1.05, z + 18.8, "#5a4a3a"]], right: [[j - .05, z + 12, j + 1.05, z + 12.8, "#5a4a3a"], [j - .05, z + 18, j + 1.05, z + 18.8, "#5a4a3a"]]}}); W.box(i + .1, j + .1, z + 22, i + .95, j + .95, z + 25, "#6a5a4a"); };
  Bd.solar = (W, i0, j0, i1, j1, z) => { W.box(i0, j0, z, i1, j1, z + 3, "#2a3a6a", {deco: {top: Array.from({length: Math.round((i1 - i0) / .5)}, (_, k) => [i0 + k * .5 + .02, j0, i0 + k * .5 + .05, j1, "#9ab4e8"]).concat([[i0, (j0 + j1) / 2 - .02, i1, (j0 + j1) / 2 + .02, "#9ab4e8"]])}}); };

  /* a facade with depth along one face: the wall sits back by r, piers and spandrels stand at the face, every window
     gets a sill below and a lintel above. face 'front' runs along i at j = at, 'right' along j at i = at.
     wins: [[a0, a1], ...] window spans along the face; zw0..zw1 the glass; glass: decals for the glass per window */
  Bd.deepWall = function (W, face, a0, a1, at, z0, z1, wins, zw0, zw1, o) {
    const r = o.r || .16, col = o.col, frame = o.frame, sill = o.sill || o.trim, B = (a, b, za, zb, c, opt) => face === "front" ? W.box(a, at - r, za, b, at, zb, c, opt) : W.box(at - r, a, za, at, b, zb, c, opt);
    wins = wins.slice().sort((p, q) => p[0] - q[0]);
    // the recessed back wall with the glass on it
    const glass = [];
    for (const [w0, w1] of wins) for (const g of o.glass(w0, w1)) glass.push(g);
    if (face === "front") W.box(a0, at - r - .3, z0, a1, at - r, z1, col, {deco: {front: glass}});
    else W.box(at - r - .3, a0, z0, at - r, a1, z1, col, {deco: {right: glass}});
    // spandrels below and above the windows, piers between them (the reveals are their side faces)
    if (o.door) { B(a0, o.door[0], z0, zw0, col); B(o.door[1], a1, z0, zw0, col); } else B(a0, a1, z0, zw0, col);
    B(a0, a1, zw1, z1, col);
    let prev = a0;
    for (const [w0, w1] of wins) { if (w0 - prev > .01) B(prev, w0, zw0, zw1, col); prev = w1; }
    if (a1 - prev > .01) B(prev, a1, zw0, zw1, col);
    // sills that stick out, lintels flush with a darker band, a frame line inside each reveal
    for (const [w0, w1] of wins) {
      if (o.door && Math.abs(w0 - o.door[0]) < .01) continue;
      if (face === "front") { W.box(w0 - .06, at, zw0 - 1.4, w1 + .06, at + .14, zw0, sill); W.box(w0, at - r, zw1, w1, at - r + .02, zw1 + .01, frame); W.box(w0 - .04, at, zw1, w1 + .04, at + .05, zw1 + 1.6, o.lintel || K.shade(col, .82)); }
      else { W.box(at, w0 - .06, zw0 - 1.4, at + .14, w1 + .06, zw0, sill); W.box(at, w0 - .04, zw1, at + .05, w1 + .04, zw1 + 1.6, o.lintel || K.shade(col, .82)); }
    }
  };

  window.Ground = G;
  window.Build = Bd;
})();
