/* The campus (D22, D33) in Spel+ (D80): Y's lively little town on a floating island, built with the world kit
   (world-kit.js, world-props.js, world-ground.js). Driven by the World: a tower per provider with one storey per project
   (deep facades, no lift, a blade sign per storey), the Server room as a pavilion with a light strip per rack and an
   amber lamp by its door, and the quest pillar on the plaza that counts what waits for you. The rest is the town:
   streets with kerbs, sidewalks and zebras, a pond park, a small park with a gazebo, trees of several kinds, shrubs,
   flower beds, ducks, squirrels and birds. With night set, the whole scene is lit by the moon and only real light
   sources glow (A8).
     BlockyWorld.campus(svg, {claude: [storey], chatgpt: [storey], waiting, quests, engine, racks, night})
   storey: {name, wait, kind: project|factory|chats, logo}. Positions in tiles (i, j), heights in units (z).

   The walkers' lanes (CampusRoads in Walking.swift) run on the sidewalks: keep these clear of anything standing. */
(function () {
  const K = window.WorldKit, Pr = window.Props, G = window.Ground, Bd = window.Build, B = window.BlockyCast, P = K.P, T = K.T;
  const FONTS = K.FONTS, GAME = FONTS.game, TEXT = FONTS.text, MONO = FONTS.mono;
  const f = v => (+v).toFixed(2);
  const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  /* the island and its streets (tiles) */
  const NI = 62, NJ = 50;
  const ROAD_I = 21, ROAD_J = 30;                 // the road along i starts at j 21, the one along j at i 30 (4 wide)
  /* where the walkers walk (Walking.swift, CampusRoads): lanes, and the loop round the crossing over its zebras */
  const LANES = [
    [[11, 19.6], [28.2, 19.6]], [[28.2, 20.4], [11, 20.4]],          // west: the north sidewalk
    [[35.4, 11.5], [35.4, 19.2]], [[34.6, 19.2], [34.6, 11.5]],      // north: the east sidewalk
    [[51, 26.4], [35.8, 26.4]], [[35.8, 25.6], [51, 25.6]],          // east: the south sidewalk
    [[28.6, 39], [28.6, 26.8]], [[29.4, 26.8], [29.4, 39]],          // south: the west sidewalk
    [[28.2, 19.2], [28.2, 26.8]], [[28.2, 26.8], [35.8, 26.8]], [[35.8, 26.8], [35.8, 19.2]], [[35.8, 19.2], [28.2, 19.2]]];
  const PROVIDERS = {
    claude: {name: "CLAUDE", i: 10, j: 6, w: 8, d: 6, door: 14.5, board: "#e0603a", mark: "#b8603d",
      col: {wall: "#e8916b", trim: "#f6c8a8", frame: "#a0563a", lobby: "#d07c5a", lobbyGlass: "#ffe2b0", fac: "#3b2f3a", facFrame: "#251c25", sill: "#f6c8a8", roof: "#8a5a50", base: "#6a4a42"}},
    chatgpt: {name: "CHATGPT", i: 38, j: 7, w: 7, d: 5, door: 41.5, board: "#1f9a7a", mark: "#2f8f7a",
      col: {wall: "#4fc0a0", trim: "#aaf0dc", frame: "#2a8070", lobby: "#3fa088", lobbyGlass: "#e6fff4", fac: "#29363a", facFrame: "#182225", sill: "#aaf0dc", roof: "#3a6a64", base: "#2a5a50"}}
  };
  /* a provider's mark as 7×7 pixels (D55): a spark for Claude, a rosette for ChatGPT, simplified, in the blocky style */
  const MARKS = {
    claude: ["x..x..x", ".x.x.x.", "..xxx..", "xxxxxxx", "..xxx..", ".x.x.x.", "x..x..x"],
    chatgpt: ["..xxx..", ".x...x.", "x.x.x.x", "x..x..x", "x.x.x.x", ".x...x.", "..xxx.."]
  };
  const PASTEL = ["#9fd0ff", "#b8f0c8", "#c8d8ff", "#ffe0b0", "#d8c8ff", "#c8f0f0"];
  const hash = s => { let h = 7; for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return h; };

  function campus(svg, opts = {}) {
    const NIGHT = !!opts.night;
    window.__NIGHT = NIGHT;
    try { return build(svg, opts, NIGHT); } finally { window.__NIGHT = false; }
  }

  function build(svg, opts, NIGHT) {
    const th = {grass: ["#5cb04e", "#55a648"], flowers: ["#ff6a8a", "#ffd04a", "#b07cf0", "#fff8ec"], walk: "#d4c9b6", joint: "#b8ac98", kerb: "#ece4d4", road: "#565a6e", line: "#f2e6c4",
      path: "#e0c890", plaza: ["#e8d8bc", "#dccaa8"], edge: "#8a6440", stone: "#9a8e80", yard: ["#8a8c9c", "#80828f"],
      strata: [[-24, "#8c6242"], [-44, "#80583c"], [-72, "#8e7a66"], [-106, "#7e6c5e"], [-150, "#6e6058"], [-210, "#605650"], [-9999, "#524a46"]]};
    const W = new K.World();
    /* ---------- the map ---------- */
    const m = G.map(NI, NJ);
    G.island(m, {round: 11, wobble: 2});
    G.road(m, "i", ROAD_I, 6, 57); G.road(m, "j", ROAD_J, 6, 45);
    // the road ends turn round a little island of grass: every road ends somewhere with a reason (A2)
    for (const [ci, cj] of [[5.5, 23], [57, 23], [32, 5.5], [32, 45]]) { m.disc(ci, cj, 5.4, 5.4, "walk", ["grass", "walk"]); m.disc(ci, cj, 4.2, 4.2, "road"); m.disc(ci, cj, 1.7, 1.7, "grass"); }
    m.each((i, j, t, mt) => { if (t === "road" && (!mt.axis || (i >= ROAD_J && i < ROAD_J + 4 && j >= ROAD_I && j < ROAD_I + 4))) mt.junction = true; });
    // zebras right at the mouths of the crossing, where the walkers' loop goes over
    G.crossing(m, "i", ROAD_I, 28); G.crossing(m, "i", ROAD_I, 34); G.crossing(m, "j", ROAD_J, 19); G.crossing(m, "j", ROAD_J, 25);
    // forecourts from each door to the sidewalk, the plaza, the server yard and its path, the gazebo park's loop
    m.rect(11, 12, 18, 19, "plaza"); m.rect(39, 12, 45, 19, "plaza");
    m.rect(36, 27, 49, 39, "plaza");
    m.rect(51, 28, 59, 38, "yard"); m.rect(49, 35, 51, 37, "path");
    m.rect(51.6, 13, 53.4, 18, "path", null, ["grass"]); m.each((i, j, t) => { const a = (i + .5 - 52.5) / 4.6, b = (j + .5 - 8.5) / 4.0, r = Math.hypot(a, b); if (t === "grass" && r > .82 && r <= 1.02) m.set(i, j, "path"); });
    // the duck pond and the path round it
    m.disc(15, 36, 6, 4.4, "water");
    m.each((i, j, t) => { const a = (i + .5 - 15) / 8.2, b = (j + .5 - 36) / 6.4, r = Math.hypot(a, b); if (t === "grass" && r > .87 && r <= 1.04) m.set(i, j, "path"); });
    m.rect(23, 27, 25, 32, "path", null, ["grass"]); m.rect(9, 27, 11, 30, "path", null, ["grass"]); m.rect(36, 39, 38, 46, "path", null, ["grass"]);
    G.terrain(W, m, th);
    G.underside(W, m, th, {lin: 24, maxD: 380, vines: "#3f9a52", spikes: [[30, 30, 9, 100], [44, 22, 7, 80], [18, 36, 7, 70]]});
    const h = (i, j) => W.h(i, j);
    const kind = (i, j) => m.get(Math.floor(i), Math.floor(j));

    /* ---------- objects: each its own sprite in the app, sorted with the walkers ---------- */
    const objs = [];
    // fn draws into a world of its own; o: {id, solid: false (people walk under it: nothing, they never do), alpha}
    const obj = (fn, o = {}) => {
      const sub = new K.World();
      const ret = fn(sub);
      if (!sub.items.length) { W.adopt(sub); return ret; }
      const it = K.World.merge(sub);
      it.id = o.id || null; it.alpha = o.alpha; it.layer = o.layer || 0;
      objs.push(it);
      W.adopt(sub);
      return ret;
    };
    // people who live on the campus (D84): the app gives them a loop of poses, so they wave, sip, read and doze
    const npcs = [];
    const npc = (role, seed, pose, view, i, j, z, mood) => npcs.push({role, seed: String(seed), pose, view, i, j, z, mood: mood || "calm"});
    // a prop only where the ground suits it (never on a road, in the pond or off the island)
    const on = (i, j, kinds = ["grass", "walk", "plaza", "path", "yard"]) => kinds.includes(kind(i, j));

    /* ---------- the towers: deep facades, no lift (A10); a blade sign per storey ---------- */
    const storeys = [], towers = [], labels = [], topParts = [], footprints = {}, streams = {};
    const tp = (id, markup) => topParts.push({id, markup});
    for (const prov of ["claude", "chatgpt"]) {
      const S = PROVIDERS[prov], list = opts[prov] || [];
      const z = h(S.i + 3, S.j + S.d + 1);
      // many projects: lower storeys, so a tall tower stays on the campus
      const H = list.length <= 6 ? 40 : Math.max(30, 40 - (list.length - 6) * 2.5);
      const t = obj(w => tower(w, prov, S, list, z, H, NIGHT), {id: "building:" + prov});
      footprints["building:" + prov] = [S.i - .3, S.j - .3, S.i + S.w + .3, S.j + S.d + .3];
      t.storeys.forEach((s, k) => storeys.push({building: prov, index: k, kind: list[k].kind || "project", faces: s.faces, windows: s.windows, mount: s.mount}));
      towers.push({building: prov, antenna: t.antenna, chimney: t.chimney, empty: list.length === 0});
      t.blades.forEach((bl, k) => { tp(`plaque:${prov}:${k}`, bl.markup); labels.push({building: prov, rect: bl.rect}); });
      // the way a deploy's packets go: out of the door, down the forecourt, along the sidewalks to the Server room
      streams[prov] = prov === "claude" ? [[S.door, S.j + S.d + .6], [S.door, 25.6], [47.6, 25.6], [47.6, 36], [52.3, 36], [52.3, 34.8]]
        : [[S.door, S.j + S.d + .6], [S.door, 20.4], [47.6, 20.4], [47.6, 36], [52.3, 36], [52.3, 34.8]];
      // a lamp each side of the forecourt
      for (const a of [S.i + 1.2, S.i + S.w - .8]) if (on(a, S.j + S.d + 4.6)) obj(w => Pr.lamp(w, a, S.j + S.d + 4.6, h(a, S.j + S.d + 4.6), {post: "#3a3550", glass: "#fff0c0"}));
    }

    /* ---------- the Server room: a pavilion, racks behind a glass front, a lamp by the door (A5) ---------- */
    const racksIn = (opts.racks || []).slice(0, 6), nR = 6;
    const zs = h(55, 32), si0 = 51.6, sj0 = 28.5, si1 = 58.6, sj1 = 34.5;
    const rackGeo = [];
    for (let k = 0; k < nR; k++) { const a = si0 + .85 + k * .9; rackGeo.push({i0: a, i1: a + .7, j0: sj1 - 1.6, j1: sj1 - .55, z0: zs + 1.2, z1: zs + 32}); }
    obj(w => serverRoom(w, {zs, si0, sj0, si1, sj1, racks: racksIn, rackGeo, NIGHT}), {id: "building:engine"});
    obj(w => serverFront(w, {zs, si0, sj0, si1, sj1}), {id: "engine:front"});
    footprints["building:engine"] = [si0 - .1, sj0 - .1, si1 + .6, sj1 + .2];
    // each rack's light strip (r 1, the state) and its row of activity lights (r 0), on its front face, for the app to light
    const racks = [], rackPanels = [];
    // where someone squats to work on a rack (D87): inside, between its front and the glass, on the floor
    // (i: seen through the glass, midway between two mullions, which stand .55 further on than the racks)
    const rackSpots = rackGeo.map(g => ({i: g.i0 + .66, j: sj1 - .24, z: zs + 1.2, i0: g.i0, i1: g.i1, front: g.j1, z0: g.z0}));
    rackGeo.forEach((g, c) => {
      const q = (a0, a1, z0, z1) => [P(a0, g.j1, z0), P(a1, g.j1, z0), P(a1, g.j1, z1), P(a0, g.j1, z1)];
      racks.push({c, r: 1, pts: q(g.i0 + .06, g.i1 - .06, g.z0 + 25.2, g.z0 + 26.4)});
      racks.push({c, r: 0, pts: q(g.i1 - .16, g.i1 - .08, g.z0 + 4, g.z0 + 20)});
      rackPanels.push({pts: q(g.i0, g.i1, g.z0, g.z1), box: [g.i0, g.i1, g.j1, g.z0, g.z1]});
    });
    // the lamp on its bracket by the door: lit by the app, amber when a server needs a look
    const lamp = {i0: si0 + .51, j0: sj1 + .29, z0: zs + 36.2, i1: si0 + .79, j1: sj1 + .57, z1: zs + 39.2};
    const beacon = {pts: [P(lamp.i0, lamp.j0, lamp.z1), P(lamp.i1, lamp.j0, lamp.z1), P(lamp.i1, lamp.j0, lamp.z0), P(lamp.i1, lamp.j1, lamp.z0), P(lamp.i0, lamp.j1, lamp.z0), P(lamp.i0, lamp.j1, lamp.z1)], at: P((lamp.i0 + lamp.i1) / 2, lamp.j1, (lamp.z0 + lamp.z1) / 2)};
    // the yard: a fence along the front and the right, the gate on the path, a bench, a bike, a bin
    obj(w => Pr.fence(w, 51, 38.4, 53.6, 38.4, zs, "#9aa3b4", 9)); obj(w => Pr.fence(w, 55.4, 38.4, 59.4, 38.4, zs, "#9aa3b4", 9));
    for (let b = 27.6; b < 38.4; b += 3.6) obj(w => Pr.fence(w, 59.4, b, 59.4, Math.min(38.4, b + 3.6), zs, "#9aa3b4", 9));
    obj(w => Pr.bench(w, 57.2, 36.8, zs, {face: "SW", len: 1.8})); obj(w => Pr.bike(w, 55.2, 37.4, zs, {col: "#3f6fd8", face: "SE"})); obj(w => Pr.bin(w, 58.8, 35.4, zs, "#3a6a4a"));

    /* ---------- the plaza: the quest pillar in its fountain (A3), café tables, string lights ---------- */
    const zp = h(42, 33), ci = 42, cj = 32.5, waiting = opts.waiting || 0, quests = (opts.quests || []).slice(0, 2);
    obj(w => pillar(w, ci, cj, zp, waiting, quests, NIGHT), {id: "fountain"});
    const hits = {fountain: [[ci - 3, cj - 1.4, ci + 3, cj + 1.4, zp + 4], [ci - .9, cj - .9, ci + .9, cj + .9, zp + 42], [ci - .3, cj - .3, ci + .3, cj + .3, zp + 80]]};
    footprints.fountain = [ci - 3, cj - 3, ci + 3, cj + 3];
    for (const [a, b] of [[37.4, 28.2], [46.6, 28.2], [37.4, 37.6], [46.6, 37.6]]) obj(w => Pr.bed(w, a - .8, b - .8, a + .8, b + .8, zp, ["#ff6a8a", "#ffd04a", "#b07cf0"], "#b9a88e", a + b));
    for (const [a, b] of [[37, 33.4], [47, 31.6]]) obj(w => Pr.bench(w, a, b, zp, {face: "SE", len: 2}));
    for (const [a, b, u] of [[38.2, 30.2, "#e0473a"], [44.4, 37.8, "#3f6fd8"], [46, 29.6, "#3fae6a"]]) obj(w => Pr.cafeTable(w, a, b, zp, {umbrella: u, stools: [[a - .75, b], [a, b + .75]]}));
    stringLights(W, obj, [[36.4, 27.4], [47.6, 27.4], [47.6, 38.4], [36.4, 38.4]], zp, NIGHT);
    // bikes at a rack on the plaza's edge
    for (const [k, c] of [[0, "#e0473a"], [1, "#3f6fd8"], [2, "#3fae6a"]]) obj(w => { Pr.bike(w, 36.6, 29.4 + k * 1.4, zp, {col: c, face: "SE"}); w.box(36.4, 29.4 + k * 1.4 - .03, zp, 36.48, 29.4 + k * 1.4 + .03, zp + 9, "#9aa3b4"); w.box(36.4, 29.4 + k * 1.4 - .03, zp + 8.2, 37.1, 29.4 + k * 1.4 + .03, zp + 9, "#9aa3b4"); });
    // the food truck by the plaza, parked on the road with its hatch to the sidewalk
    obj(w => Pr.foodTruck(w, 40.2, 22.5, -1.4, {name: "TACO BYTE", font: GAME}));
    for (const [a, b, o] of [[41.0, 28.6, {pose: "idle", view: "NE"}], [39.9, 28.8, {pose: "mug", view: "NE"}], [45.6, 34.2, {pose: "wave", view: "SW", mood: "happy"}], [40.2, 36.6, {pose: "read", view: "SE"}], [38.4, 36.4, {pose: "mug", view: "SW"}]])
      obj(w => w.fig(B.person(["pm", "tester", "devops", "dev", "designer"][Math.floor(a + b) % 5], Math.floor(a * 3 + b)), o, a, b, zp));
    obj(w => w.fig(B.person("sales", 7), {pose: "sit", view: "SE"}, 36.95, 33.4, zp + 3.2));

    /* ---------- streets: lamps, trees of several kinds, a bus shelter, signs, vans ---------- */
    const kinds = ["maple", "cherry", "oak", "poplar"];
    let kk = 0;
    const streetTree = (a, b, pit) => { if (!on(a, b)) return; obj(w => { if (pit) Pr.treePit(w, a, b, h(a, b)); Pr.tree(w, kinds[kk++ % 4], a, b, h(a, b), .62, a * 3 + b); }); };
    for (let a = 8; a <= 55; a += 3.5) {
      if (a > 25 && a < 38) continue;
      // north side: on the sidewalk east of the crossing; west of it the walkers use the sidewalk, so the trees stand on the verge
      if (!((a >= 10 && a <= 19) || (a >= 37 && a <= 46))) a < 30 ? streetTree(a, 17.4, false) : streetTree(a, 19.5, true);
      // south side: on the sidewalk west of the crossing; east of it the plaza and the walkers' sidewalk
      if (a < 30 && Math.abs(a - 22) >= 2) streetTree(a, 26.5, true);
      if (a > 50) streetTree(a, 28.4, false);
    }
    for (let b = 8; b <= 43; b += 3.5) {
      if (b > 16 && b < 29) continue;
      if (b < 20) { streetTree(28.5, b, true); streetTree(37.6, b, false); }
      else { streetTree(26.6, b, false); if (b > 40) streetTree(35.5, b, true); }
    }
    const lampTops = [];
    const streetLamp = (a, b) => { if (on(a, b)) lampTops.push(obj(w => Pr.lamp(w, a, b, h(a, b), {post: "#3a3550", glass: "#fff0c0"}))); };
    for (let a = 9.7; a <= 55; a += 7) { if (a > 26 && a < 37) continue; streetLamp(a, a < 30 ? 18.7 : 20.6); streetLamp(a + 3.5, a > 30 ? 25.15 : 25.4); }
    for (let b = 9.7; b <= 43; b += 7) { if (b > 17 && b < 29) continue; streetLamp(b < 20 ? 29.6 : 27.8, b); streetLamp(b < 20 ? 34.15 : 34.4, b + 3.5); }
    const perch = (k, o) => { const t = lampTops[k % lampTops.length]; if (t) obj(w => Pr.bird(w, ...t.top, o), {id: "bird:perch:" + k}); };
    perch(2, {kind: "pigeon"}); perch(5, {kind: "robin", dir: "SE"}); perch(9, {kind: "sparrow"});
    obj(w => { Pr.shelter(w, 22, 26.2, 1.6, {band: "#FFD83D"}); }); npc("marketing", 7, "sit", "SW", 21.6, 26, 1.6 + 3.6);
    obj(w => Pr.streetSign(w, 27.4, 18.8, 1, "Quest St", {font: GAME, bg: "#2f5a8a"})); obj(w => Pr.streetSign(w, 36.5, 27.6, zp, "Pixel Ave", {font: GAME, bg: "#2f5a8a", face: "SE"}));
    for (const [a, b] of [[26.6, 20.86], [37.4, 25.14], [29.4, 16.6], [34.6, 27.4]]) obj(w => Pr.bollard(w, a, b, 1.6, "#3a3550"));
    obj(w => Pr.hydrant(w, 23.4, 20.88, 1.6)); obj(w => Pr.postBox(w, 46.4, 20.4, 1.6)); obj(w => Pr.bin(w, 20, 19.12, 1.6, "#3a6a4a")); obj(w => Pr.bin(w, 34.4, 38, 1.6, "#3a6a4a"));
    obj(w => Pr.van(w, 16, 22.5, -1.4, {logo: "POST", col: "#f2efe6", stripe: "#e0473a", font: GAME, face: "SE"}));
    obj(w => Pr.van(w, 31, 36, -1.4, {col: "#ffd04a", stripe: "#2a2433", len: 2.6, h: 22, face: "SW"}));
    obj(w => Pr.van(w, 50, 22.5, -1.4, {col: "#5ab0e0", stripe: "#fff8ec", len: 2.6, h: 22, face: "SE"}));

    /* ---------- a small park where the empty plot was (A7): a gravel loop, a gazebo, beds, trees, a bench ---------- */
    { const gi = 52.5, gj = 8.5, z = h(50, 8);
      obj(w => gazebo(w, gi, gj, z));
      obj(w => Pr.bench(w, gi + .2, gj + 2.6, z, {face: "SW", len: 1.8}));
      npc("dev", 61, "sit", "SW", gi - .1, gj + 2.65, z + 3.2);
      npc("tester", 62, "mug", "SW", gi + 1.9, gj + 2.4, z);
      for (const [k2, a, b, sc] of [["cherry", 48.4, 5.6, .8], ["maple", 56.8, 5.2, .8], ["oak", 48.2, 11.8, .8], ["apple", 57.2, 11.6, .75]]) if (on(a, b)) obj(w => Pr.tree(w, k2, a, b, h(a, b), sc));
      for (const [a, b, c] of [[50.6, 5, ["#ff6a8a", "#fff8ec"]], [54.6, 12.6, ["#ffd04a", "#b07cf0"]]]) obj(w => Pr.bed(w, a - .9, b - .6, a + .9, b + .6, h(a, b), c, "#b9a88e", a));
      obj(w => Pr.bench(w, 56.2, 8.4, h(56, 8), {face: "SE", len: 1.6})); obj(w => Pr.lamp(w, 49.2, 8.6, h(49, 8), {post: "#3a3550", glass: "#fff0c0"}));
      obj(w => Pr.squirrel(w, 48.4, 5.76, h(48, 5) + 8, {on: "trunkF"}), {id: "squirrel:park"}); obj(w => Pr.bird(w, 56.2, 8.4, h(56, 8) + 13.4, {kind: "robin", dir: "SE"}), {id: "bird:park"}); }

    /* ---------- the pond park: ducks, an island with a bridge, groves, hedges, beds, a picnic ---------- */
    const waterT = []; m.each((i, j, t) => { if (t === "water") waterT.push([i, j]); });
    Pr.water(W, waterT, -2.4, "#3a82c8");
    obj(w => { w.box(14, 35, -5, 16.4, 37, 1, "#5cb04e", {deco: {top: [[14.2, 35.2, 16.2, 36.8, "#55a648"]]}}); Pr.tree(w, "cherry", 15.2, 36, 1, .6); });
    obj(w => Pr.duck(w, 14.4, 37.3, -2.4, {white: true}), {id: "duck:island"});
    obj(w => bridge(w, 16.2, 21.8, 35.6));
    for (const [a, b, n] of [[9.4, 34, 6], [19.6, 38.6, 5], [11, 39.4, 5]]) obj(w => Pr.reeds(w, a, b, -2.4, n));
    for (const [a, b, fl] of [[11.4, 34.4, 1], [18.6, 36.8, 0], [12.6, 38.4, 1], [17.4, 33.4, 0]]) obj(w => Pr.lily(w, a, b, -2.3, fl));
    for (const [k, [a, b, o]] of [[12, 36, {}], [13, 37.6, {white: true, dir: "SE"}], [18.4, 38, {dir: "SE"}], [17.2, 34.4, {}], [11.4, 37.2, {white: true}]].entries()) obj(w => Pr.duck(w, a, b, -2.4, o), {id: "duck:" + k});
    const grove = [["cherry", 4.6, 30.4, 1], ["cherry", 6.4, 33.4, .9], ["maple", 4.2, 37.6, 1], ["maple", 7.2, 42.6, .95], ["apple", 11, 44.4, .9], ["apple", 14, 45.2, .85], ["poplar", 25.4, 46.2, 1], ["poplar", 24.2, 43.4, 1], ["cherry", 25.4, 39.2, .9], ["oak", 24.8, 35.6, 1], ["birch", 21.4, 30.4, .85], ["pine", 4, 26.6, .9],
      ["pine", 5.6, 8.4, 1], ["pine", 4.2, 12.2, .9], ["maple", 6.8, 15.6, .9], ["oak", 21.4, 8.6, 1], ["cherry", 23.6, 12.4, .85], ["apple", 21.8, 15.2, .8], ["birch", 37.2, 4.6, .8], ["maple", 47, 15.6, .8],
      ["oak", 53, 17.8, .9], ["cherry", 56.6, 16.6, .85], ["poplar", 60.4, 26, 1], ["maple", 54.6, 42.4, .9], ["cherry", 50.6, 44, .85], ["oak", 43.6, 44.4, .9], ["apple", 40, 44.2, .8], ["poplar", 46, 42.2, 1], ["pine", 26.4, 2.6, .8], ["pine", 9.2, 21, .9]];
    for (const [k2, a, b, s] of grove) if (on(a, b, ["grass"])) obj(w => Pr.tree(w, k2, a, b, h(a, b), s));
    obj(w => Pr.hedge(w, 3, 28.2, 9, 28.6, 1, 8)); obj(w => Pr.hedge(w, 12, 28.2, 22, 28.6, 1, 8)); obj(w => Pr.hedge(w, 3, 28.6, 3.4, 33, 1, 8));
    for (const [a, b, c] of [[8.2, 30.4, ["#ff6a8a", "#fff8ec"]], [21.6, 33.6, ["#ffd04a", "#ff8a2a"]], [6.6, 39.6, ["#b07cf0", "#ff6a8a"]]]) obj(w => Pr.bed(w, a - 1, b - .7, a + 1, b + .7, 1.15, c, "#b9a88e", a));
    for (const [a, b] of [[25.4, 30.2], [8.6, 44.6], [17.4, 44.6], [3.6, 35.6], [21.2, 44.2], [48.6, 41.8], [57.8, 20.6], [24.4, 16.4], [7.4, 17.8], [44.2, 40.6]]) if (on(a, b, ["grass"])) obj(w => Pr.shrub(w, a, b, h(a, b), .9, "#3f9a52", ["#ff6a8a", "#ffd04a", null][Math.floor(a) % 3]));
    for (const [a, b, face] of [[15, 30.6, "SW"], [8, 36, "SE"], [15, 41.4, "SW"]]) obj(w => Pr.bench(w, a, b, h(a, b), {face, len: 1.9}));
    for (const [a, b] of [[10.6, 30.4], [23.4, 38.6], [9.6, 41.6]]) obj(w => Pr.lamp(w, a, b, h(a, b)));
    obj(w => { w.box(5.2, 45.4, 1, 7.2, 46.8, 1.4, "#e0473a", {deco: {top: [[5.2, 45.9, 7.2, 46.1, "#fff8ec"], [5.7, 45.4, 5.9, 46.8, "#fff8ec"], [6.5, 45.4, 6.7, 46.8, "#fff8ec"]]}}); w.box(6.4, 46.2, 1.4, 6.9, 46.6, 4.4, "#a8743a"); });
    obj(w => w.fig(B.person("designer", 5), {pose: "sit", view: "SE", zb: 1.4}, 5.6, 45.9, -1.2));
    obj(w => w.fig(B.person("pm", 9), {pose: "sit", view: "SW", zb: 1.4}, 6.5, 45.5, -1.2));
    npc("dev", 8, "sit", "SW", 14.6, 30.6, h(14, 30) + 3.2);
    npc("lead", 2, "point", "NW", 18.6, 41.6, h(18, 41));
    npc("marketing", 5, "wave", "SW", 10.2, 28.6, h(10, 28), "happy");
    npc("researcher", 2, "read", "SE", 13.4, 15.2, h(13, 15));
    npc("lead", 3, "mug", "SW", 43, 16.4, h(43, 16));
    for (const [k, [a, b, z, o]] of [[4.6, 30.56, 9, {on: "trunkF"}], [24.82, 35.6, 8, {on: "trunkR"}], [13.4, 43.2, 1.15, {dir: "SW"}], [21.2, 9.6, 1, {dir: "SE"}], [7.8, 46.6, 1, {dir: "SW"}]].entries()) obj(w => Pr.squirrel(w, a, b, z + (z > 2 ? h(a, b) - 1 : 0), o), {id: "squirrel:" + k});
    for (const [k, [a, b, z, up]] of [[14, 33, 120, 1], [15.4, 31.8, 126, 0], [12.8, 31.6, 116, 0], [16.8, 33.2, 112, 1], [44, 22, 170, 1], [45.4, 21, 176, 0], [-4, 20, 40, 1], [-2.8, 19, 46, 0]].entries()) obj(w => Pr.flyer(w, a, b, z, {up, col: "#efeaf4", tip: "#4a4460"}), {layer: 2, id: "flyer:" + k});
    for (const [k, [a, b, z, o]] of [[40.6, 30.2, zp + 4, {kind: "pigeon"}], [43.4, 34.9, zp + 4, {kind: "pigeon", dir: "SE"}], [39.4, 35.4, zp, {kind: "pigeon"}]].entries()) obj(w => Pr.bird(w, a, b, z, o), {id: "bird:plaza:" + k});
    // the edge: a lookout deck with a railing and a coin telescope
    obj(w => { w.box(30.4, 46.2, 1, 33.6, 49.2, 2.4, "#a8743a", {deco: {top: [0, 1, 2, 3, 4].map(k => [30.4, 46.6 + k * .55, 33.6, 46.63 + k * .55, "#7a5428"])}}); });
    obj(w => { Pr.fence(w, 30.4, 49.4, 33.6, 49.4, 2.4, "#3a3550", 10); w.box(32.4, 48.2, 2.4, 32.6, 48.4, 14, "#3a3550"); w.box(32.2, 48.1, 14, 32.9, 48.5, 18, "#3f6fd8"); });

    /* ---------- around the island: islets, clouds, a balloon (A4) ---------- */
    const far = [];   // [ops, layer (-1 behind the island, 1 in front of its underside), alpha]
    const isl1 = G.islet(-12, 8, 50, 3.4, th, w => { Pr.tree(w, "cherry", -12, 8, 50, .8); Pr.tree(w, "pine", -13.6, 9.4, 50, .7); });
    const isl2 = G.islet(40, -16, 110, 2.8, th, w => { Pr.tree(w, "maple", 40, -16, 110, .8); Pr.squirrel(w, 40.9, -15.4, 110, {dir: "SW"}); });
    const isl3 = G.islet(74, 46, -110, 2.6, th, w => { Pr.tree(w, "apple", 74, 46, -110, .7); Pr.rock(w, 73, 47, -110, 1); });
    far.push([isl1.ops, -1, 1], [isl2.ops, -1, 1], [isl3.ops, 1, 1]);
    const cloudCol = NIGHT ? "#3a3a66" : "#9a8fd0";
    for (const [a, b, z, s, op, sd, layer] of [[24, -18, 60, 1.8, .42, 2, -1], [-18, 30, -140, 2.2, .44, 3, -1], [12, 62, -320, 2.2, .45, 4, 1], [70, 44, -340, 2.6, .42, 5, 1], [60, 50, -210, 1.6, .5, 7, 1]]) {
      const c = Pr.cloud(W, a, b, z, s, cloudCol, op, sd); far.push([c.ops, layer, c.op]);
    }
    far.push([balloon(84, 40, 260, NIGHT, W), 1, 1, "balloon"]);

    /* ---------- depth: each object's key, so the app sorts them with its walkers ---------- */
    // the topological order of the objects; a key is at least the sum of its front corner (i1 + j1, as the walkers'), and
    // above everything that has to be drawn behind it
    const order = K.sortItems(objs), behind = objs.__behind, keyOf = new Map();
    for (const it of order) {
      let k = (it.b[3] + it.b[4]) / T;
      for (const q of behind[objs.indexOf(it)] || []) { const kq = keyOf.get(objs[q]); if (kq != null && kq + .01 > k) k = kq + .01; }
      keyOf.set(it, k);
    }
    const boxes = objs.map(it => ({i0: it.b[0] / T, j0: it.b[1] / T, i1: it.b[3] / T, j1: it.b[4] / T, key: keyOf.get(it), id: it.id || null, h: it.b[5]}));
    const out = objs.map(it => ({ops: it.ops, key: keyOf.get(it) + (it.layer === 2 ? 100 : 0), id: it.id || null, alpha: it.alpha}));
    far.forEach(([ops, layer, alpha, id], k) => out.push({ops, key: layer < 0 ? -60 - k * .01 : -48.5 + k * .01, id: id || (alpha < 1 ? "cloud:" + alpha : "far"), alpha}));

    /* ---------- the view: the island and the towers, for the camera ---------- */
    const tall = objs.filter(o => (o.id || "").startsWith("building:")).flatMap(o => o.ops);
    const view = K.opsBounds([...W.under, ...W.base, ...tall], 16), island = K.opsBounds([...W.base, ...tall], 4);
    return {P, parts: {island,under: W.under, base: W.base, water: W.water, shadows: W.shadowP, light: [...W.pools, ...W.halos], objs: out, boxes, topParts, hits, racks, rackPanels, beacon, labels, storeys, towers, footprints, streams, lanes: LANES, npcs, rackSpots,
      fountain: P(ci, cj, zp + 20), view: [view[0], view[1] - 20, view[2], view[3]]}};
  }

  /* ---------- a provider tower: lobby, a storey per project, a cornice; a blade sign per storey ---------- */
  function tower(W, prov, S, list, z, H, NIGHT) {
    const C = S.col, i = S.i, j = S.j, w = S.w, d = S.d, i1 = i + w, j1 = j + d, LH = 46, r = .16;
    // no chat with this provider lately (D84): the tower stands empty: dark glass, boarded up, lamps out, weeds
    const empty = list.length === 0;
    const warmPick = (rr, chat) => chat ? ["#ffd9a8", "#ffc48a", "#ffe6c4"][Math.floor(rr * 30) % 3] : ["#ffe6c4", "#ffc27a", "#ffd9a8", "#ffb070", "#cfe4ff"][Math.floor(rr * 50) % 5];
    const ww = .58, spans = (a0, a1) => { const out = []; for (let a = a0 + .32; a + ww <= a1 - .25; a += 1) out.push([a, a + ww]); return out; };
    // the plinth band all round, the lobby: tall shop windows between stone piers, the door set back under a canopy
    W.box(i - .1, j - .1, z, i1 + .1, j1 + .1, z + 4, C.base, {shadow: 1.6});
    const lg = C.lobbyGlass;
    const lobbyGlass = (w0, w1) => empty
      ? [[w0, z + 8, w1, z + 34, "#1c2236"], [w0, z + 22, w1, z + 34, "#262e48"], [(w0 + w1) / 2 - .02, z + 8, (w0 + w1) / 2 + .02, z + 34, C.frame],
         // every other window boarded: two planks across
         ...(Math.round(w0 * 4) % 2 ? [[w0 - .05, z + 14, w1 + .05, z + 16.6, "#8a6a44"], [w0 - .05, z + 24, w1 + .05, z + 26.6, "#7a5c3a"]] : [])]
      : [[w0, z + 8, w1, z + 34, "!" + lg], [w0, z + 26, w1, z + 34, "!" + K.shade(lg, .8)], [(w0 + w1) / 2 - .02, z + 8, (w0 + w1) / 2 + .02, z + 34, C.frame]];
    const spansF = []; for (let a = i + .4; a + .9 <= i1 - .3; a += 1.25) if (Math.abs(a + .45 - S.door) > 1.3) spansF.push([a, a + .9]);
    const spansR = []; for (let a = j + .4; a + .9 <= j1 - .3; a += 1.25) spansR.push([a, a + .9]);
    Bd.deepWall(W, "front", i, i1, j1, z + 4, z + LH, spansF.concat([[S.door - .85, S.door + .85]]), z + 8, z + 36, {col: C.lobby, frame: C.frame, trim: C.trim, r: .22, glass: (w0, w1) => Math.abs((w0 + w1) / 2 - S.door) < .1 ? [] : lobbyGlass(w0, w1), door: [S.door - .85, S.door + .85]});
    Bd.deepWall(W, "right", j, j1, i1, z + 4, z + LH, spansR, z + 8, z + 36, {col: C.lobby, frame: C.frame, trim: C.trim, r: .22, glass: lobbyGlass});
    Bd.door(W, "front", S.door, j1 - .14, z + 4, {w: 1.5, h: 30, canopy: C.trim, col: C.frame, depth: 1.3, lamps: !empty, glass: empty ? "#1c2236" : undefined});
    if (empty) {
      // planks nailed across the door, and weeds along the plinth
      for (const [zz, col] of [[z + 12, "#8a6a44"], [z + 20, "#7a5c3a"], [z + 28, "#8a6a44"]]) W.box(S.door - 1.0, j1 + .02, zz, S.door + 1.0, j1 + .16, zz + 2.6, col);
      for (const a of [i + .6, i + 2.4, i1 - 1.4, S.door + 1.6]) Pr.reeds(W, a, j1 + .35, z + 4, 3);
    }
    W.box(i - .08, j - .08, z + LH, i1 + .08, j1 + .08, z + LH + 2.4, C.trim);
    const sto = [], blades = [];
    list.forEach((s, k) => {
      const z0 = z + LH + 2.4 + k * H, z1 = z0 + H - 2.4, fac = s.kind === "factory", chat = s.kind === "chats";
      const body = fac ? C.fac : C.wall, frame = fac ? C.facFrame : C.frame, zw0 = z0 + Math.min(9, H * .22), zw1 = z1 - Math.min(7, H * .18);
      const glass = face => (w0, w1) => {
        const g = [], mid = (w0 + w1) / 2, rr = Pr.rnd(prov + k + face + w0)();
        if (fac) { g.push([w0, zw0, w1, zw1, "#121a30"]); if (rr > .15) g.push([w0 + .05, zw0 + 3, mid - .03, zw0 + 11, "!#7fd6ff"], [mid + .03, zw0 + 3, w1 - .05, zw0 + 11, rr > .5 ? "!#5fb8f0" : "!#b5f0ff"]); }
        else if (rr > .3) { const warm = warmPick(rr, chat); const hz = zw0 + (zw1 - zw0) * .62; g.push([w0, zw0, w1, hz, "!" + warm], [w0, hz, w1, zw1, "!" + K.shade(warm, .7)]); if (rr > .62) g.push([mid - .1, zw0, mid + .1, zw0 + 7, ["#4a74d8", "#3fae6a", "#e8608a", "#7a5ce0"][Math.floor(rr * 40) % 4]], [mid - .08, zw0 + 7, mid + .08, zw0 + 11, ["#f2b48a", "#a86a44", "#7a4a32"][Math.floor(rr * 30) % 3]]); }
        else g.push([w0, zw0, w1, zw1, "#24305a"], [w0, zw0 + (zw1 - zw0) * .5, w1, zw1, "#2e3a68"]);
        g.push([mid - .02, zw0, mid + .02, zw1, frame], [w0, zw0 + (zw1 - zw0) * .62, w1, zw0 + (zw1 - zw0) * .62 + .6, frame]);
        if (chat) g.push([w0, zw1 - 4, w1, zw1, "!#e0473a"]);
        return g;
      };
      const fs = spans(i, i1);
      Bd.deepWall(W, "front", i, i1, j1, z0, z1, fs, zw0, zw1, {col: body, frame, trim: fac ? C.wall : C.sill || C.trim, r, glass: glass("f"), lintel: K.shade(body, .78)});
      Bd.deepWall(W, "right", j, j1, i1, z0, z1, spans(j, j1), zw0, zw1, {col: body, frame, trim: fac ? C.wall : C.sill || C.trim, r, glass: glass("r"), lintel: K.shade(body, .78)});
      // the string course between storeys; a factory storey gets its cyan strip in it (D62)
      W.box(i - .06, j - .06, z1, i1 + .06, j1 + .06, z1 + 2.4, fac ? C.facFrame : C.trim, fac ? {deco: {front: [[i, z1 + .8, i1, z1 + 1.6, "!#9be7ff"]], right: [[j, z1 + .8, j1, z1 + 1.6, "!#9be7ff"]]}} : {});
      const top = z1 + 2.4;
      sto.push({faces: [[P(i, j1, z0), P(i1, j1, z0), P(i1, j1, top), P(i, j1, top)], [P(i1, j1, z0), P(i1, j, z0), P(i1, j, top), P(i1, j1, top)]],
        windows: fs.map(([w0, w1]) => [P(w0, j1 - r, zw0), P(w1, j1 - r, zw0), P(w1, j1 - r, zw1), P(w0, j1 - r, zw1)]),
        // where the app mounts an alarm light: on the front face near its left end, away from the blade sign
        mount: P(i + .55, j1 + .05, z0 + (z1 - z0) * .62)});
      blades.push(blade(s, k, i1, j1 - .5, z0 + Math.min(22, H * .55), Math.min(9.5, H * .24), NIGHT));
    });
    const zr = z + LH + 2.4 + list.length * H;
    // corner pilasters standing proud the full height, a cornice and a parapet
    const spansZ = [[z + 4, z + LH], ...list.map((s, k) => { const z0 = z + LH + 2.4 + k * H; return [z0, z0 + H - 2.4]; })];
    for (const [za, zb] of spansZ) { W.box(i1 - .3, j1 - .3, za, i1 + .06, j1 + .06, zb, C.trim); W.box(i - .06, j1 - .3, za, i + .3, j1 + .06, zb, C.trim); W.box(i1 - .3, j - .06, za, i1 + .06, j + .3, zb, C.trim); }
    W.box(i - .22, j - .22, zr, i1 + .22, j1 + .22, zr + 3, C.trim, {deco: {front: [[i - .22, zr, i1 + .22, zr + .8, K.shade(C.trim, .8)]], right: [[j - .22, zr, j1 + .22, zr + .8, K.shade(C.trim, .8)]]}});
    const zt = zr + 3.4;
    W.box(i, j, zr + 3, i1, j1, zt, C.roof);
    for (const [a0, b0, a1, b1] of [[i - .1, j - .1, i1 + .1, j + .2], [i - .1, j - .1, i + .2, j1 + .1], [i - .1, j1 - .2, i1 + .1, j1 + .1], [i1 - .2, j - .1, i1 + .1, j1 + .1]]) W.box(a0, b0, zr + 3, a1, b1, zr + 7, C.trim);
    // roof gear: AC units, a water tank, an antenna mast (its lamp blinks in the app), a chimney where a factory works
    Bd.ac(W, i1 - 2.4, j + 1, zt); if (w > 7) Bd.tank(W, i1 - 1.8, j + 3.4, zt);
    W.box(i + .8, j + .8, zt, i + 1.6, j + 1.6, zt + 2, "#5d6178"); W.box(i + 1.15, j + 1.15, zt + 2, i + 1.25, j + 1.25, zt + 32, "#c9cfdc");
    for (const zc of [zt + 12, zt + 22]) W.box(i + .95, j + 1.15, zc, i + 1.45, j + 1.25, zc + .8, "#c9cfdc");
    const factory = list.some(s => s.kind === "factory");
    if (factory) W.box(i + 2.3, j + 1.2, zt, i + 3.1, j + 2, zt + 22, "#6f7486", {deco: {front: [[i + 2.3, zt + 15, i + 3.1, zt + 18, "#e0473a"]], right: [[j + 1.2, zt + 15, j + 2, zt + 18, "#e0473a"]], top: [[i + 2.4, j + 1.3, i + 3, j + 1.9, "#1a1620"]]}});
    // the lit billboard with the provider's name, its mark in a framed tile at the left (D55, D74)
    roofBoard(W, S, prov, i + .6, i1 - .6, j1, zt, empty);
    return {storeys: sto, blades, antenna: P(i + 1.2, j + 1.2, zt + 32.5), chimney: factory ? P(i + 2.7, j + 1.6, zt + 22) : null};
  }

  function roofBoard(W, S, prov, i0, i1, j, z, dark) {
    for (const a of [i0 + .4, i1 - .5]) W.box(a, j - .5, z, a + .12, j - .38, z + 14, "#2a2433");
    const col = S.board, mk = [], rows = MARKS[prov] || [], px = .09, u0 = i0 + .3, v0 = z + 19.6;
    // the mark: a cream tile with the 7×7 pixels
    mk.push([i0 + .2, z + 8, i0 + .2 + 7 * px + .2, v0 + .4, "#2a1a2e"], [i0 + .26, z + 8.6, i0 + .14 + 7 * px + .2, v0 - .2, dark ? "#8a8498" : "!#fff8ec"]);
    rows.forEach((row, ri) => [...row].forEach((ch, c) => { if (ch === "x") mk.push([u0 + c * px, v0 - 1.4 - (ri + 1) * 1.45, u0 + (c + 1) * px, v0 - 1.4 - ri * 1.45, S.mark]); }));
    const tx = (i0 + .2 + 7 * px + .2 + i1) / 2;
    W.box(i0, j - .38, z + 6, i1, j - .24, z + 22, col, {deco: {front: [[i0, z + 6, i1, z + 7.2, K.shade(col, .7)], [i0, z + 20.8, i1, z + 22, K.shade(col, .7)], ...mk]},
      text: [{f: "front", a: tx, z: z + 9.6, t: S.name, s: Math.min(9, 66 / S.name.length), c: dark ? "#8a8498" : "!#fff8ec", wt: 900, font: GAME, stroke: "#2a1a2e", sw: 1.4}]});
    // an empty tower's board is switched off: no bulbs, no glow
    if (dark) return;
    for (let a = i0 + .3; a < i1; a += .7) W.box(a, j - .24, z + 22, a + .12, j - .1, z + 23, "!#fff3c0");
    W.halo((i0 + i1) / 2, j, z + 14, 60, "#ffd98a", window.__NIGHT ? .35 : .2);
  }

  /* a blade sign sticking out of the right face of a storey: its own image in the app (it moves, fades and is clicked
     with its storey). Yellow with a pixel "!" while it waits for you; a factory's is ink with cyan; else the project's
     pastel. Its logo (D58) in a framed square when it has one. Returns the markup and where it hangs (art units). */
  function blade(s, k, i0, j, zc, hh, NIGHT) {
    const wait = !!s.wait, fac = s.kind === "factory";
    const bg = wait ? "#FFD83D" : fac ? "#2a2433" : s.kind === "chats" ? "#ffd0e0" : PASTEL[hash(s.name) % PASTEL.length];
    const ink = wait ? "#2a1a2e" : fac ? "#9be7ff" : "#2a1a2e";
    const txt = String(s.name).toUpperCase(), sz = 5.2, tw = K.measure(txt, sz, GAME, 900) + 10;
    const icon = wait || s.logo ? 12 : 0, bw = tw + icon, H = hh * 2;
    // painted on the plane of the front face: u along i (16 a tile), v down (1.08 a unit up)
    const at = P(i0, j, zc);
    // moonlit at night, unless it waits for you: that one is lit from inside
    const L = c => wait || !NIGHT ? c : K.lit(c, [0, 1, 0]);
    const x0 = 6.4, edge = K.shade(bg, .7);
    let g = `<g transform="translate(${f(at[0])} ${f(at[1])}) matrix(1 .5 0 1.08 0 0)">`;
    // the two brackets into the wall
    for (const y of [-hh + .6, hh - .6]) g += `<rect x="0" y="${f(y - .6)}" width="8" height="1.2" fill="${L("#2a2433")}"/>`;
    g += `<rect x="${x0}" y="${f(-hh)}" width="${f(bw)}" height="${f(H)}" fill="${L(bg)}" stroke="${L("#2a1a2e")}" stroke-width=".8"/>`;
    g += `<rect x="${x0}" y="${f(hh - 1)}" width="${f(bw)}" height="1" fill="${L(edge)}"/>`;
    if (wait) { // a pixel "!" in an ink square
      g += `<rect x="${x0 + 2.6}" y="${f(-5.4)}" width="8.6" height="10.8" fill="#2a1a2e"/><rect x="${x0 + 5.8}" y="-4.2" width="2.2" height="5.6" fill="#FFD83D"/><rect x="${x0 + 5.8}" y="2.4" width="2.2" height="1.8" fill="#FFD83D"/>`;
    } else if (s.logo) {
      g += `<rect x="${x0 + 2.4}" y="-4.8" width="9.6" height="9.6" fill="#ffffff" stroke="#2a1a2e" stroke-width=".8"/><image href="${s.logo}" x="${x0 + 3}" y="-4.2" width="8.4" height="8.4" preserveAspectRatio="xMidYMid meet"/>`;
    }
    g += `<text x="${f(x0 + icon + tw / 2)}" y="${f(sz * .36)}" text-anchor="middle" font-family="${GAME}" font-weight="900" font-size="${sz}" fill="${L(ink)}">${esc(txt)}</text></g>`;
    // where it hangs, as a box round its corners (the sheared board)
    const xs = [at[0], at[0] + x0 + bw], ys = [at[1] - hh * 1.08, at[1] + (x0 + bw) * .5 + hh * 1.08];
    return {markup: g, rect: [xs[0], ys[0], xs[1] - xs[0], ys[1] - ys[0]]};
  }

  /* the Server room's glass front, mullions, sill and transom: a sprite of its own over the room (D87), so someone at
     work inside, between the racks and the glass, is seen through it */
  function serverFront(W, o) {
    const {zs, si0, sj0, si1, sj1} = o, SH = 42, SD = "#3a3550";
    // the glass front with mullions in the gaps between racks, a sill band, a transom
    W.box(si0 + .3, sj1 - .06, zs + 1.2, si1 - .4, sj1, zs + SH - 2, "#bfe3ff", {opacity: .18});
    // (the racks stand .55 behind the glass: seen from here a mullion in the gap between two racks sits .55 further on)
    for (let k = 0; k <= 6; k++) { const a = k === 0 ? si0 + .32 : si0 + .85 + k * .9 - .1 + .55; if (a > si1 - .45) continue; W.box(a - .05, sj1 - .06, zs + 4, a + .05, sj1 + .12, zs + SH - 2, SD); }
    W.box(si0 - .08, sj1 - .06, zs, si1 + .08, sj1 + .14, zs + 4, "#4a4468", {deco: {front: [[si0, zs + 3.2, si1, zs + 4, "#5a5478"]]}}); W.box(si1 - .06, sj0 - .08, zs, si1 + .14, sj1 - .06, zs + 4, "#4a4468");
    W.box(si0 + .3, sj1 - .08, zs + 36, si1 - .4, sj1, zs + 37, SD);
  }

  /* ---------- the Server room (A5): a low pavilion; racks right behind the glass front, a lamp on a bracket ---------- */
  function serverRoom(W, o) {
    const {zs, si0, sj0, si1, sj1, rackGeo, racks} = o, SH = 42, SW = "#5a5478", SD = "#3a3550";
    W.box(si0, sj0, zs, si1, sj1, zs + 1.2, SD);
    W.box(si0, sj0, zs + 1.2, si1, sj0 + 2.4, zs + SH, SW, {shadow: 1.2});
    W.box(si1 - .4, sj0 + 2.4, zs + 1.2, si1, sj1, zs + SH, SW, {deco: {right: [[sj0 + 2.4, zs + 1.2, sj1, zs + 4, SD], ...[0, 1, 2, 3, 4, 5].map(k => [sj0 + 3.4 + k * .4, zs + 26, sj0 + 3.7 + k * .4, zs + 34, "#4a4468"]), [sj0 + .8, zs + 1.2, sj0 + 2, zs + 30, "#2a2640"], [sj0 + .86, zs + 1.2, sj0 + 1.94, zs + 29.4, "#4a4468"], [sj0 + 1.7, zs + 14, sj0 + 1.8, zs + 17, "#c9a46a"]]}});
    // the service door on the side, with its own lamp
    W.box(si1, sj0 + .6, zs, si1 + .5, sj0 + 2.2, zs + 1.2, "#c9c0b0"); W.box(si1, sj0 + .6, zs + 31, si1 + .6, sj0 + 2.2, zs + 32.4, SD); W.box(si1 + .02, sj0 + 1.3, zs + 33, si1 + .24, sj0 + 1.5, zs + 35, "!#ffe2a8"); W.halo(si1 + .3, sj0 + 1.4, zs + 34, 9, "#ffd9a0", .7);
    W.box(si0 + .02, sj0 + 2.4, zs + 1.2, si0 + .3, sj1, zs + SH, SW);
    // the racks: dark, a name low on each, the lights painted by the app; an empty slot is a dark bay
    rackGeo.forEach((g, k) => {
      const r = racks[k];
      const vents = []; for (let q = 0; q < 5; q++) vents.push([g.i0 + .06, g.z0 + 8.8 + q * 3.4, g.i1 - .2, g.z0 + 10.6 + q * 3.4, "#20203a"]);
      if (!r) { W.box(g.i0, g.j0, g.z0, g.i1, g.j1, g.z1, "#1c1a2c"); return; }
      const nm = String(r.name || "").slice(0, 10);
      W.box(g.i0, g.j0, g.z0, g.i1, g.j1, g.z1, "#2c2a40", {deco: {front: vents.concat([[g.i0 + .06, g.z0 + 25, g.i1 - .06, g.z0 + 26.6, "#1a1828"]])},
        text: nm ? [{f: "front", a: (g.i0 + g.i1) / 2, z: g.z0 + 3.6, t: nm, s: Math.min(1.6, 8.4 / (nm.length * .62)), c: "!#c9c4dc", wt: 600, font: MONO}] : []});
    });
    W.pool(si0 + 4, sj1 - 1, zs + 1.2, 70, "#8ab4ff", .22);
    W.group(R => {
      R.box(si0 - .1, sj0 - .1, zs + SH - 2, si1 + .1, sj1 + .1, zs + SH + 1.4, "#4a4468", {deco: {top: [[si0 + .3, sj0 + .3, si1 - .3, sj1 - .3, "#55507a"]], front: [[si0 - .1, zs + SH - 2, si1 + .1, zs + SH - 1.2, "#2e2a44"]]}});
      const zr = zs + SH + 1.4;
      for (const [a0, b0, a1, b1] of [[si0 - .1, sj0 - .1, si1 + .1, sj0 + .15], [si0 - .1, sj0 - .1, si0 + .15, sj1 + .1], [si0 - .1, sj1 - .15, si1 + .1, sj1 + .1], [si1 - .15, sj0 - .1, si1 + .1, sj1 + .1]]) R.box(a0, b0, zr, a1, b1, zr + 3, "#5a5478");
      Bd.ac(R, si0 + .6, sj0 + .5, zr); Bd.ac(R, si0 + 2, sj0 + .5, zr); Bd.ac(R, si0 + 3.4, sj0 + .5, zr);
      Bd.solar(R, si0 + .6, sj0 + 2.4, si0 + 3.6, sj1 - .7, zr); Bd.solar(R, si0 + 3.9, sj0 + 2.4, si1 - .6, sj1 - .7, zr);
      R.box(si1 - 1.6, sj0 + .6, zr, si1 - .6, sj0 + 1.6, zr + 10, "#8a8496", {deco: {front: [[si1 - 1.5, zr + 4, si1 - .7, zr + 8, "#5a5470"]], right: [[sj0 + .7, zr + 4, sj0 + 1.5, zr + 8, "#5a5470"]]}}); R.box(si1 - 1.7, sj0 + .5, zr + 10, si1 - .5, sj0 + 1.7, zr + 11, "#6a6478");
      R.box(si0 + 4.8, sj0 + .3, zr, si0 + 5.2, sj0 + 1.9, zr + 1.6, "#3a3550"); R.box(si0 + 5.2, sj0 + 1.5, zr, si1 - 1.7, sj0 + 1.9, zr + 1.6, "#3a3550");
    });
    Bd.door(W, "front", si0 + .65, sj1, zs, {w: 1.1, h: 31, col: SD, glass: "#cfe8ff", canopy: false, lamps: false});
    // a small SERVER ROOM plaque on the side wall: quiet, the name only
    { const tw = K.measure("SERVER ROOM", 3.6, GAME, 900) / 16 + .8; W.box(si1, sj0 + 4.4 - tw / 2, zs + 15, si1 + .14, sj0 + 4.4 + tw / 2, zs + 22, "#c9a0ff", {deco: {right: [[sj0 + 4.4 - tw / 2, zs + 15, sj0 + 4.4 + tw / 2, zs + 15.8, "#8a6ac0"]]}, text: [{f: "right", a: sj0 + 4.4, z: zs + 16.8, t: "SERVER ROOM", s: 3.6, c: "!#2a1a2e", wt: 900, font: GAME}]}); }
    // the lamp by the door on its bracket: its glass is dark here, the app lights it
    W.box(si0 + .45, sj1, zs + 38.2, si0 + .85, sj1 + .06, zs + 41.6, SD); W.box(si0 + .6, sj1 + .06, zs + 40, si0 + .7, sj1 + .46, zs + 40.8, SD); W.box(si0 + .48, sj1 + .26, zs + 39.2, si0 + .82, sj1 + .6, zs + 40, SD);
    W.box(si0 + .51, sj1 + .29, zs + 36.2, si0 + .79, sj1 + .57, zs + 39.2, {front: "#6a5a3a", right: "#5a4a30", top: SD}); W.box(si0 + .48, sj1 + .26, zs + 35.6, si0 + .82, sj1 + .6, zs + 36.2, SD);
    Pr.bird(W, si1 - .5, sj1 + .06, zs + SH + 1.4, {kind: "gull"});
  }

  /* ---------- the quest pillar (A3): a fountain with a stone column whose board counts what waits for you ---------- */
  function pillar(W, ci, cj, zp, n, quests, NIGHT) {
    for (const [a0, b0, a1, b1] of [[-3, -1.4, 3, 1.4], [-2.6, -2.4, 2.6, 2.4], [-1.4, -3, 1.4, 3]]) W.box(ci + a0, cj + b0, zp, ci + a1, cj + b1, zp + 4, "#c9bfae", {deco: {top: [[ci + a0 + .24, cj + b0 + .24, ci + a1 - .24, cj + b1 - .24, "#4a8ad0"], [ci + a0 + .6, cj + b0 + .5, ci + a0 + 1, cj + b0 + .56, "!#cfeeff"]]}});
    W.box(ci - 1.2, cj - 1.2, zp + 4, ci + 1.2, cj + 1.2, zp + 10, "#c9bfae");
    const yel = NIGHT || n > 0 ? "!#FFD83D" : "#FFD83D", big = String(n), lines = quests.map(q => q.toUpperCase());
    const side = [];
    if (n === 0) side.push({t: "ALL", c: "!#fff8ec", z: 30}, {t: "QUIET", c: "!#9a94b0", z: 24});
    // the first quests when their words are short enough to stand there whole; else a pointer to the quest log
    else if (!lines.length) side.push({t: "SEE THE", c: "!#9a94b0", z: 30}, {t: "QUEST LOG", c: "!#fff8ec", z: 24});
    else { lines.forEach((q, k) => side.push({t: q, c: k === 0 ? yel : "!#fff8ec", z: 32.4 - k * 5.8})); if (n > lines.length) side.push({t: `+${n - lines.length} MORE`, c: "!#9a94b0", z: 32.4 - lines.length * 5.8 - 1.2}); }
    W.box(ci - .9, cj - .9, zp + 10, ci + .9, cj + .9, zp + 40, "#d8cfc0", {deco: {front: [[ci - .74, zp + 15, ci + .74, zp + 38, "#2a1a2e"], [ci - .68, zp + 15.5, ci + .68, zp + 37.5, "#3a2a50"]], right: [[cj - .74, zp + 15, cj + .74, zp + 38, "#2a1a2e"], [cj - .68, zp + 15.5, cj + .68, zp + 37.5, "#3a2a50"]]},
      text: [{f: "front", a: ci, z: zp + 22.5, t: big, s: big.length > 1 ? 11 : 14, c: n > 0 ? yel : "!#fff8ec", wt: 900, font: GAME}, {f: "front", a: ci, z: zp + 17.6, t: n === 1 ? "QUEST" : "QUESTS", s: 2.8, c: "!#fff8ec", wt: 900, font: GAME},
        ...side.filter(q => q.t.length <= 12).map(q => ({f: "right", a: cj, z: zp + q.z, t: q.t, s: 2.5, c: q.c, wt: 900, font: GAME}))]});
    W.box(ci - 1, cj - 1, zp + 40, ci + 1, cj + 1, zp + 42, "#c9bfae");
    // the quest marker over it: a voxel "!" while something waits (the app turns its glow)
    if (n > 0) {
      const col = yel, dark = "#b08a00", z = zp + 46, i = ci, j = cj;
      W.box(i - .3, j - .3, z + 10, i + .3, j + .3, z + 34, col, {deco: {front: [[i - .3, z + 10, i + .3, z + 11.6, dark]], right: [[j - .3, z + 10, j + .3, z + 11.6, dark]], top: [[i - .3, j - .3, i + .3, j + .3, "!" + K.tint("#FFD83D", .4)]]}});
      W.box(i - .3, j - .3, z, i + .3, j + .3, z + 6.4, col, {deco: {front: [[i - .3, z, i + .3, z + 1.4, dark]], right: [[j - .3, z, j + .3, z + 1.4, dark]], top: [[i - .3, j - .3, i + .3, j + .3, "!" + K.tint("#FFD83D", .4)]]}});
      W.halo(i, j, z + 18, 46, "#FFD83D", .4);
    }
    // water jets round the column
    for (const [di, dj] of [[0, 1], [1, 0], [0, -1], [-1, 0]]) for (let k = 0; k < 16; k++) { const t = (k + 1) / 16, ri = ci + di * (1.2 + t * 1.3), rj = cj + dj * (1.2 + t * 1.3), zz = zp + 8 + Math.sin(t * Math.PI * .85) * 6 - t * t * 8; W.box(ri - .07, rj - .07, zz - .8, ri + .07, rj + .07, zz + .8, "#d6efff", {opacity: .9, noStroke: true}); }
    W.pool(ci, cj, zp, 130, "#FFD83D", n > 0 ? .22 : .08);
  }

  /* string lights over the plaza on four posts */
  function stringLights(W, obj, posts, zp, NIGHT) {
    for (const [a, b] of posts) obj(w => { w.box(a - .07, b - .07, zp, a + .07, b + .07, zp + 46, "#2a2433"); w.box(a - .14, b - .14, zp + 46, a + .14, b + .14, zp + 47.4, "#2a2433"); });
    const bulbs = ["#ffd04a", "#ff6a8a", "#7cdcff", "#9cff8a", "#ffb070"];
    for (let e = 0; e < 4; e++) {
      const [a0, b0] = posts[e], [a1, b1] = posts[(e + 1) % 4], n = 18;
      obj(w => {
        for (let k = 0; k < n; k++) {
          const t0 = k / n, t1 = (k + 1) / n, za = zp + 45 - Math.sin(t0 * Math.PI) * 4, zb = zp + 45 - Math.sin(t1 * Math.PI) * 4;
          const pa = P(a0 + (a1 - a0) * t0, b0 + (b1 - b0) * t0, za), pb = P(a0 + (a1 - a0) * t1, b0 + (b1 - b0) * t1, zb);
          w.raw([["l", pa[0], pa[1], pb[0], pb[1], "#2a2433", .5, null, null]], Math.min(a0 + (a1 - a0) * t0, a0 + (a1 - a0) * t1) - .02, Math.min(b0 + (b1 - b0) * t0, b0 + (b1 - b0) * t1) - .02, Math.min(za, zb) - .1, Math.max(a0 + (a1 - a0) * t0, a0 + (a1 - a0) * t1) + .02, Math.max(b0 + (b1 - b0) * t0, b0 + (b1 - b0) * t1) + .02, Math.max(za, zb));
        }
        for (let k = 1; k < n; k++) { const t = k / n, a = a0 + (a1 - a0) * t, b = b0 + (b1 - b0) * t, z = zp + 45 - Math.sin(t * Math.PI) * 4; w.box(a - .05, b - .05, z - 1.2, a + .05, b + .05, z, NIGHT || true ? "!" + bulbs[k % 5] : bulbs[k % 5]); if (k % 3 === 0) w.halo(a, b, z - .6, NIGHT ? 9 : 6, bulbs[k % 5], NIGHT ? .8 : .5); }
      });
    }
  }

  function gazebo(W, gi, gj, z) {
    W.box(gi - 1.6, gj - 1.6, z, gi + 1.6, gj + 1.6, z + 1.4, "#c9bfae", {deco: {top: [[gi - 1.4, gj - 1.4, gi + 1.4, gj + 1.4, "#b9845a"]]}});
    for (const [a, b] of [[-1.3, -1.3], [1.2, -1.3], [-1.3, 1.2], [1.2, 1.2]]) W.box(gi + a, gj + b, z + 1.4, gi + a + .14, gj + b + .14, z + 30, "#f2efe6");
    for (let q = 0; q < 6; q++) { const t = (q + .5) / 6; W.box(gi - 1.3 + t * 2.6 - .05, gj + 1.22, z + 1.4, gi - 1.3 + t * 2.6 + .05, gj + 1.32, z + 8, "#f2efe6"); W.box(gi + 1.22, gj - 1.3 + t * 2.6 - .05, z + 1.4, gi + 1.32, gj - 1.3 + t * 2.6 + .05, z + 8, "#f2efe6"); }
    W.box(gi - 1.3, gj + 1.2, z + 8, gi + 1.34, gj + 1.34, z + 9, "#f2efe6"); W.box(gi + 1.2, gj - 1.3, z + 8, gi + 1.34, gj + 1.34, z + 9, "#f2efe6");
    [[1.9, 3], [1.5, 3], [1.1, 3], [.6, 3], [.18, 3]].reduce((zz, [r, hh], k) => { W.box(gi - r, gj - r, zz, gi + r, gj + r, zz + hh, k % 2 ? "#3f7a8a" : "#4a8a9a", {deco: {front: [[gi - r, zz, gi + r, zz + .8, "#2f5a6a"]], right: [[gj - r, zz, gj + r, zz + .8, "#2f5a6a"]]}}); return zz + hh; }, z + 30);
  }

  function bridge(W, a0, a1, j0) {
    const n = 14;
    for (let k = 0; k < n; k++) {
      const t = (k + .5) / n, zb = 1 + Math.sin(t * Math.PI) * 6, x0 = a0 + (a1 - a0) * k / n, x1 = a0 + (a1 - a0) * (k + 1) / n;
      W.box(x0, j0, zb - 1.4, x1, j0 + 1, zb, "#b9845a", {deco: {top: [[x0, j0, x0 + .04, j0 + 1, "#8a5a3a"]]}});
      if (k % 3 === 1 || k === n - 1) for (const b of [j0, j0 + .9]) W.box(x0, b, zb, x0 + .1, b + .1, zb + 8, "#8a5a3a");
      for (const b of [j0, j0 + .9]) W.box(x0, b, zb + 7, x1, b + .1, zb + 8.2, "#8a5a3a");
    }
    for (const a of [17.6, 20.4]) W.box(a, j0 + .1, -5, a + .2, j0 + .9, 1 + Math.sin((a - a0) / (a1 - a0) * Math.PI) * 6 - 1.4, "#7a5a3a");
  }

  /* a hot-air balloon drifting beside the island, a passenger waving; its burner glows at night */
  function balloon(bi, bj, bz, NIGHT, W) {
    const bal = new K.World(), cols = ["#e0473a", "#FFD83D", "#e0473a", "#FFD83D"];
    [[.5, 6], [.9, 7], [1.4, 8], [1.8, 9], [2.1, 10], [2.2, 12], [2.1, 10], [1.8, 8], [1.3, 6], [.6, 4]].reduce((z, [r, hh], k) => { bal.box(bi - r, bj - r, z, bi + r, bj + r, z + hh, cols[k % 4], {deco: {front: [[bi - .15, z, bi + .15, z + hh, "#fff8ec"]], right: [[bj - .15, z, bj + .15, z + hh, "#fff8ec"]]}}); return z + hh; }, bz);
    for (const [a, b] of [[-.75, -.75], [.75, -.75], [-.75, .75], [.75, .75]]) bal.box(bi + a - .03, bj + b - .03, bz - 44, bi + a + .03, bj + b + .03, bz + 3, "#3a3550");
    bal.box(bi - .25, bj - .25, bz - 44, bi + .25, bj + .25, bz - 38, NIGHT ? "!#ff9a3a" : "#ff9a3a"); if (NIGHT) W.halo(bi, bj, bz - 40, 18, "#ff9a3a", .6);
    bal.box(bi - .8, bj - .8, bz - 56, bi + .8, bj + .8, bz - 44, "#a8743a", {deco: {front: [[bi - .8, bz - 46, bi + .8, bz - 44.6, "#7a5428"], [bi - .8, bz - 52, bi + .8, bz - 51, "#7a5428"]], right: [[bj - .8, bz - 46, bj + .8, bz - 44.6, "#7a5428"]]}});
    bal.fig(B.person("marketing", 2), {pose: "wave", view: "SW", mood: "happy", zb: bz - 44}, bi, bj, bz - 55);
    const ops = []; for (const it of K.sortItems(bal.items)) for (const q of it.ops) ops.push(q);
    return ops;
  }

  window.BlockyWorld = Object.assign(window.BlockyWorld || {}, {campus, CAMPUS: {NI, NJ, LANES, ROAD_I, ROAD_J}});
})();
