/* The blocky cast: people built from boxes on a small 3D rig, projected in the world's own 2:1 isometric view.
   Every face is shaded by one light, faces are painted on as flat decals, and every pose is joint rotation, so the
   four views (front-left, front-right, back-left, back-right) come for free. A plain script (no imports):
     BlockyCast.figure(name, {pose, mood, view, frame}) → SVG markup round the feet at (0, 0)
   view: SE (front-right) | SW (front-left) | NE (back-right) | NW (back-left)
   pose: idle | walkA | walkB | sit | type | typeB | read | point | snooze | wave | ask | stuck | mug | cheer
   mood: calm | happy | focus | wait | stuck | tired */
(function () {
  const f = v => (+v).toFixed(2);
  const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
  const toHex = c => "#" + c.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")).join("");
  const LIGHT = (() => { const v = [-.35, .55, 1], n = Math.hypot(...v); return v.map(x => x / n); })();
  const VIEWDIR = [1, 1, 1].map(x => x / Math.sqrt(3));
  // flat shading with a warm light and cool shadows
  function lit(base, n) {
    if (window.__NIGHT) { // moonlight from the same side (D80, A8): dark, cool, with the faces still told apart
      const d = Math.max(0, n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]), k = .21 + .22 * d;
      const c = hex(base), moon = [26, 32, 66];
      return toHex(c.map((v, i) => v * k + moon[i] * (.55 + .25 * d)));
    }
    const d = Math.max(0, n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]), k = .58 + .5 * d;
    const c = hex(base), warm = [255, 244, 225], cool = [70, 60, 120];
    return toHex(c.map((v, i) => k >= 1 ? v + (warm[i] - v) * (k - 1) * .9 : v * k + cool[i] * (1 - k) * .28));
  }

  /* ---------- tiny 3D maths ---------- */
  const rx = a => { const c = Math.cos(a), s = Math.sin(a); return [[1, 0, 0], [0, c, -s], [0, s, c]]; };
  const ry = a => { const c = Math.cos(a), s = Math.sin(a); return [[c, 0, s], [0, 1, 0], [-s, 0, c]]; };
  const rz = a => { const c = Math.cos(a), s = Math.sin(a); return [[c, -s, 0], [s, c, 0], [0, 0, 1]]; };
  const mm = (A, B) => A.map((r, i) => [0, 1, 2].map(j => r[0] * B[0][j] + r[1] * B[1][j] + r[2] * B[2][j]));
  const mv = (A, v) => [0, 1, 2].map(i => A[i][0] * v[0] + A[i][1] * v[1] + A[i][2] * v[2]);
  const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const D = Math.PI / 180;
  // a frame: rotation R and origin o; child frames compose
  const frame = (R, o) => ({R, o});
  const child = (F, R, o) => ({R: mm(F.R, R), o: add(F.o, mv(F.R, o))});
  const toWorld = (F, p) => add(F.o, mv(F.R, p));
  const projWith = S => p => [(p[0] - p[1]) * S, (p[0] + p[1]) * .5 * S - p[2] * S * 1.08];

  /* ---------- the scene being built: faces with depth, decals glued to faces ---------- */
  /* a scene at S screen px per model unit (the cast sheet uses 4.2; a whole floor much less) */
  function Scene(S = 4.2) { this.S = S; this.proj = projWith(S); this.faces = []; }
  /* a box from min to max in frame F. col: one colour or {top, front, back, left, right, bottom}. deco: decals per face */
  Scene.prototype.box = function (F, min, max, col, deco = {}, opt = {}) {
    const [x0, y0, z0] = min, [x1, y1, z1] = max, proj = this.proj;
    const FACES = {
      top: {n: [0, 0, 1], p: [[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]], uv: (p) => [p[0], p[1]]},
      bottom: {n: [0, 0, -1], p: [[x0, y1, z0], [x1, y1, z0], [x1, y0, z0], [x0, y0, z0]], uv: (p) => [p[0], p[1]]},
      front: {n: [0, 1, 0], p: [[x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1]], uv: (p) => [p[0], p[2]]},
      back: {n: [0, -1, 0], p: [[x1, y0, z0], [x0, y0, z0], [x0, y0, z1], [x1, y0, z1]], uv: (p) => [-p[0], p[2]]},
      right: {n: [1, 0, 0], p: [[x1, y1, z0], [x1, y0, z0], [x1, y0, z1], [x1, y1, z1]], uv: (p) => [-p[1], p[2]]},
      left: {n: [-1, 0, 0], p: [[x0, y0, z0], [x0, y1, z0], [x0, y1, z1], [x0, y0, z1]], uv: (p) => [p[1], p[2]]}
    };
    for (const [name, fc] of Object.entries(FACES)) {
      const n = mv(F.R, fc.n);
      if (n[0] + n[1] + n[2] <= 1e-6) continue;                               // facing away from us
      const w = fc.p.map(p => toWorld(F, p)), c = typeof col === "string" ? col : (col[name] || col.side || col.base);
      const depth = w.reduce((s, p) => s + p[0] + p[1] + p[2], 0) / 4;
      const face = {depth, n, pts: w.map(proj), fill: lit(c, n), decals: [], opacity: opt.opacity};
      // decals: [u0, v0, u1, v1, colour] in the face's own plane (x/z for front, x/y for top, …), in local units
      for (const d of deco[name] || []) {
        const isPoly = d[2] === "poly", dcol = isPoly ? d[1] : d[4], shape = isPoly ? "poly" : null;
        const pt = (u, v) => {
          if (name === "front") return toWorld(F, [u, y1 + .02, v]);
          if (name === "back") return toWorld(F, [-u, y0 - .02, v]);
          if (name === "top") return toWorld(F, [u, v, z1 + .02]);
          if (name === "right") return toWorld(F, [x1 + .02, -u, v]);
          if (name === "left") return toWorld(F, [x0 - .02, u, v]);
          return toWorld(F, [u, y1, v]);
        };
        if (shape === "poly") face.decals.push({pts: d[0].map(([u, v]) => proj(pt(u, v))), fill: lit(dcol, n)});
        else face.decals.push({pts: [pt(d[0], d[1]), pt(d[2], d[1]), pt(d[2], d[3]), pt(d[0], d[3])].map(proj), fill: window.__NIGHT ? lit(dcol[0] === "!" ? dcol.slice(1) : dcol, n) : dcol === "#ffffff" || dcol[0] === "!" ? (dcol[0] === "!" ? dcol.slice(1) : dcol) : lit(dcol, n)});
      }
      this.faces.push(face);
    }
  };
  Scene.prototype.svg = function () {
    this.faces.sort((a, b) => a.depth - b.depth);
    const P = pts => pts.map(p => f(p[0]) + "," + f(p[1])).join(" ");
    const sw = f(this.S * .14);
    return this.faces.map(fc => `<polygon points="${P(fc.pts)}" fill="${fc.fill}"${fc.opacity != null ? ` opacity="${fc.opacity}"` : ` stroke="${fc.fill}" stroke-width="${sw}" stroke-linejoin="round"`}/>` + fc.decals.map(d => `<polygon points="${P(d.pts)}" fill="${d.fill}"/>`).join("")).join("");
  };

  /* ---------- the team ---------- */
  const CAST = {
    Rue:  {role: "dev", skin: "#f2b48a", hair: "#d9502a", hairStyle: "pony", top: "#3fae6a", outfit: "hoodie", legs: "#3b5a9a", shoes: "#f4f1ea", brows: "#a63c1d", tall: 1.08, prop: "laptop"},
    Teo:  {role: "dev", skin: "#a86a44", hair: "#2b1d24", hairStyle: "afro", top: "#4a74d8", outfit: "flannel", legs: "#b89a6a", shoes: "#6a4026", brows: "#1a1116", extra: "headset", beard: "#2b1d24", wide: 1.15, prop: "laptop"},
    Uma:  {role: "designer", skin: "#f6c9a0", hair: "#f2c23a", hairStyle: "bun", top: "#2a2433", outfit: "turtleneck", legs: "#3a3256", shoes: "#8a5cf0", brows: "#c69a30", extra: "glasses", glasses: "#ff6ad5", tall: .92, prop: "tablet"},
    Pax:  {role: "devops", skin: "#e0a07a", hair: "#d9d4cf", hairStyle: "bald", top: "#7a5ce0", outfit: "overalls", under: "#9aa3b4", legs: "#7a5ce0", shoes: "#3a3340", brows: "#9a948f", extra: "goggles", moustache: "#d9d4cf", wide: 1.08, prop: "wrench"},
    Ines: {role: "pm", skin: "#7a4a32", hair: "#4a2560", hairStyle: "braids", top: "#2fb0a8", outfit: "cardigan", under: "#f4f1ea", legs: "#d9a43a", shoes: "#2a1a2e", brows: "#2e1640", extra: "lanyard", hoops: true, tall: 1.06, prop: "clipboard"}
  };
  /* roles: what they wear and carry, so you can tell them apart at a glance */
  const ROLES = {
    // the CEO (D73): a dark suit and tie, long hair swept back and a short beard; nobody else dresses so
    // D73 keeps a dark suit; Spel+ makes it read as a person: charcoal with lit and shadow faces, a white shirt, a
    // violet tie, and brown hair and beard that stand apart from the suit
    ceo:        {label: "CEO", outfits: ["suit"], tops: ["#3c3c4a"], legs: ["#33333f"], hair: ["long"], hairColor: "#5a3a2a", beard: true, shirt: "#e8e6ee", tie: "#7a5ce0", shoes: "#1a1a20", props: ["mug"], extras: [null, "watch"]},
    // a plain project's main chat: smart casual, a navy jacket over a light shirt, a lanyard and a mug; not the CEO's black
    lead:       {label: "Lead", outfits: ["blazer"], tops: ["#33507e", "#3d6a6a"], legs: ["#2a2433", "#5a6a8a"], hair: ["short", "curly", "bob", "slick"], props: ["mug"], extras: ["lanyard"]},
    sales:      {label: "Sales", outfits: ["blazer"], tops: ["#5a7ab0", "#8a5a7a", "#4a8a8a"], legs: ["#b89a6a", "#3a3f63"], hair: ["slick", "long", "short"], props: ["phone"], extras: [null]},
    marketing:  {label: "Marketing", outfits: ["tee"], tops: ["#ff7a5a", "#ff6ad5", "#3fd0a0"], legs: ["#3b5a9a", "#2a2433"], hair: ["long", "spiky", "short"], hats: ["beanie", "cap", null], props: ["megaphone"], extras: [null]},
    pm:         {label: "Product", outfits: ["cardigan"], tops: ["#2fb0a8", "#e0a04a", "#8a5cf0"], legs: ["#3a3f63", "#d9a43a"], hair: ["bun", "short", "long"], props: ["clipboard"], extras: ["lanyard"]},
    dev:        {label: "Developer", outfits: ["hoodie", "flannel", "tee"], tops: ["#3fae6a", "#4a74d8", "#2a2433", "#b04a5e", "#5a6a8a"], legs: ["#3b5a9a", "#2a2433", "#b89a6a"], hair: ["short", "spiky", "long", "curly", "buzz", "pony"], hats: [null, null, "cap", "beanie"], props: ["laptop"], extras: ["headphones", null, "glasses"]},
    designer:   {label: "Designer", outfits: ["turtleneck", "tee"], tops: ["#2a2433", "#f2efe6", "#ff9a5a"], legs: ["#2a2433", "#f2efe6", "#5a3a6a"], hair: ["bob", "long", "short", "bun"], hats: ["beret", null, null], props: ["tablet"], extras: ["glasses", null]},
    tester:     {label: "Tester", outfits: ["labcoat"], tops: ["#f4f4f0"], under: ["#3fae6a", "#5b8cf0", "#e05a86"], legs: ["#3a3f63", "#5a6a8a"], hair: ["short", "long", "curly", "buzz"], props: ["clipboard"], extras: ["goggles", "glasses", null]},
    devops:     {label: "DevOps", outfits: ["overalls"], tops: ["#7a5ce0", "#3a6ab0"], under: ["#9aa3b4", "#d9d4cf"], legs: ["#7a5ce0", "#3a6ab0"], hair: ["buzz", "short", "bald"], hats: ["hardhat", null], props: ["wrench"], extras: [null, "goggles"]},
    researcher: {label: "Research", outfits: ["cardigan"], tops: ["#6a8a4a", "#8a6a4a"], under: ["#f4f1ea"], legs: ["#5a4a3a", "#3a3f63"], hair: ["curly", "long", "short"], props: ["book"], extras: ["glasses"]}
  };
  const SKINS = ["#f6c9a0", "#f2b48a", "#e0a07a", "#c98a5e", "#a86a44", "#7a4a32", "#5a3424"];
  const HAIRS = ["#2b1d24", "#4a2e20", "#7a4a2e", "#d9502a", "#f2c23a", "#d9d4cf", "#4a2560", "#2e4a8a"];
  const rnd = seed => { let x = 2166136261; for (const c of String(seed)) x = Math.imul(x ^ c.charCodeAt(0), 16777619); return () => ((x = Math.imul(x ^ (x >>> 15), 2246822507) ^ Math.imul(x ^ (x >>> 13), 3266489909)) >>> 0) / 4294967296; };
  /* a person for a role: the role decides the outfit and the prop; the seed decides the rest */
  function person(role, seed) {
    const R = ROLES[role], r = rnd(role + ":" + seed), pick = a => a[Math.floor(r() * a.length)];
    const hair = R.hairColor || pick(HAIRS), skin = pick(SKINS), outfit = pick(R.outfits);
    const shoes = pick(["#2a1a2e", "#f4f1ea", "#6a4026", "#8a5cf0"]), beardRoll = r() < .25;
    return {role, skin, hair, hairStyle: pick(R.hair), top: pick(R.tops), outfit, under: R.under ? pick(R.under) : "#f4f1ea", legs: pick(R.legs), shoes: R.shoes || shoes,
      brows: shade(hair, .7), hat: R.hats ? pick(R.hats) : null, prop: pick(R.props), extra: pick(R.extras), glasses: pick(["#2a1a2e", "#8a5cf0", "#e05a5a", "#3f6fd8"]),
      beard: R.beard || beardRoll ? hair : null, shirt: R.shirt, tie: R.tie, tall: .92 + r() * .18, wide: .94 + r() * .2};
  }
  const VIEWS = {SW: 0, SE: -90, NW: 90, NE: 180};

  /* poses: angles in degrees. arm: [pitch forward, raise sideways, elbow bend]; leg: pitch forward */
  const POSES = {
    idle:  {armL: [0, 6, 0], armR: [0, 6, 0], legL: 0, legR: 0},
    walkA: {armL: [28, 4, 10], armR: [-28, 4, 10], legL: -26, legR: 26, bob: .4},
    walkB: {armL: [-28, 4, 10], armR: [28, 4, 10], legL: 26, legR: -26, bob: .4},
    sit:   {armL: [20, 6, 30], armR: [20, 6, 30], legL: 90, legR: 90, sit: true},
    type:  {armL: [52, 8, 60], armR: [52, 8, 60], legL: 90, legR: 90, sit: true, head: -8},
    typeB: {armL: [44, 8, 72], armR: [60, 8, 48], legL: 90, legR: 90, sit: true, head: -6},
    read:  {armL: [46, 12, 84], armR: [46, 12, 84], legL: 0, legR: 0, head: -14},
    point: {armL: [0, 6, 0], armR: [78, 14, 4], legL: 0, legR: 0, head: 6},
    snooze: {armL: [16, 6, 26], armR: [16, 6, 26], legL: 90, legR: 90, sit: true, head: -24},
    wave:  {armL: [0, 6, 0], armR: [0, 150, -40], legL: 0, legR: 0, head: 6},
    ask:   {armL: [10, 28, 70], armR: [-10, 146, -26], legL: 0, legR: 0, head: 8},
    stuck: {armL: [0, 140, 95], armR: [0, 140, 95], legL: 0, legR: 0, head: -10},
    mug:   {armL: [0, 6, 0], armR: [40, 10, 90], legL: 0, legR: 0},
    cheer: {armL: [0, 160, 10], armR: [0, 160, 10], legL: 0, legR: 0, head: 10, hop: 1.2}
  };

  /* a person added to scene sc with their feet at world point `at`; returns their ground shadow as SVG */
  function figureInto(sc, name, o = {}, at = [0, 0, 0]) {
    const proj = sc.proj;
    const C = typeof name === "string" ? CAST[name] : name, pose = POSES[o.pose || "idle"] || POSES.idle, mood = o.mood || "calm";
    const T = C.tall || 1, Wd = C.wide || 1;
    const root = frame(rz((VIEWS[o.view || "SW"] || 0) * D), [at[0], at[1], at[2] + (pose.bob || 0) + (pose.hop || 0) + (o.seat || 0)]);
    const legH = 6.6 * T, hipZ = pose.sit ? 4.2 : legH + 1.6, torsoH = 8.2 * T, torsoW = 9 * Wd, torsoD = 5.4 * Wd;
    const body = child(root, rx(0), [0, 0, hipZ]);
    const shoes = {base: C.shoes};

    /* legs: a block each with a shoe; sitting puts them straight out in front */
    for (const side of [-1, 1]) {
      const pitch = (side < 0 ? pose.legL : pose.legR) * D;
      const hip = child(body, rx(pitch), [side * 2.25 * Wd, 0, 0]);
      sc.box(hip, [-1.9 * Wd, -1.9, -legH], [1.9 * Wd, 1.9, 0], C.legs);
      sc.box(hip, [-2 * Wd, -2.1, -legH - 1.8], [2 * Wd, 2.9, -legH], shoes, {front: [[-2 * Wd, -legH - 1.8, 2 * Wd, -legH - 1.2, "!#e8e2d4"]]});
    }
    /* the torso, with the outfit painted on */
    const tdeco = {front: [], back: [], left: [], right: [], top: []};
    const F = tdeco.front, x0 = -torsoW / 2, x1 = torsoW / 2;
    if (C.outfit === "hoodie") {
      F.push([-3.2, 1.0, 3.2, 3.6, shade(C.top, .82)], [-1.6, 5.4, -1.1, torsoH - .4, "#f4f1ea"], [1.1, 5.4, 1.6, torsoH - .4, "#f4f1ea"]);
      tdeco.back.push([-3.6, torsoH - 2.6, 3.6, torsoH + .2, shade(C.top, .82)]);
    }
    if (C.outfit === "flannel") {
      for (let u = x0 + .6; u < x1; u += 2.1) F.push([u, 0, u + .5, torsoH, shade(C.top, .72)]);
      for (let v = .9; v < torsoH; v += 2.1) F.push([x0, v, x1, v + .45, tint(C.top, .3)]);
      F.push([-.2, 0, .2, torsoH, "#2a1a2e"]);
      for (const sd of ["left", "right", "back"]) for (let v = .9; v < torsoH; v += 2.1) { const half = sd === "back" ? torsoW / 2 : torsoD / 2; tdeco[sd].push([-half, v, half, v + .45, tint(C.top, .3)]); }
    }
    if (C.outfit === "turtleneck") for (let v = 1.2; v < torsoH - .6; v += 1.6) F.push([x0, v, x1, v + .35, shade(C.top, .86)]);
    if (C.outfit === "overalls") {
      F.push([x0, torsoH - .01, x1, torsoH, C.under]);
      F.push([x0 + .01, 3.4, x0 + 2.2, torsoH, "!" + C.under], [x1 - 2.2, 3.4, x1 - .01, torsoH, "!" + C.under]);
      F.push([-3, 3.6, 3, 7, shade(C.top, .88)], [-2.4, 6.2, -1.6, 7, "#f2c94c"], [1.6, 6.2, 2.4, 7, "#f2c94c"]);
      F.push([x0, .2, x1, 1.3, "#7a4a2e"], [-.6, .2, .6, 1.3, "#c9a46a"]);
      for (const sd of ["left", "right"]) tdeco[sd].push([-torsoD / 2, .2, torsoD / 2, 1.3, "#7a4a2e"]);
      tdeco.back.push([-torsoW / 2, .2, torsoW / 2, 1.3, "#7a4a2e"]);
    }
    if (C.outfit === "suit" || C.outfit === "blazer") {
      const shirt = C.shirt || (C.outfit === "suit" ? "#f4f4f0" : "#cfe0ff");
      F.push([[[-2.6, torsoH], [2.6, torsoH], [0, torsoH - 4.6]], "!" + shirt, "poly"]);
      F.push([[[-2.6, torsoH], [-3.6, torsoH - .4], [-.6, torsoH - 5.6], [0, torsoH - 4.6]], shade(C.top, .8), "poly"], [[[2.6, torsoH], [3.6, torsoH - .4], [.6, torsoH - 5.6], [0, torsoH - 4.6]], shade(C.top, .8), "poly"]);
      if (C.outfit === "suit") F.push([[[-.5, torsoH - .6], [.5, torsoH - .6], [.8, torsoH - 5.2], [0, torsoH - 6], [-.8, torsoH - 5.2]], "!" + (C.tie || "#d9453a"), "poly"]);
      F.push([-.25, .6, .25, torsoH - 5.6, shade(C.top, .7)], [.6, 1.6, 1.2, 2.2, "#c9a46a"], [.6, 3.4, 1.2, 4, "#c9a46a"]);
      if (C.outfit === "blazer") F.push([2.2, 3.2, 3.6, 3.6, "!#f4f4f0"]);
    }
    if (C.outfit === "tee") F.push([-2.4, 2.6, 2.4, 6, tint(C.top, .55)], [-1.4, 3.4, 1.4, 5.2, shade(C.top, .6)], [-.6, 3.9, .6, 4.7, tint(C.top, .55)]);
    if (C.outfit === "labcoat") F.push([-1.2, 0, 1.2, torsoH, "!" + (C.under || "#3fae6a")], [[[-1.2, torsoH], [1.2, torsoH], [0, torsoH - 2.6]], "!#f4f4f0", "poly"], [2.2, 4.6, 3.8, 6.4, "#dcdcd6"], [2.5, 6.2, 2.8, 7.4, "!#3f6fd8"], [3.1, 6.2, 3.4, 7.2, "!#e05a5a"]);
    if (C.extra === "lanyard") F.push([[[-2.6, torsoH], [-2, torsoH], [-.2, torsoH - 4.6], [-.8, torsoH - 4.6]], "#e05a86", "poly"], [[[2.6, torsoH], [2, torsoH], [.2, torsoH - 4.6], [.8, torsoH - 4.6]], "#e05a86", "poly"], [-1.2, torsoH - 6.8, 1.2, torsoH - 4.4, "!#f4f4f0"], [-.9, torsoH - 5.6, .9, torsoH - 5.2, "!#3f6fd8"]);
    if (C.outfit === "cardigan") F.push([-1.5, 0, 1.5, torsoH, "!" + C.under], [-2.3, 2, -1.7, 2.6, "#f2c94c"], [-2.3, 4.2, -1.7, 4.8, "#f2c94c"], [-2.3, 6.4, -1.7, 7, "#f2c94c"]);
    sc.box(body, [x0, -torsoD / 2, 0], [x1, torsoD / 2, torsoH], C.top, tdeco);
    if (C.outfit === "overalls") sc.box(body, [x0 + .1, -torsoD / 2 + .1, -.2], [x1 - .1, torsoD / 2 - .1, 1.6], C.top);   // the seat of the overalls under the belt
    if (C.outfit === "labcoat" && !pose.sit) sc.box(body, [x0 - .15, -torsoD / 2 - .15, -3.6], [x1 + .15, torsoD / 2 + .15, .2], C.top, {front: [[-.15, -3.6, .15, .2, "#cfcfc8"]]});
    if (C.outfit === "suit" || C.outfit === "blazer") sc.box(body, [-2.6, -1.8, torsoH], [2.6, 1.8, torsoH + .9], C.shirt || (C.outfit === "suit" ? "#f4f4f0" : "#cfe0ff"));
    // a collar or hood
    if (C.outfit === "hoodie") sc.box(body, [-3.8, -torsoD / 2 - .8, torsoH - .4], [3.8, -torsoD / 2 + 1.4, torsoH + 1.6], shade(C.top, .9));
    if (C.outfit === "turtleneck") sc.box(body, [-2.6, -1.8, torsoH], [2.6, 1.8, torsoH + 1.4], shade(C.top, .92));

    /* arms: upper arm and forearm, with a hand; raising rotates round the forward axis */
    const sleeve = C.outfit === "overalls" ? C.under : C.top, shortSleeve = C.outfit === "overalls" || C.outfit === "tee";
    for (const side of [-1, 1]) {
      const [pitch, raise, bend] = side < 0 ? pose.armL : pose.armR;
      const sh = child(body, mm(ry(-side * raise * D), rx(pitch * D)), [side * (torsoW / 2 + 1.35), 0, torsoH - 1.2]);
      sc.box(sh, [-1.35, -1.35, -4.2], [1.35, 1.35, 1.2], sleeve, C.outfit === "flannel" ? {front: [[-1.35, -3, 1.35, -2.5, tint(C.top, .3)]], [side < 0 ? "left" : "right"]: [[-1.35, -3, 1.35, -2.5, tint(C.top, .3)]]} : {});
      const el = child(sh, rx(bend * D), [0, 0, -4.2]);
      sc.box(el, [-1.3, -1.3, -3.6], [1.3, 1.3, 0], shortSleeve ? C.skin : sleeve);
      if (C.extra === "watch" && side < 0) sc.box(el, [-1.4, -1.4, -3.6], [1.4, 1.4, -2.9], "#c9a46a");
      sc.box(el, [-1.25, -1.25, -5.4], [1.25, 1.25, -3.6], C.skin);
      const freeHand = side > 0 && ["idle", "walkA", "walkB"].includes(o.pose || "idle") && !o.noProp;
      if (freeHand && C.prop) prop(sc, child(el, rx(0), [0, 0, -5.4]), C.prop, C);
      if (o.pose === "mug" && side > 0) sc.box(child(el, rx(-90 * D), [0, 0, -5.4]), [-1.3, .2, -.6], [1.3, 2.8, 2.2], "#f4f1ea", {front: [[-1.3, .2, 1.3, .8, "#3fae6a"]]});
    }

    /* the head: a big block with the face painted on its front */
    const neck = child(body, rx((pose.head || 0) * D), [0, 0, torsoH]);
    const hz = .6, H = 9.6, HW = 10, HD = 9;
    const face = [];
    const look = mood === "wait" ? [.3, .35] : mood === "stuck" ? [0, -.3] : mood === "focus" ? [0, -.35] : [.25, 0];
    // eyes: white blocks with a dark pupil
    for (const s of [-1, 1]) {
      const ex = s * 2.3;
      face.push([ex - 1.25, hz + 4.6, ex + 1.25, hz + 6.6, "!#fffdf6"]);
      face.push([ex - .55 + look[0], hz + 4.95 + look[1], ex + .55 + look[0], hz + 6.2 + look[1], "!#231a2e"]);
      if (mood === "tired" || mood === "focus" || mood === "stuck") face.push([ex - 1.3, hz + 5.7, ex + 1.3, hz + 6.7, C.skin]);
    }
    // brows: their tilt is the mood
    // brows: [outer end, inner end] raised or lowered; their tilt is the mood
    const brow = {calm: [0, 0], happy: [.5, .5], focus: [.3, -.6], wait: [0, .8], stuck: [-.5, .9], tired: [-.3, -.3]}[mood] || [0, 0];
    for (const s of [-1, 1]) {
      const ex = s * 2.3, ou = ex + s * 1.5, iu = ex - s * 1.5, zo = hz + 7.4 + brow[0], zi = hz + 7.4 + brow[1];
      face.push([[[ou, zo], [iu, zi], [iu, zi + .8], [ou, zo + .8]], C.brows, "poly"]);
    }
    // the mouth
    if (mood === "happy") face.push([-1.8, hz + 2.1, 1.8, hz + 3.2, "!#5a1c28"], [-1.4, hz + 2.8, 1.4, hz + 3.2, "!#fffdf6"]);
    else if (mood === "wait") face.push([-.7, hz + 1.8, .7, hz + 3.2, "!#5a1c28"]);
    else if (mood === "stuck") face.push([-1.8, hz + 2.3, 1.8, hz + 3.1, "!#fffdf6"], [-1.8, hz + 2.6, 1.8, hz + 2.75, "!#231a2e"]);
    else face.push([-1.4, hz + 2.4, 1.4, hz + 2.9, "!#7a2a34"]);
    const GL = "!" + (C.glasses || "#8a5cf0");
    if (C.extra === "glasses") face.push([-4, hz + 4.2, -.6, hz + 4.4, GL], [.6, hz + 4.2, 4, hz + 4.4, GL], [-4, hz + 6.8, -.6, hz + 7, GL], [.6, hz + 6.8, 4, hz + 7, GL], [-4, hz + 4.2, -3.8, hz + 7, GL], [-.8, hz + 4.2, -.6, hz + 7, GL], [.6, hz + 4.2, .8, hz + 7, GL], [3.8, hz + 4.2, 4, hz + 7, GL], [-.6, hz + 5.6, .6, hz + 5.8, GL]);
    if (mood === "happy" || mood === "wait") face.push([-4.2, hz + 3.6, -3, hz + 4.2, "#ff8a8a"], [3, hz + 3.6, 4.2, hz + 4.2, "#ff8a8a"]);
    // hair painted on the head's own faces
    const hdeco = {front: face, top: [], back: [], left: [], right: []};
    const hairEdge = (sd, from) => hdeco[sd].push(sd === "back" ? [-HW / 2, hz + from, HW / 2, hz + H, C.hair] : [-HD / 2, hz + from, HD / 2, hz + H, C.hair]);
    if (C.hairStyle === "pony" || C.hairStyle === "bun" || C.hairStyle === "braids") { face.push([-HW / 2, H - 1.3, HW / 2, H + hz, C.hair], [-HW / 2, H - 2.6, -2.4, H, C.hair]); hairEdge("left", 4.6); hairEdge("right", 4.6); hairEdge("back", 1.2); hdeco.top.push([-HW / 2, -HD / 2, HW / 2, HD / 2, C.hair]); }
    if (C.hairStyle === "afro") { face.push([-HW / 2, H - .9, HW / 2, H + hz, C.hair]); }
    const capped = ["short", "spiky", "slick", "long", "curly", "bob"].includes(C.hairStyle);
    if (capped) { face.push([-HW / 2, hz + H - 1.4, HW / 2, hz + H, C.hair]); if (C.hairStyle !== "slick") face.push([-HW / 2, hz + H - 2.4, -1.2, hz + H, C.hair]); hairEdge("left", C.hairStyle === "long" || C.hairStyle === "bob" ? 1.6 : 5.6); hairEdge("right", C.hairStyle === "long" || C.hairStyle === "bob" ? 1.6 : 5.6); hairEdge("back", C.hairStyle === "long" || C.hairStyle === "bob" ? .2 : 3.6); }
    if (C.hairStyle === "buzz") { hairEdge("left", 6.6); hairEdge("right", 6.6); hairEdge("back", 5); face.push([-HW / 2, hz + H - .8, HW / 2, hz + H, C.hair]); hdeco.top.push([-HW / 2, -HD / 2, HW / 2, HD / 2, C.hair]); }
    if (C.hat) hairEdge("back", 3);
    if (C.hairStyle === "bald") { hdeco.left.push([-HD / 2, hz + 4.2, 1.6, hz + 6.8, C.hair]); hdeco.right.push([-1.6, hz + 4.2, HD / 2, hz + 6.8, C.hair]); hdeco.back.push([-HW / 2, hz + 4.2, HW / 2, hz + 6.8, C.hair]); hdeco.top.push([-2.6, -1.4, -.6, 1.2, "!#fff4e6"]); }
    if (C.beard) { face.push([-HW / 2, hz, HW / 2, hz + 1.6, C.beard], [-HW / 2, hz, -3.4, hz + 4.6, C.beard], [3.4, hz, HW / 2, hz + 4.6, C.beard], [-1.8, hz + 1.6, 1.8, hz + 2.1, C.beard]); hdeco.left.push([-HD / 2, hz, HD / 2, hz + 4.6, C.beard]); hdeco.right.push([-HD / 2, hz, HD / 2, hz + 4.6, C.beard]); }
    const head = child(neck, rz(0), [0, .4, 0]);
    sc.box(head, [-HW / 2, -HD / 2, hz], [HW / 2, HD / 2, hz + H], C.skin, hdeco);
    // a nose block and ears
    sc.box(head, [-.8, HD / 2, hz + 3.4], [.8, HD / 2 + 1.1, hz + 5.2], C.skin);
    for (const s of [-1, 1]) sc.box(head, s < 0 ? [-HW / 2 - .7, -1, hz + 3.6] : [HW / 2, -1, hz + 3.6], s < 0 ? [-HW / 2, 1, hz + 6] : [HW / 2 + .7, 1, hz + 6], C.skin);
    if (C.moustache) sc.box(head, [-2.8, HD / 2, hz + 2.6], [2.8, HD / 2 + .9, hz + 3.6], C.moustache);
    // hair in blocks
    if (C.hairStyle === "pony") { sc.box(head, [-HW / 2 - .4, -HD / 2 - .4, hz + H - 1.4], [HW / 2 + .4, HD / 2 + .3, hz + H + 1.2], C.hair); sc.box(head, [-1.4, -HD / 2 - 2.6, hz + 2.4], [1.4, -HD / 2 - .2, hz + 9], C.hair); sc.box(head, [-1.8, -HD / 2 - 1.2, hz + 7.4], [1.8, -HD / 2 + .2, hz + 9.4], "#8a5cf0"); }
    if (C.hairStyle === "bun") { sc.box(head, [-HW / 2 - .3, -HD / 2 - .3, hz + H - 1.2], [HW / 2 + .3, HD / 2 + .3, hz + H + .8], C.hair); sc.box(head, [-2.2, -2.2, hz + H + .8], [2.2, 2.2, hz + H + 4.6], C.hair); sc.box(head, [-2.4, -2.4, hz + H + .8], [2.4, 2.4, hz + H + 1.6], "#8a5cf0"); }
    if (C.hairStyle === "afro") {
      // a crown above the brows and a mass behind the head, so the big block never lands in front of the face
      sc.box(head, [-HW / 2 - 2.2, -HD / 2 - 2.4, hz + H - 1.1], [HW / 2 + 2.2, HD / 2 + .5, hz + H + 4.4], C.hair, {top: [[-3, -3, -1, -1, tint(C.hair, .12)], [1, 1, 3, 3, tint(C.hair, .12)]], front: [[-HW / 2 - 2.2, hz + H + 1.4, -2, hz + H + 1.9, tint(C.hair, .1)]]});
      sc.box(head, [-HW / 2 - 2.2, -HD / 2 - 2.4, hz + 2.4], [HW / 2 + 2.2, -HD / 2 + .2, hz + H - 1.1], C.hair);
      for (const sd of [-1, 1]) sc.box(head, sd < 0 ? [-HW / 2 - 2.2, -HD / 2 + .2, hz + 5.4] : [HW / 2, -HD / 2 + .2, hz + 5.4], sd < 0 ? [-HW / 2, 1.2, hz + H - 1.1] : [HW / 2 + 2.2, 1.2, hz + H - 1.1], C.hair);
    }
    if (C.hairStyle === "braids") { sc.box(head, [-HW / 2 - .4, -HD / 2 - .4, hz + H - 1.4], [HW / 2 + .4, HD / 2 + .3, hz + H + 1], C.hair); for (const [bx, by] of [[-4.2, -3.4], [-1.4, -4.4], [1.4, -4.4], [4.2, -3.4], [-5.2, -.4], [5.2, -.4]]) sc.box(head, [bx - .7, by - .7, hz - 4], [bx + .7, by + .7, hz + H - 1], C.hair, {front: [[-1, hz - 3, 1, hz - 2.6, tint(C.hair, .25)], [-1, hz - .4, 1, hz, tint(C.hair, .25)], [-1, hz + 2.2, 1, hz + 2.6, tint(C.hair, .25)]]}); }
    if (capped) {
      sc.box(head, [-HW / 2 - .3, -HD / 2 - .3, hz + H - .8], [HW / 2 + .3, HD / 2 + .3, hz + H + (C.hairStyle === "slick" ? .7 : 1.3)], C.hair, C.hairStyle === "slick" ? {top: [[-2.6, -HD / 2, -2.2, HD / 2, tint(C.hair, .3)]]} : {});
      if (C.hairStyle === "spiky") for (const [bx, by, bh] of [[-3, -1, 2.2], [0, 1.4, 2.8], [3, -.6, 2], [-.6, -3, 2.4], [2.6, 2.6, 1.6]]) sc.box(head, [bx - 1.1, by - 1.1, hz + H + 1.2], [bx + 1.1, by + 1.1, hz + H + 1.2 + bh], C.hair);
      if (C.hairStyle === "curly") for (const [bx, by] of [[-4.4, -3.6], [-1.4, -4.2], [1.6, -4.2], [4.4, -3.6], [-4.8, .4], [4.8, .4], [-3, 3.4], [3, 3.4]]) sc.box(head, [bx - 1.3, by - 1.3, hz + H - .6], [bx + 1.3, by + 1.3, hz + H + 2], C.hair);
      if (C.hairStyle === "long" || C.hairStyle === "bob") { const low = C.hairStyle === "bob" ? hz + 3 : hz - 2.6; for (const sd of [-1, 1]) sc.box(head, sd < 0 ? [-HW / 2 - 1, -HD / 2 - .6, low] : [HW / 2, -HD / 2 - .6, low], sd < 0 ? [-HW / 2, .6, hz + H - .6] : [HW / 2 + 1, .6, hz + H - .6], C.hair); sc.box(head, [-HW / 2 - .6, -HD / 2 - 1, low], [HW / 2 + .6, -HD / 2, hz + H - .6], C.hair); }
    }
    // hats
    if (C.hat === "beanie") { sc.box(head, [-HW / 2 - .5, -HD / 2 - .5, hz + H - 2.4], [HW / 2 + .5, HD / 2 + .5, hz + H + 2], C.top === "#ff7a5a" ? "#3f6fd8" : "#ff7a5a", {front: [[-HW / 2 - .5, hz + H - 2.4, HW / 2 + .5, hz + H - 1.2, "#f4f1ea"]]}); sc.box(head, [-1.2, -1.2, hz + H + 2], [1.2, 1.2, hz + H + 3.6], "#f4f1ea"); }
    // the CEO's crown (D73): a gold band with prongs, so a CEO never passes for anyone else
    if (C.hat === "crown") {
      // an open ring (the hair shows inside it), tall prongs and a red stone at the front
      const G = "#f2c23a", t = .8, x0 = -HW / 2 - .4, x1 = HW / 2 + .4, y0 = -HD / 2 - .4, y1 = HD / 2 + .4, z0 = hz + H - .6, z1 = hz + H + 1.6;
      sc.box(head, [x0, y1 - t, z0], [x1, y1, z1], G, {front: [[-.8, z0 + .5, .8, z1 - .4, "!#e0473a"]]});
      sc.box(head, [x0, y0, z0], [x1, y0 + t, z1], G);
      sc.box(head, [x0, y0, z0], [x0 + t, y1, z1], G);
      sc.box(head, [x1 - t, y0, z0], [x1, y1, z1], G);
      for (const [x, y] of [[x0, y1 - t], [-.4, y1 - t], [x1 - t, y1 - t], [x0, y0], [x1 - t, y0], [x0, -.4], [x1 - t, -.4]]) sc.box(head, [x, y, z1], [x + t, y + t, z1 + 3], G, {top: [[x, y, x + t, y + t, "!#ffe58a"]]});
    }
    if (C.hat === "beret") sc.box(head, [-HW / 2 - 1.2, -HD / 2 - .8, hz + H - .2], [HW / 2 + .4, HD / 2 + .4, hz + H + 1.6], "#c4364a", {top: [[-.5, -.5, .5, .5, "#8a2434"]]});
    if (C.hat === "hardhat") { sc.box(head, [-HW / 2 - .6, -HD / 2 - .6, hz + H - 1], [HW / 2 + .6, HD / 2 + .6, hz + H + 2.8], "#ff8a2a", {top: [[-.5, -HD / 2 - .6, .5, HD / 2 + .6, "#ffb070"]]}); sc.box(head, [-HW / 2 - .6, HD / 2 + .6, hz + H - 1], [HW / 2 + .6, HD / 2 + 2, hz + H - .3], "#ff8a2a"); }
    if (C.hat === "cap") { sc.box(head, [-HW / 2 - .4, -HD / 2 - .4, hz + H - 1], [HW / 2 + .4, HD / 2 + .4, hz + H + 1.8], C.top, {front: [[-1.2, hz + H, 1.2, hz + H + 1.2, "#f4f1ea"]]}); sc.box(head, [-HW / 2 + 1, HD / 2 + .4, hz + H - 1], [HW / 2 - 1, HD / 2 + 3.4, hz + H - .3], shade(C.top, .85)); }
    if (C.extra === "headphones") { const top = hz + H + (C.hat ? 2.4 : capped ? 1.5 : .2); sc.box(head, [-HW / 2 - .9, -.6, top], [HW / 2 + .9, .6, top + .8], "#2a2433"); for (const sd of [-1, 1]) sc.box(head, sd < 0 ? [-HW / 2 - .9, -.6, hz + 6.4] : [HW / 2 + .1, -.6, hz + 6.4], sd < 0 ? [-HW / 2 - .1, .6, top + .8] : [HW / 2 + .9, .6, top + .8], "#2a2433"); for (const sd of [-1, 1]) sc.box(head, sd < 0 ? [-HW / 2 - 2.2, -1.8, hz + 3] : [HW / 2, -1.8, hz + 3], sd < 0 ? [-HW / 2, 1.8, hz + 7] : [HW / 2 + 2.2, 1.8, hz + 7], "#ff6ad5"); }
    // accessories
    if (C.extra === "headset") { sc.box(head, [-HW / 2 - 2.8, -1, hz + 3], [-HW / 2 - .1, 1.6, hz + 6.6], "#3b3f63"); sc.box(head, [HW / 2 + .1, -1, hz + 3], [HW / 2 + 2.8, 1.6, hz + 6.6], "#3b3f63"); sc.box(head, [HW / 2 + .6, 1.6, hz + 3.2], [HW / 2 + 1.2, 5.6, hz + 3.8], "#2a1a2e"); }
    if (C.extra === "goggles") { sc.box(head, [-HW / 2 - .3, -HD / 2 - .3, hz + 7.2], [HW / 2 + .3, HD / 2 + .3, hz + 8.2], "#3a3340"); for (const s of [-1, 1]) sc.box(head, [s * 2.3 - 1.6, HD / 2, hz + 6.9], [s * 2.3 + 1.6, HD / 2 + 1, hz + 9], "#5fe0c0", {front: [[s * 2.3 - 1.2, hz + 8.1, s * 2.3 - .2, hz + 8.7, "!#e8fff8"]]}); }
    if (C.extra === "hoops" || C.hoops) for (const s of [-1, 1]) sc.box(head, s < 0 ? [-HW / 2 - 1.1, -.5, hz + 1.2] : [HW / 2 + .4, -.5, hz + 1.2], s < 0 ? [-HW / 2 - .4, .5, hz + 3.4] : [HW / 2 + 1.1, .5, hz + 3.4], "#f2c94c");

    // the ground shadow: an iso diamond
    const sh = [[-6, -5], [6, -5], [6, 5], [-6, 5]].map(([x, y]) => proj([at[0] + x * 1.1, at[1] + y * 1.1, at[2]]));
    return `<polygon points="${sh.map(p => f(p[0]) + "," + f(p[1])).join(" ")}" fill="#140c22" opacity=".28"/>`;
  }
  function figure(name, o = {}) {
    const sc = new Scene(o.scale || 4.2), shadow = figureInto(sc, name, o);
    return `<g class="bc-fig">${shadow}${sc.svg()}</g>`;
  }
  /* things people carry: held in the hand frame, which points down along the arm */
  function prop(sc, H, kind, C) {
    if (kind === "laptop") sc.box(H, [-.45, -3.4, -5.2], [.45, 3.4, .6], "#9aa3b4", {right: [[-1, -2.6, 1, -1.2, "#e8ecf3"]], left: [[-1, -2.6, 1, -1.2, "#e8ecf3"]]});
    if (kind === "tablet") { sc.box(H, [-.35, -2.6, -4.6], [.35, 2.6, .8], "#2a2433", {right: [[-2.2, -4, 2.2, .2, "!#7ad7ff"], [-1.6, -3, .4, -2.2, "!#ff6ad5"], [-.8, -1.6, 1.6, -.8, "!#f2c23a"]], left: [[-2.2, -4, 2.2, .2, "!#7ad7ff"]]}); sc.box(H, [-.25, 2.8, -4], [.25, 3.2, 1.2], "#f4f1ea"); }
    if (kind === "clipboard") sc.box(H, [-.3, -2.4, -5.4], [.3, 2.4, .6], "#a8743a", {right: [[-2, -4.8, 2, -.4, "!#fdfbf4"], [-1.4, -1.6, 1.4, -1.2, "#3fae6a"], [-1.4, -2.8, 1.4, -2.4, "#3fae6a"], [-1.4, -4, .6, -3.6, "#3fae6a"], [-.8, -.2, .8, .6, "#9aa3b4"]], left: [[-2, -4.8, 2, -.4, "!#fdfbf4"]]});
    if (kind === "phone") sc.box(H, [-.4, -1, -2.6], [.4, 1, .2], "#2a2433", {front: [[-.8, -2.4, .8, -.2, "!#7ad7ff"]], right: [[-.8, -2.4, .8, -.2, "!#7ad7ff"]]});
    if (kind === "mug") { sc.box(H, [-1.3, -1.3, -1.2], [1.3, 1.3, 1.6], "#f4f1ea", {front: [[-1.3, .2, 1.3, .7, "#e05a5a"]]}); }
    if (kind === "wrench") { sc.box(H, [-.35, -.35, -6.4], [.35, .35, .2], "#9aa3b4"); sc.box(H, [-.45, -1.3, -7.6], [.45, 1.3, -6.2], "#9aa3b4"); }
    if (kind === "book") sc.box(H, [-.7, -2.2, -4.6], [.7, 2.2, .4], "#c4364a", {right: [[-2, -.4, 2, 0, "#f2c94c"]], left: [[-2, -.4, 2, 0, "#f2c94c"]]});
    if (kind === "megaphone") { sc.box(H, [-.8, -.8, -1.6], [.8, .8, .4], "#2a2433"); sc.box(H, [-1.2, -.6, -1.4], [1.2, 3, .6], "#ff8a2a"); sc.box(H, [-1.9, 3, -2.1], [1.9, 4.2, 1.3], "#f4f1ea"); }
  }
  function shade(h, k) { return toHex(hex(h).map(v => v * k)); }
  function tint(h, k) { return toHex(hex(h).map(v => v + (255 - v) * k)); }

  window.BlockyCast = {figure, figureInto, person, CAST, ROLES, POSES, VIEWS, engine: {Scene, frame, child, toWorld, rx, ry, rz, mm, D, lit, projWith, shade, tint}};
})();
