// Behavioural checks of fpn_3d_viewer.html in headless Chromium (needs the playwright package).
// Run: node tests/viewer/verify_3d.js   (exit code 1 on any failure)
const { chromium } = require('playwright');
const fails = [];
const check = (ok, msg) => { console.log((ok ? 'ok   ' : 'FAIL ') + msg); if (!ok) fails.push(msg); };
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const pg = await b.newPage({ viewport: { width: 1100, height: 700 } });
  const errs = [];
  pg.on('pageerror', e => errs.push(e.message));
  pg.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  await pg.goto('file://' + require('path').resolve(__dirname, '../../fpn_3d_viewer.html') + '?autoplay=0');
  await pg.waitForFunction(() => window.viewer, null, { timeout: 30000 });

  const r = await pg.evaluate(() => {
    const v = window.viewer, out = {};
    v.load('Stand', 'm'); v.seek(0);
    const A = v.world('A', 'head'), Bh = v.world('B', 'head'), An = v.world('A', 'nose'), Bn = v.world('B', 'nose');
    out.facing = (An[0] - A[0]) * (Bh[0] - A[0]) > 0 && (Bn[0] - Bh[0]) * (A[0] - Bh[0]) > 0;
    // A faces +X, so A's left is -Z; orthodox lead (left) foot is ahead of the rear foot.
    const lT = v.world('A', 'lToe'), rT = v.world('A', 'rToe');
    out.leftSide = v.world('A', 'lFist')[2] < v.world('A', 'rFist')[2] && lT[2] < rT[2];
    out.leadAhead = lT[0] > rT[0];
    out.headHeight = v.world('A', 'head')[1];
    // Every frame of every action: no foot under the floor, planted feet on it, nothing NaN.
    const all = Object.keys(v.ACTIONS).join(' > ');
    out.worst = {};
    for (const d of ['c', 's', 'm', 'l', 'v']) {
      v.load(all, d);
      let minSole = 9, nan = false, maxPlanted = 0;
      for (let t = 0; t <= v.timeline.dur; t += 0.02) {
        v.seek(t);
        for (const w of ['A', 'B']) {
          const s = v.soles(w);
          if (s.some(x => !Number.isFinite(x))) nan = true;
          minSole = Math.min(minSole, ...s);
          const p = v.fighters[w].pose;
          for (const [f, h, tt] of [['lFoot', 'lHeel', 'lToe'], ['rFoot', 'rHeel', 'rToe']])
            if (p[f] && p[f].lift < 0.005) maxPlanted = Math.max(maxPlanted, Math.abs(v.world(w, h)[1]), Math.abs(v.world(w, tt)[1]));
        }
      }
      out.worst[d] = { minSole: +minSole.toFixed(3), nan, maxPlanted: +maxPlanted.toFixed(3) };
    }
    // Strikes land at their range.
    const reachAt = { m: 'Jab > Cross > Hook > Haymaker > BodyHook > FingerJab > Counter > GroinKick',
      l: 'Teep > RoundKick > LowKick > ObliqueKick', s: 'Elbow > Knee > Headbutt > Stomp' };
    out.miss = {};
    for (const [d, seq] of Object.entries(reachAt)) { v.load(seq, d); for (const e of v.resolveAll()) out.miss[e.action + '@' + d] = +(e.miss * 100).toFixed(1); }
    // Out of range, a jab misses.
    v.load('Jab', 'v'); out.jabOut = v.resolveAll()[0].miss;
    // A slip takes the head off the line.
    v.load('Jab / Slip', 'm'); out.slipMiss = v.resolveAll()[0].miss;
    // MPN round trip.
    v.load('Hook', 'm'); v.seek(v.timeline.events[0].t);
    const s1 = v.sceneMPN(); v.loadScene(s1); out.mpn1 = s1; out.mpn2 = v.sceneMPN();
    // Legacy MPN still loads.
    try { v.loadScene('0,0.0,0,0.20,5,20,5.90,90.10,0,-5,0.15,15.40,90/0,0.0,0,0.20,5,20,5.90,90.-10,0,5,0.15,15.40,90/m'); out.legacy = v.soles('A').every(x => Math.abs(x) < 0.02) || v.soles('A').some(x => Math.abs(x) < 0.002); }
    catch (e) { out.legacy = 'error ' + e.message; }
    // Southpaw mirrors: lead foot is the right one.
    v.state.stance.B = 'southpaw'; v.load('Jab', 'm'); v.seek(0);
    const bl = v.world('B', 'lToe'), br = v.world('B', 'rToe');
    out.southpawLead = br[0] < bl[0];   // B faces -X: the lead foot has the smaller x
    out.southpawJab = v.resolveAll()[0].miss;
    v.state.stance.B = 'orthodox';
    return out;
  });
  check(r.facing, 'fighters face each other');
  check(r.leftSide, "left limbs are on the fighter's left");
  check(r.leadAhead, 'orthodox lead foot is forward');
  check(r.headHeight > 1.5 && r.headHeight < 1.75, `head height ${r.headHeight.toFixed(2)} m`);
  for (const [d, w] of Object.entries(r.worst)) {
    check(!w.nan, `no NaN at range ${d}`);
    check(w.minSole > -0.025, `no sole under the floor at range ${d} (min ${w.minSole})`);
    check(w.maxPlanted < 0.02, `planted feet stay on the floor at range ${d} (max ${w.maxPlanted})`);
  }
  for (const [k, m] of Object.entries(r.miss)) check(m < 6, `${k} lands (${m} cm)`);
  check(r.jabOut > 0.3, `jab from out of range misses (${r.jabOut.toFixed(2)} m)`);
  check(r.slipMiss > 0.09, `slip makes the jab miss (${(r.slipMiss * 100).toFixed(0)} cm)`);
  check(r.mpn1 === r.mpn2, `MPN round trip (${r.mpn1})`);
  check(r.legacy === true, `legacy MPN loads (${r.legacy})`);
  check(r.southpawLead, 'southpaw leads with the right foot');
  check(r.southpawJab < 0.06, `southpaw is still hit by the jab (${(r.southpawJab * 100).toFixed(1)} cm)`);
  // Playback in real time fires events and logs results.
  await pg.evaluate(() => { const v = window.viewer; v.load('Jab > Cross', 'm'); v.state.t = 0; v.play(); });
  await pg.waitForTimeout(2500);
  const log = await pg.evaluate(() => window.viewer.log());
  check(log.some(l => l.includes('lands')), `playback logs hits: ${JSON.stringify(log)}`);
  // UI: example button and phone layout.
  await pg.click('#examples button:nth-child(4)');
  await pg.setViewportSize({ width: 390, height: 800 });
  await pg.waitForTimeout(300);
  const overflow = await pg.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check(overflow <= 0, `no horizontal scroll on a phone (${overflow}px)`);
  check(errs.length === 0, `no page errors ${JSON.stringify(errs)}`);
  await b.close();
  console.log(fails.length ? `${fails.length} FAILED` : 'all passed');
  process.exit(fails.length ? 1 : 0);
})();
