/* Review sheets for the Orbit generator, in the Starfield style: warm grey space, monospace caps, hairlines.
   Shared by tools/orbit-gen.html and the PNG export for the design canvas. Every sheet returns {w, h, svg}.
   OrbitSheet.hero · big · world · galaxies · engine · wormholes (G, o); o.animate adds SMIL to markers, o.spin turns
   the hero planets. Browser only (the bodies are painted on canvases). Demo ids and titles only. */
(function () {
  const f = v => (+v).toFixed(1);
  const MONO = `font-family="'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, monospace"`;
  const C = {ink: "#ebe8e1", dim: "#9c988f", faint: "#5f5c56", tag: "#d6d3cb", yellow: "#ffd23f", red: "#ff6b6b", done: "#6f6c66", violet: "#b99cff"};
  const ROLES = ["dev", "designer", "tester", "devops", "pm", "researcher", "ceo", "sales", "marketing"];
  const ROLE_LABEL = {dev: "Developer", designer: "Designer", tester: "Tester", devops: "DevOps", pm: "Product", researcher: "Research", ceo: "CEO", sales: "Sales", marketing: "Marketing"};
  const STATE_COL = {working: C.dim, waiting: C.yellow, stuck: C.red, done: C.done};
  const STATE_LABEL = {working: "working", waiting: "waits on you", stuck: "stuck", done: "done"};
  const esc = t => String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const at = (x, y, s) => `<g transform="translate(${f(x)},${f(y)})">${s}</g>`;
  const text = (x, y, t, size = 10, fill = C.ink, weight = 500, anchor = "middle", ls = 1.2) => `<text x="${f(x)}" y="${f(y)}" text-anchor="${anchor}" ${MONO} font-size="${size}" font-weight="${weight}" letter-spacing="${ls}" fill="${fill}">${esc(String(t).toUpperCase())}</text>`;
  const label = (x, y, a, b, col = C.dim) => text(x, y, a, 10, C.tag, 500) + text(x, y + 15, b, 9, col, 400);
  // a section header like the survey HUD: caps title, a hairline, a quiet explanation
  const heading = (y, t, sub, w = 1200) => text(40, y, t, 15, C.ink, 700, "start", 2.6) + `<rect x="40" y="${f(y + 9)}" width="${w - 80}" height="1" fill="#ebe8e1" opacity=".13"/>` + text(40, y + 28, sub, 10, C.dim, 400, "start", 1);
  const stateOf = i => i % 9 === 4 ? "waiting" : i % 13 === 7 ? "stuck" : i % 7 === 5 ? "done" : "working";
  function find(G, prefix, pred) { for (let i = 1; i < 3000; i++) { const id = `${prefix}-${i}`; if (pred(G.planet(id))) return id; } return prefix + "-1"; }
  const heroIds = G => [find(G, "demo-hero", p => p.kind === "gas" && p.ring && p.storm), find(G, "demo-hero", p => p.kind === "jungle" && !p.ring),
    find(G, "demo-hero", p => p.kind === "lava" && !p.ring), find(G, "demo-hero", p => p.kind === "ice" && p.ring)];
  const LIGHT = -2.5;

  function hero(G, o = {}) {
    const w = 1200, h = 360, ids = heroIds(G);
    let s = o.noSky ? "" : G.skySVG(w, h, 3);
    ids.forEach((id, k) => { const p = G.planet(id), r = Math.min(88, 118 / p.extent); s += at(150 + k * 300, 165, p.svg(r, {spin: o.spin || 0, light: LIGHT, animate: o.animate})) + label(150 + k * 300, 320, `${p.kind} · ${p.palette}${p.ring ? " · ringed" : ""}`, id); });
    return {w, h, svg: s};
  }

  function big(G, o = {}) {
    const w = 1200, A = {animate: o.animate, light: LIGHT};
    let y = 0, s = "";
    if (o.hero !== false) { s += hero(G, {...o, noSky: true}).svg; y = 360; }
    s += heading(y + 40, "Sessions → planets", "40 demo sessions. The role leans the landscape; the id decides the rest, so a session always looks the same."); y += 80;
    for (let i = 0; i < 40; i++) {
      const id = `demo-session-${String(i + 1).padStart(2, "0")}`, role = ROLES[i % 9], st = stateOf(i), p = G.planet(id, {role, state: st});
      const cx = 75 + (i % 8) * 150, cy = y + 74 + Math.floor(i / 8) * 172, r = Math.min(30, 54 / p.extent);
      s += at(cx, cy, p.svg(r, A)) + label(cx, cy + 78, `${p.kind} · ${p.palette}`, `${ROLE_LABEL[role]} · ${STATE_LABEL[st]}`, STATE_COL[st]);
    }
    y += 5 * 172 + 20;
    s += heading(y + 40, "State reads as a hexagon", "Waits on you: a dashed yellow hexagon. Stuck: a red one with a flag. Done: the body dims. Selected (in the app): cyan."); y += 80;
    const picks = [find(G, "demo-state", p => p.kind === "rocky" && p.palette === "dust" && !p.ring), find(G, "demo-state", p => p.kind === "lava" && !p.ring)];
    ["working", "waiting", "stuck", "done"].forEach((st, k) => picks.forEach((id, j) => {
      const cx = 75 + (j * 4 + k) * 150, cy = y + 74, p = G.planet(id, {state: st});
      s += at(cx, cy, p.svg(Math.min(34, 52 / p.extent), {...A, state: st})) + label(cx, cy + 78, STATE_LABEL[st], `${p.kind} · ${p.palette}`, STATE_COL[st]);
    }));
    y += 200;
    s += heading(y + 40, "Projects → stars", "Class sets the colour, red dwarf to blue supergiant; granulation, spots, sometimes a companion. A quiet project dims; waiting gets the hexagon (D25)."); y += 80;
    for (let i = 0; i < 12; i++) {
      const id = `demo-project-${i + 1}`, st = i === 2 || i === 9 ? "waiting" : "working", act = i === 7 ? .15 : 1, p = G.star(id, {state: st, activity: act});
      const cx = 100 + (i % 6) * 200, cy = y + 84 + Math.floor(i / 6) * 200;
      s += at(cx, cy, p.svg(Math.min(22, 44 / p.scale), {...A, bloom: .5, streak: .42})) + label(cx, cy + 86, `${p.label} ${p.size}${p.companion ? " + companion" : ""}`, st === "waiting" ? "waits on you" : act < .5 ? "quiet" : "active", st === "waiting" ? C.yellow : C.dim);
    }
    y += 2 * 200 + 20;
    s += heading(y + 40, "Sub-agents → moons", "The sub-agent type picks the rock: Explore grey regolith, Plan ice, Review rust, Test sage, Build basalt with seams. A finished moon fades."); y += 80;
    const TYPES = ["Explore", "Plan", "general-purpose", "code-reviewer", "test-runner", "deploy-checker", "docs-researcher", "ui-designer"];
    TYPES.forEach((type, k) => [false, true].forEach((fin, j) => {
      const m = G.moon(`demo-agent-${k + 1}`, {type, finished: fin}), cx = 75 + k * 150, cy = y + 44 + j * 130;
      s += at(cx, cy, m.svg(24, A)) + label(cx, cy + 52, fin ? "finished" : m.label, fin ? "dimmed" : type, fin ? C.done : C.dim);
    }));
    y += 280;
    return {w, h: y, svg: G.skySVG(w, y, 7) + s};
  }

  const P = (G, id, role, st, rx, a, name, num, sub, moons = []) => ({look: G.planet(id, {role, state: st}), rx, a, r: 9, state: st, name, num, sub,
    moons: moons.map(([type, d, ma, fin], j) => ({look: G.moon(id + "-agent-" + (j + 1), {type, finished: fin}), d, a: ma, r: 2.6}))});
  const shopfront = (G, x, y, o = {}) => ({x, y, K: .46, star: G.star("demo-project-Shopfront", {state: "waiting"}), starR: o.starR || 15, starState: "waiting",
    starTag: {name: "SHOPFRONT · PROJECT", num: "★", numColor: "#6b5a2a", numInk: C.yellow, sub: "1 NEEDS YOU"},
    planets: [P(G, "demo-session-darkmode", "designer", "working", 80, .55, "Dark mode for settings", "I", "BUILDING · 62%"),
      P(G, "demo-session-flaky", "dev", "waiting", 120, 2.45, "Fix flaky checkout test", "II", "WAITS ON YOU", [["Explore", 20, 1.2, true], ["code-review", 27, 3.9]]),
      P(G, "demo-session-shipping", "marketing", "done", 160, 4.25, "Update shipping copy", "III", "DONE"),
      P(G, "demo-session-cart", "dev", "working", 200, 5.55, "Refactor cart totals", "IV", "TESTING · 40%", [["test-runner", 21, .4]]),
      P(G, "demo-session-preview", "devops", "stuck", 240, 1.25, "Deploy preview env", "V", "STUCK · HEALTH CHECK"),
      P(G, "demo-session-tax", "researcher", "working", 280, 3.05, "Research tax rules", "VI", "RESEARCH"),
      P(G, "demo-session-icons", "designer", "working", 320, 5.0, "Tidy icon set", "VII", "BUILDING · 15%")]});

  /* one solar system as the camera shows it, then the smallest sizes */
  function world(G, o = {}) {
    const w = 1200, h = 660, A = {animate: o.animate};
    let s = G.skySVG(w, h, 11);
    s += heading(44, "At world size", "One project as the camera shows it: planets about 9 px, moons 3 px, the sun 15 px. Right: the smallest sizes in every state.");
    s += G.systemSVG(shopfront(G, 440, 390), 860, 660, {t: 0, still: true});
    const x0 = 870;
    s += text(x0, 130, "Planets at 8 px", 10, C.tag, 600, "start");
    ["working", "waiting", "stuck", "done"].forEach((st, j) => {
      s += text(x0, 168 + j * 46, STATE_LABEL[st], 9, STATE_COL[st], 400, "start");
      for (let k = 0; k < 5; k++) { const p = G.planet(`demo-session-${String(k * 5 + j + 1).padStart(2, "0")}`, {role: ROLES[(k * 5 + j) % 9], state: st}); s += at(x0 + 110 + k * 46, 164 + j * 46, p.svg(8 / Math.max(1, p.scale * .9), {...A, light: LIGHT})); }
    });
    s += text(x0, 378, "Moons at 3 px", 10, C.tag, 600, "start");
    [false, true].forEach((fin, j) => {
      s += text(x0, 410 + j * 30, fin ? "finished" : "running", 9, fin ? C.done : C.dim, 400, "start");
      for (let k = 0; k < 8; k++) s += at(x0 + 110 + k * 26, 406 + j * 30, G.moon(`demo-agent-${k + 1}`, {type: Object.keys(G.MOON_TYPES)[k], finished: fin}).svg(3.4, {light: LIGHT}));
    });
    s += text(x0, 498, "Stars at 12 px", 10, C.tag, 600, "start");
    for (let k = 0; k < 5; k++) { const st = G.star(`demo-project-${k + 1}`, {state: k === 2 ? "waiting" : "working"}); s += at(x0 + 30 + k * 56, 560, st.svg(12 / Math.max(1, st.scale), {...A, bloom: .55, streak: .5})); }
    return {w, h, svg: s};
  }

  /* providers as galaxies, with their projects as stars on the arms */
  function galaxies(G, o = {}) {
    const w = 1200, A = {animate: o.animate};
    let y = 0, s = "";
    s += heading(y + 48, "Providers → galaxies", "One galaxy per provider. Claude and ChatGPT keep their colours; the id decides the shape. Projects sit on fixed slots on the arms (D15)."); y += 90;
    const HERO = [["claude", "Claude", [["Shopfront", "waiting"], ["Tide Notes"], ["Lighthouse"], ["Night Office", "stuck"], ["Garden Log"]]], ["chatgpt", "ChatGPT", [["Recipe Box", "waiting"], ["Harbor API"], ["Weather Kit"]]]];
    HERO.forEach(([pid, name, projects], k) => {
      const g = G.galaxy(pid), cx = 300 + k * 600, cy = y + 230, R = 200;
      s += at(cx, cy, g.svg(R, A));
      projects.forEach(([pn, st], i) => {
        const [sx, sy] = g.slot(i), x = cx + sx * R, yy = cy + sy * R, star = G.star("demo-project-" + pn, {state: st});
        s += at(x, yy, star.svg(3.4, {...A, bloom: .5, streak: .5})) + text(x + 14, yy + 3.5, pn, 9, st === "waiting" ? C.yellow : st === "stuck" ? C.red : C.tag, 500, "start");
      });
      s += text(cx, cy + 222, name, 13, g.color, 700, "middle", 2.4) + text(cx, cy + 240, `${g.shape}${g.arms ? ` · ${g.arms} arms` : ""} · demo projects`, 9, C.dim, 400);
    });
    y += 510;
    s += heading(y + 40, "Every id its own galaxy", "Spiral, barred, elliptical, ring and irregular, each with its own arms, tilt, dust lanes and star-forming knots."); y += 70;
    const want = {spiral: 3, barred: 3, elliptical: 2, ring: 2, irregular: 2}, ids = [];
    for (let n = 1; ids.length < 12 && n < 500; n++) { const g = G.galaxy(`demo-provider-${n}`); if (want[g.shape] > 0) { want[g.shape]--; ids.push(g.id); } }
    ids.forEach((id, i) => { const g = G.galaxy(id), cx = 100 + (i % 6) * 200, cy = y + 100 + Math.floor(i / 6) * 220; s += at(cx, cy, g.svg(80, A)) + label(cx, cy + 100, `${g.shape}${g.arms ? ` · ${g.arms} arms` : ""}`, id); });
    y += 2 * 220 + 20;
    s += heading(y + 30, "At the All level", "Every provider at once, at the size the camera shows them from furthest out."); y += 60;
    ["claude", "chatgpt", "demo-provider-3", "demo-provider-5", "demo-provider-8", "demo-provider-11"].forEach((id, i) => { const g = G.galaxy(id); s += at(100 + i * 200, y + 60, g.svg(30, A)) + text(100 + i * 200, y + 118, id === "claude" ? "Claude" : id === "chatgpt" ? "ChatGPT" : id, 9, id.startsWith("demo") ? C.dim : g.color, 600); });
    y += 150;
    return {w, h: y, svg: G.skySVG(w, y, 19) + s};
  }

  /* the Engine room: the black hole with its infra, the infra kinds, and where it sits */
  function engine(G, o = {}) {
    const w = 1200, A = {animate: o.animate};
    let y = 0, s = "";
    s += heading(y + 48, "Engine room → the black hole", "One supermassive black hole north of every galaxy, violet and always on (D26). Servers are pulsars, deploys comets, backups icy moonlets."); y += 90;
    const hx = 440, hy = y + 300, R = 58, hole = G.blackHole("engine-room", {state: "waiting"});
    const ITEMS = [["web-01", "server", "ok"], ["web-02", "server", "warning"], ["deploy · shopfront → prod", "deploy", "ok"], ["db-01", "server", "ok"], ["backup · nightly", "backup", "ok"], ["backup · offsite", "backup", "down"]];
    const bodies = [{y: hy, s: at(hx, hy, hole.svg(R, {...A, spin: o.spin || 0}))}];
    let orbits = "";
    [4.6, 5.8].forEach(d => { orbits += `<ellipse cx="${hx}" cy="${hy}" rx="${f(d * R)}" ry="${f(d * R * .42)}" transform="rotate(${f(hole.pa)} ${hx} ${hy})" fill="none" stroke="#ebe8e1" stroke-opacity=".12"/>`; });
    ITEMS.forEach(([name, kind, st], i) => {
      const [ux, uy] = hole.slot(i, ITEMS.length), x = hx + ux * R, yy = hy + uy * R, it = G.infra("demo-" + name, {kind, state: st});
      const lc = st === "warning" ? C.yellow : st === "down" ? C.red : C.tag, left = x < hx;
      bodies.push({y: yy, s: at(x, yy, it.svg(8, {...A, tail: Math.atan2(yy - hy, x - hx), light: Math.atan2(hy - yy, hx - x)})) + text(left ? x - 18 : x + 18, yy + 3, name, 9, lc, 500, left ? "end" : "start") + text(left ? x - 18 : x + 18, yy + 16, `${kind} · ${st}`, 8, C.dim, 400, left ? "end" : "start")});
    });
    s += orbits + bodies.sort((a, b) => a.y - b.y).map(b => b.s).join("") + text(hx, hy + 205, "Engine room", 12, C.violet, 700, "middle", 2.4) + text(hx, hy + 222, "servers · deploys · backups · one warning", 9, C.dim, 400);
    const x0 = 860;
    s += text(x0, y + 40, "Infra in every state", 10, C.tag, 600, "start");
    ["ok", "warning", "down"].forEach((st, j) => s += text(x0 + 80 + j * 90, y + 70, st, 9, st === "warning" ? C.yellow : st === "down" ? C.red : C.dim, 400));
    ["server", "deploy", "backup"].forEach((kind, i) => {
      s += text(x0, y + 126 + i * 110, kind, 10, C.tag, 600, "start") + text(x0, y + 141 + i * 110, kind === "server" ? "pulsar" : kind === "deploy" ? "comet" : "moonlet", 8, C.dim, 400, "start");
      ["ok", "warning", "down"].forEach((st, j) => s += at(x0 + 80 + j * 90, y + 130 + i * 110, G.infra(`demo-${kind}-${j}`, {kind, state: st}).svg(11, {...A, tail: -2.4, light: LIGHT})));
    });
    y += 560;
    s += heading(y + 40, "At the All level", "The black hole sits north of every galaxy, where the Engine room stands on the campus. It never belongs to a provider."); y += 70;
    s += at(600, y + 60, G.blackHole("engine-room", {state: "waiting"}).svg(11, A)) + text(600, y + 112, "Engine room · 1 warning", 9, C.violet, 600);
    [["claude", "Claude", 330], ["chatgpt", "ChatGPT", 870]].forEach(([id, name, x]) => { const g = G.galaxy(id); s += at(x, y + 230, g.svg(75, A)) + text(x, y + 330, name, 10, g.color, 700, "middle", 2); });
    y += 360;
    return {w, h: y, svg: G.skySVG(w, y, 23) + s};
  }

  /* one project at two providers: the same sun twice, joined by a wormhole (D16) */
  function wormholes(G, o = {}) {
    const w = 1200, A = {animate: o.animate}, CL = "#e8916b", GPT = "#6fd3b8", GEM = "#8ab4ff";
    let y = 0, s = "";
    s += heading(y + 48, "One project, two providers → a wormhole", "The same project at Claude and ChatGPT is a system in each galaxy with the same sun, joined by a wormhole (D16). Each mouth shows the other end's sky."); y += 90;
    const wh = G.wormhole("demo-project-Shopfront", {colors: [CL, GPT]});
    const sys = (x, prefix, states) => ({x, y: y + 270, K: .46, star: G.star("demo-project-Shopfront"), starR: 14, starTag: {name: "SHOPFRONT", num: "★", numColor: "#6b5a2a", numInk: C.yellow, sub: prefix === "a" ? "IN CLAUDE" : "IN CHATGPT"},
      planets: [[72, .6, "I"], [112, 2.7, "II"], [152, 4.5, "III"]].map(([rx, a, num], i) => ({...P(G, `demo-wh-${prefix}-${i + 1}`, ["dev", "tester", "designer"][i], states[i], rx, a + (prefix === "b" ? 2.6 : 0), null, num, null)}))});
    s += G.systemSVG(sys(250, "a", ["waiting", "working", "done"]), 600, 520, {t: 0, still: true});
    s += `<g transform="translate(600,0)">${G.systemSVG(sys(350, "b", ["working", "working", "working"]), 600, 520, {t: 0, still: true})}</g>`;
    const m1 = [425, y + 140], m2 = [775, y + 140];
    s += wh.link(m1[0], m1[1], m2[0], m2[1], A) + at(m1[0], m1[1], wh.svg(22, {...A, side: 0})) + at(m2[0], m2[1], wh.svg(22, {...A, side: 1}));
    s += text(600, y + 62, "wormhole · same git root", 9, C.dim, 500);
    y += 440;
    s += heading(y + 40, "Every project its own mouth", "The id sets the far sky you see through the mouth; the provider pair sets the colours. State reads as the same hexagon as everywhere else."); y += 70;
    const V = [["demo-project-2", [CL, GPT], "working", "Claude · ChatGPT"], ["demo-project-3", [CL, GEM], "working", "Claude · Gemini"], ["demo-project-4", [GPT, GEM], "working", "ChatGPT · Gemini"], ["demo-project-5", [CL, GPT], "waiting", "waits on you"], ["demo-project-6", [CL, GPT], "stuck", "stuck"], ["demo-project-7", [CL, GPT], "done", "done"]];
    V.forEach(([id, cols, st, lab], i) => { const cx = 100 + i * 200, cy = y + 85; s += at(cx, cy, G.wormhole(id, {colors: cols, state: st}).svg(24, {...A, side: i % 2})) + label(cx, cy + 82, lab, id, STATE_COL[st]); });
    y += 210;
    s += heading(y + 40, "At the All level", "Seen from furthest out, the wormhole is a thin bridge between the two galaxies, under the Engine room."); y += 70;
    const gA = G.galaxy("claude"), gB = G.galaxy("chatgpt"), ax = 300, bx = 900, gy = y + 200, GR = 120, sun = G.star("demo-project-Shopfront");
    s += at(600, y + 30, G.blackHole("engine-room").svg(8, A)) + at(ax, gy, gA.svg(GR, A)) + at(bx, gy, gB.svg(GR, A));
    const [sa1, sa2] = gA.slot(0), [sb1, sb2] = gB.slot(0), p1 = [ax + sa1 * GR, gy + sa2 * GR], p2 = [bx + sb1 * GR, gy + sb2 * GR];
    s += wh.link(p1[0], p1[1], p2[0], p2[1], A) + at(p1[0], p1[1], sun.svg(3.4, {bloom: .5, streak: .5}) + `<g transform="translate(14,-10)">${wh.svg(5, {side: 0})}</g>`) + at(p2[0], p2[1], sun.svg(3.4, {bloom: .5, streak: .5}) + `<g transform="translate(-14,-10)">${wh.svg(5, {side: 1})}</g>`);
    s += text(ax, gy + 150, "Claude", 10, CL, 700, "middle", 2) + text(bx, gy + 150, "ChatGPT", 10, GPT, 700, "middle", 2) + text(600, gy - 84, "Shopfront", 9, C.tag, 600);
    y += 380;
    return {w, h: y, svg: G.skySVG(w, y, 29) + s};
  }

  window.OrbitSheet = {hero, big, world, galaxies, engine, wormholes, shopfront};
})();
