/* The world kit (Spel+, D80): the blocky engine (blocky-cast.js) grown into a scene builder, ported from the world
   artist's standalone kit (assets/ux-spelplus/world/kit.js) to paint straight onto a canvas. Same projection
   (x = (i - j)·16, y = (i + j)·8 − z·1.08), the same one warm light (or moonlight, with window.__NIGHT), cool shadows.
   Every box is a sortable item that holds draw ops; items are ordered by a topological sort on their 3D boxes, so big
   and small things interleave correctly. Ground is a heightfield: kerbs, banks and island edges come from height steps.

   Draw ops (arrays, so a whole campus stays light):
     ["p", [x0, y0, x1, y1, …], fill, alpha|null, seam]       a polygon; seam > 0 strokes it in its own colour
     ["e", cx, cy, rx, ry, fill|null, stroke|null, width, alpha] an ellipse
     ["g", cx, cy, rx, ry, colour, alpha]                       a soft glow (radial gradient)
     ["l", x0, y0, x1, y1, stroke, width, dash|null, alpha]     a line
     ["t", [a, b, c, d, e, f], text, font, size, weight, anchor, fill, stroke|null, strokeWidth, alpha] text on a face */
(function () {
  const B = window.BlockyCast, E = B.engine, T = 16;
  const lit = (c, n) => E.lit(c, n);
  const PX = (x, y, z) => [x - y, (x + y) * .5 - z * 1.08];
  const P = (i, j, z = 0) => PX(i * T, j * T, z);
  const NRM = {top: [0, 0, 1], front: [0, 1, 0], right: [1, 0, 0]};
  const paint = (c, face) => c[0] === "!" ? c.slice(1) : lit(c, NRM[face]);
  const flat = pts => { const a = new Array(pts.length * 2); for (let k = 0; k < pts.length; k++) { a[2 * k] = pts[k][0]; a[2 * k + 1] = pts[k][1]; } return a; };
  const poly = (pts, fill, alpha = null, seam = 0) => ["p", flat(pts), fill, alpha, seam];
  /* the faces the app paints in: no web fonts load in the art engine */
  const FONTS = {game: "'Arial Black', 'Avenir Next', Helvetica, sans-serif", text: "'Avenir Next', 'Helvetica Neue', Helvetica, sans-serif", mono: "Menlo, monospace"};

  let _m = null;
  const measure = (t, s, font = FONTS.text, wt = 600, ls = 0) => { try { _m = _m || document.createElement("canvas").getContext("2d"); _m.font = `${wt} ${s * 10}px ${font}`; const w = _m.measureText(t).width; if (w > 0) return w / 10 + ls * t.length; } catch (e) {} return t.length * s * .6 + ls * t.length; };

  function World() {
    this.items = []; this.base = []; this.shadowP = []; this.pools = []; this.halos = []; this.over = []; this.water = []; this.under = [];
    this.anchors = {};
  }
  const W = World.prototype;
  W.P = P;

  /* face text: {f: 'front'|'right'|'top', a, b (top only), z, t, s, c, anchor, font, wt, stroke, sw, op} */
  function faceText(box, tx) {
    const [, , , i1, j1, z1] = box;
    let at, m;
    if (tx.f === "front") { at = P(tx.a, j1 + .004, tx.z); m = [1, .5, 0, 1.08]; }
    else if (tx.f === "right") { at = P(i1 + .004, tx.a, tx.z); m = [1, -.5, 0, 1.08]; }
    else { at = P(tx.a, tx.b, z1 + .05); m = tx.dir === "-j" ? [1, -.5, 1, .5] : [1, .5, -1, .5]; }
    const fill = tx.c ? paint(tx.c, tx.f) : "#2a1a2e";
    // text is drawn upright in its own space: y up the face is -y on the canvas, so the matrix flips v
    return ["t", [m[0], m[1], m[2], m[3], at[0], at[1]], String(tx.t), tx.font || FONTS.text, tx.s || 8, tx.wt || 700, tx.anchor || "middle", fill, tx.stroke || null, tx.sw || 1, tx.op != null ? tx.op : null];
  }

  /* the faces of one box as ops; coordinates in tiles (i, j) and units (z) */
  function boxOps(i0, j0, z0, i1, j1, z1, col, o = {}) {
    const C = typeof col === "string" ? {top: col, front: col, right: col} : {top: col.top || col.base || col.side, front: col.front || col.side || col.base, right: col.right || col.side || col.base};
    const op = o.opacity != null ? o.opacity : null;
    const seam = o.opacity != null || o.noStroke ? 0 : (o.seam || .3);
    const hide = o.hide || [];
    const faces = {
      right: hide.includes("right") ? null : [P(i1, j1, z0), P(i1, j0, z0), P(i1, j0, z1), P(i1, j1, z1)],
      front: hide.includes("front") ? null : [P(i0, j1, z0), P(i1, j1, z0), P(i1, j1, z1), P(i0, j1, z1)],
      top: hide.includes("top") ? null : [P(i0, j0, z1), P(i1, j0, z1), P(i1, j1, z1), P(i0, j1, z1)]
    };
    const D = o.deco || {}, out = [];
    for (const name of ["right", "front", "top"]) {
      const pts = faces[name];
      if (!pts) continue;
      const fill = paint(C[name], name);
      out.push(poly(pts, fill, op, seam));
      for (const d of D[name] || []) {
        if (d.p) {
          const pp = d.p.map(([a, b]) => name === "front" ? P(a, j1 + .003, b) : name === "right" ? P(i1 + .003, a, b) : P(a, b, z1 + .03));
          out.push(poly(pp, paint(d.c, name), d.op != null ? d.op : null));
          continue;
        }
        const [a0, b0, a1, b1, c, dop] = d;
        let pp;
        if (name === "front") pp = [P(a0, j1 + .003, b0), P(a1, j1 + .003, b0), P(a1, j1 + .003, b1), P(a0, j1 + .003, b1)];
        else if (name === "right") pp = [P(i1 + .003, a0, b0), P(i1 + .003, a1, b0), P(i1 + .003, a1, b1), P(i1 + .003, a0, b1)];
        else pp = [P(a0, b0, z1 + .03), P(a1, b0, z1 + .03), P(a1, b1, z1 + .03), P(a0, b1, z1 + .03)];
        out.push(poly(pp, paint(c, name), dop != null ? dop : null, dop == null && o.seam ? o.seam : 0));
      }
    }
    for (const tx of o.text || []) out.push(faceText([i0, j0, z0, i1, j1, z1], tx));
    return out;
  }
  World.boxOps = boxOps;

  const sbOf = b => { // screen bbox of a model-unit AABB
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (const x of [b[0], b[3]]) for (const y of [b[1], b[4]]) for (const z of [b[2], b[5]]) { const p = PX(x, y, z); x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]); y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); }
    return [x0, y0, x1, y1];
  };
  World.sbOf = sbOf;

  /* a box as an item; returns the item */
  W.box = function (i0, j0, z0, i1, j1, z1, col, o = {}) {
    if (i1 < i0) [i0, i1] = [i1, i0];
    if (j1 < j0) [j0, j1] = [j1, j0];
    const it = {b: [i0 * T, j0 * T, z0, i1 * T, j1 * T, z1], ops: boxOps(i0, j0, z0, i1, j1, z1, col, o), bias: o.bias || 0};
    it.sb = sbOf(it.b);
    (o.into || this.items).push(it);
    if (o.shadow) this.shadow(i0, j0, i1, j1, z1 - z0, z0, o.shadow === true ? 1 : o.shadow);
    return it;
  };
  /* raw ops with an explicit model-space AABB (tiles for x/y, units for z) */
  W.raw = function (ops, i0, j0, z0, i1, j1, z1, o = {}) {
    const it = {b: [i0 * T, j0 * T, z0, i1 * T, j1 * T, z1], ops, bias: o.bias || 0};
    it.sb = o.sb || sbOf(it.b);
    this.items.push(it);
    return it;
  };
  /* what a sub-world adds besides its items goes up to this one */
  W.adopt = function (sub) {
    this.shadowP.push(...sub.shadowP); this.pools.push(...sub.pools); this.halos.push(...sub.halos); this.over.push(...sub.over); this.water.push(...sub.water);
    Object.assign(this.anchors, sub.anchors);
  };
  /* a group: drawn by fn into its own world, sorted inside, one item outside */
  W.group = function (fn, o = {}) {
    const sub = new World();
    fn(sub);
    const it = World.merge(sub);
    if (o.b) it.b = [o.b[0] * T, o.b[1] * T, o.b[2], o.b[3] * T, o.b[4] * T, o.b[5]];
    it.bias = o.bias || 0;
    this.items.push(it);
    this.adopt(sub);
    return it;
  };
  /* a sub-world's items, sorted, as one item */
  World.merge = function (sub) {
    const order = sortItems(sub.items);
    let x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9;
    for (const it of sub.items) { x0 = Math.min(x0, it.b[0]); y0 = Math.min(y0, it.b[1]); z0 = Math.min(z0, it.b[2]); x1 = Math.max(x1, it.b[3]); y1 = Math.max(y1, it.b[4]); z1 = Math.max(z1, it.b[5]); }
    const ops = [];
    for (const t of order) for (const q of t.ops) ops.push(q);
    const it = {b: [x0, y0, z0, x1, y1, z1], ops, bias: 0};
    it.sb = sub.items.length ? sub.items.reduce((s, q) => [Math.min(s[0], q.sb[0]), Math.min(s[1], q.sb[1]), Math.max(s[2], q.sb[2]), Math.max(s[3], q.sb[3])], [1e9, 1e9, -1e9, -1e9]) : [0, 0, 0, 0];
    return it;
  };
  /* a person (BlockyCast) standing with their feet at tile (i, j), height z */
  W.fig = function (who, o = {}, i, j, z = 0) {
    const sc = new E.Scene(1), at = [i * T, j * T, z];
    const C = typeof who === "string" ? B.CAST[who] : who;
    B.figureInto(sc, C, {pose: o.pose || "idle", view: o.view || "SW", mood: o.mood || "calm", seat: o.seat || 0, noProp: o.noProp}, at);
    const sit = ["sit", "type", "typeB", "snooze"].includes(o.pose);
    let ext = [-.42, -.42, .42, .42];
    if (sit) { const v = o.view || "SW"; if (v === "SW") ext[3] = .9; if (v === "SE") ext[2] = .9; if (v === "NE") ext[1] = -.9; if (v === "NW") ext[0] = -.9; }
    const zb = o.zb != null ? o.zb : z;
    const it = {b: [(i + ext[0]) * T, (j + ext[1]) * T, zb, (i + ext[2]) * T, (j + ext[3]) * T, z + 36], ops: World.sceneOps(sc), bias: o.bias || 0, fig: o.name || "p@" + i.toFixed(1) + "," + j.toFixed(1), at: [i, j, z]};
    it.sb = sbOf(it.b);
    it.sb = [it.sb[0] - 8, it.sb[1] - 10, it.sb[2] + 8, it.sb[3] + 4];
    this.items.push(it);
    if (!o.noShadow && !sit) this.shadowP.push(poly([[-6, -5], [6, -5], [6, 5], [-6, 5]].map(([x, y]) => PX(at[0] + x * 1.1, at[1] + y * 1.1, z)), "#140c22"));
    return {item: it, head: P(i, j, z + (sit ? 26 : 33)), feet: P(i, j, z)};
  };
  /* a cast scene's faces as ops, back to front */
  World.sceneOps = function (sc) {
    const out = [];
    sc.faces.sort((a, b) => a.depth - b.depth);
    for (const fc of sc.faces) {
      out.push(poly(fc.pts, fc.fill, fc.opacity != null ? fc.opacity : null, fc.opacity != null ? 0 : .14));
      for (const d of fc.decals) out.push(poly(d.pts, d.fill));
    }
    return out;
  };
  /* a ground shadow under a box footprint, cast away from the light */
  W.shadow = function (i0, j0, i1, j1, h, z = 0, k = 1) {
    const L = Math.min(h, 46) * .42 * k / T, dx = .35 * L, dy = -.55 * L;
    const pts = [[i0, j0], [i1, j0], [i1, j1], [i0, j1], [i0 + dx, j0 + dy], [i1 + dx, j0 + dy], [i1 + dx, j1 + dy], [i0 + dx, j1 + dy]].map(([a, b]) => P(a, b, z));
    this.shadowP.push(poly(hull(pts), "#140c22"));
  };
  W.shadowEllipse = function (i, j, r, z = 0, k = 1) {
    const [x, y] = P(i + .12 * k, j - .2 * k, z);
    this.shadowP.push(["e", x, y, r * T * 1.25, r * T * .62, "#140c22", null, 0, null]);
  };
  /* light: a pool on the ground and a halo at the source */
  W.pool = function (i, j, z, r, col, a = .45) { const [x, y] = P(i, j, z); this.pools.push(["g", x, y, r, r * .5, col, a]); };
  W.halo = function (i, j, z, r, col, a = .6) { const [x, y] = P(i, j, z); this.halos.push(["g", x, y, r, r, col, a]); };
  W.anchor = function (name, i, j, z = 0) { this.anchors[name] = P(i, j, z); };

  /* ---------- terrain: a heightfield of tiles ---------- */
  /* tiles: fn(i, j) → null (void) or {h, c (top colour), side, deco: [...top decals], edge (side colour at an island edge)} */
  W.terrain = function (ni, nj, fn, o = {}) {
    const g = [], I0 = o.i0 || 0, J0 = o.j0 || 0;
    for (let i = 0; i < ni; i++) { g[i] = []; for (let j = 0; j < nj; j++) g[i][j] = fn(i + I0, j + J0); }
    if (!o.keepGrid) { this.grid = g; this.ni = ni; this.nj = nj; }
    const at0 = (i, j) => (i >= 0 && j >= 0 && i < ni && j < nj) ? g[i][j] : null;
    const at = (i, j) => at0(i - I0, j - J0);
    const base = o.base != null ? o.base : -10;
    const s = o.into || this.base;
    for (let d = 0; d < ni + nj; d++) for (let i0 = 0; i0 <= d; i0++) {
      const i = i0 + I0, j = d - i0 + J0, t = at(i, j);
      if (!t) continue;
      const h = t.h, nF = at(i, j + 1), nR = at(i + 1, j);
      const fz = nF ? nF.h : base, rz = nR ? nR.h : base;
      const edgeCol = t.edge || "#8a6440";
      if (rz < h) {
        const c = nR ? (t.side || t.c) : edgeCol;
        s.push(poly([P(i + 1, j + 1, rz), P(i + 1, j, rz), P(i + 1, j, h), P(i + 1, j + 1, h)], lit(c, NRM.right)));
        if (!nR) { s.push(poly([P(i + 1, j + 1, h - 2.4), P(i + 1, j, h - 2.4), P(i + 1, j, h), P(i + 1, j + 1, h)], lit(t.lip || t.c, NRM.right))); for (const dd of t.edgeDecoR || []) s.push(poly([P(i + 1.003, j + dd[0], dd[1]), P(i + 1.003, j + dd[2], dd[1]), P(i + 1.003, j + dd[2], dd[3]), P(i + 1.003, j + dd[0], dd[3])], paint(dd[4], "right"))); }
        else if (t.kerb) s.push(poly([P(i + 1, j + 1, h - .5), P(i + 1, j, h - .5), P(i + 1, j, h), P(i + 1, j + 1, h)], lit(t.kerb, NRM.right)));
      }
      if (fz < h) {
        const c = nF ? (t.side || t.c) : edgeCol;
        s.push(poly([P(i, j + 1, fz), P(i + 1, j + 1, fz), P(i + 1, j + 1, h), P(i, j + 1, h)], lit(c, NRM.front)));
        if (!nF) { s.push(poly([P(i, j + 1, h - 2.4), P(i + 1, j + 1, h - 2.4), P(i + 1, j + 1, h), P(i, j + 1, h)], lit(t.lip || t.c, NRM.front))); for (const dd of t.edgeDecoF || []) s.push(poly([P(i + dd[0], j + 1.003, dd[1]), P(i + dd[2], j + 1.003, dd[1]), P(i + dd[2], j + 1.003, dd[3]), P(i + dd[0], j + 1.003, dd[3])], paint(dd[4], "front"))); }
        else if (t.kerb) s.push(poly([P(i, j + 1, h - .5), P(i + 1, j + 1, h - .5), P(i + 1, j + 1, h), P(i, j + 1, h)], lit(t.kerb, NRM.front)));
      }
      const fill = lit(t.c, NRM.top);
      s.push(poly([P(i, j, h), P(i + 1, j, h), P(i + 1, j + 1, h), P(i, j + 1, h)], fill, null, .35));
      for (const d of t.deco || []) {
        if (d.p) { s.push(poly(d.p.map(([a, b]) => P(a, b, h + .02)), paint(d.c, "top"), d.op != null ? d.op : null)); continue; }
        s.push(poly([P(d[0], d[1], h + .02), P(d[2], d[1], h + .02), P(d[2], d[3], h + .02), P(d[0], d[3], h + .02)], paint(d[4], "top"), d[5] != null ? d[5] : null));
      }
    }
    return g;
  };
  W.h = function (i, j) { const t = this.grid && this.grid[Math.floor(i)] && this.grid[Math.floor(i)][Math.floor(j)]; return t ? t.h : 0; };
  /* the underside: columns hanging from the island, in back-to-front order */
  W.underside = function (cols, strata, top = -10, into) {
    cols.sort((a, b) => (a.i + a.j) - (b.i + b.j));
    const s = into || this.under;
    for (const c of cols) { for (const q of boxOps(c.i, c.j, top - c.d, c.i + (c.w || 1), c.j + (c.w || 1), top, c.col || strataCol(strata, top - c.d / 2), {hide: ["top"], deco: c.deco || strataDeco(strata, c, top), seam: 1.1})) s.push(q); }
  };
  const strataCol = (st, z) => { for (const [z0, c] of st) if (z >= z0) return c; return st[st.length - 1][1]; };
  function strataDeco(st0, c, top) {
    const w = c.w || 1, z0 = top - c.d, fr = [], ri = [];
    const jit = k => ((c.i * 7 + c.j * 13 + k * 5) % 4 === 0) ? -2 : 0;
    const st = st0.map(([zb, col], k) => [k < st0.length - 1 ? zb + jit(k) : zb, col]);
    for (let k = 0; k < st.length; k++) {
      const zt = k === 0 ? top : st[k - 1][0], zb = st[k][0];
      const a = Math.max(zb, z0), b = Math.min(zt, top);
      if (b > a) { fr.push([c.i, a, c.i + w, b, st[k][1]]); ri.push([c.j, a, c.j + w, b, st[k][1]]); }
    }
    { const tc = E.shade(strataCol(st0, z0 + 1), .86); fr.push([c.i, z0, c.i + w, z0 + 2.4, tc]); ri.push([c.j, z0, c.j + w, z0 + 2.4, tc]); }
    for (const e of c.extra || []) (e.f === "front" ? fr : ri).push(e.r);
    return {front: fr, right: ri};
  }

  /* ---------- sorting ---------- */
  function sortItems(items) {
    const n = items.length, CELL = 64, grid = new Map();
    items.forEach((it, k) => {
      const [x0, y0, x1, y1] = it.sb;
      for (let cx = Math.floor(x0 / CELL); cx <= Math.floor(x1 / CELL); cx++) for (let cy = Math.floor(y0 / CELL); cy <= Math.floor(y1 / CELL); cy++) {
        const key = cx * 100003 + cy; let l = grid.get(key); if (!l) grid.set(key, l = []); l.push(k);
      }
    });
    const behind = items.map(() => []), stamp = new Int32Array(n).fill(-1), e = .01;
    items.forEach((A, a) => {
      const [x0, y0, x1, y1] = A.sb;
      for (let cx = Math.floor(x0 / CELL); cx <= Math.floor(x1 / CELL); cx++) for (let cy = Math.floor(y0 / CELL); cy <= Math.floor(y1 / CELL); cy++) {
        const l = grid.get(cx * 100003 + cy);
        for (const b of l) {
          if (b <= a || stamp[b] === a) continue;
          stamp[b] = a;
          const Bb = items[b];
          if (Bb.sb[0] >= x1 || Bb.sb[2] <= x0 || Bb.sb[1] >= y1 || Bb.sb[3] <= y0) continue;
          const p = A.b, q = Bb.b;
          // do the projected hexagons really overlap? (three screen axes: x-y, y-1.08z, x-1.08z)
          const hx = (lo0, hi0, lo1, hi1) => hi0 <= lo1 + .3 || hi1 <= lo0 + .3;
          if (hx(p[0] - p[4], p[3] - p[1], q[0] - q[4], q[3] - q[1]) || hx(p[1] - 1.08 * p[5], p[4] - 1.08 * p[2], q[1] - 1.08 * q[5], q[4] - 1.08 * q[2]) || hx(p[0] - 1.08 * p[5], p[3] - 1.08 * p[2], q[0] - 1.08 * q[5], q[3] - 1.08 * q[2])) continue;
          let aBehind;
          if (p[3] <= q[0] + e) aBehind = true; else if (q[3] <= p[0] + e) aBehind = false;
          else if (p[4] <= q[1] + e) aBehind = true; else if (q[4] <= p[1] + e) aBehind = false;
          else if (p[5] <= q[2] + e) aBehind = true; else if (q[5] <= p[2] + e) aBehind = false;
          else {
            const ox = Math.min(p[3], q[3]) - Math.max(p[0], q[0]), oy = Math.min(p[4], q[4]) - Math.max(p[1], q[1]);
            const cxa = (p[0] + p[3]) / 2, cxb = (q[0] + q[3]) / 2, cya = (p[1] + p[4]) / 2, cyb = (q[1] + q[4]) / 2;
            let da, db;
            if (ox < oy * .8) { da = cxa; db = cxb; } else if (oy < ox * .8) { da = cya; db = cyb; } else { da = cxa + cya; db = cxb + cyb; }
            da += A.bias; db += Bb.bias;
            aBehind = Math.abs(da - db) > .5 ? da < db : (p[2] + p[5]) < (q[2] + q[5]);
          }
          if (aBehind) behind[b].push(a); else behind[a].push(b);
        }
      }
    });
    items.__behind = behind;
    const order = [], state = new Uint8Array(n);
    const idx = [...items.keys()].sort((a, b) => { const p = items[a].b, q = items[b].b; return (p[0] + p[1] + p[2]) - (q[0] + q[1] + q[2]); });
    for (const s0 of idx) {
      if (state[s0]) continue;
      const stack = [[s0, 0]]; state[s0] = 1;
      while (stack.length) {
        const top = stack[stack.length - 1], [v, k] = top;
        if (k < behind[v].length) { top[1]++; const w = behind[v][k]; if (!state[w]) { state[w] = 1; stack.push([w, 0]); } }
        else { stack.pop(); state[v] = 2; order.push(items[v]); }
      }
    }
    return order;
  }
  World.sortItems = sortItems;

  function hull(pts) {
    const p = pts.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    const cr = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
    const lo = [], up = [];
    for (const q of p) { while (lo.length >= 2 && cr(lo[lo.length - 2], lo[lo.length - 1], q) <= 0) lo.pop(); lo.push(q); }
    for (const q of p.reverse()) { while (up.length >= 2 && cr(up[up.length - 2], up[up.length - 1], q) <= 0) up.pop(); up.push(q); }
    return lo.slice(0, -1).concat(up.slice(0, -1));
  }

  /* ---------- painting ops on a canvas ---------- */
  const rgba = (hex, a) => { const h = hex.replace("#", ""); return `rgba(${parseInt(h.slice(0, 2), 16)},${parseInt(h.slice(2, 4), 16)},${parseInt(h.slice(4, 6), 16)},${a})`; };
  function draw(g, ops) {
    g.lineJoin = "round";
    for (const q of ops) {
      const t = q[0];
      if (t === "p") {
        const a = q[1];
        g.beginPath(); g.moveTo(a[0], a[1]); for (let k = 2; k < a.length; k += 2) g.lineTo(a[k], a[k + 1]); g.closePath();
        g.fillStyle = q[2];
        if (q[3] != null) { g.globalAlpha = q[3]; g.fill(); g.globalAlpha = 1; }
        else { g.fill(); if (q[4]) { g.strokeStyle = q[2]; g.lineWidth = q[4]; g.stroke(); } }
      } else if (t === "e") {
        g.beginPath(); g.ellipse(q[1], q[2], Math.max(.01, q[3]), Math.max(.01, q[4]), 0, 0, Math.PI * 2);
        if (q[8] != null) g.globalAlpha = q[8];
        if (q[5]) { g.fillStyle = q[5]; g.fill(); }
        if (q[6]) { g.strokeStyle = q[6]; g.lineWidth = q[7]; g.stroke(); }
        g.globalAlpha = 1;
      } else if (t === "g") {
        const [, cx, cy, rx, ry, col, al] = q;
        if (rx <= 0 || ry <= 0) continue;
        g.save(); g.translate(cx, cy); g.scale(1, ry / rx);
        const gr = g.createRadialGradient(0, 0, 0, 0, 0, rx);
        gr.addColorStop(0, rgba(col, 1)); gr.addColorStop(.45, rgba(col, .45)); gr.addColorStop(1, rgba(col, 0));
        g.globalAlpha = al; g.fillStyle = gr; g.beginPath(); g.arc(0, 0, rx, 0, Math.PI * 2); g.fill();
        g.restore();
      } else if (t === "l") {
        g.beginPath(); g.moveTo(q[1], q[2]); g.lineTo(q[3], q[4]); g.strokeStyle = q[5]; g.lineWidth = q[6];
        if (q[7]) g.setLineDash(q[7]);
        if (q[8] != null) g.globalAlpha = q[8];
        g.lineCap = "round"; g.stroke(); g.setLineDash([]); g.globalAlpha = 1;
      } else if (t === "t") {
        const [, m, text, font, size, wt, anchor, fill, stroke, sw, al] = q;
        g.save(); g.transform(m[0], m[1], m[2], m[3], m[4], m[5]);
        // the matrix maps a face's (u, v) with v up the face; canvas text runs with y down, so draw it flipped back
        g.scale(1, 1);
        g.font = `${wt} ${size}px ${font}`; g.textAlign = anchor === "middle" ? "center" : anchor === "end" ? "right" : "left"; g.textBaseline = "alphabetic";
        if (al != null) g.globalAlpha = al;
        if (stroke) { g.strokeStyle = stroke; g.lineWidth = sw; g.lineJoin = "round"; g.strokeText(text, 0, 0); }
        g.fillStyle = fill; g.fillText(text, 0, 0);
        g.restore();
      }
    }
  }
  /* the screen box of a list of ops */
  function opsBounds(ops, pad = .5) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    const add = (x, y) => { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; };
    for (const q of ops) {
      const t = q[0];
      if (t === "p") { const a = q[1]; for (let k = 0; k < a.length; k += 2) add(a[k], a[k + 1]); }
      else if (t === "e" || t === "g") { add(q[1] - q[3], q[2] - q[4]); add(q[1] + q[3], q[2] + q[4]); }
      else if (t === "l") { add(q[1], q[2]); add(q[3], q[4]); }
      else if (t === "t") { const m = q[1], w = measure(q[2], q[4], q[3], q[5]), s = q[4]; for (const [u, v] of [[-w, -s], [w, -s], [-w, s * .4], [w, s * .4]]) add(m[4] + m[0] * u + m[2] * v, m[5] + m[1] * u + m[3] * v); }
    }
    return [x0 - pad, y0 - pad, x1 + pad, y1 + pad];
  }

  window.WorldKit = {measure, World, P, PX, T, lit, paint, poly, boxOps, hull, draw, opsBounds, sortItems, FONTS, shade: E.shade, tint: E.tint, B};
})();
