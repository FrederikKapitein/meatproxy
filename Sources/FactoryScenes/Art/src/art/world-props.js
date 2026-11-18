/* Props for the world kit (Spel+, D80), from the world artist's props.js, painted by world-kit.js: trees of several species, shrubs, hedges, flower beds, water life, birds, squirrels,
   street furniture and vehicles. Everything is boxes, in tiles (i, j) and units (z), standing at height z. */
(function () {
  const K = window.WorldKit, T = K.T, P = K.P, f = K.f;
  const rnd = seed => { let x = 2166136261; for (const c of String(seed)) x = Math.imul(x ^ c.charCodeAt(0), 16777619); return () => ((x = Math.imul(x ^ (x >>> 15), 2246822507) ^ Math.imul(x ^ (x >>> 13), 3266489909)) >>> 0) / 4294967296; };
  const shade = K.shade, tint = K.tint;
  const Pr = {rnd};

  /* leaf texture: a few lighter and darker squares on a canopy box's faces */
  function leafDeco(i0, j0, z0, i1, j1, z1, col, r, n = 5) {
    const top = [], front = [], right = [];
    const lt = tint(col, .22), dk = shade(col, .82);
    for (let k = 0; k < n; k++) {
      const a = i0 + (i1 - i0) * r() * .8, b = j0 + (j1 - j0) * r() * .8, s = .1 + r() * .12;
      top.push([a, b, Math.min(i1, a + s), Math.min(j1, b + s), k % 2 ? lt : dk]);
      const z = z0 + (z1 - z0) * (.15 + r() * .6), zs = 1.4 + r() * 1.6;
      front.push([i0 + (i1 - i0) * r() * .85, z, 0, z + zs, k % 3 ? dk : lt]);
      right.push([j0 + (j1 - j0) * r() * .85, z, 0, z + zs, k % 3 ? dk : lt]);
    }
    front.forEach(d => d[2] = Math.min(i1, d[0] + .12)); right.forEach(d => d[2] = Math.min(j1, d[0] + .12));
    return {top, front, right};
  }
  Pr.leafDeco = leafDeco;
  const canopy = (W, i0, j0, z0, i1, j1, z1, col, r, n) => W.box(i0, j0, z0, i1, j1, z1, col, {deco: leafDeco(i0, j0, z0, i1, j1, z1, col, r, n)});

  /* ---------- trees ---------- */
  Pr.tree = function (W, kind, i, j, z = 0, s = 1, seed = i * 31 + j) {
    const r = rnd(kind + seed); s *= 1.75;
    const trunk = (h, w = .13, col = "#7a4a2e") => (w = Math.min(w, .26),  W.box(i - w, j - w, z, i + w, j + w, z + h, col, {deco: {front: [[i - w, z + h * .3, i - w + .06, z + h * .55, shade(col, .8)]]}}));
    if (kind === "oak") {
      const g = ["#3f9a52", "#4aa65a", "#3a8f4c"][Math.floor(r() * 3)];
      trunk(16 * s, .15 * s);
      W.box(i + .08 * s, j - .05, z + 10 * s, i + .42 * s, j + .05, z + 11.4 * s, "#7a4a2e");             // a branch
      canopy(W, i - .78 * s, j - .78 * s, z + 13 * s, i + .78 * s, j + .78 * s, z + 27 * s, g, r, 7);
      canopy(W, i - .55 * s, j - .55 * s, z + 27 * s, i + .55 * s, j + .55 * s, z + 34 * s, tint(g, .12), r, 4);
      canopy(W, i - .98 * s, j - .4 * s, z + 15 * s, i - .78 * s, j + .45 * s, z + 24 * s, shade(g, .95), r, 2);
      canopy(W, i - .35 * s, j + .78 * s, z + 15 * s, i + .5 * s, j + .98 * s, z + 24 * s, g, r, 2);
      canopy(W, i + .78 * s, j - .5 * s, z + 16 * s, i + .96 * s, j + .3 * s, z + 25 * s, shade(g, .9), r, 2);
      W.shadowEllipse(i, j, .95 * s, z, 1.3);
    }
    if (kind === "pine") {
      const g = ["#2f7a5a", "#2a6f55", "#327f60"][Math.floor(r() * 3)];
      trunk(10 * s, .12 * s, "#6a3f28");
      const tiers = [[.82, 7, 15], [.64, 15, 22], [.46, 22, 29], [.28, 29, 35], [.12, 35, 39]];
      for (const [w, a, b] of tiers) canopy(W, i - w * s, j - w * s, z + a * s, i + w * s, j + w * s, z + b * s, g, r, 3);
      W.shadowEllipse(i, j, .75 * s, z, 1.2);
    }
    if (kind === "birch") {
      const g = ["#8fc25a", "#9ccc62", "#86b852"][Math.floor(r() * 3)];
      const h = 26 * s;
      W.box(i - .09, j - .09, z, i + .09, j + .09, z + h, "#efeae0", {deco: {front: [[i - .09, z + 4, i + .02, z + 5.2, "#2a2433"], [i - .02, z + 10, i + .09, z + 11, "#2a2433"], [i - .09, z + 17, i, z + 18, "#2a2433"]], right: [[j - .09, z + 7, j + .02, z + 8, "#2a2433"], [j - .02, z + 14, j + .09, z + 15.2, "#2a2433"]]}});
      canopy(W, i - .5 * s, j - .5 * s, z + 14 * s, i + .5 * s, j + .5 * s, z + 24 * s, g, r, 4);
      canopy(W, i - .36 * s, j - .36 * s, z + 24 * s, i + .36 * s, j + .36 * s, z + 32 * s, tint(g, .1), r, 3);
      canopy(W, i + .1 * s, j + .3 * s, z + 10 * s, i + .62 * s, j + .66 * s, z + 17 * s, shade(g, .94), r, 2);
      W.shadowEllipse(i, j, .6 * s, z, 1.3);
    }
    if (kind === "cherry") {
      const g = ["#f2a6c8", "#f7b8d4", "#ec9cc0"][Math.floor(r() * 3)];
      trunk(13 * s, .13 * s, "#5e3a32");
      W.box(i - .4 * s, j - .05, z + 9 * s, i - .1, j + .05, z + 10.4 * s, "#5e3a32");
      const deco = (a, b, c, d, e, h) => { const L = leafDeco(a, b, c, d, e, h, g, r, 6); L.top.push(...[0, 1, 2].map(k => [a + (d - a) * r() * .8, b + (e - b) * r() * .8, 0, 0, "#fff0f6"]).map(q => [q[0], q[1], q[0] + .08, q[1] + .08, q[4]])); return L; };
      W.box(i - .85 * s, j - .7 * s, z + 11 * s, i + .7 * s, j + .85 * s, z + 23 * s, g, {deco: deco(i - .85 * s, j - .7 * s, z + 11 * s, i + .7 * s, j + .85 * s, z + 23 * s)});
      W.box(i - .5 * s, j - .5 * s, z + 23 * s, i + .5 * s, j + .5 * s, z + 29 * s, tint(g, .15), {deco: deco(i - .5 * s, j - .5 * s, z + 23 * s, i + .5 * s, j + .5 * s, z + 29 * s)});
      W.shadowEllipse(i, j, .9 * s, z, 1.2);
    }
    if (kind === "poplar") {
      const g = ["#4c9a4a", "#55a24f"][Math.floor(r() * 2)];
      trunk(8 * s, .11 * s);
      canopy(W, i - .38 * s, j - .38 * s, z + 6 * s, i + .38 * s, j + .38 * s, z + 40 * s, g, r, 7);
      canopy(W, i - .24 * s, j - .24 * s, z + 40 * s, i + .24 * s, j + .24 * s, z + 47 * s, tint(g, .1), r, 2);
      W.shadowEllipse(i, j, .45 * s, z, 1.6);
    }
    if (kind === "maple") {
      const g = ["#e07a3a", "#e8913f", "#d4642f"][Math.floor(r() * 3)];
      trunk(14 * s, .14 * s, "#5e3a28");
      canopy(W, i - .8 * s, j - .8 * s, z + 12 * s, i + .8 * s, j + .8 * s, z + 25 * s, g, r, 7);
      canopy(W, i - .5 * s, j - .5 * s, z + 25 * s, i + .5 * s, j + .5 * s, z + 31 * s, tint(g, .12), r, 3);
      canopy(W, i - .3 * s, j + .8 * s, z + 14 * s, i + .45 * s, j + 1 * s, z + 22 * s, shade(g, .92), r, 2);
      W.shadowEllipse(i, j, .95 * s, z, 1.2);
    }
    if (kind === "apple") {
      const g = "#4f9e48";
      trunk(10 * s, .14 * s, "#6a4026");
      const D = leafDeco(i - .7 * s, j - .7 * s, z + 9 * s, i + .7 * s, j + .7 * s, z + 21 * s, g, r, 5);
      for (let k = 0; k < 6; k++) { D.front.push([i - .6 * s + r() * 1.1 * s, z + 11 * s + r() * 8 * s, 0, 0, "#e0473a"]); D.right.push([j - .6 * s + r() * 1.1 * s, z + 11 * s + r() * 8 * s, 0, 0, "#e0473a"]); }
      D.front.forEach(d => { if (d[4] === "#e0473a") { d[2] = d[0] + .1; d[3] = d[1] + 1.8; } }); D.right.forEach(d => { if (d[4] === "#e0473a") { d[2] = d[0] + .1; d[3] = d[1] + 1.8; } });
      W.box(i - .7 * s, j - .7 * s, z + 9 * s, i + .7 * s, j + .7 * s, z + 21 * s, g, {deco: D});
      canopy(W, i - .42 * s, j - .42 * s, z + 21 * s, i + .42 * s, j + .42 * s, z + 26 * s, tint(g, .1), r, 3);
      W.shadowEllipse(i, j, .8 * s, z, 1.1);
    }
  };
  /* a tree pit in a pavement: a square of soil with a low iron edge */
  Pr.treePit = function (W, i, j, z, col = "#3a2a22") { W.box(i - .45, j - .45, z, i + .45, j + .45, z + .4, "#5a5a6a", {deco: {top: [[i - .38, j - .38, i + .38, j + .38, col]]}}); };

  /* ---------- low green ---------- */
  Pr.shrub = function (W, i, j, z = 0, s = 1, col = "#3f9a52", flowers = null, seed = i * 7 + j) {
    const r = rnd("sh" + seed);
    const parts = [[-.42, -.36, .3, .32, 7.5], [-.1, -.1, .5, .46, 6], [-.5, .0, .05, .5, 5]];
    W.group(sub => {
      for (const [a, b, c, d, h] of parts) {
        const D = leafDeco(i + a * s, j + b * s, z, i + c * s, j + d * s, z + h * s, col, r, 3);
        if (flowers) for (let k = 0; k < 3; k++) { const fa = i + (a + (c - a) * r()) * s, fb = j + (b + (d - b) * r()) * s; D.top.push([fa, fb, fa + .09, fb + .09, flowers]); D.front.push([i + (a + (c - a) * r() * .9) * s, z + h * s * (.4 + r() * .4), 0, 0, flowers]); }
        D.front.forEach(d => { if (d[3] === 0) { d[2] = d[0] + .08; d[3] = d[1] + 1.2; } });
        sub.box(i + a * s, j + b * s, z, i + c * s, j + d * s, z + h * s, col, {deco: D});
      }
    });
    W.shadowEllipse(i, j, .5 * s, z, .5);
  };
  /* a trimmed hedge along i or j */
  Pr.hedge = function (W, i0, j0, i1, j1, z = 0, h = 8, col = "#3a8a4a") {
    const r = rnd("hd" + i0 + j0 + i1);
    W.box(i0, j0, z, i1, j1, z + h, col, {deco: leafDeco(i0, j0, z, i1, j1, z + h, col, r, Math.ceil(Math.max(i1 - i0, j1 - j0) * 4)), shadow: .6});
  };
  /* a flower bed: a low border, soil and rows of flowers */
  Pr.bed = function (W, i0, j0, i1, j1, z = 0, cols = ["#ff6a8a", "#ffd04a", "#b07cf0"], border = "#b9a88e", seed = 1) {
    const r = rnd("bed" + seed + i0 + j0);
    W.group(sub => {
      const t = .14, bh = 3;
      sub.box(i0, j0, z, i1, j0 + t, z + bh, border); sub.box(i0, j1 - t, z, i1, j1, z + bh, border);
      sub.box(i0, j0 + t, z, i0 + t, j1 - t, z + bh, border); sub.box(i1 - t, j0 + t, z, i1, j1 - t, z + bh, border);
      sub.box(i0 + t, j0 + t, z, i1 - t, j1 - t, z + 2.2, "#4a3226");
      const step = .3;
      let row = 0;
      for (let a = i0 + .26; a < i1 - .2; a += step, row++) for (let b = j0 + .26; b < j1 - .2; b += step) {
        const c = cols[(Math.floor((a - i0) / step) + Math.floor((b - j0) / (step * 2))) % cols.length];
        const h = 2.2 + r() * 1.5;
        sub.box(a - .06, b - .06, z + 2.2, a + .06, b + .06, z + 2.2 + h, "#3f8f3f");
        sub.box(a - .08, b - .08, z + 2.2 + h, a + .08, b + .08, z + 4.4 + h, c, {deco: {top: [[a - .03, b - .03, a + .03, b + .03, "#fff3b0"]]}});
      }
    });
  };
  /* reeds at a pond edge */
  Pr.reeds = function (W, i, j, z = 0, n = 5, seed = 3) {
    const r = rnd("rd" + seed + i + j);
    W.group(sub => { for (let k = 0; k < n; k++) { const a = i + (r() - .5) * .5, b = j + (r() - .5) * .5, h = 7 + r() * 6; sub.box(a - .03, b - .03, z, a + .03, b + .03, z + h, "#6a9a3a"); if (k % 2) sub.box(a - .05, b - .05, z + h - 3, a + .05, b + .05, z + h - .4, "#6a4026"); } });
  };
  Pr.lily = (W, i, j, z, flower) => { W.box(i - .2, j - .16, z, i + .2, j + .16, z + .25, "#4f9a48", {deco: {top: [[i - .02, j - .16, i + .03, j - .02, "#3a7a38"]].concat(flower ? [[i - .06, j - .04, i + .06, j + .08, "#ff9ac8"]] : [])}}); };
  Pr.rock = function (W, i, j, z = 0, s = 1, col = "#8a8696") {
    W.group(sub => { sub.box(i - .32 * s, j - .26 * s, z, i + .3 * s, j + .28 * s, z + 4 * s, col, {deco: {top: [[i - .2 * s, j - .1 * s, i, j + .1 * s, tint(col, .15)]]}}); sub.box(i - .15 * s, j - .12 * s, z + 4 * s, i + .18 * s, j + .16 * s, z + 6 * s, tint(col, .08)); });
  };

  /* ---------- animals ---------- */
  /* a squirrel; where: ground (sitting up, tail curled behind) or trunk (clinging to the face of a trunk) */
  Pr.squirrel = function (W, i, j, z = 0, o = {}) {
    const fur = o.fur || "#c0602a", belly = "#f0c89a", dir = o.dir || "SW";
    W.group(sub => {
      if (o.on === "trunkF") {      // on the front (+y) face of a trunk, head up
        const y = j;
        sub.box(i - .1, y, z, i + .1, y + .12, z + 4, fur, {deco: {front: [[i - .05, z + .6, i + .05, z + 3, belly]]}});
        sub.box(i - .09, y + .02, z + 4, i + .09, y + .16, z + 6.4, fur, {deco: {front: [[i - .07, z + 5.2, i - .03, z + 5.8, "!#1a1020"], [i + .03, z + 5.2, i + .07, z + 5.8, "!#1a1020"], [i - .02, z + 4.3, i + .02, z + 4.8, "#3a2020"]]}});
        sub.box(i - .08, y + .04, z + 6.4, i - .04, y + .1, z + 7.4, fur); sub.box(i + .04, y + .04, z + 6.4, i + .08, y + .1, z + 7.4, fur);
        sub.box(i - .13, y + .02, z - 4.5, i + .13, y + .2, z + .4, tint(fur, .1));            // tail hanging below
        sub.box(i - .14, y + .1, z + .6, i - .08, y + .2, z + 1.4, fur); sub.box(i + .08, y + .1, z + .6, i + .14, y + .2, z + 1.4, fur);
        return;
      }
      if (o.on === "trunkR") {      // on the right (+x) face of a trunk
        sub.box(i, j - .1, z, i + .12, j + .1, z + 4, fur, {deco: {right: [[j - .05, z + .6, j + .05, z + 3, belly]]}});
        sub.box(i + .02, j - .09, z + 4, i + .16, j + .09, z + 6.4, fur, {deco: {right: [[j - .07, z + 5.2, j - .03, z + 5.8, "!#1a1020"], [j + .03, z + 5.2, j + .07, z + 5.8, "!#1a1020"]]}});
        sub.box(i + .04, j - .08, z + 6.4, i + .1, j - .04, z + 7.4, fur); sub.box(i + .04, j + .04, z + 6.4, i + .1, j + .08, z + 7.4, fur);
        sub.box(i + .02, j - .13, z - 4.5, i + .2, j + .13, z + .4, tint(fur, .1));
        return;
      }
      // sitting on the ground, facing +y (SW) or +x (SE), tail up behind
      const fy = dir === "SW";
      sub.box(i - .12, j - .1, z, i + .12, j + .1, z + 3.8, fur, {deco: fy ? {front: [[i - .06, z + .5, i + .06, z + 3, belly]]} : {right: [[j - .06, z + .5, j + .06, z + 3, belly]]}});
      sub.box(i - .1, j - .09, z + 3.8, i + .1, j + .11, z + 6.2, fur, {deco: fy ? {front: [[i - .07, z + 4.9, i - .03, z + 5.5, "!#1a1020"], [i + .03, z + 4.9, i + .07, z + 5.5, "!#1a1020"]]} : {right: [[j - .07, z + 4.9, j - .03, z + 5.5, "!#1a1020"], [j + .03, z + 4.9, j + .07, z + 5.5, "!#1a1020"]]}});
      sub.box(i - .08, j - .05, z + 6.2, i - .04, j, z + 7.2, fur); sub.box(i + .04, j - .05, z + 6.2, i + .08, j, z + 7.2, fur);
      if (fy) { sub.box(i - .1, j + .1, z + 1.6, i + .1, j + .2, z + 2.6, "#8a5a2a"); sub.box(i - .14, j - .34, z, i + .14, j - .1, z + 5.5, tint(fur, .1)); sub.box(i - .14, j - .3, z + 5.5, i + .14, j - .12, z + 8, tint(fur, .15)); }
      else { sub.box(i + .1, j - .1, z + 1.6, i + .2, j + .1, z + 2.6, "#8a5a2a"); sub.box(i - .34, j - .14, z, i - .1, j + .14, z + 5.5, tint(fur, .1)); sub.box(i - .3, j - .14, z + 5.5, i - .12, j + .14, z + 8, tint(fur, .15)); }
    }, o.b ? {b: o.b} : {});
  };
  /* a perched bird (pigeon, robin, sparrow), facing +y or +x */
  Pr.bird = function (W, i, j, z, o = {}) {
    const kind = o.kind || "pigeon", C = {pigeon: ["#8a8ea8", "#6a6e88", "#5aa08a"], robin: ["#7a5a3e", "#e0603a", "#7a5a3e"], sparrow: ["#9a7a52", "#d8c09a", "#6a4a32"], gull: ["#f2f0ea", "#c8ccd8", "#f2f0ea"]}[kind];
    const fy = (o.dir || "SW") === "SW";
    W.group(sub => {
      if (fy) {
        sub.box(i - .07, j - .14, z, i + .07, j + .08, z + 2, C[0], {deco: {front: [[i - .05, z + .2, i + .05, z + 1.6, C[1]]]}});
        sub.box(i - .055, j + .02, z + 1.6, i + .055, j + .14, z + 3.1, C[2], {deco: {front: [[i - .04, z + 2.3, i - .015, z + 2.7, "!#140c18"], [i + .015, z + 2.3, i + .04, z + 2.7, "!#140c18"]]}});
        sub.box(i - .018, j + .14, z + 2, i + .018, j + .2, z + 2.4, "#e8a03a");
        sub.box(i - .04, j - .24, z + .8, i + .04, j - .14, z + 1.5, C[0]);
      } else {
        sub.box(i - .14, j - .07, z, i + .08, j + .07, z + 2, C[0], {deco: {right: [[j - .05, z + .2, j + .05, z + 1.6, C[1]]]}});
        sub.box(i + .02, j - .055, z + 1.6, i + .14, j + .055, z + 3.1, C[2], {deco: {right: [[j - .04, z + 2.3, j - .015, z + 2.7, "!#140c18"], [j + .015, z + 2.3, j + .04, z + 2.7, "!#140c18"]]}});
        sub.box(i + .14, j - .018, z + 2, i + .2, j + .018, z + 2.4, "#e8a03a");
        sub.box(i - .24, j - .04, z + .8, i - .14, j + .04, z + 1.5, C[0]);
      }
    });
  };
  /* a bird in flight, wings up or level */
  Pr.flyer = function (W, i, j, z, o = {}) {
    const col = o.col || "#2a2440", tip = o.tip || "#3a3450", up = o.up;
    W.group(sub => {
      sub.box(i - .06, j - .16, z, i + .06, j + .14, z + 1.2, col);
      sub.box(i - .04, j + .14, z + .3, i + .04, j + .24, z + 1.1, col);
      sub.box(i - .03, j + .24, z + .5, i + .03, j + .3, z + .9, "#e8a03a");
      const lift = up ? 2.6 : 1.2;
      sub.box(i - .34, j - .06, z + .7, i - .06, j + .06, z + .7 + 1, col); sub.box(i + .06, j - .06, z + .7, i + .34, j + .06, z + 1.7, col);
      sub.box(i - .62, j - .05, z + .7 + lift, i - .34, j + .04, z + 1.5 + lift, tip); sub.box(i + .34, j - .05, z + .7 + lift, i + .62, j + .04, z + 1.5 + lift, tip);
      sub.box(i - .4, j - .05, z + 1.4, i - .3, j + .05, z + .9 + lift, col); sub.box(i + .3, j - .05, z + 1.4, i + .4, j + .05, z + .9 + lift, col);
    });
  };
  /* a duck swimming (mallard or white) */
  Pr.duck = function (W, i, j, z, o = {}) {
    const white = o.white, fy = (o.dir || "SW") === "SW";
    const body = white ? "#f4f1ea" : "#9a7a5a", head = white ? "#f4f1ea" : "#2f7a4a";
    W.group(sub => {
      if (fy) {
        sub.box(i - .14, j - .24, z, i + .14, j + .16, z + 2.6, body, {deco: {front: [[i - .14, z + .4, i + .14, z + .8, white ? "#e8e2d4" : "#f2efe6"]]}});
        sub.box(i - .05, j - .32, z + 1.8, i + .05, j - .22, z + 3.2, body);
        sub.box(i - .09, j + .04, z + 2.6, i + .09, j + .2, z + 5, head, {deco: {front: [[i - .07, z + 3.8, i - .03, z + 4.3, "!#140c18"], [i + .03, z + 3.8, i + .07, z + 4.3, "!#140c18"]]}});
        sub.box(i - .05, j + .2, z + 3, i + .05, j + .3, z + 3.6, "#f2a23a");
        if (!white) sub.box(i - .095, j + .04, z + 2.6, i + .095, j + .2, z + 3, "#f4f1ea");
      } else {
        sub.box(i - .24, j - .14, z, i + .16, j + .14, z + 2.6, body, {deco: {right: [[j - .14, z + .4, j + .14, z + .8, white ? "#e8e2d4" : "#f2efe6"]]}});
        sub.box(i - .32, j - .05, z + 1.8, i - .22, j + .05, z + 3.2, body);
        sub.box(i + .04, j - .09, z + 2.6, i + .2, j + .09, z + 5, head, {deco: {right: [[j - .07, z + 3.8, j - .03, z + 4.3, "!#140c18"], [j + .03, z + 3.8, j + .07, z + 4.3, "!#140c18"]]}});
        sub.box(i + .2, j - .05, z + 3, i + .3, j + .05, z + 3.6, "#f2a23a");
        if (!white) sub.box(i + .04, j - .095, z + 2.6, i + .2, j + .095, z + 3, "#f4f1ea");
      }
    });
    // a ripple ring on the water
    const [x, y] = P(i, j, z);
    W.water.push(["e", x, y + 1, 9, 4.5, null, "#cfeaff", .7, .45]);
  };
  Pr.cat = function (W, i, j, z, col = "#3a3340") {
    W.group(sub => {
      sub.box(i - .14, j - .25, z, i + .14, j + .2, z + 3.4, col);
      sub.box(i - .12, j + .12, z + 2.6, i + .12, j + .34, z + 5.4, col, {deco: {front: [[i - .08, z + 4, i - .03, z + 4.6, "!#c8f06a"], [i + .03, z + 4, i + .08, z + 4.6, "!#c8f06a"]]}});
      sub.box(i - .11, j + .14, z + 5.4, i - .05, j + .22, z + 6.6, col); sub.box(i + .05, j + .14, z + 5.4, i + .11, j + .22, z + 6.6, col);
      sub.box(i - .04, j - .45, z + .4, i + .04, j - .25, z + 1.2, col); sub.box(i - .04, j - .5, z + 1.2, i + .04, j - .42, z + 4, col);
    });
  };

  /* ---------- street furniture ---------- */
  /* a street lamp: base, post, arm, lantern; glows */
  Pr.lamp = function (W, i, j, z = 0, o = {}) {
    const post = o.post || "#2a2433", h = o.h || 50, NV = window.__NIGHT, tone = NV ? ["#fff0d0", "#ffd8a0", "#ffe6c0"][Math.floor(Math.abs(i * 7 + j * 3)) % 3] : null, glass = NV ? "!" + tone : (o.glass || "#ffe2a8"), col = NV ? (tone === "#ffd8a0" ? "#ffb070" : "#ffd9a0") : (o.light || "#ffb070");
    W.box(i - .14, j - .14, z, i + .14, j + .14, z + 3.4, post);
    W.box(i - .06, j - .06, z + 3.4, i + .06, j + .06, z + h, post);
    if (o.style === "arm") {
      W.box(i - .045, j - .045, z + h - 1, i + .045, j + .5, z + h, post);
      W.box(i - .12, j + .32, z + h - 4, i + .12, j + .56, z + h - 1, glass, {deco: {front: [[i - .12, z + h - 4, i + .12, z + h - 3.4, post]]}});
      W.halo(i, j + .44, z + h - 3, 14, col, .7); W.pool(i, j + .44, z, 52, col, .5);
    } else {
      W.box(i - .2, j - .2, z + h - .6, i + .2, j + .2, z + h, post);
      W.box(i - .18, j - .18, z + h, i + .18, j + .18, z + h + 7, glass, {deco: {front: [[i - .025, z + h, i + .025, z + h + 7, post]], right: [[j - .025, z + h, j + .025, z + h + 7, post]]}});
      W.box(i - .24, j - .24, z + h + 7, i + .24, j + .24, z + h + 8.6, post);
      W.box(i - .06, j - .06, z + h + 8.6, i + .06, j + .06, z + h + 10.4, post);
      W.halo(i, j, z + h + 3.5, NV ? 24 : 18, col, .75); W.pool(i, j, z, NV ? 96 : 70, col, NV ? .6 : .5);
    }
    return {top: [i, j, z + h + (o.style === "arm" ? 0 : 10.4)]};
  };
  /* a bench along i (facing +y) or along j (facing +x) */
  Pr.bench = function (W, i, j, z = 0, o = {}) {
    const wood = o.wood || "#a8743a", iron = o.iron || "#2a2433", alongI = (o.face || "SW") === "SW", L = o.len || 1.3;
    W.group(sub => {
      if (alongI) {
        for (const a of [i - L / 2 + .08, i + L / 2 - .16]) { sub.box(a, j - .18, z, a + .08, j + .18, z + 4.4, iron); sub.box(a, j - .24, z + 4.4, a + .08, j - .16, z + 10, iron); }
        sub.box(i - L / 2, j - .18, z + 4.4, i + L / 2, j + .2, z + 5.4, wood, {deco: {top: [[i - L / 2, j - .03, i + L / 2, j, shade(wood, .8)], [i - L / 2, j + .09, i + L / 2, j + .12, shade(wood, .8)]]}});
        sub.box(i - L / 2, j - .26, z + 6.4, i + L / 2, j - .18, z + 8, wood); sub.box(i - L / 2, j - .26, z + 8.6, i + L / 2, j - .18, z + 10.2, wood);
      } else {
        for (const b of [j - L / 2 + .08, j + L / 2 - .16]) { sub.box(i - .18, b, z, i + .18, b + .08, z + 4.4, iron); sub.box(i - .24, b, z + 4.4, i - .16, b + .08, z + 10, iron); }
        sub.box(i - .18, j - L / 2, z + 4.4, i + .2, j + L / 2, z + 5.4, wood, {deco: {top: [[i - .03, j - L / 2, i, j + L / 2, shade(wood, .8)], [i + .09, j - L / 2, i + .12, j + L / 2, shade(wood, .8)]]}});
        sub.box(i - .26, j - L / 2, z + 6.4, i - .18, j + L / 2, z + 8, wood); sub.box(i - .26, j - L / 2, z + 8.6, i - .18, j + L / 2, z + 10.2, wood);
      }
    });
    W.shadow(alongI ? i - L / 2 : i - .2, alongI ? j - .2 : j - L / 2, alongI ? i + L / 2 : i + .2, alongI ? j + .2 : j + L / 2, 5, z, .5);
  };
  Pr.bin = function (W, i, j, z = 0, col = "#3a5a4a") { W.box(i - .14, j - .14, z, i + .14, j + .14, z + 7, col, {deco: {front: [[i - .14, z + 5.4, i + .14, z + 6, shade(col, .7)]], right: [[j - .14, z + 5.4, j + .14, z + 6, shade(col, .7)]]}}); W.box(i - .17, j - .17, z + 7, i + .17, j + .17, z + 7.8, shade(col, .85)); };
  Pr.bollard = function (W, i, j, z = 0, col = "#2a2433") { W.box(i - .07, j - .07, z, i + .07, j + .07, z + 5, col, {deco: {front: [[i - .07, z + 3.6, i + .07, z + 4.2, "#e9dcc0"]], right: [[j - .07, z + 3.6, j + .07, z + 4.2, "#e9dcc0"]]}}); };
  /* a fence of posts and two rails, along i or j */
  Pr.fence = function (W, i0, j0, i1, j1, z = 0, col = "#c9a46a", h = 7) {
    const alongI = Math.abs(i1 - i0) > Math.abs(j1 - j0), L = alongI ? i1 - i0 : j1 - j0, n = Math.max(1, Math.round(Math.abs(L) / .8));
    for (let k = 0; k <= n; k++) { const t = k / n, a = i0 + (i1 - i0) * t, b = j0 + (j1 - j0) * t; W.box(a - .06, b - .06, z, a + .06, b + .06, z + h, col); }
    for (const zz of [h * .45, h * .85]) alongI ? W.box(Math.min(i0, i1), j0 - .03, z + zz, Math.max(i0, i1), j0 + .03, z + zz + 1, col) : W.box(i0 - .03, Math.min(j0, j1), z + zz, i0 + .03, Math.max(j0, j1), z + zz + 1, col);
  };
  /* a street-name sign on a post */
  Pr.streetSign = function (W, i, j, z, name, o = {}) {
    const post = o.post || "#2a2433", bg = o.bg || "#2f5a8a", ink = o.ink || "#f4f1ea", alongI = (o.face || "SW") === "SW";
    W.box(i - .04, j - .04, z, i + .04, j + .04, z + 30, post);
    const w = Math.max(1, name.length * .2 + .3);
    if (alongI) W.box(i - w / 2, j - .03, z + 24, i + w / 2, j + .03, z + 29, bg, {text: [{f: "front", a: i, z: z + 25.4, t: name, s: 3.6, c: "!" + ink, wt: 700, font: o.font}]});
    else W.box(i - .03, j - w / 2, z + 24, i + .03, j + w / 2, z + 29, bg, {text: [{f: "right", a: j, z: z + 25.4, t: name, s: 3.6, c: "!" + ink, wt: 700, font: o.font}]});
  };
  /* a bicycle along i or j */
  Pr.bike = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#e0473a", alongI = (o.face || "SW") === "SE";
    W.group(sub => {
      const wheel = (c) => {
        const R = 4, pts = [[-1, 0], [-.7, .7], [0, 1], [.7, .7], [1, 0], [.7, -.7], [0, -1], [-.7, -.7]];
        for (const [u, v] of pts) { const a = alongI ? c + u * R / T : i, b = alongI ? j : c + u * R / T, zz = z + R + v * R; sub.box(alongI ? a - .05 : i - .02, alongI ? j - .02 : b - .05, zz - .6, alongI ? a + .05 : i + .02, alongI ? j + .02 : b + .05, zz + .6, "#1a1620"); }
      };
      if (alongI) { wheel(i - .3); wheel(i + .3); sub.box(i - .3, j - .02, z + 4, i + .3, j + .02, z + 5, col); sub.box(i - .08, j - .02, z + 4, i + .02, j + .02, z + 9, col); sub.box(i - .16, j - .06, z + 9, i + .06, j + .06, z + 9.8, "#2a2433"); sub.box(i + .22, j - .02, z + 5, i + .28, j + .02, z + 10, col); sub.box(i + .22, j - .14, z + 10, i + .28, j + .14, z + 10.6, "#2a2433"); }
      else { wheel(j - .3); wheel(j + .3); sub.box(i - .02, j - .3, z + 4, i + .02, j + .3, z + 5, col); sub.box(i - .02, j - .08, z + 4, i + .02, j + .02, z + 9, col); sub.box(i - .06, j - .16, z + 9, i + .06, j + .06, z + 9.8, "#2a2433"); sub.box(i - .02, j + .22, z + 5, i + .02, j + .28, z + 10, col); sub.box(i - .14, j + .22, z + 10, i + .14, j + .28, z + 10.6, "#2a2433"); }
    });
  };
  /* a van (packet van, delivery), along i (driving +i) or j; logo text on its side */
  Pr.van = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#f2efe6", alongI = (o.face || "SE") === "SE", L = o.len || 1.9, Wd = .5;
    W.group(sub => {
      if (alongI) {
        sub.box(i - L / 2, j - Wd, z + 2, i + L / 2 - .5, j + Wd, z + 15, col, {deco: {front: [[i - L / 2 + .1, z + 4, i + L / 2 - .6, z + 4.8, o.stripe || "#3f6fd8"]]}, text: o.logo ? [{f: "front", a: i - .2, z: z + 7.5, t: o.logo, s: 3.6, c: o.ink || "#2a2433", wt: 800, font: o.font}] : []});
        sub.box(i + L / 2 - .5, j - Wd, z + 2, i + L / 2, j + Wd, z + 11, col, {deco: {front: [[i + L / 2 - .44, z + 6, i + L / 2 - .06, z + 10.4, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")]], right: [[j - Wd + .08, z + 6, j + Wd - .08, z + 10.4, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")], [j - Wd + .04, z + 3, j - Wd + .16, z + 4.4, "!#fff3c0"], [j + Wd - .16, z + 3, j + Wd - .04, z + 4.4, "!#fff3c0"]]}});
        for (const a of [i - L / 2 + .35, i + L / 2 - .4]) for (const b of [j - Wd - .02, j + Wd - .12]) sub.box(a - .2, b, z, a + .2, b + .14, z + 4.4, "#1a1620", {deco: {front: [[a - .08, z + 1.4, a + .08, z + 3, "#8a8ea8"]]}});
        W.pool(i + L / 2 + .9, j, z, 26, "#fff3c0", .35);
      } else {
        sub.box(i - Wd, j - L / 2, z + 2, i + Wd, j + L / 2 - .5, z + 15, col, {deco: {right: [[j - L / 2 + .1, z + 4, j + L / 2 - .6, z + 4.8, o.stripe || "#3f6fd8"]]}, text: o.logo ? [{f: "right", a: j - .2, z: z + 7.5, t: o.logo, s: 3.6, c: o.ink || "#2a2433", wt: 800, font: o.font}] : []});
        sub.box(i - Wd, j + L / 2 - .5, z + 2, i + Wd, j + L / 2, z + 11, col, {deco: {right: [[j + L / 2 - .44, z + 6, j + L / 2 - .06, z + 10.4, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")]], front: [[i - Wd + .08, z + 6, i + Wd - .08, z + 10.4, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")], [i - Wd + .04, z + 3, i - Wd + .16, z + 4.4, "!#fff3c0"], [i + Wd - .16, z + 3, i + Wd - .04, z + 4.4, "!#fff3c0"]]}});
        for (const b of [j - L / 2 + .35, j + L / 2 - .4]) for (const a of [i - Wd - .02, i + Wd - .12]) sub.box(a, b - .2, z, a + .14, b + .2, z + 4.4, "#1a1620", {deco: {right: [[b - .08, z + 1.4, b + .08, z + 3, "#8a8ea8"]]}});
        W.pool(i, j + L / 2 + .9, z, 26, "#fff3c0", .35);
      }
    });
    W.shadow(alongI ? i - L / 2 : i - Wd, alongI ? j - Wd : j - L / 2, alongI ? i + L / 2 : i + Wd, alongI ? j + Wd : j + L / 2, 10, z, .6);
  };
  /* a food truck parked along i, serving hatch on its +y side, an awning and a menu board */
  Pr.foodTruck = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#ff8a5a", L = 2.6, Wd = .62;
    W.group(sub => {
      sub.box(i - L / 2, j - Wd, z + 2.4, i + L / 2 - .7, j + Wd, z + 20, col, {deco: {front: [[i - L / 2 + .3, z + 9, i + L / 2 - 1, z + 16, "#2a1a2e"], [i - L / 2 + .36, z + 9.4, i + L / 2 - 1.06, z + 15.6, "!#ffd98a"], [i - L / 2, z + 2.4, i + L / 2 - .7, z + 4, shade(col, .8)]]}, text: [{f: "front", a: i - .35, z: z + 17, t: o.name || "TACO BYTE", s: 2.6, c: "!#fff8ec", wt: 800, font: o.font}]});
      sub.box(i - L / 2 + .3, j + Wd, z + 8.6, i + L / 2 - 1, j + Wd + .16, z + 9.2, "#e9dcc0");               // the counter shelf
      sub.box(i - L / 2 + .2, j + Wd, z + 16.4, i + L / 2 - .9, j + Wd + .5, z + 17.2, "#fff3d6", {deco: {top: Array.from({length: 6}, (_, k) => [i - L / 2 + .2 + k * .25, j + Wd, i - L / 2 + .32 + k * .25, j + Wd + .5, "#e0473a"])}});
      sub.box(i + L / 2 - .7, j - Wd, z + 2.4, i + L / 2, j + Wd, z + 15, tint(col, .1), {deco: {front: [[i + L / 2 - .64, z + 8, i + L / 2 - .08, z + 14, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")]], right: [[j - Wd + .1, z + 8, j + Wd - .1, z + 14, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")]]}});
      for (const a of [i - L / 2 + .45, i + L / 2 - .45]) for (const b of [j - Wd - .02, j + Wd - .12]) sub.box(a - .24, b, z, a + .24, b + .14, z + 5, "#1a1620", {deco: {front: [[a - .1, z + 1.6, a + .1, z + 3.4, "#8a8ea8"]]}});
      sub.box(i - .2, j - .2, z + 20, i + .4, j + .2, z + 23, "#9aa3b4");
    });
    W.pool(i - .3, j + Wd + .6, z, 40, "#ffd98a", .55);
    W.shadow(i - L / 2, j - Wd, i + L / 2, j + Wd, 14, z, .6);
  };
  /* a picnic / café table with two stools */
  Pr.cafeTable = function (W, i, j, z = 0, o = {}) {
    const top = o.top || "#f2efe6";
    W.group(sub => {
      sub.box(i - .05, j - .05, z, i + .05, j + .05, z + 7, "#2a2433");
      sub.box(i - .3, j - .3, z + 7, i + .3, j + .3, z + 7.8, top);
      if (o.umbrella) { sub.box(i - .03, j - .03, z + 7.8, i + .03, j + .03, z + 20, "#2a2433"); sub.box(i - .7, j - .7, z + 20, i + .7, j + .7, z + 21.4, o.umbrella, {deco: {top: [[i - .7, j - .1, i + .7, j + .1, "#fff8ec"], [i - .1, j - .7, i + .1, j + .7, "#fff8ec"]]}}); sub.box(i - .4, j - .4, z + 21.4, i + .4, j + .4, z + 22.6, o.umbrella); }
    });
    for (const [a, b] of [[i - .55, j], [i + .55, j]]) W.box(a - .14, b - .14, z, a + .14, b + .14, z + 4.4, o.stool || "#a8743a");
  };
  /* a planter box with a shrub */
  Pr.planter = function (W, i, j, z = 0, o = {}) {
    W.box(i - .3, j - .3, z, i + .3, j + .3, z + 4, o.col || "#7a6a5a", {deco: {top: [[i - .24, j - .24, i + .24, j + .24, "#4a3226"]]}});
    Pr.shrub(W, i, j, z + 4, .62, o.green || "#3f9a52", o.flowers || null, i * 13 + j);
  };
  /* a fire hydrant / post box for the street */
  Pr.hydrant = function (W, i, j, z = 0) { W.box(i - .08, j - .08, z, i + .08, j + .08, z + 5, "#e0473a"); W.box(i - .1, j - .1, z + 5, i + .1, j + .1, z + 6, "#c4364a"); W.box(i - .13, j - .03, z + 2.6, i + .13, j + .03, z + 3.6, "#c4364a"); };
  Pr.postBox = function (W, i, j, z = 0) { W.box(i - .16, j - .16, z, i + .16, j + .16, z + 10, "#e0473a", {deco: {front: [[i - .1, z + 7.6, i + .1, z + 8.2, "#2a1a2e"]]}}); W.box(i - .18, j - .18, z + 10, i + .18, j + .18, z + 11, "#c4364a"); };
  /* a bus-stop / shelter: posts, a roof, a glass back and a bench */
  Pr.shelter = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#2a2433";
    for (const a of [i - .7, i + .62]) W.box(a, j - .3, z, a + .08, j - .22, z + 24, col);
    W.box(i - .7, j - .3, z + 2, i + .7, j - .26, z + 22, "#bfe3ff", {opacity: .28});
    W.box(i - .8, j - .4, z + 24, i + .8, j + .3, z + 26, col, {deco: {front: [[i - .8, z + 24.2, i + .8, z + 25.8, o.band || "#FFD83D"]]}});
    W.box(i - .55, j - .22, z + 4.4, i + .55, j + .02, z + 5.4, "#a8743a");
  };

  /* ---------- water ---------- */
  /* water surface over a list of tiles at height z, translucent, with glints */
  Pr.water = function (W, tiles, z, col = "#3f7fc0", o = {}) {
    const r = rnd("w" + tiles.length), fill = K.lit(col, [0, 0, 1]);
    for (const [i, j] of tiles) {
      W.water.push(K.poly([P(i, j, z), P(i + 1, j, z), P(i + 1, j + 1, z), P(i, j + 1, z)], fill, o.op || .86));
      if (r() < .45) { const a = i + r() * .7, b = j + r() * .8; W.water.push(K.poly([P(a, b, z + .05), P(a + .3, b, z + .05), P(a + .3, b + .06, z + .05), P(a, b + .06, z + .05)], "#bfe6ff", .55)); }
    }
  };

  /* ---------- people-scaled street furniture (overrides) ---------- */
  Pr.bench = function (W, i, j, z = 0, o = {}) {
    const wood = o.wood || "#a8743a", iron = o.iron || "#2a2433", alongI = (o.face || "SW") === "SW", L = o.len || 1.9;
    W.group(sub => {
      if (alongI) {
        for (const a of [i - L / 2 + .1, i + L / 2 - .22]) { sub.box(a, j - .26, z, a + .12, j + .26, z + 6, iron); sub.box(a, j - .34, z + 6, a + .12, j - .24, z + 14, iron); }
        sub.box(i - L / 2, j - .26, z + 6, i + L / 2, j + .3, z + 7.4, wood, {deco: {top: [[i - L / 2, j - .05, i + L / 2, j - .01, shade(wood, .8)], [i - L / 2, j + .12, i + L / 2, j + .16, shade(wood, .8)]]}});
        sub.box(i - L / 2, j - .36, z + 8.6, i + L / 2, j - .26, z + 10.6, wood); sub.box(i - L / 2, j - .36, z + 11.4, i + L / 2, j - .26, z + 13.4, wood);
      } else {
        for (const b of [j - L / 2 + .1, j + L / 2 - .22]) { sub.box(i - .26, b, z, i + .26, b + .12, z + 6, iron); sub.box(i - .34, b, z + 6, i - .24, b + .12, z + 14, iron); }
        sub.box(i - .26, j - L / 2, z + 6, i + .3, j + L / 2, z + 7.4, wood, {deco: {top: [[i - .05, j - L / 2, i - .01, j + L / 2, shade(wood, .8)], [i + .12, j - L / 2, i + .16, j + L / 2, shade(wood, .8)]]}});
        sub.box(i - .36, j - L / 2, z + 8.6, i - .26, j + L / 2, z + 10.6, wood); sub.box(i - .36, j - L / 2, z + 11.4, i - .26, j + L / 2, z + 13.4, wood);
      }
    }, {bias: -30});
    W.shadow(alongI ? i - L / 2 : i - .3, alongI ? j - .3 : j - L / 2, alongI ? i + L / 2 : i + .3, alongI ? j + .3 : j + L / 2, 7, z, .5);
    return {seat: z + 7.4 - 4.2};
  };
  Pr.bin = function (W, i, j, z = 0, col = "#3a5a4a") { W.box(i - .2, j - .2, z, i + .2, j + .2, z + 10, col, {deco: {front: [[i - .2, z + 7.6, i + .2, z + 8.4, shade(col, .7)], [i - .2, z + 2, i + .2, z + 2.6, shade(col, .7)]], right: [[j - .2, z + 7.6, j + .2, z + 8.4, shade(col, .7)], [j - .2, z + 2, j + .2, z + 2.6, shade(col, .7)]]}}); W.box(i - .24, j - .24, z + 10, i + .24, j + .24, z + 11.2, shade(col, .85)); };
  Pr.bollard = function (W, i, j, z = 0, col = "#2a2433") { W.box(i - .1, j - .1, z, i + .1, j + .1, z + 8, col, {deco: {front: [[i - .1, z + 5.6, i + .1, z + 6.6, "#e9dcc0"]], right: [[j - .1, z + 5.6, j + .1, z + 6.6, "#e9dcc0"]]}}); };
  Pr.streetSign = function (W, i, j, z, name, o = {}) {
    const post = o.post || "#2a2433", bg = o.bg || "#2f5a8a", ink = o.ink || "#f4f1ea", alongI = (o.face || "SW") === "SW";
    W.box(i - .06, j - .06, z, i + .06, j + .06, z + 46, post);
    W.box(i - .08, j - .08, z + 46, i + .08, j + .08, z + 47.2, post);
    const w = Math.max(1.2, name.length * .3 + .4);
    if (alongI) W.box(i - w / 2, j - .04, z + 38, i + w / 2, j + .04, z + 45, bg, {deco: {front: [[i - w / 2 + .06, z + 38.6, i + w / 2 - .06, z + 38.9, "!" + ink], [i - w / 2 + .06, z + 44.1, i + w / 2 - .06, z + 44.4, "!" + ink]]}, text: [{f: "front", a: i, z: z + 39.9, t: name, s: 4.6, c: "!" + ink, wt: 700, font: o.font, ls: .3}]});
    else W.box(i - .04, j - w / 2, z + 38, i + .04, j + w / 2, z + 45, bg, {deco: {right: [[j - w / 2 + .06, z + 38.6, j + w / 2 - .06, z + 38.9, "!" + ink], [j - w / 2 + .06, z + 44.1, j + w / 2 - .06, z + 44.4, "!" + ink]]}, text: [{f: "right", a: j, z: z + 39.9, t: name, s: 4.6, c: "!" + ink, wt: 700, font: o.font, ls: .3}]});
  };
  /* a wheel as a stepped disc in the plane of travel */
  const wheel = (sub, alongI, c, other, z, R, th) => {
    const rows = [[-.45, .45], [-.8, .8], [-1, 1], [-1, 1], [-.8, .8], [-.45, .45]];
    rows.forEach(([a0, a1], k) => {
      const z0 = z + k * (2 * R / rows.length), z1 = z0 + 2 * R / rows.length;
      const u0 = c + a0 * R / 16, u1 = c + a1 * R / 16;
      const rim = k === 0 || k === rows.length - 1;
      if (alongI) sub.box(u0, other - th, z0, u1, other + th, z1, "#1a1620", {deco: {front: rim ? [] : [[c - .06 * R / 6, z0, c + .06 * R / 6, z1, "#8a8ea8"]]}});
      else sub.box(other - th, u0, z0, other + th, u1, z1, "#1a1620", {deco: {right: rim ? [] : [[c - .06 * R / 6, z0, c + .06 * R / 6, z1, "#8a8ea8"]]}});
    });
  };
  Pr.bike = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#e0473a", alongI = (o.face || "SW") === "SE", R = 6;
    W.group(sub => {
      if (alongI) {
        wheel(sub, true, i - .5, j, z, R, .03); wheel(sub, true, i + .5, j, z, R, .03);
        sub.box(i - .5, j - .03, z + R - .5, i + .5, j + .03, z + R + .7, col); sub.box(i - .12, j - .03, z + R, i, j + .03, z + 13, col);
        sub.box(i - .24, j - .1, z + 13, i + .06, j + .1, z + 14.2, "#2a2433"); sub.box(i + .38, j - .03, z + R, i + .46, j + .03, z + 15, col); sub.box(i + .36, j - .24, z + 15, i + .46, j + .24, z + 15.8, "#2a2433");
      } else {
        wheel(sub, false, j - .5, i, z, R, .03); wheel(sub, false, j + .5, i, z, R, .03);
        sub.box(i - .03, j - .5, z + R - .5, i + .03, j + .5, z + R + .7, col); sub.box(i - .03, j - .12, z + R, i + .03, j, z + 13, col);
        sub.box(i - .1, j - .24, z + 13, i + .1, j + .06, z + 14.2, "#2a2433"); sub.box(i - .03, j + .38, z + R, i + .03, j + .46, z + 15, col); sub.box(i - .24, j + .36, z + 15, i + .24, j + .46, z + 15.8, "#2a2433");
      }
    });
  };
  /* a van along i (driving +i, face SE) or along j (SW) */
  Pr.van = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#f2efe6", alongI = (o.face || "SE") === "SE", L = o.len || 3.2, Wd = .78, H = o.h || 28;
    const g = W.group(sub => {
      if (alongI) {
        sub.box(i - L / 2, j - Wd, z + 4, i + L / 2 - .9, j + Wd, z + H, col, {deco: {front: [[i - L / 2 + .1, z + 7, i + L / 2 - 1, z + 8.4, o.stripe || "#3f6fd8"]], top: [[i - L / 2 + .2, j - Wd + .2, i + L / 2 - 1.1, j + Wd - .2, shade(col, .94)]]}, text: o.logo ? [{f: "front", a: i - .45, z: z + 12.5, t: o.logo, s: 6.4, c: o.ink || "#2a2433", wt: 800, font: o.font, ls: .4}] : []});
        sub.box(i + L / 2 - .9, j - Wd, z + 4, i + L / 2, j + Wd, z + H - 7, col, {deco: {front: [[i + L / 2 - .82, z + 12, i + L / 2 - .12, z + H - 9, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")]], right: [[j - Wd + .1, z + 12, j + Wd - .1, z + H - 9, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")], [j - Wd + .06, z + 6, j - Wd + .3, z + 8.4, "!#fff3c0"], [j + Wd - .3, z + 6, j + Wd - .06, z + 8.4, "!#fff3c0"], [j - Wd, z + 4, j + Wd, z + 5.4, "#2a2433"]]}});
        wheel(sub, true, i - L / 2 + .65, j + Wd - .02, z, 4.6, .1); wheel(sub, true, i + L / 2 - .7, j + Wd - .02, z, 4.6, .1);
        wheel(sub, true, i - L / 2 + .65, j - Wd + .02, z, 4.6, .1); wheel(sub, true, i + L / 2 - .7, j - Wd + .02, z, 4.6, .1);
      } else {
        sub.box(i - Wd, j - L / 2, z + 4, i + Wd, j + L / 2 - .9, z + H, col, {deco: {right: [[j - L / 2 + .1, z + 7, j + L / 2 - 1, z + 8.4, o.stripe || "#3f6fd8"]], top: [[i - Wd + .2, j - L / 2 + .2, i + Wd - .2, j + L / 2 - 1.1, shade(col, .94)]]}, text: o.logo ? [{f: "right", a: j - .45, z: z + 12.5, t: o.logo, s: 6.4, c: o.ink || "#2a2433", wt: 800, font: o.font, ls: .4}] : []});
        sub.box(i - Wd, j + L / 2 - .9, z + 4, i + Wd, j + L / 2, z + H - 7, col, {deco: {right: [[j + L / 2 - .82, z + 12, j + L / 2 - .12, z + H - 9, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")]], front: [[i - Wd + .1, z + 12, i + Wd - .1, z + H - 9, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")], [i - Wd + .06, z + 6, i - Wd + .3, z + 8.4, "!#fff3c0"], [i + Wd - .3, z + 6, i + Wd - .06, z + 8.4, "!#fff3c0"], [i - Wd, z + 4, i + Wd, z + 5.4, "#2a2433"]]}});
        wheel(sub, false, j - L / 2 + .65, i + Wd - .02, z, 4.6, .1); wheel(sub, false, j + L / 2 - .7, i + Wd - .02, z, 4.6, .1);
        wheel(sub, false, j - L / 2 + .65, i - Wd + .02, z, 4.6, .1); wheel(sub, false, j + L / 2 - .7, i - Wd + .02, z, 4.6, .1);
      }
    });
    if (alongI) W.pool(i + L / 2 + 1.6, j, z, 34, "#fff3c0", .3); else W.pool(i, j + L / 2 + 1.6, z, 34, "#fff3c0", .3);
    W.shadow(alongI ? i - L / 2 : i - Wd, alongI ? j - Wd : j - L / 2, alongI ? i + L / 2 : i + Wd, alongI ? j + Wd : j + L / 2, 16, z, .6);
    return g;
  };
  Pr.foodTruck = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#ff8a5a", L = 4.2, Wd = 1, H = 34;
    W.group(sub => {
      sub.box(i - L / 2, j - Wd, z + 4.6, i + L / 2 - 1.1, j + Wd, z + H, col, {deco: {front: [[i - L / 2 + .35, z + 13, i + L / 2 - 1.5, z + 25, "#2a1a2e"], [i - L / 2 + .42, z + 13.6, i + L / 2 - 1.58, z + 24.4, "!#ffd98a"], [i - L / 2 + .7, z + 17, i - L / 2 + 1.1, z + 22, "!#c4364a"], [i - L / 2 + 1.4, z + 16, i - L / 2 + 1.7, z + 23, "!#5a3a2a"], [i - L / 2, z + 4.6, i + L / 2 - 1.1, z + 6.4, shade(col, .8)]]}, text: [{f: "front", a: i - .55 - .1, z: z + 28.6, t: o.name || "TACO BYTE", s: 4.8, c: "!#fff8ec", wt: 900, font: o.font, ls: .3}]});
      sub.box(i - L / 2 + .35, j + Wd, z + 12.4, i + L / 2 - 1.5, j + Wd + .24, z + 13.2, "#e9dcc0");
      // the hatch has a real frame: jambs and a header that stand proud of the body, so the opening reads as a recess
      for (const a of [i - L / 2 + .25, i + L / 2 - 1.6]) sub.box(a, j + Wd, z + 13.2, a + .12, j + Wd + .14, z + 25.2, shade(col, .75));
      sub.box(i - L / 2 + .25, j + Wd, z + 25, i + L / 2 - 1.48, j + Wd + .14, z + 25.6, shade(col, .75));
      sub.box(i - L / 2 + .25, j + Wd, z + 25.6, i + L / 2 - 1.4, j + Wd + .7, z + 26.6, "#fff3d6", {deco: {top: Array.from({length: 8}, (_, k) => [i - L / 2 + .25 + k * .32, j + Wd, i - L / 2 + .41 + k * .32, j + Wd + .7, "#e0473a"])}});
      sub.box(i + L / 2 - 1.1, j - Wd, z + 4.6, i + L / 2, j + Wd, z + 25, tint(col, .1), {deco: {front: [[i + L / 2 - 1, z + 13, i + L / 2 - .12, z + 22, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")]], right: [[j - Wd + .14, z + 13, j + Wd - .14, z + 22, (window.__NIGHT ? "#5a7aa8" : "!#9fd0ff")], [j - Wd + .08, z + 7, j - Wd + .34, z + 9.4, "!#fff3c0"], [j + Wd - .34, z + 7, j + Wd - .08, z + 9.4, "!#fff3c0"]]}});
      for (const a of [i - L / 2 + .75, i + L / 2 - .75]) { wheel(sub, true, a, j + Wd - .02, z, 5, .12); }
      sub.box(i - .4, j - .4, z + H, i + .5, j + .3, z + H + 4, "#9aa3b4");
      // the menu board on an easel by the hatch
      sub.box(i - L / 2 - .1, j + Wd + .9, z, i - L / 2 + .02, j + Wd + 1.0, z + 14, "#5a3a2a");
    });
    W.box(i - L / 2 - .5, j + Wd + .9, z + 5, i - L / 2 + .4, j + Wd + 1.0, z + 16, "#2a2433", {deco: {front: [[i - L / 2 - .44, z + 13.4, i - L / 2 + .34, z + 14, "!#fff3d6"], [i - L / 2 - .44, z + 11.4, i - L / 2 + .2, z + 12, "!#fff3d6"], [i - L / 2 - .44, z + 9.4, i - L / 2 + .3, z + 10, "!#fff3d6"], [i - L / 2 - .44, z + 7.4, i - L / 2 + .1, z + 8, "!#ffd04a"]]}});
    W.pool(i - .5, j + Wd + 1, z, 56, "#ffd98a", .55);
    W.shadow(i - L / 2, j - Wd, i + L / 2, j + Wd, 20, z, .6);
  };
  Pr.cafeTable = function (W, i, j, z = 0, o = {}) {
    const top = o.top || "#f2efe6";
    W.box(i - .07, j - .07, z, i + .07, j + .07, z + 10, "#2a2433");
    W.box(i - .4, j - .4, z + 10, i + .4, j + .4, z + 11, top);
    if (o.umbrella) { W.box(i - .04, j - .04, z + 11, i + .04, j + .04, z + 30, "#2a2433"); W.box(i - 1, j - 1, z + 30, i + 1, j + 1, z + 32, o.umbrella, {deco: {top: [[i - 1, j - .14, i + 1, j + .14, "#fff8ec"], [i - .14, j - 1, i + .14, j + 1, "#fff8ec"]], front: [[i - 1, z + 30, i - .5, z + 32, "#fff8ec"], [i, z + 30, i + .5, z + 32, "#fff8ec"]], right: [[j - 1, z + 30, j - .5, z + 32, "#fff8ec"], [j, z + 30, j + .5, z + 32, "#fff8ec"]]}}); W.box(i - .6, j - .6, z + 32, i + .6, j + .6, z + 34, o.umbrella); }
    for (const [a, b] of (o.stools || [[i - .75, j], [i + .75, j]])) { // a chair: legs, a seat, a back on the side away from the table
      const col = o.stool || "#a8743a", di = Math.sign(Math.round((a - i) * 10)), dj = Math.sign(Math.round((b - j) * 10));
      for (const [p, q] of [[-.16, -.16], [.12, -.16], [-.16, .12], [.12, .12]]) W.box(a + p, b + q, z, a + p + .05, b + q + .05, z + 5.4, "#2a2433");
      W.box(a - .2, b - .2, z + 5.4, a + .2, b + .2, z + 6.4, col);
      if (di) W.box(di > 0 ? a + .14 : a - .2, b - .2, z + 6.4, di > 0 ? a + .2 : a - .14, b + .2, z + 13, col);
      else if (dj) W.box(a - .2, dj > 0 ? b + .14 : b - .2, z + 6.4, a + .2, dj > 0 ? b + .2 : b - .14, z + 13, col);
    }
  };
  Pr.shelter = function (W, i, j, z = 0, o = {}) {
    const col = o.col || "#2a2433";
    for (const a of [i - 1.1, i + 1.0]) W.box(a, j - .5, z, a + .1, j - .4, z + 50, col);
    W.box(i - 1.1, j - .5, z + 3, i + 1.1, j - .44, z + 46, "#bfe3ff", {opacity: .3});
    W.box(i - 1.25, j - .65, z + 50, i + 1.25, j + .5, z + 53, col, {deco: {front: [[i - 1.25, z + 50.4, i + 1.25, z + 52.6, o.band || "#FFD83D"]]}});
    W.box(i - .9, j - .4, z + 6.4, i + .9, j - .02, z + 7.8, "#a8743a");
  };

  /* a rounded voxel crown: stacked slabs [half-width, height] from z0, plus lumps [di, dj, half, z, h] */
  const crown = (W, i, j, z0, s, slabs, lumps, col, r, extra) => {
    let z = z0;
    slabs.forEach(([hw, h], k) => {
      const c = k >= slabs.length - 2 ? tint(col, .08 * (k - slabs.length + 3)) : col;
      const D = leafDeco(i - hw * s, j - hw * s, z, i + hw * s, j + hw * s, z + h * s, c, r, 3 + Math.round(hw * 3));
      if (extra) extra(D, i - hw * s, j - hw * s, z, i + hw * s, j + hw * s, z + h * s);
      W.box(i - hw * s, j - hw * s, z, i + hw * s, j + hw * s, z + h * s, c, {deco: D});
      z += h * s;
    });
    for (const [di, dj, hw, lz, h] of lumps || []) {
      const D = leafDeco(i + (di - hw) * s, j + (dj - hw) * s, z0 + lz * s, i + (di + hw) * s, j + (dj + hw) * s, z0 + (lz + h) * s, shade(col, .96), r, 2);
      if (extra) extra(D, i + (di - hw) * s, j + (dj - hw) * s, z0 + lz * s, i + (di + hw) * s, j + (dj + hw) * s, z0 + (lz + h) * s);
      W.box(i + (di - hw) * s, j + (dj - hw) * s, z0 + lz * s, i + (di + hw) * s, j + (dj + hw) * s, z0 + (lz + h) * s, shade(col, .96), {deco: D});
    }
  };
  Pr.crown = crown;
  const baseTree = Pr.tree;
  Pr.tree = function (W, kind, i, j, z = 0, s = 1, seed = i * 31 + j) {
    const r = rnd(kind + seed), S = s * 1.75;
    const trunk = (h, w, col = "#7a4a2e") => W.box(i - w, j - w, z, i + w, j + w, z + h, col, {deco: {front: [[i - w, z + h * .3, i - w + .06, z + h * .55, shade(col, .8)], [i + w - .08, z + h * .6, i + w - .02, z + h * .8, shade(col, .8)]], right: [[j - w + .05, z + h * .4, j - w + .1, z + h * .7, shade(col, .8)]]}});
    if (kind === "oak") {
      const g = ["#3f9a52", "#4aa65a", "#3a8f4c"][Math.floor(r() * 3)];
      trunk(15 * S, .2 * Math.min(1.2, s));
      W.box(i + .1, j - .06, z + 11 * S, i + .55 * s, j + .06, z + 12.2 * S, "#7a4a2e");
      crown(W, i, j, z + 12 * S, S, [[.62, 3], [.84, 6], [.92, 8], [.8, 5], [.56, 3]], [[-.62, .2, .3, 6, 9], [.25, .72, .32, 5, 8], [.6, -.3, .28, 9, 8]], g, r);
      W.shadowEllipse(i, j, .95 * S, z, 1.3);
      return;
    }
    if (kind === "maple") {
      const g = ["#e07a3a", "#e8913f", "#d4642f"][Math.floor(r() * 3)];
      trunk(14 * S, .2 * Math.min(1.2, s), "#5e3a28");
      crown(W, i, j, z + 11 * S, S, [[.6, 3], [.86, 7], [.9, 7], [.7, 4], [.4, 3]], [[.3, .7, .3, 4, 8], [-.65, -.2, .28, 6, 7]], g, r);
      W.shadowEllipse(i, j, .95 * S, z, 1.2);
      return;
    }
    if (kind === "cherry") {
      const g = ["#f2a6c8", "#f7b8d4", "#ec9cc0"][Math.floor(r() * 3)];
      trunk(12 * S, .17 * Math.min(1.2, s), "#5e3a32");
      W.box(i - .5 * s, j - .06, z + 8 * S, i - .1, j + .06, z + 9.2 * S, "#5e3a32");
      const bloom = (D, a, b, c, d, e, h) => { for (let k = 0; k < 4; k++) { const u = a + (d - a) * r() * .85, v = b + (e - b) * r() * .85; D.top.push([u, v, u + .09, v + .09, "!#fff0f6"]); } };
      crown(W, i, j, z + 10 * S, S, [[.7, 3], [.92, 6], [.86, 5], [.56, 3]], [[-.55, .55, .32, 3, 6], [.6, .2, .3, 5, 6]], g, r, bloom);
      W.shadowEllipse(i, j, .9 * S, z, 1.2);
      return;
    }
    if (kind === "apple") {
      const g = "#4f9e48";
      trunk(9 * S, .19 * Math.min(1.2, s), "#6a4026");
      const fruit = (D, a, b, c, d, e, h) => { for (let k = 0; k < 3; k++) { D.front.push([a + (d - a) * r() * .85, c + (h - c) * (.2 + r() * .5), 0, 0, "#e0473a"]); D.right.push([b + (e - b) * r() * .85, c + (h - c) * (.2 + r() * .5), 0, 0, "#e0473a"]); } D.front.forEach(q => { if (q[3] === 0) { q[2] = q[0] + .1; q[3] = q[1] + 2; } }); D.right.forEach(q => { if (q[3] === 0) { q[2] = q[0] + .1; q[3] = q[1] + 2; } }); };
      crown(W, i, j, z + 8 * S, S, [[.6, 3], [.78, 7], [.7, 4], [.42, 3]], [[.5, .5, .25, 3, 6]], g, r, fruit);
      W.shadowEllipse(i, j, .8 * S, z, 1.1);
      return;
    }
    if (kind === "birch") {
      const g = ["#8fc25a", "#9ccc62", "#86b852"][Math.floor(r() * 3)];
      const h = 25 * S, w = .12;
      const marks = []; for (let k = 0; k < 6; k++) marks.push([i - w + (k % 2) * .1, z + 3 + k * h / 7, i - w + (k % 2) * .1 + .12, z + 4.2 + k * h / 7, "#2a2433"]);
      W.box(i - w, j - w, z, i + w, j + w, z + h, "#efeae0", {deco: {front: marks, right: marks.map(m => [j - w + (m[0] - i + w), m[1] + 3, j - w + (m[2] - i + w), m[3] + 3, m[4]])}});
      crown(W, i, j, z + 13 * S, S, [[.42, 4], [.56, 7], [.5, 6], [.32, 4]], [[.32, .42, .24, 0, 6], [-.4, -.1, .2, 6, 6]], g, r);
      W.shadowEllipse(i, j, .6 * S, z, 1.3);
      return;
    }
    if (kind === "poplar") {
      const g = ["#4c9a4a", "#55a24f"][Math.floor(r() * 2)];
      W.box(i - .12, j - .12, z, i + .12, j + .12, z + 9 * S, "#7a4a2e");
      crown(W, i, j, z + 6 * S, S, [[.3, 4], [.42, 12], [.4, 12], [.3, 8], [.16, 4]], [], g, r);
      W.shadowEllipse(i, j, .45 * S, z, 1.6);
      return;
    }
    if (kind === "pine") {
      const g = ["#2f7a5a", "#2a6f55", "#327f60"][Math.floor(r() * 3)];
      W.box(i - .16, j - .16, z, i + .16, j + .16, z + 9 * S, "#6a3f28");
      const tiers = [[.78, 6, 13], [.6, 13, 19], [.44, 19, 25], [.28, 25, 31], [.12, 31, 35]];
      for (const [w, a, b] of tiers) {
        const D = leafDeco(i - w * S, j - w * S, z + a * S, i + w * S, j + w * S, z + b * S, g, r, 3);
        D.front.push([i - w * S, z + a * S, i + w * S, z + a * S + 1.2, shade(g, .78)]); D.right.push([j - w * S, z + a * S, j + w * S, z + a * S + 1.2, shade(g, .78)]);
        W.box(i - w * S, j - w * S, z + a * S, i + w * S, j + w * S, z + b * S, g, {deco: D});
      }
      W.shadowEllipse(i, j, .75 * S, z, 1.2);
      return;
    }
    baseTree(W, kind, i, j, z, s, seed);
  };

  /* a cloud: rounded puffs, moonlit on top, as svg (for the layers behind or in front of the island) */
  Pr.cloud = function (W, i, j, z, s = 1, col = "#a49ad6", op = .5, seed = 1) {
    const sub = new K.World(), r = rnd("cl" + i + j + seed);
    const puffs = [[0, 0, 1.2], [1.3, .4, .95], [-1.25, .35, .9], [.4, -.9, .85], [.3, 1.0, .75], [2.2, .9, .6], [-2.1, .9, .55]];
    for (const [a, b, rad] of puffs) {
      const ci = i + a * s, cj = j + b * s, R = rad * s * (.85 + r() * .3), h = R * 16 * .95;
      const prof = [[.7, .18], [.95, .22], [1, .22], [.86, .18], [.55, .2]];
      let zz = z;
      prof.forEach(([w, dh], k) => { const c = k >= 3 ? tint(col, .1 * (k - 2)) : col; sub.box(ci - R * w, cj - R * w * .85, zz, ci + R * w, cj + R * w * .85, zz + h * dh, c, {noStroke: true}); zz += h * dh; });
    }
    // the puffs as one piece; the app gives it its see-through
    const ops = []; for (const it of K.World.sortItems(sub.items)) for (const q of it.ops) ops.push(q);
    return {ops, op};
  };

  window.Props = Pr;
})();
