/* The blocky world (D32): the same box engine as the cast (blocky-cast.js), now for whole scenes. One floor from the
   inside (the atrium, D38), with the team (D41) in it. A plain script; needs BlockyCast first.
     const scene = BlockyWorld.atrium(svgElement, {team})
     scene.person(name, {pos: [i, j], pose, dir, state, emote, seat}) · scene.tokens([...]) · scene.fx(kind, step)
     scene.moveCat(toPorch) · scene.roomAt(i, j) · scene.toTile(x, y) · scene.P(i, j, z)
   Positions are in tiles (i, j) as on the floor plan; one tile is 16 model units, a person about 28. */
(function () {
  const B = window.BlockyCast, E = B.engine, T = 16, S = 1;
  const NS = "http://www.w3.org/2000/svg";
  const f = v => (+v).toFixed(1);
  const F0 = E.frame([[1, 0, 0], [0, 1, 0], [0, 0, 1]], [0, 0, 0]);
  const proj = E.projWith(S);
  const P = (i, j, z = 0) => proj([i * T, j * T, z]);
  const FONT = "Bungee, 'Archivo Black', Archivo, sans-serif";
  /* a storey plaque's width: its text as painted (the app paints signs in a system face and sets BlockyWorld.signFont),
     with the same 6 units of padding left and right */
  let measurer = null;
  const plaqueW = txt => {
    try {
      measurer = measurer || document.createElement("canvas").getContext("2d");
      measurer.font = `7.4px ${(window.BlockyWorld && window.BlockyWorld.signFont) || FONT}`;
      const w = measurer.measureText(txt).width;
      if (w > 0) return Math.ceil(w) + 12;
    } catch (e) { /* no canvas: estimate */ }
    return txt.length * 6.4 + 12;
  };
  /* a storey plaque (D22, D58, D62): a bracket off the facade, the cream board (a factory's is ink with a cyan edge;
     yellow while it waits for you), and the project's own logo as a small framed square left of its name */
  const LOGO_W = 12;
  const plaqueBoxW = fl => plaqueW(fl.name) + (fl.logo ? LOGO_W : 0);
  const plaqueSVG = (x, y, fl) => {
    const w = plaqueBoxW(fl), lw = fl.logo ? LOGO_W : 0, dark = fl.kind === "factory" && !fl.wait;
    const logo = fl.logo ? `<rect x="${f(x + 18)}" y="${f(y - 4.6)}" width="9.2" height="9.2" rx="1.6" fill="#ffffff" stroke="#2a1a2e" stroke-width="1"/><image href="${fl.logo}" x="${f(x + 18.6)}" y="${f(y - 4)}" width="8" height="8" preserveAspectRatio="xMidYMid meet"/>` : "";
    return `<g><line x1="${f(x)}" y1="${f(y)}" x2="${f(x + 14)}" y2="${f(y)}" stroke="#2a1a2e" stroke-width="1.6"/><rect x="${f(x + 14)}" y="${f(y - 7)}" width="${f(w)}" height="13" fill="${fl.wait ? "#FFD83D" : dark ? "#2a1a2e" : "#fff3d6"}" stroke="#2a1a2e" stroke-width="1.6"/>${dark ? `<rect x="${f(x + 15.6)}" y="${f(y - 5.4)}" width="1.6" height="9.8" fill="#9be7ff"/>` : ""}${logo}<text x="${f(x + 20 + lw)}" y="${f(y + 2.6)}" font-family="${FONT}" font-size="7.4" fill="${dark ? "#fff3d6" : "#2a1a2e"}">${fl.name}</text></g>`;
  };

  /* the plan, in tiles: the same rooms, gardens and void as before */
  const ROOMS = [
    {id: "stacks", n: 2, name: "RESEARCH", i: 0, j: 0, w: 4, d: 5, floor: ["#b97a4a", "#a86c40"]},
    {id: "landing", n: 1, name: "ENTRANCE", i: 4, j: 0, w: 4, d: 5, floor: ["#7a4e8c", "#6c4480"]},
    {id: "war", n: 3, name: "PLANNING", i: 8, j: 0, w: 6, d: 5, floor: ["#d4a76a", "#c4955a"]},
    {id: "workshop", n: 4, name: "DEVELOPMENT", i: 14, j: 0, w: 7, d: 5, floor: ["#5d7fa8", "#54739a"]},
    {id: "switch", n: 9, name: "TOOLS", i: 21, j: 3, w: 3, d: 2, floor: ["#3f8f8a", "#357a76"]},
    {id: "boiler", n: 5, name: "BUILDS", i: 18, j: 5, w: 6, d: 6, floor: ["#8a6656", "#7a5848"]},
    {id: "crash", n: 6, name: "TESTING", i: 17, j: 11, w: 7, d: 5, floor: ["#9ee0c4", "#86ccb0"]},
    {id: "mail", n: 7, name: "PULL REQUESTS", i: 9, j: 11, w: 5, d: 5, floor: ["#b2aaa4", "#a29a94"]},
    {id: "launch", n: 8, name: "DEPLOY", i: 3, j: 11, w: 6, d: 5, floor: ["#5c6a8a", "#52607e"]},
    {id: "porch", n: 11, name: "LOUNGE", i: 0, j: 9, w: 3, d: 7, floor: ["#dba664", "#c9944f"]}
  ];
  const HALL = {i: 3, j: 5, w: 15, d: 6}, CENTER = [10.5, 8];
  const GARDENS = [{i: 0, j: 5, w: 3, d: 4}, {i: 21, j: 0, w: 3, d: 3}], VOID = {i: 14, j: 11, w: 3, d: 5};
  const DIAL = {rx: [2.15, 4.55], ry: [2.0, 2.75], phases: [
    {name: "PLAN", col: "#f2a65a", a0: -165, a1: -58}, {name: "BUILD", col: "#5b8cf0", a0: -58, a1: 14}, {name: "TEST", col: "#3fd0a0", a0: 14, a1: 52},
    {name: "SHIP", col: "#b07cf0", a0: 52, a1: 138}, {name: "DONE", col: "#e98aa8", a0: 138, a1: 195}]};
  const inRect = (i, j, r) => i >= r.i && i < r.i + r.w && j >= r.j && j < r.j + r.d;
  const dp = (deg, k) => { const t = deg * Math.PI / 180, rx = DIAL.rx[0] + (DIAL.rx[1] - DIAL.rx[0]) * k, ry = DIAL.ry[0] + (DIAL.ry[1] - DIAL.ry[0]) * k; return [CENTER[0] + Math.cos(t) * rx, CENTER[1] + Math.sin(t) * ry]; };
  const ST = {work: "#5b8cf0", wait: "#FFD83D", stuck: "#ff4a4a", done: "#9aa19a"};
  const GLOWS = ["ffb070", "ffd9a0", "7cff9a", "8ab4ff", "ff8a5a", "FFD83D", "ff4a4a"];
  const glow = (x, y, r, col, a = .35, cls = "") => `<ellipse class="${cls}" cx="${f(x)}" cy="${f(y)}" rx="${r}" ry="${r * .55}" fill="url(#bw-glow-${col.replace("#", "")})" opacity="${a}" style="mix-blend-mode:screen;pointer-events:none"/>`;

  /* a provider's mark as 7×7 pixels (D55): a spark for Claude, a rosette for ChatGPT. Simplified marks in the
     blocky style that say whose building you are in; not the providers' own artwork. */
  const MARKS = {
    claude: ["x..x..x", ".x.x.x.", "..xxx..", "xxxxxxx", "..xxx..", ".x.x.x.", "x..x..x"],
    chatgpt: ["..xxx..", ".x...x.", "x.x.x.x", "x..x..x", "x.x.x.x", ".x...x.", "..xxx.."]
  };
  /* the mark's pixels as face rectangles [u0, v0, u1, v1, colour], from (u, v) at the top left, px units a pixel; v
     counts up (a face's height), so row 0 is the highest */
  const markRects = (prov, u, v, px, col) => {
    const rows = MARKS[prov] || [], out = [];
    rows.forEach((row, r) => [...row].forEach((ch, c) => { if (ch === "x") out.push([u + c * px, v - (r + 1) * px, u + (c + 1) * px, v - r * px, col]); }));
    return out;
  };
  /* the same mark lying on the floor, as top-face rectangles in floor units */
  const markFloor = (prov, x, y, px, col) => {
    const rows = MARKS[prov] || [], out = [];
    rows.forEach((row, r) => [...row].forEach((ch, c) => { if (ch === "x") out.push([x + c * px, y + r * px, x + (c + 1) * px, y + (r + 1) * px, col]); }));
    return out;
  };

  function atrium(svg, opts = {}) {
    const objs = [], boxes = [];
    let base = new E.Scene(S), top = "", under = "";
    // an object: its own little scene, sorted by the depth of its front corner
    const obj = (key, draw, block) => { const sc = new E.Scene(S); draw(sc); objs.push({key, sc}); if (block) boxes.push({...block, key}); };
    // things people walk round that do not hide what stands behind them (plants, lamps, the rocket), in tiles
    const solids = [];
    const solid = (i0, j0, i1, j1) => solids.push({i0, j0, i1, j1});
    // a box in tile coordinates for x/y and model units for z
    const bx = (sc, i0, j0, z0, i1, j1, z1, col, deco, opt) => sc.box(F0, [i0 * T, j0 * T, z0], [i1 * T, j1 * T, z1], col, deco || {}, opt || {});
    const prop = (i0, j0, i1, j1, z1, col, deco, extra, z0 = 0) => obj(i1 + j1, sc => { bx(sc, i0, j0, z0, i1, j1, z1, col, deco); if (extra) extra(sc); }, {i0, j0, i1, j1});

    /* ---------- the slab, the floor below in the void, the floors ---------- */
    const slab = new E.Scene(S);
    bx(slab, 0, 0, -14, 24, 11, -1, {base: "#3a3f63", top: "#3a3f63"});
    bx(slab, 0, 11, -14, VOID.i, 16, -1, {base: "#3a3f63"}); bx(slab, VOID.i + VOID.w, 11, -14, 24, 16, -1, {base: "#3a3f63"});
    const lower = new E.Scene(S);
    bx(lower, VOID.i, VOID.j, -44, VOID.i + VOID.w, VOID.j + VOID.d, -43, "#2a2d4d");
    bx(lower, 14.4, 12.4, -43, 15.8, 13.2, -36, "#4a4870"); bx(lower, 15.3, 14.2, -43, 16.6, 14.9, -36, "#4a4870");
    under += lower.svg() + slab.svg();
    // lit windows of the floor below on the slab's edge
    for (let a = .5; a < 24; a += 1.4) if (!(a > 13.3 && a < 17)) bx(base, a, 16, -11, a + .7, 16.05, -4, Math.floor(a * 3) % 3 ? "#ffd98a" : "#4a4870");
    for (let b = .5; b < 16; b += 1.4) bx(base, 24, b, -11, 24.05, b + .7, -4, Math.floor(b * 5) % 3 ? "#e8c27a" : "#3a3f63");
    // floor tiles: a checker per room, terrazzo in the hall (the provider's colour in it), grass in the gardens
    const PV = PROVIDERS[opts.provider], hallMark = PV ? markFloor(opts.provider, 4.3 * T, 6.9 * T, 5.5, PV.body) : [];
    for (let i = 0; i < 24; i++) for (let j = 0; j < 16; j++) {
      const c = i + .5, d = j + .5;
      if (inRect(c, d, VOID)) continue;
      const room = ROOMS.find(r => inRect(c, d, r)), garden = GARDENS.some(g => inRect(c, d, g)), hall = inRect(c, d, HALL);
      let col = "#c9bfae", deco = [];
      if (room) col = room.floor[(i + j) % 2];
      if (hall) {
        col = (i + j) % 2 ? "#e2d6c0" : "#d8cbb3"; const k = (i * 7 + j * 3) % 5;
        deco = [[i * T + 3 + k, j * T + 4, i * T + 5 + k, j * T + 6, "#b9a88e"], [i * T + 10 - k, j * T + 11, i * T + 12 - k, j * T + 13, PV ? PV.dark : "#c9726a"]];
        // the provider's mark, inlaid in the hall west of the counter (D55)
        deco.push(...hallMark.filter(m => m[0] >= i * T && m[0] < (i + 1) * T && m[1] >= j * T && m[1] < (j + 1) * T));
      }
      if (garden) { col = (i + j) % 2 ? "#5fb04f" : "#57a548"; deco = [[i * T + 4, j * T + 5, i * T + 6, j * T + 7, (i + j) % 3 ? "#7fd06a" : "#f2c23a"]]; }
      bx(base, i, j, -1, i + 1, j + 1, 0, col, {top: deco});
    }
    /* ---------- walls: the two back walls full height, low walls along the gardens ---------- */
    const WALL = 46, WC = "#5d6f9a";
    const back = new E.Scene(S);
    const win = (i0, i1) => [[i0 * T, 18, i1 * T, 38, "#22305e"], [i0 * T + 1.5, 20, i1 * T - 1.5, 27, "#3a5a9a"], [(i0 + i1) / 2 * T - .6, 18, (i0 + i1) / 2 * T + .6, 38, "#e9dcc0"], [i0 * T, 28, i1 * T, 29.2, "#e9dcc0"]];
    const backDeco = [[0, 0, 21 * T, 6, "#46557f"]];
    for (const a of [14.6, 17, 19.2]) backDeco.push(...win(a, a + 1.6));
    backDeco.push(...win(8.3, 9.4));
    // the Stacks: books to the ceiling
    for (let a = 0; a < 3.9; a += .25) for (let z = 8; z < 44; z += 9) backDeco.push([a * T + .4, z, a * T + 3.6, z + 6.5 - ((a * 7 + z) % 3), ["#e05a5a", "#5b8cf0", "#f2b34a", "#3fae6a", "#b07cf0", "#f08a5a"][Math.floor((a * 13 + z) % 6)]]);
    for (let z = 7; z < 46; z += 9) backDeco.push([0, z, 3.95 * T, z + 1.2, "#7a4a2e"]);
    // the lift, the whiteboard, the story board
    backDeco.push([4.7 * T, 0, 6.7 * T, 32, "#9aa7c8"], [5.7 * T - .5, 0, 5.7 * T + .5, 32, "#2a1a2e"], [5.3 * T, 34, 6.1 * T, 39, "#2a1a2e"], [5.6 * T, 35, 5.8 * T, 38, "#ff9a4a"]);
    backDeco.push([9.6 * T, 16, 12.4 * T, 38, "#fdfbf4"], [12.7 * T, 16, 13.8 * T, 36, "#c9944f"]);
    for (let k = 0; k < 6; k++) backDeco.push([(12.8 + (k % 2) * .5) * T, 19 + Math.floor(k / 2) * 5.5, (13.2 + (k % 2) * .5) * T, 23 + Math.floor(k / 2) * 5.5, ["#fff27a", "#9fe0ff", "#ffb0c8", "#b8f0a0", "#fff27a", "#ffd0a0"][k]]);
    bx(back, 0, -.25, 0, 21, 0, WALL, WC, {front: backDeco, top: [[0, -.25 * T, 21 * T, 0, "#e9dcc0"]]});
    bx(back, 21, -.25, 0, 24, 0, 6, WC);
    const leftDeco = [[-16 * T, 0, 0, 6, "#46557f"]];
    for (const b of [10, 13.2]) leftDeco.push([-(b + 2.6) * T, 16, -b * T, 40, "#22305e"], [-(b + 2.6) * T + 1.5, 18, -b * T - 1.5, 26, "#3a5a9a"], [-(b + 1.3) * T - .6, 16, -(b + 1.3) * T + .6, 40, "#e9dcc0"]);
    for (let b = 0; b < 4.9; b += .25) for (let z = 8; z < 44; z += 9) leftDeco.push([-(b + .25) * T + .4, z, -b * T - .4, z + 6.5 - ((b * 5 + z) % 3), ["#5b8cf0", "#3fae6a", "#e05a5a", "#f2b34a", "#b07cf0"][Math.floor((b * 11 + z) % 5)]]);
    // the left wall's front is its +x face ("right"), whose u runs along -y
    bx(back, -.25, 0, 0, 0, 5, WALL, WC, {right: leftDeco.filter(d => d[0] >= -5 * T)});
    bx(back, -.25, 5, 0, 0, 9, 6, WC);
    bx(back, -.25, 9, 0, 0, 16, WALL, WC, {right: leftDeco.filter(d => d[0] < -9 * T)});
    under += back.svg();

    /* ---------- walls inside: solid below, glass above, one tile at a time; doors are gaps ---------- */
    const PART = "#7a8fb8";
    const piece = (i0, j0, i1, j1, solid, glass) => {
      const alongI = i1 - i0 > j1 - j0, t = .07;
      const a0 = alongI ? i0 : j0, a1 = alongI ? i1 : j1;
      for (let a = a0; a < a1 - 1e-6; a += .5) {
        const b = Math.min(a1, a + .5);
        const [x0, y0, x1, y1] = alongI ? [a, j0 - t, b, j0 + t] : [i0 - t, a, i0 + t, b];
        obj(x1 + y1 + .02, sc => { bx(sc, x0, y0, 0, x1, y1, solid, PART, {top: [[x0 * T, y0 * T, x1 * T, y1 * T, "#e9dcc0"]]}); if (glass) bx(sc, x0, y0, solid, x1, y1, solid + glass, "#bfe3ff", {}, {opacity: .32}); }, {i0: x0, j0: y0, i1: x1, j1: y1});
      }
    };
    const run = (i0, j0, i1, j1, solid, glass, doors = []) => {
      const alongI = i1 - i0 > j1 - j0, a0 = alongI ? i0 : j0, a1 = alongI ? i1 : j1;
      const cuts = [a0, ...doors.flatMap(c => [c - .5, c + .5]), a1].sort((x, y) => x - y);
      for (let k = 0; k < cuts.length; k += 2) { const s0 = cuts[k], e = cuts[k + 1]; if (e - s0 < .05) continue; alongI ? piece(s0, j0, e, j0, solid, glass) : piece(i0, s0, i0, e, solid, glass); }
    };
    const RW = [12, 8], HW = [6, 7], GW = [3, 12];
    run(4, 0, 4, 5, ...RW); run(8, 0, 8, 5, ...RW); run(14, 0, 14, 5, ...RW);
    run(21, 0, 21, 3, ...GW); run(21, 3, 21, 5, ...RW, [4]); run(21, 3, 24, 3, ...GW);
    run(18, 5, 24, 5, ...RW); run(18, 11, 24, 11, ...RW);
    run(0, 5, 3, 5, ...GW); run(0, 9, 3, 9, ...GW);
    run(3, 11, 3, 16, ...RW); run(9, 11, 9, 16, ...RW); run(17, 11, 17, 16, ...RW);
    run(3, 5, 18, 5, ...HW, [3.5, 6, 11, 16.5]); run(18, 5, 18, 11, ...HW, [8]);
    run(3, 11, 14, 11, ...HW, [6, 11.5]); run(3, 5, 3, 9, ...GW); run(3, 9, 3, 11, ...HW, [10]);
    // the void's railing and the cut-away stubs at the front, in the building's colour on top
    for (let a = 14; a < 17; a += .5) obj(a + .5 + 11, sc => { bx(sc, a, 10.96, 0, a + .06, 11.04, 9, "#c9a46a"); bx(sc, a, 10.96, 9, a + .5, 11.04, 10.4, "#c9a46a"); });
    for (let b = 11; b < 16; b += .5) obj(14 + b + .5, sc => { bx(sc, 13.96, b, 0, 14.04, b + .06, 9, "#c9a46a"); bx(sc, 13.96, b, 9, 14.04, b + .5, 10.4, "#c9a46a"); });
    for (let a = 0; a < 24; a++) if (!(a >= 14 && a < 17)) obj(a + 1 + 16 + .3, sc => bx(sc, a, 15.86, 0, a + 1, 16, 4, {base: WC, top: "#f0a07a"}));
    for (let b = 0; b < 16; b++) obj(24 + b + 1 + .3, sc => bx(sc, 23.86, b, 0, 24, b + 1, 4, {base: WC, top: "#f0a07a"}));

    /* ---------- furniture: every room full of stuff ---------- */
    const plant = (i, j, s = 1) => { solid(i - .24 * s, j - .26 * s, i + .24 * s, j + .24 * s); obj(i + j + .4, sc => { bx(sc, i - .2, j - .2, 0, i + .2, j + .2, 6, "#d9704a", {top: [[(i - .15) * T, (j - .15) * T, (i + .15) * T, (j + .15) * T, "#5a3a26"]]}); bx(sc, i - .26 * s, j - .26 * s, 6, i + .26 * s, j + .26 * s, 12 * s, "#3fae6a"); bx(sc, i - .12 * s, j - .3 * s, 12 * s, i + .2 * s, j + .1 * s, 17 * s, "#5fd08a"); }); }
    const lamps = [];
    const lamp = (i, j, col = "#ffb070") => { solid(i - .14, j - .14, i + .14, j + .14); obj(i + j + .3, sc => { bx(sc, i - .12, j - .12, 0, i + .12, j + .12, 1.4, "#3b3f63"); bx(sc, i - .03, j - .03, 1.4, i + .03, j + .03, 26, "#2a2433"); bx(sc, i - .22, j - .22, 26, i + .22, j + .22, 31, "#ffe2a8"); }); lamps.push([i, j, col]); };
    const chair = (i, j, col = "#4a74d8", facing = "down") => obj(i + j + .05, sc => { bx(sc, i - .28, j - .28, 0, i + .28, j + .28, 5, col); if (facing === "down") bx(sc, i - .28, j - .32, 5, i + .28, j - .2, 14, col); else bx(sc, i - .28, j + .2, 5, i + .28, j + .32, 14, col); }, {i0: i - .28, j0: j - .32, i1: i + .28, j1: j + .28});
    const screenDeco = (i0, i1, z0, z1, col) => ({back: [[-i1 * T + 1, z0 + 1, -i0 * T - 1, z1 - 1, "#20263a"]], front: [[i0 * T + .8, z0 + .8, i1 * T - .8, z1 - .8, col], [i0 * T + 2, z0 + 3, i1 * T - 4, z0 + 4, "!" + (col === "#7cff9a" ? "#e8ffe8" : "#e8f0ff")]]});
    // 2 Stacks: a free-standing shelf, an armchair with a lamp, a globe, a pile of books
    prop(1.3, 1.1, 3.5, 1.6, 30, "#7a4a2e", {front: Array.from({length: 24}, (_, k) => [1.3 * T + 1 + (k % 8) * 4.2, 3 + Math.floor(k / 8) * 9, 1.3 * T + 4 + (k % 8) * 4.2, 9 + Math.floor(k / 8) * 9 - (k % 3), ["#e05a5a", "#5b8cf0", "#f2b34a", "#3fae6a", "#b07cf0"][k % 5]])});
    prop(.5, 3, 1.5, 4, 6, "#c4566a", {}, sc => { bx(sc, .5, 3, 6, .8, 4, 14, "#b04a5e"); bx(sc, .5, 3, 6, 1.5, 3.25, 10, "#b04a5e"); bx(sc, .5, 3.75, 6, 1.5, 4, 10, "#b04a5e"); });
    lamp(.4, 2.3);
    prop(2.6, 3.3, 3.1, 3.8, 8, "#7a4a2e", {}, sc => bx(sc, 2.62, 3.32, 8, 3.08, 3.78, 15, "#4fb0e0", {top: [[2.7 * T, 3.4 * T, 2.9 * T, 3.6 * T, "#3fae6a"]], front: [[2.7 * T, 10, 2.95 * T, 13, "#3fae6a"]], right: [[-3.7 * T, 9, -3.5 * T, 12, "#3fae6a"]]}));
    for (let k = 0; k < 4; k++) prop(1.8, 2.3, 2.4, 2.7, 2 + k * 2, ["#e05a5a", "#5b8cf0", "#f2b34a", "#3fae6a"][k], {}, null, k * 2);
    // 1 Landing: a doormat, the lift robot, a coat rack, a plant
    bx(base, 5, 3.2, 0, 6.6, 4.2, .4, "#c4566a", {top: [[5.2 * T, 3.4 * T, 6.4 * T, 3.5 * T, "#fff8ec"], [5.2 * T, 3.9 * T, 6.4 * T, 4 * T, "#fff8ec"]]});
    obj(7.2 + 1.2 + .3, sc => { bx(sc, 6.9, .9, 0, 7.5, 1.4, 14, "#9aa7c8", {front: [[6.95 * T, 9, 7.2 * T, 11, "!#fffdf6"], [7.22 * T, 9, 7.45 * T, 11, "!#fffdf6"], [7.05 * T, 9.4, 7.12 * T, 10.4, "!#231a2e"], [7.3 * T, 9.4, 7.37 * T, 10.4, "!#231a2e"]]}); bx(sc, 7.15, 1.1, 14, 7.25, 1.2, 18, "#2a1a2e"); bx(sc, 7.12, 1.07, 18, 7.28, 1.23, 20, "#ff9a4a"); }, {i0: 6.9, j0: .9, i1: 7.5, j1: 1.4});
    solid(4.2, .45, 5, .75);
    obj(4.6 + .6 + .3, sc => { bx(sc, 4.5, .5, 0, 4.7, .7, 30, "#7a4a2e"); bx(sc, 4.2, .5, 26, 5, .7, 27.5, "#7a4a2e"); bx(sc, 4.25, .45, 16, 4.5, .75, 25, "#3fae6a"); bx(sc, 4.75, .45, 17, 5, .75, 25, "#e0a03a"); });
    plant(7.5, 4.4);
    // 3 War room: the table with laptops and papers, chairs, a hanging lamp
    for (const [i, j] of [[9.4, 1.6], [10.6, 1.6], [11.8, 1.6]]) chair(i, j, "#8a5cf0", "down");
    prop(8.9, 2.1, 13.3, 3.6, 9, "#9a6a3a", {}, sc => { for (const [a, b] of [[9, 2.2], [13.1, 2.2], [9, 3.4], [13.1, 3.4]]) bx(sc, a, b, 0, a + .12, b + .12, 7, "#3b3f63"); bx(sc, 9.6, 2.5, 9, 10.4, 3, 9.6, "#fdfbf4"); bx(sc, 10.9, 2.6, 9, 11.8, 3.1, 9.8, "#3b3f63"); bx(sc, 11.2, 2.62, 9.8, 11.8, 2.7, 15, "#3b3f63", screenDeco(11.2, 11.8, 9.8, 15, "#8ab4ff")); bx(sc, 12.5, 2.4, 9, 12.8, 2.7, 12, "#f4f1ea"); }, 7);
    for (const [i, j] of [[9.4, 3.9], [10.6, 3.9], [11.8, 3.9]]) chair(i, j, "#8a5cf0", "up");
    lamp(13.4, .6);
    // 4 Workshop: three pairs of desks with screens, mugs, papers; a blinking server rack
    // the developers sit on the near side of their desks, backs to you, facing their screens
    const DESK = [[14.5, .9], [16.7, .9], [18.9, .9], [14.5, 2.95], [16.7, 2.95], [18.9, 2.95]];
    DESK.forEach(([i, j], k) => {
      chair(i + .92, j + 1.07, "#4a74d8", "up");
      prop(i, j, i + 1.8, j + .8, 12, "#e0a96a", {}, sc => {
        bx(sc, i + .05, j + .05, 0, i + .17, j + .17, 10, "#3b3f63"); bx(sc, i + 1.6, j + .05, 0, i + 1.72, j + .17, 10, "#3b3f63");
        bx(sc, i + .5, j + .12, 12, i + 1.4, j + .22, 22, "#2a2433", screenDeco(i + .5, i + 1.4, 12, 22, k % 2 ? "#7cff9a" : "#8ab4ff"));
        bx(sc, i + .85, j + .22, 12, i + 1.05, j + .32, 14, "#2a2433");
        bx(sc, i + 1.45, j + .45, 12, i + 1.65, j + .65, 15, ["#e05a5a", "#f4f1ea", "#5b8cf0"][k % 3]);
        bx(sc, i + .15, j + .4, 12, i + .5, j + .7, 12.6, "#fdfbf4");
      }, 10);
    });
    solid(14.15, 4.35, 14.7, 4.8);
    obj(14.15 + 4.8 + .9, sc => { for (let k = 0; k < 4; k++) bx(sc, 14.15 + (k % 2) * .03, 4.35, k * 2, 14.7, 4.8, k * 2 + 2, k % 2 ? "#efe9df" : "#fdfbf4"); }, null);
    prop(20.2, .1, 20.9, .7, 34, "#3b3f63", {front: [6, 11, 16, 21, 26].flatMap((z, k) => [[20.3 * T, z, 20.8 * T, z + 1.4, "#2a2433"], [20.7 * T - 1, z + .2, 20.7 * T, z + 1.2, k % 2 ? "!#7cff9a" : "!#ff9a4a"]])});
    // 9 Switchboard: the phone booth and the patch panel
    prop(22.7, 3.2, 23.8, 4.3, 32, "#2fb0b0", {front: [[22.85 * T, 6, 23.65 * T, 26, "#c8eaff"], [23 * T, 27.5, 23.5 * T, 30.5, "#fff8ec"]], right: [[-4.2 * T, 6, -3.35 * T, 26, "#c8eaff"]]});
    prop(21.3, 4.45, 22.3, 4.75, 18, "#3b3f63", {front: [0, 1, 2, 3, 4, 5].map(k => [21.4 * T + k * 2.5, 6 + (k % 2) * 5, 21.4 * T + k * 2.5 + 1.6, 7.6 + (k % 2) * 5, ["!#7cff9a", "!#ff9a4a", "!#8ab4ff", "!#ff6ad5", "!#7cff9a", "!#ff9a4a"][k]])});
    // gardens: a tree each, flowers, a pond, a bench
    const tree = (i, j, s = 1) => obj(i + j + .6, sc => { bx(sc, i - .12, j - .12, 0, i + .12, j + .12, 18 * s, "#7a4a2e"); bx(sc, i - .7 * s, j - .7 * s, 14 * s, i + .7 * s, j + .7 * s, 28 * s, "#3fae6a"); bx(sc, i - .45 * s, j - .45 * s, 28 * s, i + .45 * s, j + .45 * s, 36 * s, "#5fd08a"); bx(sc, i + .2 * s, j - .9 * s, 18 * s, i + .9 * s, j - .2 * s, 26 * s, "#4fc07a"); }, {i0: i - .7 * s, j0: j - .7 * s, i1: i + .7 * s, j1: j + .7 * s});
    tree(1.2, 6.2, 1.05); tree(22.6, 1.3, 1.1);
    bx(base, 1.2, 7, 0, 2.6, 7.8, .5, "#4fb0e0", {top: [[1.4 * T, 7.1 * T, 1.9 * T, 7.3 * T, "#bfeaff"]]});
    prop(.4, 8.1, 2.2, 8.5, 4, "#9a6a3a");
    // 5 Boiler room: the tank with its terminal, pipes, the valve, barrels of goo
    prop(19.1, 5.4, 21.5, 6.8, 28, "#7a8aa8", {front: [[19.4 * T, 8, 20.9 * T, 18, "#0e2a1e"], [19.6 * T, 14, 20.4 * T, 15.2, "!#7cff9a"], [19.6 * T, 11, 20.1 * T, 12.2, "!#7cff9a"], [21 * T, 18, 21.35 * T, 24, "#fdfbf4"]]});
    prop(22.5, 5.4, 22.8, 5.7, 44, "#9aa7c8"); prop(23.1, 5.4, 23.4, 5.7, 44, "#c9a46a"); prop(22.5, 5.7, 22.8, 8.8, 20, "#9aa7c8", {}, null, 17);
    prop(22.4, 7.5, 22.9, 7.7, 22, "#e05a5a", {}, null, 14);
    for (const [i, j] of [[19.2, 9.3], [20.1, 9.7]]) prop(i, j, i + .7, j + .7, 12, "#5d6178", {top: [[i * T + 1, j * T + 1, (i + .7) * T - 1, (j + .7) * T - 1, "!#7cff9a"]]});
    lamps.push([20.2, 7.2, "#ff8a5a"]);
    // 6 Crash lab: the sled track, the dummy, the scoreboard, flasks, Gauge
    bx(base, 18.4, 13.4, 0, 22.9, 13.95, 2, "#9aa7c8", {top: Array.from({length: 9}, (_, k) => [(18.6 + k * .5) * T, 13.45 * T, (18.6 + k * .5) * T + 1.2, 13.9 * T, "#6a7290"])});
    obj(19 + 11.4 + 2.8, sc => bx(sc, 19.2, 11.2, 8, 22, 11.4, 22, "#20182c"), {i0: 19.2, j0: 11.2, i1: 22, j1: 11.4});
    solid(22.5, 13.4, 23.05, 13.95);
    obj(22.8 + 13.7 + .3, sc => { bx(sc, 22.6, 13.5, 2, 22.95, 13.85, 12, "#f2c66a"); bx(sc, 22.5, 13.4, 12, 23.05, 13.95, 19, "#f2c66a", {front: [[22.6 * T, 15, 22.7 * T, 16.4, "!#2a1a2e"], [22.85 * T, 15, 22.95 * T, 16.4, "!#2a1a2e"]]}); });
    prop(17.5, 14.6, 19.7, 15.4, 9, "#e9ecf3", {}, sc => { for (let k = 0; k < 3; k++) bx(sc, 17.8 + k * .65, 14.85, 9, 18.1 + k * .65, 15.15, 15, "#7cff9a", {}, {opacity: .85}); });
    obj(23.2 + 12.5 + .4, sc => { bx(sc, 22.9, 12.2, 0, 23.5, 12.7, 14, "#3fd0a0", {front: [[22.95 * T, 9, 23.15 * T, 11, "!#fffdf6"], [23.25 * T, 9, 23.45 * T, 11, "!#fffdf6"]]}); bx(sc, 23.17, 12.42, 14, 23.23, 12.48, 18, "#2a1a2e"); bx(sc, 23.13, 12.38, 18, 23.27, 12.52, 20, "#ff9a4a"); }, {i0: 22.9, j0: 12.2, i1: 23.5, j1: 12.7});
    lamps.push([18.4, 15, "#7cff9a"]);
    // 7 Mailroom: pigeonholes, the brass tube, the sorting table, a mail cart, the bench outside
    prop(9.15, 11.9, 9.75, 15.1, 22, "#9a6a3a", {right: Array.from({length: 20}, (_, k) => [-(12.05 + (k % 5) * .6) * T - 8, 3 + Math.floor(k / 5) * 4.6, -(12.05 + (k % 5) * .6) * T - 1, 6.6 + Math.floor(k / 5) * 4.6, (k * 7) % 3 ? "#2a1d18" : "#fdfbf4"])});
    // the brass tube: no taller than the glass wall in front of it, so it never stands over the counter's queue
    prop(13.4, 11.3, 13.85, 11.75, 16, "#c9a46a", {}, sc => bx(sc, 13.15, 11.2, 0, 14.1, 11.8, 7, "#c9a46a"));
    prop(10.8, 13.4, 13, 14.4, 9, "#e0a96a", {}, sc => { bx(sc, 11.1, 13.6, 9, 11.7, 14.1, 12, "#c9944f"); bx(sc, 11.9, 13.55, 9, 12.4, 14, 13, "#d9b07a"); bx(sc, 12.5, 13.8, 9, 12.9, 14.15, 11, "#fdfbf4"); });
    prop(9.6, 15.2, 10.4, 15.8, 5, "#5b8cf0", {}, sc => bx(sc, 9.7, 15.25, 5, 10.3, 15.75, 7, "#fdfbf4"));
    // the bench where finished work waits (parked), out in the open hall east of the counter: nothing tall in front.
    // Sorted by its near-left corner, like a chair, so whoever sits on it is drawn on it, not behind it.
    obj(15.6 + 8.8 + .05, sc => bx(sc, 15.6, 8.45, 0, 17.2, 8.8, 4.5, "#9a6a3a"), {i0: 15.6, j0: 8.45, i1: 17.2, j1: 8.8});
    // 8 Launch pad: the countdown board, the console with the big button, the balcony with the rocket and the bridge
    prop(3.5, 11.3, 5.7, 11.5, 22, "#20182c", {front: [[3.7 * T, 12, 5.5 * T, 18, "#2a1a2e"]]}, null, 8);
    prop(5.6, 13.2, 7.2, 14.1, 10, "#5d6178", {top: [[6 * T, 13.4 * T, 6.5 * T, 13.8 * T, "#ff9a4a"], [6.7 * T, 13.4 * T, 7.1 * T, 13.9 * T, "#8ab4ff"]]});
    bx(base, 4, 16, -6, 9, 19.6, 0, "#5c6a8a", {top: Array.from({length: 18}, (_, k) => [(4 + (k % 6) * .84) * T + 2, (16 + Math.floor(k / 6) * 1.2) * T + 2, (4 + (k % 6) * .84) * T + 6, (16 + Math.floor(k / 6) * 1.2) * T + 4, "#6a7aa0"])});
    for (let a = 4.2; a < 9; a += .6) obj(a + 19.6, sc => { bx(sc, a, 19.5, 0, a + .06, 19.6, 9, "#9aa7c8"); bx(sc, a, 19.5, 9, a + .6, 19.6, 10.4, "#9aa7c8"); });
    prop(8.6, 16.3, 8.9, 16.6, 50, "#9aa7c8");
    solid(7.15, 17.35, 8.05, 18.05);
    obj(7.6 + 17.6 + .5, sc => {
      bx(sc, 7.35, 17.35, 0, 7.85, 17.85, 30, "#f2efe6", {front: [[7.45 * T, 18, 7.75 * T, 22, "#4fb0e0"]], right: [[-17.75 * T, 18, -17.45 * T, 22, "#4fb0e0"]]});
      bx(sc, 7.43, 17.43, 30, 7.77, 17.77, 36, "#f2efe6"); bx(sc, 7.52, 17.52, 36, 7.68, 17.68, 40, "#e05a5a");
      bx(sc, 7.15, 17.5, 0, 7.35, 17.7, 10, "#e05a5a"); bx(sc, 7.85, 17.5, 0, 8.05, 17.7, 10, "#e05a5a"); bx(sc, 7.5, 17.85, 0, 7.7, 18.05, 10, "#e05a5a");
    });
    const bridge = [];
    for (let k = 0; k < 9; k++) { const i0 = 3.6 - k * .55, j0 = 18 + k * .32; bx(base, i0 - .5, j0, -3 - Math.sin(k / 8 * Math.PI) * 2, i0, j0 + .6, -2 - Math.sin(k / 8 * Math.PI) * 2, "#c9a46a"); if (k % 2) bridge.push([i0 - .25, j0 + .3]); }
    // 11 Back porch: a sofa under the big window, the coffee machine, the jigsaw, the arcade, a beanbag
    prop(.3, 11.1, 1.3, 14, 6, "#2fb0b0", {}, sc => { bx(sc, .3, 11.1, 6, .65, 14, 14, "#269a9a"); bx(sc, .3, 11.1, 6, 1.3, 11.45, 10, "#269a9a"); bx(sc, .3, 13.65, 6, 1.3, 14, 10, "#269a9a"); bx(sc, .7, 11.6, 6, 1.2, 12.2, 8, "#ffd0a0"); });
    prop(.3, 9.3, 1.2, 10.4, 18, "#5d6178", {right: [[-10.2 * T, 9, -9.5 * T, 13, "!#7cff9a"]]});
    prop(1.5, 13.8, 2.7, 15, 6, "#9a6a3a", {top: Array.from({length: 9}, (_, k) => [(1.6 + (k % 3) * .35) * T, (13.9 + Math.floor(k / 3) * .35) * T, (1.6 + (k % 3) * .35) * T + 4.6, (13.9 + Math.floor(k / 3) * .35) * T + 4.6, ["#c9a0dc", "#9fc2ff", "#ffb0c8"][k % 3]])});
    prop(.3, 15, 1.2, 15.9, 24, "#8a5cf0", {right: [[-15.8 * T, 12, -15.1 * T, 19, "!#ff6ad5"], [-15.7 * T, 8, -15.2 * T, 10, "#f2c23a"]]});
    prop(1.8, 10.7, 2.6, 11.5, 6, "#e05a86");
    lamp(2.6, 9.6);
    // 10 the counter: a ring of desk round an empty chair, the bell, the ticket machine
    const CT = {base: "#c98a4e", top: "#efe2c8"};
    prop(9.3, 6.8, 11.7, 7.4, 11, CT); prop(9.3, 7.4, 9.9, 8.6, 11, CT); prop(11.1, 7.4, 11.7, 8.6, 11, CT);
    chair(10.5, 8.05, "#8a5cf0", "down");
    prop(9.3, 8.6, 11.7, 9.2, 11, CT, {front: [[9.6 * T, 3, 11.4 * T, 8, "#20182c"], [9.75 * T, 4.5, 11.25 * T, 6.5, "!#FFD83D"]]}, sc => bx(sc, 11.1, 8.75, 11, 11.4, 9.05, 13, "#c9a46a"));
    obj(9.9 + 8.9 + .3, sc => { bx(sc, 9.5, 8.7, 11, 10.3, 9.05, 14, "#f2efe6"); bx(sc, 10.1, 8.75, 14, 10.4, 9.05, 17, "#f2efe6", {front: [[10.15 * T, 15, 10.22 * T, 15.6, "!#2a1a2e"], [10.3 * T, 15, 10.37 * T, 15.6, "!#2a1a2e"]]}); });
    prop(12.4, 9.5, 12.85, 9.9, 16, "#e05a86", {front: [[12.5 * T, 12, 12.75 * T, 14, "#fdfbf4"]]});
    // plants and lamps in the hall
    plant(7.4, 5.6); plant(15.3, 10.4, 1.1); plant(3.6, 8.7, .9); plant(17.3, 5.6); plant(8.6, 15.4); plant(23.4, 15.3);
    lamp(14.6, 6.0); lamp(6.4, 10.3);

    /* ---------- signs: on top of the back walls, or hanging under the slab ---------- */
    // one plain word per room, no numbers: the floor has no order to follow
    const labels = [];   // where the signs hang, so the app can keep speech bubbles off them
    const sign = (x, y, r, hl) => { const w = r.name.length * 8.6 + 16; labels.push([x - w / 2, y - 11, w, 17]); return `<g><rect x="${f(x - w / 2)}" y="${f(y - 11)}" width="${f(w)}" height="17" fill="${hl ? "#FFD83D" : "#fff3d6"}" stroke="#2a1a2e" stroke-width="2"/><text x="${f(x)}" y="${f(y + 2.4)}" font-family="${FONT}" font-size="10.5" text-anchor="middle" fill="#2a1a2e">${r.name}</text></g>`; };
    const SIGN = {stacks: P(2, 0, WALL + 12), landing: P(5.8, 0, WALL + 12), war: P(11, 0, WALL + 12), workshop: P(17.4, 0, WALL + 12), switch: P(22.6, 0, 22), porch: P(0, 12.5, WALL + 12),
      boiler: P(24, 8, -26), crash: P(20.5, 16, -26), mail: P(11.5, 16, -26), launch: P(6.5, 19.8, -22)};
    // every sign also on its own (topParts), so the app can paint each one sharp
    const topParts = [], tp = (id, markup) => { topParts.push({id, markup}); top += markup; };
    for (const r of ROOMS) tp("room:" + r.id, sign(...SIGN[r.id], r));
    // the hall's front desk: a quiet sign; yellow stays for what really waits for you (D73)
    tp("needsYou", sign(...P(10.5, 8, 74), {name: "FRONT DESK"}, false));
    // light pools: lamps, screens, the counter
    let light = "";
    for (const [i, j, c] of lamps) { const [x, y] = P(i, j, 22); light += glow(x, y + 16, 46, c, .5); }
    for (const r of ROOMS) { const [x, y] = P(r.i + r.w / 2, r.j + r.d / 2); light += glow(x, y, 90, "#ffd9a0", .22); }
    { const [x, y] = P(10.5, 8); light += glow(x, y, 120, "#ffd9a0", .25); }
    const bridgeLights = bridge.map(([i, j]) => { const [x, y] = P(i, j, 6); return `<rect class="bw-lantern" x="${f(x - 2.5)}" y="${f(y - 5)}" width="5" height="6" fill="#3a3550" stroke="#2a1a2e" stroke-width="1.2"/>`; }).join("");
    { const [x, y] = P(1.5, 19.2, -6); tp("bridge", `<text x="${f(x)}" y="${f(y + 26)}" text-anchor="middle" font-family="${FONT}" font-size="10" fill="#c9a0ff" stroke="#2a1a2e" stroke-width="2" paint-order="stroke">← SERVER ROOM</text>`); }

    /* ---------- put it together ---------- */
    objs.sort((a, b) => a.key - b.key);
    const defs = `<defs>${GLOWS.map(c => `<radialGradient id="bw-glow-${c}"><stop offset="0" stop-color="#${c}" stop-opacity="1"/><stop offset="1" stop-color="#${c}" stop-opacity="0"/></radialGradient>`).join("")}</defs>`;
    svg.innerHTML = defs + under + base.svg() + `<g id="bw-shadows"></g><g id="bw-objs"></g>` + light + bridgeLights + top + `<g id="bw-over"></g><g id="bw-fx"></g>`;
    const layer = svg.querySelector("#bw-objs"), keyed = [];
    objs.forEach(o => { const g = document.createElementNS(NS, "g"); g.innerHTML = o.sc.svg(); layer.appendChild(g); keyed.push({k: o.key, el: g}); });
    { const bb = svg.getBBox(); svg.setAttribute("viewBox", `${Math.floor(bb.x - 10)} ${Math.floor(bb.y - 24)} ${Math.ceil(bb.width + 20)} ${Math.ceil(bb.height + 34)}`); }

    /* ---------- people ---------- */
    const LOOKS = Object.assign({}, B.CAST, opts.team || {});
    const VIEW = {down: "SW", right: "SE", up: "NE", left: "NW"};
    const MOOD = {work: "calm", wait: "wait", stuck: "stuck", done: "tired"};
    const people = {}, shadows = svg.querySelector("#bw-shadows"), over = svg.querySelector("#bw-over");
    const keyAt = (i, j) => { let k = i + j + .3; for (const b of boxes) if ((i >= b.i1 || j >= b.j1) && i > b.i0 - 1.5 && j > b.j0 - 1.5) k = Math.max(k, b.key + .01); return k; };
    function person(name, o) {
      const p = people[name] || (people[name] = {g: document.createElementNS(NS, "g"), sh: document.createElementNS(NS, "g"), ov: document.createElementNS(NS, "g")});
      let pose = o.pose === "stand" ? "idle" : o.pose === "walk" ? (Math.floor(performance.now() / 170) % 2 ? "walkA" : "walkB") : o.pose;
      const seat = o.seat ? 1 : 0, at = [o.pos[0] * T, o.pos[1] * T, 0];
      const sc = new E.Scene(S);
      const shadow = B.figureInto(sc, LOOKS[name] || name, {pose, mood: pose === "type" ? "focus" : MOOD[o.state] || "calm", view: VIEW[o.dir] || "SW", seat, noProp: o.pose === "type" || o.pose === "sit"}, at);
      p.g.innerHTML = sc.svg(); p.sh.innerHTML = seat ? "" : shadow;
      // the name tag, an emote, a ring on the floor for wait and stuck
      const [hx, hy] = P(o.pos[0], o.pos[1], 34 + seat * 2 + (pose === "cheer" ? 4 : 0));
      const tw = name.length * 7 + 14, wait = o.state === "wait";
      let ov = o.state !== "done" ? `<g transform="translate(${f(hx)},${f(hy - (o.emote ? 20 : 2))})"><rect x="${f(-tw / 2)}" y="-9" width="${tw}" height="12" fill="${wait ? "#FFD83D" : "#20182c"}" stroke="#2a1a2e" stroke-width="1.6"/><text x="0" y="1" font-family="${FONT}" font-size="8" text-anchor="middle" fill="${wait ? "#1d1626" : "#fff8ec"}">${name.toUpperCase()}</text></g>` : "";
      if (o.emote) { const G = {"?": ["?", "#3f6fd8"], "!": ["!", "#e0473a"], dots: ["…", "#2a1a2e"], coffee: ["☕", "#7a4a30"], check: ["✓", "#2f9a5a"], back: ["↩", "#3f6fd8"], bug: ["✗", "#8a5cf0"], wait: ["⏳", "#2a1a2e"]}[o.emote] || ["!", "#e0473a"]; ov += `<g transform="translate(${f(hx)},${f(hy - 4)})" class="bw-bob"><rect x="-9" y="-16" width="18" height="15" fill="#fffaf0" stroke="#2a1a2e" stroke-width="1.6"/><path d="M-3,-1 l3,5 l2,-5z" fill="#fffaf0" stroke="#2a1a2e" stroke-width="1.4" stroke-linejoin="round"/><text x="0" y="-4.5" font-family="${FONT}" font-size="11" text-anchor="middle" fill="${G[1]}">${G[0]}</text></g>`; }
      if (wait || o.state === "stuck") { const [x, y] = P(o.pos[0], o.pos[1]); ov += `<polygon points="${f(x)},${f(y - 8.4)} ${f(x + 16.8)},${f(y)} ${f(x)},${f(y + 8.4)} ${f(x - 16.8)},${f(y)}" fill="none" stroke="${ST[o.state]}" stroke-width="2.6" stroke-linejoin="miter" class="bw-pulse"/>`; }
      if (o.state === "stuck") { const [x, y] = P(o.pos[0], o.pos[1], 52); ov += `<g transform="translate(${f(x)},${f(y)})"><rect x="-12" y="-6" width="24" height="9" fill="#5a5a6e" stroke="#2a1a2e" stroke-width="1.4"/><rect x="-6" y="-10" width="12" height="6" fill="#6a6a80" stroke="#2a1a2e" stroke-width="1.4"/><path d="M2,4 l-3,5 h4 l-2,5" stroke="#ff4a4a" stroke-width="2" fill="none" class="bw-blink"/></g>`; }
      p.ov.innerHTML = ov;
      if (!p.sh.parentNode) shadows.appendChild(p.sh);
      if (!p.ov.parentNode) over.appendChild(p.ov);
      const k = keyAt(o.pos[0], o.pos[1]);
      let lo = 0, hi = keyed.length; while (lo < hi) { const m = (lo + hi) >> 1; if (keyed[m].k <= k) lo = m + 1; else hi = m; }
      const ref = keyed[lo] ? keyed[lo].el : null;
      if (p.g.parentNode !== layer || p.g.nextSibling !== ref) layer.insertBefore(p.g, ref);
    }
    function tokens() {}                     // the dial is gone (the room is the phase); kept so callers need not change
    /* the things that change with the story */
    const fxLayer = svg.querySelector("#bw-fx");
    function fx(kind, step) {
      fxLayer.innerHTML = "";
      svg.querySelectorAll(".bw-lantern").forEach(l => l.setAttribute("fill", "#3a3550"));
      const pop = (i, j, z, s, col) => { const [x, y] = P(i, j, z); fxLayer.innerHTML += `<text class="bw-bob" x="${f(x)}" y="${f(y)}" text-anchor="middle" font-family="${FONT}" font-size="13" fill="${col}" stroke="#2a1a2e" stroke-width="3" paint-order="stroke">${s}</text>`; };
      if (kind === "ding") pop(5.7, 0, 48, "DING!", "#ff9a4a");
      if (kind === "bell") pop(11.3, 8.9, 24, "DING", "#FFD83D");
      if (kind === "fail") { pop(22.8, 13.6, 30, "✗ 3 FAILED", "#b07cf0"); }
      if (kind === "pass") pop(22.8, 13.6, 30, "✓ ALL GREEN", "#3fd0a0");
      if (kind === "push") pop(13.6, 11.5, 66, "PR #42", "#c9a46a");
      if (kind === "ci") pop(23.2, 12.4, 30, "CI 3/5", "#ff9a4a");
      if (kind === "plan") pop(11, 0, 50, "PLAN v2", "#3f6fd8");
      if (kind === "launch") {
        const lan = [...svg.querySelectorAll(".bw-lantern")], t0 = performance.now();
        (function up(now) { const t = Math.min(1, (now - t0) / 2000); lan.forEach((l, k) => l.setAttribute("fill", t > (k + 1) / (lan.length + 1) ? "#ffb070" : "#3a3550")); if (t < 1) requestAnimationFrame(up); })(t0);
        pop(7.6, 17.6, 60, "LIFT-OFF!", "#ff9a4a");
      }
    }
    function moveCat() {}
    const roomAt = (i, j) => ROOMS.find(r => i >= r.i && i < r.i + r.w && j >= r.j && j < r.j + r.d)?.id || (i >= 9.3 && i < 11.7 && j >= 6.8 && j < 9.2 ? "counter" : null);
    const toTile = (x, y) => { const a = x / (T * S), b = (y / (T * S)) * 2; return [(a + b) / 2, (b - a) / 2]; };
    // the layers on their own, for the native apps: they paint each one and let SpriteKit sort and animate
    const parts = {under: [lower, slab, back], base, objs, boxes, solids, light: light + bridgeLights, top, topParts, defs, labels};
    return {P, person, tokens, fx, moveCat, roomAt, toTile, parts};
  }
  /* ---------- outside: a provider building and the campus ---------- */
  const PROVIDERS = {
    // fac/facDark: a Dark Software Factory's storey (D62), charcoal with a hint of the provider
    claude: {name: "CLAUDE", body: "#e8916b", trim: "#f4c2a4", dark: "#b8603d", fac: "#3b2f3a", facDark: "#251c25"},
    chatgpt: {name: "CHATGPT", body: "#4fbf9f", trim: "#a8ecd8", dark: "#2f8f7a", fac: "#29363a", facDark: "#182225"}
  };
  const FLOOR_H = 30, OUT = .2;   // OUT: how far a factory's storey stands proud of its tower (D62)
  /* a provider's name painted on its roof board: centred on the board's face, sheared along it (the face runs down
     to the right, half a unit per unit) */
  const roofSign = (at, name) => {
    const size = Math.min(15, 62 / (.72 * name.length));
    return `<g transform="translate(${f(at[0])} ${f(at[1] + .353 * size)}) matrix(1 .5 0 1 0 0)"><text x="0" y="0" text-anchor="middle" font-family="${FONT}" font-size="${f(size)}" fill="#fff8ec" stroke="#2a1a2e" stroke-width="3" paint-order="stroke">${name}</text></g>`;
  };
  /* a provider tower: one storey per project, windows with people at desks, the project's name on a plaque, a
     yellow pulse on a storey that waits for you, a roof sign. Built into scene sc at tile (i, j). */
  function tower(sc, i, j, w, d, prov, floors, add) {
    const Pv = PROVIDERS[prov], H = floors.length * FLOOR_H;
    // the plinth with the door and an awning
    add(i + w + j + d, s2 => {
      bx2(s2, i - .2, j - .2, 0, i + w + .2, j + d + .2, 8, "#8a8fb0", {front: [[(i + w / 2 - .6) * T, 0, (i + w / 2 + .6) * T, 7.4, "#2a2433"], [(i + w / 2 - .5) * T, .5, (i + w / 2 - .05) * T, 7, "#3a5a9a"], [(i + w / 2 + .05) * T, .5, (i + w / 2 + .5) * T, 7, "#3a5a9a"]]});
      bx2(s2, i + w / 2 - .9, j + d + .2, 7.4, i + w / 2 + .9, j + d + 1, 8.6, Pv.dark);
      // planters either side of the door
      for (const px of [i + w / 2 - 1.7, i + w / 2 + 1.1]) { bx2(s2, px, j + d + .3, 0, px + .6, j + d + .9, 3, "#6b4430"); bx2(s2, px + .05, j + d + .35, 3, px + .55, j + d + .85, 6.5, "#3f9a48"); }
      floors.forEach((fl, k) => {
        // three kinds of storey (D62): a Dark Software Factory (charcoal, cool screens, an LED strip: it never sleeps),
        // the Chats lounge (awnings and planters), and an ordinary project
        const z0 = 8 + k * FLOOR_H, z1 = z0 + FLOOR_H, fac = fl.kind === "factory", chat = fl.kind === "chats";
        const body = fac ? Pv.fac : Pv.body, frame = fac ? Pv.facDark : Pv.dark, trim = fac ? Pv.body : Pv.trim;
        // a factory's storey stands a little proud of the tower, so you pick it out from across the campus
        const o = fac ? OUT : 0, jd = j + d + o, iw = i + w + o;
        const winF = [], winR = [];
        for (let a = 0; a < w; a += 1) {
          const x0 = (i + a + .14) * T, x1 = (i + a + .86) * T, mid = (x0 + x1) / 2;
          winF.push([x0 - 1, z0 + 6, x1 + 1, z1 - 5, frame], [x0, z0 + 7, x1, z1 - 6, fac ? "#121a30" : "#24305a"]);
          if (fac) {
            // screens in every window, cool light, and a desk silhouette now and then
            const on = (k * 5 + a * 3) % 7 !== 0;
            winF.push([x0, z0 + 7, x1, z0 + 9, "#1d2a48"]);
            if (on) winF.push([x0 + 2, z0 + 10, mid - .8, z0 + 17, "#7fd6ff"], [mid + .8, z0 + 10, x1 - 2, z0 + 17, (a + k) % 3 ? "#5fb8f0" : "#b5f0ff"], [x0 + 1, z0 + 7, x1 - 1, z0 + 8.4, "#2f4c78"]);
            if (on && (k + a) % 2) winF.push([mid - 1.6, z0 + 7, mid + 1.6, z0 + 13, "#0c1220"]);
          } else {
            const lit = (k * 7 + a * 3) % 5 !== 0;
            if (lit) winF.push([x0, z0 + 7, x1, z0 + 16, chat ? "#ffd59a" : "#ffc27a"], [x0, z0 + 16, x1, z1 - 6, "#3a4a80"]);
            if (lit && (k + a) % 2 === 0) winF.push([x0 + 3, z0 + 7, x1 - 3, z0 + 11, "#3a3f63"], [mid - 2, z0 + 11, mid + 2, z0 + 17, ["#4a74d8", "#3fae6a", "#e8608a", "#7a5ce0"][(k + a) % 4]], [mid - 1.6, z0 + 17, mid + 1.6, z0 + 20.5, ["#f2b48a", "#a86a44", "#f6c9a0", "#7a4a32"][(k + a) % 4]]);
          }
          winF.push([mid - .5, z0 + 7, mid + .5, z1 - 6, frame]);
          if (chat) {
            // a striped awning over the window and a planter under it
            const sw = (x1 - x0 + 3) / 4;
            winF.push([x0 - 1.5, z1 - 10.5, x1 + 1.5, z1 - 3, "#2a1a2e"]);
            for (let q = 0; q < 4; q++) winF.push([x0 - 1 + q * sw, z1 - 10, x0 - 1 + (q + 1) * sw, z1 - 3.5, q % 2 ? "#fff3d6" : "#e0473a"]);
            winF.push([x0 - .5, z0 + 4.2, x1 + .5, z0 + 7.6, "#6b4430"], [x0 + .5, z0 + 7.6, x1 - .5, z0 + 9.6, a % 2 ? "#4caf50" : "#3f9a48"], [mid - 1, z0 + 9.2, mid + 1.4, z0 + 10.6, "#ff7aa8"]);
          }
        }
        for (let b = 0; b < d; b += 1) {
          const u0 = -(j + b + .86) * T, u1 = -(j + b + .14) * T;
          winR.push([u0 - 1, z0 + 6, u1 + 1, z1 - 5, frame], [u0, z0 + 7, u1, z1 - 6, fac ? "#101728" : "#202a52"]);
          if (fac) { if ((k * 3 + b) % 5) winR.push([u0 + 2, z0 + 10, u1 - 2, z0 + 16, "#5aa6d8"]); }
          else if ((k * 5 + b) % 4 !== 0) winR.push([u0, z0 + 7, u1, z0 + 15, chat ? "#f0b878" : "#e8aa6a"]);
        }
        // corner pilasters, so a tower reads as built rather than stacked, and a factory's LED strip under its windows
        const fx0 = (i - o) * T, fx1 = iw * T, ru0 = -jd * T, ru1 = -(j - o) * T;
        const front = [[fx0, z0, fx1, z0 + 3, trim], [fx0, z0, fx0 + 2.4, z1, frame], [fx1 - 2.4, z0, fx1, z1, frame], ...winF];
        const right = [[ru0, z0, ru1, z0 + 3, trim], [ru0, z0, ru0 + 2.4, z1, frame], [ru1 - 2.4, z0, ru1, z1, frame], ...winR];
        if (fac) for (const zz of [z0 + 3, z1 - 2.2]) { front.push([i * T + 2.4, zz, (i + w) * T - 2.4, zz + 1.4, "#9be7ff"]); right.push([-(j + d) * T + 2.4, zz, -j * T - 2.4, zz + 1.4, "#9be7ff"]); }
        bx2(s2, i - o, j - o, z0, iw, jd, z1, body, {front, right});
      });
      // the roof: an edge, AC units, the sign
      const zr = 8 + H;
      bx2(s2, i - .15, j - .15, zr, i + w + .15, j + d + .15, zr + 3, Pv.dark);
      bx2(s2, i + .6, j + .6, zr + 3, i + 1.8, j + 1.8, zr + 9, "#9aa3b4", {top: [[(i + .8) * T, (j + .8) * T, (i + 1.6) * T, (j + 1.6) * T, "#5d6178"]]});
      bx2(s2, i + 2.2, j + .6, zr + 3, i + 3.4, j + 1.8, zr + 9, "#9aa3b4", {top: [[(i + 2.4) * T, (j + .8) * T, (i + 3.2) * T, (j + 1.6) * T, "#5d6178"]]});
      bx2(s2, i + .4, j + d - .5, zr + 3, i + w - .4, j + d - .3, zr + 20, "#2a2433", {front: [[(i + .5) * T, zr + 4, (i + w - .5) * T, zr + 19, Pv.body]]});
      // an antenna mast (its lamp blinks in the app) and, when a factory works here, a chimney (it smokes in the app)
      bx2(s2, i + .8, j + 2.5, zr + 3, i + 1.6, j + 3.3, zr + 5, "#5d6178");
      bx2(s2, i + 1.15, j + 2.85, zr + 5, i + 1.25, j + 2.95, zr + 36, "#c9cfdc");
      for (const zc of [zr + 14, zr + 24]) bx2(s2, i + .95, j + 2.85, zc, i + 1.45, j + 2.95, zc + .8, "#c9cfdc");
      if (floors.some(fl => fl.kind === "factory")) {
        bx2(s2, i + 2.3, j + 2.3, zr + 3, i + 3.1, j + 3.1, zr + 26, "#6f7486", {front: [[(i + 2.3) * T, zr + 18, (i + 3.1) * T, zr + 21, "#e0473a"]], right: [[-(j + 3.1) * T, zr + 18, -(j + 2.3) * T, zr + 21, "#e0473a"]], top: [[(i + 2.4) * T, (j + 2.4) * T, (i + 3) * T, (j + 3) * T, "#1a1620"]]});
      }
      // the provider's mark on a board of its own behind the name, so you see whose building it is (D55)
      bx2(s2, i + w - 1.75, j + .9, zr + 3, i + w - .45, j + 1.1, zr + 26, "#2a2433", {front: [[(i + w - 1.7) * T, zr + 4, (i + w - .5) * T, zr + 25, Pv.trim],
        ...markRects(prov, (i + w - 1.66) * T + .8, zr + 23.6, 2.6, Pv.dark)]});
    }, {i0: i - .2, j0: j - .2, i1: i + w + .2, j1: j + d + .2}, "building:" + prov);
    const proud = k => floors[k].kind === "factory" ? OUT : 0;
    const faces = k => { const z0 = 8 + k * FLOOR_H, z1 = z0 + FLOOR_H, o = proud(k), i0 = i - o, j0 = j - o, iw = i + w + o, jd = j + d + o;
      return [[P(i0, jd, z0), P(iw, jd, z0), P(iw, jd, z1), P(i0, jd, z1)], [P(iw, jd, z0), P(iw, j0, z0), P(iw, j0, z1), P(iw, jd, z1)]]; };
    const zr = 8 + H;
    const zt = 8 + H;
    const windows = floors.map((fl, k) => { const z0 = 8 + k * FLOOR_H, z1 = z0 + FLOOR_H;
      const jd = j + d + proud(k);
      return Array.from({length: w}, (_, a) => [P(i + a + .14, jd, z0 + 7), P(i + a + .86, jd, z0 + 7), P(i + a + .86, jd, z1 - 6), P(i + a + .14, jd, z1 - 6)]); });
    return {antenna: P(i + 1.2, j + 2.9, zt + 36.5), chimney: floors.some(fl => fl.kind === "factory") ? P(i + 2.7, j + 2.7, zt + 26) : null, windows,
      sign: P(i + w / 2, j + d - .3, zr + 11.5), plaques: floors.map((fl, k) => ({at: P(i + w + .05 + proud(k), j + d / 2, 8 + k * FLOOR_H + FLOOR_H / 2), fl})), storeys: floors.map((fl, k) => ({fl, faces: faces(k)}))};
  }
  let bx2 = null;
  /* the campus: a floating island with the provider buildings, the Server room, a square plaza with the fountain
     that counts what waits for you, roads on the grid, trees, lamps, benches and people about */
  function campus(svg, opts = {}) {
    const objs = [], boxes = [], base = new E.Scene(S), under = new E.Scene(S);
    let top = "";
    const add = (key, draw, block, id) => { const sc = new E.Scene(S); draw(sc); objs.push({key, sc, id}); if (block) boxes.push({...block, key, id: id || null}); };
    // every sign also on its own, named after what it hangs on ("roof:claude", "plaque:claude:0", "roof:engine",
    // "plot", "fountain"), so the app can paint it sharp, sort it with its building and dim it with it
    const topParts = [], tp = (id, markup) => { topParts.push({id, markup}); top += markup; };
    const bx = (sc, i0, j0, z0, i1, j1, z1, col, deco, opt) => sc.box(F0, [i0 * T, j0 * T, z0], [i1 * T, j1 * T, z1], col, deco || {}, opt || {});
    bx2 = bx;
    const NI = 30, NJ = 26;
    // the island: grass on top, earth and rock below, stepping in
    // the underside: earth, then rock, stepping in a little at a time so it shows below the edge, and a few hanging rocks
    const LAY = [["#8a6440", 0], ["#7a5636", .5], ["#6a4e3e", 1.2], ["#5a4a52", 2.2], ["#4a4060", 3.6]];
    LAY.forEach(([col, ins], k) => bx(under, ins, ins, -8 - (k + 1) * 20, NI - ins, NJ - ins, -8 - k * 20, col, {front: [[0, -8 - k * 20 - 3, NI * T, -8 - k * 20 - 2, "#4a3a2e"]].filter(() => k > 0 && false)}));
    for (const [i, j, w, h] of [[6, 22, 3, 40], [16, 20, 4, 56], [24, 12, 3, 44], [12, 8, 4, 50], [22, 22, 2.5, 30]]) bx(under, i, j, -108 - h, i + w, j + w * .8, -108, "#433a58");
    bx(under, 0, 0, -8, NI, NJ, 0, {base: "#9a7048", top: "#3f9a4a"});
    // grass tiles with a little variation, roads on the grid, the plaza
    const ROAD = (i, j) => (j >= 12 && j < 14 && i >= 2 && i < 28) || (i >= 14 && i < 16 && j >= 3 && j < 24);
    const PLAZA = (i, j) => i >= 11 && i < 19 && j >= 9 && j < 17;
    for (let i = 0; i < NI; i++) for (let j = 0; j < NJ; j++) {
      let col = (i * 7 + j * 3) % 5 ? "#5fb04f" : "#57a548", deco = [];
      if ((i * 13 + j * 7) % 11 === 0) deco = [[i * T + 5, j * T + 6, i * T + 7, j * T + 8, ["#f2c23a", "#ff6ad5", "#fff8ec"][(i + j) % 3]]];
      if (ROAD(i, j)) { col = "#8a8fa8"; deco = (i % 2 === 0 && j % 2 === 0) ? [[i * T + 7, j * T + 2, i * T + 9, j * T + 6, "#e9dcc0"]] : []; }
      if (PLAZA(i, j)) { col = (i + j) % 2 ? "#e2d6c0" : "#d4c6ad"; deco = []; }
      bx(base, i, j, -1, i + 1, j + 1, 0, col, {top: deco});
    }
    // the fountain in the middle of the plaza: the Needs-you counter
    const waiting = opts.waiting ?? 3;
    add(15 + 13 + 2, sc => { bx(sc, 13.4, 11.4, 0, 16.6, 14.6, 4, "#b9b2c6", {top: [[13.6 * T, 11.6 * T, 16.4 * T, 14.4 * T, "#4fb0e0"]]}); bx(sc, 14.6, 12.6, 4, 15.4, 13.4, 16, "#b9b2c6"); bx(sc, 14.4, 12.4, 16, 15.6, 13.6, 20, "#FFD83D", {front: [[14.6 * T, 16.5, 15.4 * T, 19.5, "#2a1a2e"]]}); }, {i0: 13.4, j0: 11.4, i1: 16.6, j1: 14.6}, "fountain");
    { const [x, y] = P(15, 13.6, 18); tp("fountain", `<text x="${f(x)}" y="${f(y + 1)}" text-anchor="middle" font-family="${FONT}" font-size="9" fill="#FFD83D">${waiting}</text>`); }
    // what you can point at, as boxes [i0, j0, i1, j1, height] (the app tests their outlines on screen)
    const hits = {fountain: [[13.4, 11.4, 16.6, 14.6, 4], [14.6, 12.6, 15.4, 13.4, 16], [14.4, 12.4, 15.6, 13.6, 20]]};
    // the buildings
    const claude = tower(null, 3, 3, 5, 4, "claude", opts.claude || [{name: "SHOPFRONT", wait: true}, {name: "RECIPE BOX"}, {name: "TIDE NOTES"}, {name: "CHAT · FONTS", wait: true}], add);
    const gpt = tower(null, 21, 16, 5, 4, "chatgpt", opts.chatgpt || [{name: "HARBOR API"}, {name: "RECIPE BOX", wait: true}], add);
    // the Server room: a low datacenter, racks behind glass, AC units and a dish on the roof
    add(25 + 8, sc => {
      bx(sc, 19, 3, 0, 26, 8, 22, "#6a5ab0", {front: [[19.4 * T, 3, 25.6 * T, 18, "#1e1a3a"], ...Array.from({length: 10}, (_, k) => [(19.6 + k * .6) * T, 4, (19.6 + k * .6 + .4) * T, 17, "#2a2a4e"]), ...Array.from({length: 20}, (_, k) => [(19.7 + (k % 10) * .6) * T, 6 + Math.floor(k / 10) * 6, (19.7 + (k % 10) * .6) * T + 2, 7 + Math.floor(k / 10) * 6, "#34305a"])], right: [[-8 * T + 4, 3, -7 * T, 16, "#2a2433"], [-6.6 * T, 12, -4 * T, 14, "#c9a0ff"]]});
      for (const a of [19.6, 21.2, 22.8]) bx(sc, a, 3.6, 22, a + 1.2, 4.8, 28, "#9aa3b4", {top: [[(a + .2) * T, 3.8 * T, (a + 1) * T, 4.6 * T, "#5d6178"]]});
      bx(sc, 24.4, 4, 22, 24.6, 4.2, 30, "#9aa3b4"); bx(sc, 23.9, 3.5, 30, 25.1, 4.7, 32, "#e9ecf3");
      // the roof sign's posts and the beacon (its lamp is lit by the app, D26)
      for (const a of [20.5, 24.5]) bx(sc, a - .05, 7.75, 22, a + .05, 7.85, 38, "#2a2433");
      bx(sc, 25.3, 7.3, 22, 25.6, 7.6, 25, "#3a3550"); bx(sc, 25.33, 7.33, 25, 25.57, 7.57, 27.5, "#4a4870");
    }, {i0: 19, j0: 3, i1: 26, j1: 8}, "building:engine");
    // the rack LEDs as quads on the front face (c: rack 0-9, r: 0 activity, 1 status) and the beacon's lens
    const racks = [];
    for (let r = 0; r < 2; r++) for (let c = 0; c < 10; c++) { const i0 = 19.7 + c * .6, i1 = i0 + .125, z0 = 6 + r * 6, z1 = z0 + 1; racks.push({c, r, pts: [P(i0, 8, z0), P(i1, 8, z0), P(i1, 8, z1), P(i0, 8, z1)]}); }
    const lens = (i0, j0, z0, i1, j1, z1) => [P(i0, j0, z1), P(i1, j0, z1), P(i1, j0, z0), P(i1, j1, z0), P(i0, j1, z0), P(i0, j1, z1)];
    const beacon = {pts: lens(25.33, 7.33, 25, 25.57, 7.57, 27.5), at: P(25.45, 7.45, 27.5)};
    { // the sign on the roof, and above it a chip that says how the servers are (nothing when all is well)
      const [x, y] = P(22.5, 8, 44), eng = opts.engine || {total: 0, warn: 0, down: 0};
      // the board stands on its posts along the front face, so it is sheared along it (down to the right)
      let sign = `<rect x="-52" y="-9" width="104" height="15" fill="#c9a0ff" stroke="#2a1a2e" stroke-width="1.8"/><text x="0" y="2.4" text-anchor="middle" font-family="${FONT}" font-size="9" fill="#2a1a2e">SERVER ROOM</text>`;
      const parts = [], down = eng.down || 0, warn = eng.warn || 0;
      if (down) parts.push(`${down} DOWN`);
      if (warn) parts.push(`${warn} WARNING`);
      const txt = !eng.total ? "NOT CONNECTED" : parts.join(" · ");
      if (txt) {
        // a strip along the board's top edge, as wide as the board: part of the sign, not a chip in the air
        const fill = !eng.total ? "#20182c" : down ? "#ff4a4a" : "#FF9F43", ink = !eng.total ? "#a4a3b6" : down ? "#fff8ec" : "#2a1a2e";
        sign = `<rect x="-52" y="-20" width="104" height="11" fill="${fill}" stroke="#2a1a2e" stroke-width="1.8"/><text x="0" y="-12.2" text-anchor="middle" font-family="${FONT}" font-size="6.4" fill="${ink}">${txt}</text>` + sign;
      }
      tp("roof:engine", `<g transform="translate(${f(x)} ${f(y)}) matrix(1 .5 0 1 0 0)">${sign}</g>`);
    }
    // a plot for the next provider: scaffolding
    add(5 + 21 + 1, sc => { bx(sc, 3, 18, 0, 8, 22, 1, "#a8743a"); for (const [a, b] of [[3, 18], [8, 18], [3, 22], [8, 22]]) bx(sc, a - .1, b - .1, 1, a + .1, b + .1, 34, "#c9a46a"); for (const z of [12, 24, 34]) { bx(sc, 3, 21.9, z, 8, 22.1, z + 1, "#c9a46a"); bx(sc, 7.9, 18, z, 8.1, 22, z + 1, "#c9a46a"); } bx(sc, 5, 22.1, 0, 6.4, 22.3, 10, "#fff3d6", {front: [[5.1 * T, 2, 6.3 * T, 9, "#3f6fd8"]]}); }, {i0: 3, j0: 18, i1: 8, j1: 22}, "plot");
    { // the plot's board hangs on the scaffold's front, its top edge on the top beam, sheared along the face like the
      // Server room's; opaque, so no post shows through
      const [x, y] = P(5.5, 22.12, 29), txt = "GEMINI · SOON", w = 72;
      tp("plot", `<g transform="translate(${f(x)} ${f(y)}) matrix(1 .5 0 1 0 0)"><rect x="${f(-w / 2)}" y="-7" width="${w}" height="13" fill="#fff3d6" stroke="#2a1a2e" stroke-width="1.6"/><text x="0" y="2.4" text-anchor="middle" font-family="${FONT}" font-size="6.6" fill="#6a6478">${txt}</text></g>`); }
    // trees, lamps, benches round the plaza and along the roads
    const tree = (i, j, s = 1) => add(i + j + .6, sc => { bx(sc, i - .12, j - .12, 0, i + .12, j + .12, 16 * s, "#7a4a2e"); bx(sc, i - .7 * s, j - .7 * s, 12 * s, i + .7 * s, j + .7 * s, 26 * s, "#3fae6a"); bx(sc, i - .45 * s, j - .45 * s, 26 * s, i + .45 * s, j + .45 * s, 34 * s, "#5fd08a"); }, {i0: i - .7, j0: j - .7, i1: i + .7, j1: j + .7});
    for (const [i, j, s] of [[1.5, 9, 1], [2.5, 15.5, .9], [10, 3.5, 1.1], [12, 6.5, .8], [18.5, 9.5, .9], [27.5, 10.5, 1], [27, 14.5, .9], [10.5, 21.5, 1.1], [13, 23.5, .9], [18, 23, 1], [1.8, 23.5, .9], [28, 23.5, 1], [17.5, 3, .9], [9.5, 15.5, .8], [20, 10.5, .8]]) tree(i, j, s);
    const lamps = [];
    for (const [i, j] of [[11, 9], [19, 9], [11, 17], [19, 17], [6, 12], [24, 12], [14, 6], [16, 20]]) { add(i + j + .3, sc => { bx(sc, i - .08, j - .08, 0, i + .08, j + .08, 24, "#2a2433"); bx(sc, i - .2, j - .2, 24, i + .2, j + .2, 28, "#ffe2a8"); }); lamps.push([i, j]); }
    for (const [i, j] of [[12, 10.2], [17, 15.6], [12, 15.6], [17, 10.2]]) add(i + j + .4, sc => bx(sc, i - .7, j - .2, 0, i + .7, j + .2, 4, "#9a6a3a"));
    // a lookout at the edge of the island
    add(15 + 26, sc => { bx(sc, 14, 24, 0, 16, 26.6, 1, "#9a6a3a"); for (let a = 14; a < 16.01; a += .5) bx(sc, a - .05, 26.5, 1, a + .05, 26.6, 8, "#9a6a3a"); bx(sc, 14, 26.5, 8, 16, 26.6, 9, "#9a6a3a"); });
    // people about: a few of the team out on the campus
    const team = opts.people || [["Rue", [14.6, 8.2], "walkA", "SW"], ["Teo", [15.4, 18], "walkB", "NE"], [B.person("designer", 2), [12, 12.8], "idle", "SE"], [B.person("tester", 1), [9, 12.6], "walkA", "SE"], [B.person("marketing", 1), [17.2, 15.2], "wave", "SW"], [B.person("sales", 1), [22, 13.4], "walkB", "NW"], ["Pax", [21.5, 9], "idle", "SW"], [B.person("dev", 5), [6.5, 12.8], "walkA", "SE"]];
    for (const [who, [i, j], pose, view] of team) add(i + j + .3, sc => { B.figureInto(sc, typeof who === "string" ? B.CAST[who] : who, {pose, view, mood: pose === "wave" ? "happy" : "calm", noProp: false}, [i * T, j * T, 0]); });
    objs.sort((a, b) => a.key - b.key);
    // labels: the roof signs and the storey plaques
    const labels = [];
    for (const [b, prov] of [[claude, "claude"], [gpt, "chatgpt"]]) {
      tp("roof:" + prov, roofSign(b.sign, PROVIDERS[prov].name));
      b.plaques.forEach((pq, k) => tp(`plaque:${prov}:${k}`, plaqueSVG(pq.at[0], pq.at[1], pq.fl)));
      for (const pq of b.plaques) { labels.push({building: prov, rect: [pq.at[0], pq.at[1] - 8, 14 + plaqueBoxW(pq.fl) + 1, 15]}); }
    }
    let light = "";
    for (const [i, j] of lamps) { const [x, y] = P(i, j, 24); light += glow(x, y + 18, 40, "#ffb070", .45); }
    // the fountain's glow is its own sprite in the app, so it can pulse
    const defs = `<defs>${GLOWS.map(c => `<radialGradient id="bw-glow-${c}"><stop offset="0" stop-color="#${c}" stop-opacity="1"/><stop offset="1" stop-color="#${c}" stop-opacity="0"/></radialGradient>`).join("")}</defs>`;
    svg.innerHTML = defs + under.svg() + base.svg() + objs.map(o => o.sc.svg()).join("") + light + top;
    const bb = svg.getBBox(); svg.setAttribute("viewBox", `${Math.floor(bb.x - 16)} ${Math.floor(bb.y - 16)} ${Math.ceil(bb.width + 32)} ${Math.ceil(bb.height + 32)}`);
    return {P, parts: {under: [under], base, objs, boxes, light, top, topParts, hits, defs, racks, beacon, labels, storeys: [[claude, "claude"], [gpt, "chatgpt"]].flatMap(([b, prov]) => b.storeys.map((s, k) => ({building: prov, index: k, kind: s.fl.kind || "project", faces: s.faces, windows: b.windows[k]}))),
      towers: [[claude, "claude"], [gpt, "chatgpt"]].map(([b, prov]) => ({building: prov, antenna: b.antenna, chimney: b.chimney}))}};
  }
  /* one provider building on its own, close up */
  function building(svg, prov = "claude", floors) {
    const objs = [];
    const add = (key, draw) => { const sc = new E.Scene(S); draw(sc); objs.push({key, sc}); };
    bx2 = (sc, i0, j0, z0, i1, j1, z1, col, deco, opt) => sc.box(F0, [i0 * T, j0 * T, z0], [i1 * T, j1 * T, z1], col, deco || {}, opt || {});
    const ground = new E.Scene(S);
    for (let i = -1; i < 8; i++) for (let j = -1; j < 8; j++) bx2(ground, i, j, -1, i + 1, j + 1, 0, (i >= 2 && i < 4 && j >= 5) ? "#8a8fa8" : (i + j) % 2 ? "#5fb04f" : "#57a548");
    const fl = floors || [{name: "SHOPFRONT", wait: true}, {name: "RECIPE BOX"}, {name: "TIDE NOTES"}, {name: "CHAT · FONTS", wait: true}];
    const b = tower(null, 0, 0, 5, 4, prov, fl, add);
    add(6.5 + 6.5, sc => { B.figureInto(sc, B.CAST.Rue, {pose: "walkA", view: "SW"}, [3 * T, 6.2 * T, 0]); });
    add(1 + 6, sc => { bx2(sc, -.6, 5.4, 0, -.48, 5.52, 22, "#2a2433"); bx2(sc, -.75, 5.25, 22, -.33, 5.67, 26, "#ffe2a8"); });
    let top = roofSign(b.sign, PROVIDERS[prov].name);
    for (const pq of b.plaques) top += plaqueSVG(pq.at[0], pq.at[1], pq.fl);
    const defs = `<defs>${GLOWS.map(c => `<radialGradient id="bw-glow-${c}"><stop offset="0" stop-color="#${c}" stop-opacity="1"/><stop offset="1" stop-color="#${c}" stop-opacity="0"/></radialGradient>`).join("")}</defs>`;
    svg.innerHTML = defs + ground.svg() + objs.sort((a, c) => a.key - c.key).map(o => o.sc.svg()).join("") + top;
    const bb = svg.getBBox(); svg.setAttribute("viewBox", `${Math.floor(bb.x - 16)} ${Math.floor(bb.y - 16)} ${Math.ceil(bb.width + 32)} ${Math.ceil(bb.height + 32)}`);
  }
  window.BlockyWorld = {atrium, campus, building};
})();
