/* The art engine of the native apps. FactoryScenes/ArtEngine.swift loads engine.html in a hidden WebKit view and calls
   window.sf.*. It runs the same blocky world (blocky-cast.js, blocky-world.js) and Orbit generator (orbit-gen.js) as
   the design board, and hands back PNG layers as data URLs; SpriteKit sorts them by depth, moves the people and zooms.

   Coordinates are art units: the blocky world's own projection at S = 1, where a floor tile is 32 units wide and a person
   about 30 tall. Every image says where its top-left corner goes (x, y) and how big it is (w, h) in art units; it is
   painted at R pixels per unit. Positions on a floor are tiles (i, j), as on the floor plan. */
(function () {
  const B = window.BlockyCast, W = window.BlockyWorld, OG = window.OrbitGen;
  const NS = "http://www.w3.org/2000/svg";
  // web fonts do not load into an SVG image: the signs get a heavy system face instead of Bungee
  const FONT = 'font-family="Arial Black, Avenir Next, Helvetica, sans-serif"';
  const fontFix = s => s.replace(/font-family="[^"]*"/g, FONT);
  // plaques are sized to their text in the face they are painted in
  if (W) W.signFont = "Arial Black, Avenir Next, Helvetica, sans-serif";

  function scratch() {
    const s = document.createElementNS(NS, "svg");
    s.setAttribute("width", "10"); s.setAttribute("height", "10");
    s.style.position = "absolute"; s.style.left = "-99999px";
    document.body.appendChild(s);
    return s;
  }
  function canvas(w, h) { const c = document.createElement("canvas"); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }
  const png = c => c.toDataURL("image/png");

  /* ---------- painting a blocky scene's faces straight onto a canvas, as Scene.svg() would draw them ---------- */
  function bounds(faces, pad = .5) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const f of faces) for (const p of f.pts) { if (p[0] < x0) x0 = p[0]; if (p[0] > x1) x1 = p[0]; if (p[1] < y0) y0 = p[1]; if (p[1] > y1) y1 = p[1]; }
    return [x0 - pad, y0 - pad, x1 + pad, y1 + pad];
  }
  const union = bs => bs.reduce((a, b) => [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])], [Infinity, Infinity, -Infinity, -Infinity]);
  function path(g, pts) { g.beginPath(); g.moveTo(pts[0][0], pts[0][1]); for (let k = 1; k < pts.length; k++) g.lineTo(pts[k][0], pts[k][1]); g.closePath(); }
  function drawFaces(g, faces) {
    faces.sort((a, b) => a.depth - b.depth);
    g.lineJoin = "round"; g.lineWidth = .14;
    for (const fc of faces) {
      path(g, fc.pts); g.fillStyle = fc.fill;
      if (fc.opacity != null) { g.globalAlpha = fc.opacity; g.fill(); g.globalAlpha = 1; }
      else { g.fill(); g.strokeStyle = fc.fill; g.stroke(); }
      for (const d of fc.decals) { path(g, d.pts); g.fillStyle = d.fill; g.fill(); }
    }
  }
  /* several scenes in one image, in the order given */
  function image(scenes, R) {
    const box = union(scenes.filter(sc => sc.faces.length).map(sc => bounds(sc.faces)));
    const c = canvas((box[2] - box[0]) * R, (box[3] - box[1]) * R), g = c.getContext("2d");
    g.setTransform(R, 0, 0, R, -box[0] * R, -box[1] * R);
    for (const sc of scenes) drawFaces(g, sc.faces);
    return {png: png(c), x: box[0], y: box[1], w: c.width / R, h: c.height / R};
  }
  /* every object on its own, packed onto atlas pages: each becomes a sprite that SpriteKit sorts by its key */
  function atlas(objs, R, side = 4096) {
    const list = objs.filter(o => o.sc.faces.length).map(o => { const b = bounds(o.sc.faces); return {o, b, pw: Math.ceil((b[2] - b[0]) * R) + 2, ph: Math.ceil((b[3] - b[1]) * R) + 2}; });
    const pages = [];
    let page = null, x = 0, y = 0, shelf = 0;
    const open = () => { page = {w: 0, h: 0, items: []}; pages.push(page); x = 0; y = 0; shelf = 0; };
    open();
    for (const e of list.slice().sort((a, b) => b.ph - a.ph)) {
      if (x + e.pw > side) { x = 0; y += shelf; shelf = 0; }
      if (y + e.ph > side) open();
      e.page = pages.length - 1; e.px = x; e.py = y;
      x += e.pw; shelf = Math.max(shelf, e.ph);
      page.w = Math.max(page.w, e.px + e.pw); page.h = Math.max(page.h, e.py + e.ph); page.items.push(e);
    }
    const out = pages.map(pg => {
      const c = canvas(pg.w, pg.h), g = c.getContext("2d");
      for (const e of pg.items) { g.setTransform(R, 0, 0, R, e.px + 1 - e.b[0] * R, e.py + 1 - e.b[1] * R); drawFaces(g, e.o.sc.faces); }
      return {png: png(c), w: c.width, h: c.height};
    });
    return {R, pages: out, items: list.map(e => ({id: e.o.id || null, key: e.o.key, page: e.page, px: e.px, py: e.py, pw: e.pw, ph: e.ph,
      x: e.b[0] - 1 / R, y: e.b[1] - 1 / R, w: e.pw / R, h: e.ph / R}))};
  }
  /* SVG markup (signs, glows) as an image over a box in art units */
  function raster(markup, defs, box, R) {
    return new Promise(done => {
      const w = box[2] - box[0], h = box[3] - box[1];
      const svg = `<svg xmlns="${NS}" width="${Math.ceil(w * R)}" height="${Math.ceil(h * R)}" viewBox="${box[0]} ${box[1]} ${w} ${h}">${defs || ""}${fontFix(markup)}</svg>`;
      const img = new Image();
      img.onload = () => { const c = canvas(w * R, h * R); c.getContext("2d").drawImage(img, 0, 0, c.width, c.height); done({png: png(c), x: box[0], y: box[1], w: c.width / R, h: c.height / R}); };
      img.onerror = () => done(null);
      img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
    });
  }
  /* each sign on its own image, just big enough, at a high R so it stays sharp close up: [{id, png, x, y, w, h}] */
  async function rasterParts(svg, list, defs, R) {
    const out = [];
    for (const part of list || []) {
      const g = document.createElementNS(NS, "g");
      g.innerHTML = part.markup; svg.appendChild(g);
      const b = g.getBBox(); g.remove();
      if (!b.width || !b.height) continue;
      // room for strokes and for the app's heavier sign face
      const box = [Math.floor(b.x - 6), Math.floor(b.y - 4), Math.ceil(b.x + b.width + 6), Math.ceil(b.y + b.height + 4)];
      const img = await raster(part.markup, defs, box, R);
      if (img) out.push({id: part.id, key: part.key != null ? part.key : null, ...img});
    }
    return out;
  }
  const viewBox = svg => { const v = svg.getAttribute("viewBox").split(/\s+/).map(Number); return [v[0], v[1], v[0] + v[2], v[1] + v[3]]; };

  /* ---------- one floor from the inside: the atrium (D38) ---------- */
  /* where people stand, per room: [i, j, pose, dir, seat]. The room is the phase, the person the state (D39). */
  const SPOTS = {
    entrance: [[6, 2.8, "wave", "down"], [5.2, 2.0, "idle", "down"], [7.1, 3.6, "idle", "left"], [5.0, 4.2, "idle", "right"]],
    research: [[3.2, 2.6, "idle", "down"], [2.2, 3.9, "idle", "down"], [0.95, 1.9, "idle", "up"], [3.4, 4.4, "idle", "left"], [1.3, 4.6, "idle", "right"]],
    planning: [[11.8, 1.6, "sit", "down", 6], [10.6, 1.6, "sit", "down", 6], [9.4, 1.6, "sit", "down", 6], [9.4, 3.9, "sit", "up", 6], [10.6, 3.9, "sit", "up", 6], [11.8, 3.9, "sit", "up", 6], [12.7, 1.05, "idle", "up"]],
    // at a desk: on the near side, back to you, facing the screen
    development: [[15.42, 1.97, "type", "up", 6], [17.62, 1.97, "type", "up", 6], [19.82, 1.97, "type", "up", 6], [15.42, 4.02, "type", "up", 6], [17.62, 4.02, "type", "up", 6], [19.82, 4.02, "type", "up", 6], [16.6, 2.4, "idle", "down"]],
    tools: [[22.3, 3.7, "idle", "right"], [21.6, 3.7, "idle", "down"]],
    builds: [[20.4, 7.7, "idle", "down"], [19.6, 7.4, "idle", "up"], [21.4, 8.6, "idle", "left"], [20.6, 10.4, "idle", "down"], [22.0, 9.9, "idle", "left"]],
    testing: [[19.8, 14.4, "idle", "right"], [21.0, 12.4, "idle", "down"], [19.2, 12.3, "idle", "down"], [22.2, 14.9, "idle", "left"], [18.2, 13.0, "idle", "right"]],
    pullRequests: [[11.9, 12.9, "idle", "down"], [10.4, 12.7, "idle", "down"], [12.6, 15.0, "idle", "up"], [10.8, 15.0, "idle", "up"]],
    deploy: [[6.2, 18.0, "cheer", "down"], [6.4, 12.6, "idle", "down"], [4.6, 17.5, "idle", "right"], [5.0, 14.8, "idle", "right"], [7.6, 15.0, "idle", "left"]],
    // the sofa seats sit on the front edge of the cushion (i 1.3): further in, the sofa is drawn over whoever sits there;
    // the standing spots are spread across the room so full-size people do not stand in each other
    // the break room (B2): coffee at the bar, a rally at the ping-pong table, the arcade, a nap on the beanbag; everyone
    // clear of the furniture (nobody sits in a sofa that hides them) and apart on screen
    lounge: [[2.2, 6.4, "mug", "up"], [1.45, 8.85, "cheer", "down"], [1.45, 12.35, "wave", "up"], [1.85, 15.2, "type", "left"], [2.6, 10.6, "idle", "down"], [2.25, 13.6, "snooze", "down", 4]],
    // in front of the counter and west of it, clear of the hall's way through, looking at you
    needsYou: [[10.4, 9.55, "idle", "down"], [9.2, 9.55, "idle", "down"], [8.0, 9.55, "idle", "down"], [6.8, 9.55, "idle", "down"], [8.4, 8.2, "idle", "down"], [7.2, 8.2, "idle", "down"]],
    parked: [[16.0, 8.62, "sit", "down", 4], [16.8, 8.62, "sit", "down", 4]],
    // a factory's CEO: under the board's left end in Planning, facing you, clear of the desks next door (B1)
    ceo: [[8.65, 1.15, "point", "down"]]
  };
  const ROOM_OF = {entrance: "landing", research: "stacks", planning: "war", development: "workshop", tools: "switch", builds: "boiler", testing: "crash",
    pullRequests: "mail", deploy: "launch", lounge: "porch", needsYou: "counter", parked: "counter"};
  const NAMES = [["research", "Research"], ["entrance", "Entrance"], ["planning", "Planning"], ["development", "Development"], ["tools", "Tools"], ["builds", "Builds"],
    ["testing", "Testing"], ["pullRequests", "Pull requests"], ["deploy", "Deploy"], ["lounge", "Lounge"]];

  async function floor(spec) {
    const R = spec.R || 4, svg = scratch();
    const scene = W.atrium(svg, {team: {}, provider: spec.provider}), parts = scene.parts, view = viewBox(svg);
    const ground = image([...parts.under, parts.base], R);
    const objects = atlas(parts.objs, R);
    const light = await raster(parts.light, parts.defs, view, Math.min(R, 2));
    const signs = await rasterParts(svg, parts.topParts, parts.defs, 10);
    svg.remove();
    // the rooms, with their centres in tiles, for clicks and the camera
    const rooms = NAMES.map(([id, name]) => { const r = ROOMS_PLAN[ROOM_OF[id]]; return {id, name, i: r.i, j: r.j, w: r.w, d: r.d}; });
    rooms.push({id: "needsYou", name: "Needs you", i: 9.3, j: 6.8, w: 2.4, d: 2.4});
    return {R, view, ground, objects, light, signParts: signs, labels: parts.labels || [], boxes: parts.boxes, solids: parts.solids || [], spots: SPOTS, rooms};
  }
  // the room rectangles, in tiles, as the atrium lays them out
  const ROOMS_PLAN = {stacks: {i: 0, j: 0, w: 4, d: 5}, landing: {i: 4, j: 0, w: 4, d: 5}, war: {i: 8, j: 0, w: 6, d: 5}, workshop: {i: 14, j: 0, w: 7, d: 5},
    switch: {i: 21, j: 3, w: 3, d: 2}, boiler: {i: 18, j: 5, w: 6, d: 6}, crash: {i: 17, j: 11, w: 7, d: 5}, mail: {i: 9, j: 11, w: 5, d: 5},
    launch: {i: 3, j: 11, w: 6, d: 8.6}, porch: {i: 0, j: 5, w: 3, d: 11}, counter: {i: 9.3, j: 6.8, w: 2.4, d: 2.4}};

  /* ---------- a person: frames from the blocky rig (D41) ---------- */
  /* who: {role, seed} → BlockyCast.person(role, seed); or {name} for the named cast. frames: [{pose, view, mood, seat, noProp}] */
  function figure(who, frames, R = 6) {
    const cast = who.name ? B.CAST[who.name] : B.person(who.role, who.seed);
    const objs = frames.map((fr, k) => {
      const sc = new B.engine.Scene(1);
      B.figureInto(sc, cast, {pose: fr.pose, mood: fr.mood || "calm", view: fr.view || "SW", seat: fr.seat || 0, noProp: !!fr.noProp}, [0, 0, 0]);
      return {id: String(k), key: k, sc};
    });
    const a = atlas(objs, R, 2048);
    // the foot (art origin) inside each frame: x and y are where the frame's top-left goes relative to the feet
    return {R, page: a.pages[0], pages: a.pages, frames: a.items.sort((p, q) => +p.id - +q.id).map(it => ({page: it.page, px: it.px, py: it.py, pw: it.pw, ph: it.ph, x: it.x, y: it.y, w: it.w, h: it.h})), top: cast.top, skin: cast.skin};
  }

  /* a name plate (Spel+, B2 B3 B6 B7), centred on its anchor (x 0 at the head, y 0 the plate's bottom tip):
     o: {text, sub, state: work|wait|stuck|done|back, role (colour), helper, badge (colour of a shared diamond)} */
  const PLATE_FONT = "'Arial Black', 'Avenir Next', Helvetica, sans-serif", SUB_FONT = "'Avenir Next', 'Helvetica Neue', Helvetica, sans-serif";
  let measureCtx = null;
  const textW = (t, font) => { measureCtx = measureCtx || document.createElement("canvas").getContext("2d"); measureCtx.font = font; return measureCtx.measureText(t).width; };
  function tag(o) {
    const R = o.R || 5, name = String(o.text || "").toUpperCase().replace(/[<&>]/g, ""), sub = String(o.sub || "").replace(/[<&>]/g, "");
    const st = o.state || "work", wait = st === "wait", stuck = st === "stuck", back = st === "back", done = st === "done";
    // (ss: FloorScene.plateLineUnits; the app scales the plate so this line is 11 pt on screen)
    const s = 5.8, ss = 4.4, role = o.role || "#6a6478", badge = o.badge;
    const tw = Math.max(textW(name, `900 ${s * 10}px ${PLATE_FONT}`) / 10, sub ? textW(sub, `600 ${ss * 10}px ${SUB_FONT}`) / 10 : 0) + 9;
    const th = sub ? s + ss + 6.4 : s + 5.6, ty = -3 - th;
    const bg = wait ? "#FFD83D" : stuck ? "#ff4a4a" : "#20182c", ink = wait ? "#1d1626" : stuck ? "#fff8ec" : done ? "#c9c4dc" : "#f3ebdd";
    const sub2 = wait ? "#3a2e10" : stuck ? "#ffe0d8" : done ? "#8a84a0" : "#b9b2cc";
    const edge = wait ? "#b08a00" : stuck ? "#a02020" : done ? "#4a4460" : role;
    let g = `<rect x="${-tw / 2}" y="${ty + 1.4}" width="${tw}" height="${th}" rx="2" fill="#0e0a18" opacity=".45"/>`;
    g += `<rect x="${-tw / 2}" y="${ty}" width="${tw}" height="${th}" rx="2" fill="${bg}" stroke="${edge}" stroke-width="1.2"/>`;
    if (!wait && !stuck) g += `<rect x="${-tw / 2 + .6}" y="${ty + .6}" width="2.2" height="${th - 1.2}" fill="${done ? "#4a4460" : role}"/>`;
    g += `<text x="0" y="${ty + s + 1.6}" text-anchor="middle" font-family="${PLATE_FONT}" font-weight="900" font-size="${s}" fill="${ink}">${name}</text>`;
    if (sub) g += `<text x="0" y="${ty + s + ss + 3.8}" text-anchor="middle" font-family="${SUB_FONT}" font-weight="600" font-size="${ss}" fill="${sub2}">${sub}</text>`;
    g += `<path d="M-2.4,${ty + th} L0,-.2 L2.4,${ty + th}" fill="${bg}" stroke="${edge}" stroke-width="1.2" stroke-linejoin="round"/><rect x="-2.2" y="${ty + th - 1.2}" width="4.4" height="1.6" fill="${bg}"/>`;
    if (badge) { const bx = tw / 2 - 1, by = ty + 1; g += `<path d="M${bx},${by - 3.2} l3.2,3.2 l-3.2,3.2 l-3.2,-3.2z" fill="${badge}" stroke="#f3ebdd" stroke-width=".7"/>`; }
    let top = ty;
    if (wait || stuck) { // crisp pixel art straight above the plate: a quest "!" or a storm cloud with its bolt
      const px = wait ? 1.6 : 2.0, art = wait ? ["..yyyy..", ".yykkyy.", "yyykkyyy", "yyykkyyy", "yyykkyyy", "yyyyyyyy", ".yykkyy.", "..yyyy.."] : ["....gggg.....", "..ggGGGGgg...", ".gGGGGGGGGgg.", "gGGGGGGGGGGGg", "gGGGGGGGGGGGg", ".ggggggggggg.", ".....yy......", "....yy.......", "...yyyy......", ".....yy......", ".....y......."];
      const C = {y: "#FFD83D", k: "#2a1a2e", g: "#3a3a4e", G: "#9a9ab4"};
      const w0 = art[0].length * px, h0 = art.length * px, oy = ty - 2;
      art.forEach((row, ri) => [...row].forEach((ch, ci) => { if (C[ch]) g += `<rect x="${(-w0 / 2 + ci * px).toFixed(2)}" y="${(oy - h0 + ri * px).toFixed(2)}" width="${px + .05}" height="${px + .05}" fill="${C[ch]}"/>`; }));
      top = oy - h0;
    }
    if (back) { // a small blue "sent back" bubble above the plate: quiet, not a shout
      const bw = 12, bh = 9.5, bx = -bw / 2, by = ty - bh - 3.5;
      g += `<rect x="${bx}" y="${by}" width="${bw}" height="${bh}" rx="2" fill="#3f6fd8" stroke="#1d3a8a" stroke-width=".8"/><path d="M-1,${by + bh} l1,2.6 l1,-2.6z" fill="#3f6fd8"/><path d="M3,${by + 3} v2.6 h-5.6 M-2.6,${by + 5.6} l1.7,-1.7 M-2.6,${by + 5.6} l1.7,1.7" stroke="#fff" stroke-width="1.1" fill="none"/>`;
      top = by;
    }
    return raster(g, "", [-tw / 2 - 5, top - 2, tw / 2 + 5, 1.5], R);
  }

  /* one calm board on the Planning wall (B1, B5): a dark header, five columns, a card per workstream in its column.
     o: {cards: [{id, title, phase: 0-4, wait, back, done}], w (tiles), h (units)}. Painted flat; the app lays it on the
     wall's plane. */
  function board(o) {
    const R = o.R || 6, W = (o.w || 5.2) * 16, H = o.h || 30, cols = ["PLAN", "BUILD", "TEST", "SHIP", "DONE"], cw = W / 5;
    let g = `<rect x="0" y="0" width="${W}" height="${H}" fill="#f6f1e6" stroke="#2a2433" stroke-width="1"/><rect x="0" y="0" width="${W}" height="5.6" fill="#3a3550"/>`;
    g += `<text x="${W / 2}" y="4.1" text-anchor="middle" font-family="${PLATE_FONT}" font-weight="900" font-size="3" fill="#f3ebdd">PLANNING · WORKSTREAMS</text>`;
    cols.forEach((c, k) => { g += `<text x="${(k + .5) * cw}" y="9.4" text-anchor="middle" font-family="${PLATE_FONT}" font-weight="900" font-size="2.1" fill="#5a5040">${c}</text>`; if (k) g += `<rect x="${k * cw - .15}" y="7" width=".3" height="${H - 8}" fill="#d8cfbd"/>`; });
    const per = [0, 0, 0, 0, 0];
    for (const c of o.cards || []) {
      const k = Math.max(0, Math.min(4, c.phase)), n = per[k]++;
      if (n > 2) continue;
      const x = k * cw + 1.2, y = 11 + n * 6.4, w = cw - 2.4, h = 5.6;
      if (n === 2 && (o.cards || []).filter(q => q.phase === k).length > 3) { g += `<text x="${x + w / 2}" y="${y + 3.6}" text-anchor="middle" font-family="${SUB_FONT}" font-weight="700" font-size="2" fill="#8a7a60">+${(o.cards || []).filter(q => q.phase === k).length - 2} more</text>`; continue; }
      const bgc = c.wait ? "#FFD83D" : c.done ? "#d8d2c4" : "#fffaf0", edge = c.wait ? "#b08a00" : "#8a7a60";
      g += `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${bgc}" stroke="${edge}" stroke-width=".35"/>`;
      g += `<text x="${x + 1}" y="${y + 2.5}" font-family="Menlo, monospace" font-weight="700" font-size="1.9" fill="#231a2e">${String(c.id).replace(/[<&>]/g, "")}</text>`;
      const t = String(c.title || "").replace(/[<&>]/g, ""), cut = t.length > 14 ? t.slice(0, 13) + "…" : t;
      g += `<text x="${x + 1}" y="${y + 4.8}" font-family="${SUB_FONT}" font-weight="600" font-size="1.55" fill="#3a3040">${cut}</text>`;
      if (c.back) g += `<rect x="${x + w - 2.6}" y="${y + .6}" width="2" height="2" rx=".4" fill="#3f6fd8"/>`;
    }
    // laid on the wall's plane (the front face of the back wall: u along i, v down the wall): its top-left corner at (0, 0)
    return raster(`<g transform="matrix(1 .5 0 1.08 0 0)">${g}</g>`, "", [-1.5, -1.5, W + 1.5, H * 1.08 + W * .5 + 1.5], R);
  }
  const GLYPH = {"?": ["?", "#3f6fd8"], "!": ["!", "#e0473a"], dots: ["…", "#2a1a2e"], coffee: ["☕", "#7a4a30"], check: ["✓", "#2f9a5a"], back: ["↩", "#3f6fd8"], zzz: ["z", "#5b6ad0"], bug: ["✗", "#8a5cf0"], wait: ["⏳", "#2a1a2e"]};
  function emote(o) {
    const G = GLYPH[o.kind] || GLYPH["!"];
    const markup = `<rect x="-9" y="-16" width="18" height="15" fill="#fffaf0" stroke="#2a1a2e" stroke-width="1.6"/><path d="M-3,-1 l3,5 l2,-5z" fill="#fffaf0" stroke="#2a1a2e" stroke-width="1.4" stroke-linejoin="round"/><text x="0" y="-4.5" font-family="x" font-size="11" text-anchor="middle" fill="${G[1]}">${G[0]}</text>`;
    return raster(markup, "", [-10.5, -17.5, 10.5, 5.5], o.R || 5);
  }
  function cloud(o) {
    const markup = `<rect x="-12" y="-6" width="24" height="9" fill="#5a5a6e" stroke="#2a1a2e" stroke-width="1.4"/><rect x="-6" y="-10" width="12" height="6" fill="#6a6a80" stroke="#2a1a2e" stroke-width="1.4"/><path d="M2,4 l-3,5 h4 l-2,5" stroke="#ff4a4a" stroke-width="2" fill="none"/>`;
    return raster(markup, "", [-13.5, -11.5, 13.5, 15], o.R || 5);
  }

  /* ---------- the campus (D22, D33, Spel+ D80): ops from the world kit onto layers and atlases ---------- */
  const K = window.WorldKit;
  /* ops onto one image over their own box (pad in art units); extra: [ops, alpha] drawn after, each through its own canvas */
  function opsImage(ops, R, box, extra = []) {
    box = box || K.opsBounds(ops, 1);
    const c = canvas((box[2] - box[0]) * R, (box[3] - box[1]) * R), g = c.getContext("2d");
    g.setTransform(R, 0, 0, R, -box[0] * R, -box[1] * R);
    K.draw(g, ops);
    for (const [more, alpha] of extra) {
      if (!more.length) continue;
      // shadows overlap: paint them solid on their own, then lay them down at once, see-through
      const o = canvas(c.width, c.height), og = o.getContext("2d");
      og.setTransform(R, 0, 0, R, -box[0] * R, -box[1] * R); K.draw(og, more);
      g.setTransform(1, 0, 0, 1, 0, 0); g.globalAlpha = alpha; g.drawImage(o, 0, 0); g.globalAlpha = 1;
      g.setTransform(R, 0, 0, R, -box[0] * R, -box[1] * R);
    }
    return {png: png(c), x: box[0], y: box[1], w: c.width / R, h: c.height / R};
  }
  /* objects of ops packed onto atlas pages, as atlas() does for scenes */
  function opsAtlas(objs, R, side = 4096) {
    const list = objs.filter(o => o.ops.length).map(o => { const b = K.opsBounds(o.ops); return {o, b, pw: Math.ceil((b[2] - b[0]) * R) + 2, ph: Math.ceil((b[3] - b[1]) * R) + 2}; })
      .filter(e => e.pw < side && e.ph < side);
    const pages = [];
    let page = null, x = 0, y = 0, shelf = 0;
    const open = () => { page = {w: 0, h: 0, items: []}; pages.push(page); x = 0; y = 0; shelf = 0; };
    open();
    for (const e of list.slice().sort((a, b) => b.ph - a.ph)) {
      if (x + e.pw > side) { x = 0; y += shelf; shelf = 0; }
      if (y + e.ph > side) open();
      e.page = pages.length - 1; e.px = x; e.py = y;
      x += e.pw; shelf = Math.max(shelf, e.ph);
      page.w = Math.max(page.w, e.px + e.pw); page.h = Math.max(page.h, e.py + e.ph); page.items.push(e);
    }
    const out = pages.filter(pg => pg.items.length).map(pg => {
      const c = canvas(pg.w, pg.h), g = c.getContext("2d");
      for (const e of pg.items) { g.setTransform(R, 0, 0, R, e.px + 1 - e.b[0] * R, e.py + 1 - e.b[1] * R); K.draw(g, e.o.ops); }
      return {png: png(c), w: c.width, h: c.height};
    });
    return {R, pages: out, items: list.map(e => ({id: e.o.id || null, key: e.o.key, alpha: e.o.alpha != null ? e.o.alpha : 1, page: e.page, px: e.px, py: e.py, pw: e.pw, ph: e.ph,
      x: e.b[0] - 1 / R, y: e.b[1] - 1 / R, w: e.pw / R, h: e.ph / R}))};
  }

  async function campus(input) {
    const R = input.R || 2, t0 = performance.now(), svg = scratch();
    const floors = list => list.map(f => ({name: String(f.name), wait: !!f.wait, kind: ["factory", "chats"].includes(f.kind) ? f.kind : "project", logo: /^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(f.logo || "") ? f.logo : null}));
    const c = W.campus(svg, {claude: floors(input.claude || []), chatgpt: floors(input.chatgpt || []), waiting: input.waiting || 0, quests: input.quests || [],
      engine: input.engine, racks: input.racks || [], night: !!input.night});
    const parts = c.parts, t1 = performance.now();
    // the island's underside is coarse rock: fewer pixels; the top with its kerbs and paving gets the full R
    const under = opsImage(parts.under, Math.max(1, R * .6));
    const ground = opsImage([...parts.base], R, null, [[parts.shadows, input.night ? .35 : .24], [parts.water, 1]]);
    // the buildings get more pixels than the rest: the camera comes close to them (the Provider and Server room levels)
    const isB = o => (o.id || "").startsWith("building:");
    const objects = opsAtlas(parts.objs.filter(o => !isB(o)), input.RO || 3);
    // a tower with many storeys is tall: its pixels go down so it still fits on one atlas page
    const tallest = Math.max(1, ...parts.objs.filter(isB).map(o => { const b = K.opsBounds(o.ops); return Math.max(b[2] - b[0], b[3] - b[1]); }));
    const buildings = opsAtlas(parts.objs.filter(isB), Math.min(input.RB || 8, 4000 / tallest));
    const light = opsImage(parts.light, 1, parts.view);
    const signs = await rasterParts(svg, parts.topParts, "", input.RS || 12);
    svg.remove();
    const t2 = performance.now();
    return {R, view: parts.view, island: parts.island, night: !!input.night, under, ground, objects, buildings, light, signParts: signs, boxes: parts.boxes, storeys: parts.storeys, fountain: parts.fountain, footprints: parts.footprints,
      racks: parts.racks, rackPanels: parts.rackPanels, beacon: parts.beacon, towers: parts.towers, npcs: parts.npcs || [], rackSpots: parts.rackSpots || [], labels: parts.labels, hits: parts.hits, streams: parts.streams,
      timing: [Math.round(t1 - t0), Math.round(t2 - t1)]};
  }

  /* ---------- Orbit (D6, D14, D42): bodies from the generator, one image per size and light ---------- */
  const LOOKS = new Map();
  function look(kind, id, opts) {
    const k = kind + "|" + id + "|" + JSON.stringify(opts || {});
    // the app sends every option as a string
    const o = Object.fromEntries(Object.entries(opts || {}).map(([a, v]) => [a, v === "true" ? true : v === "false" ? false : v]));
    if (!LOOKS.has(k)) LOOKS.set(k, OG[kind](id, o));
    return LOOKS.get(k);
  }
  /* what the layout needs before any image: the sizes, and where systems sit in a galaxy */
  function orbitLayout(input) {
    const galaxies = (input.galaxies || []).map(g => { const L = look("galaxy", g.id, {}); return {id: g.id, extent: L.extent, slots: Array.from({length: g.n}, (_, i) => L.slot(i))}; });
    const hole = look("blackHole", "engine-room", input.holeState ? {state: input.holeState} : {});
    const bodies = (input.bodies || []).map(b => { const L = look(b.kind, b.id, b.opts); return {scale: L.scale || 1, extent: L.extent || 1}; });
    /* what the app needs to turn galaxies and the black hole itself, as named point lists next to the galaxies' slots:
       "meta:<galaxy>" = [[pa°, incl], [sign of twist, E]]; "meta:hole" = [[pa°, sy], [inner, outer], [spin, 0]] */
    const meta = galaxies.map(g => { const L = look("galaxy", g.id, {}); return {id: "meta:" + g.id, extent: 0, slots: [[L.pa, L.incl], [Math.sign(L.twist) || 1, 1.1]]}; });
    meta.push({id: "meta:hole", extent: hole.extent, slots: [[hole.pa, hole.sy], [hole.inner, hole.outer], [hole.spin, 0]]});
    return {galaxies: [...galaxies, ...meta], hole: {extent: hole.extent, slots: Array.from({length: input.holeItems || 0}, (_, i) => hole.slot(i, input.holeItems))}, bodies};
  }
  /* one body at radius R (device pixels), lit from angle light; the image is w × h pixels round the body's centre.
     Options the app sends as strings: layer (a galaxy's "plane" or "static" part, the hole's "disk" table), tail and spin
     (numbers) go to the sprite; the rest picks the look. */
  const SPRITE_OPTS = {layer: v => v, tail: v => +v, spin: v => +v};
  function body(req) {
    const lookOpts = {}, o = {dpr: 1, mark: false};
    for (const [k, v] of Object.entries(req.opts || {})) { if (SPRITE_OPTS[k]) o[k] = SPRITE_OPTS[k](v); else lookOpts[k] = v; }
    const L = look(req.kind, req.id, lookOpts);
    if (req.light != null) o.light = req.light;
    if (req.kind === "blackHole" && o.layer === "disk") { const c = L.diskCanvas(); return {png: png(c), w: c.width, h: c.height}; }
    const s = L.sprite(req.R, o);
    return {png: png(s.canvas), w: s.w, h: s.h};
  }
  function sky(req) {
    const c = canvas(req.w, req.h), g = c.getContext("2d");
    OG.paintSky(g, req.w, req.h, req.seed || 77);
    return {png: c.toDataURL("image/jpeg", .9), w: c.width, h: c.height};
  }

  window.sf = {floor, figure, tag, board, emote, cloud, campus, orbitLayout, body, sky, ready: true};
})();
