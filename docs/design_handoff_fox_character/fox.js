// fox.js — the fox character: physics controller + two interchangeable visuals
// (A) billboard sprite from the uploaded illustration, (B) a low-poly chibi fox model.
// Toggle with fox.setStyle('billboard' | 'model').

class FoxCharacter {
  constructor(scene) {
    this.root = new THREE.Group();
    scene.add(this.root);

    // physics
    this.pos = new THREE.Vector3(0, 4, 0);
    this.vel = new THREE.Vector3();
    this.onGround = false;
    this.jumps = 0;            // jumps used since leaving ground
    this.facing = 0;           // yaw the model faces
    this.height = 2.3;
    this.radius = 0.6;
    this.lastSafe = this.pos.clone();
    this.ray = new THREE.Raycaster();
    this.down = new THREE.Vector3(0, -1, 0);

    // tunables
    this.gravity = 30;
    this.moveSpeed = 9.5;
    this.accel = 70;
    this.jumpV = 13.5;
    this.doubleJumpV = 12.5;

    // anim state
    this.walkPhase = 0;
    this.squash = 1;       // current vertical squash factor (1 = neutral)
    this.targetSquash = 1;
    this.speed01 = 0;      // 0..1 horizontal speed for anim blending

    this.style = 'model';
    this._buildBillboard();
    this._buildModel();
    this.setStyle('model');
  }

  // ── visual A: billboard ────────────────────────────────────────
  _buildBillboard() {
    this.billboard = new THREE.Group();
    const tex = new THREE.TextureLoader().load(FoxCharacter.BILLBOARD_SRC || 'uploads/fox-cutout.png');
    tex.colorSpace = THREE.SRGBColorSpace !== undefined ? THREE.SRGBColorSpace : tex.colorSpace;
    tex.anisotropy = 8;
    const aspect = 433 / 780;
    const h = 2.7, w = h * aspect;
    const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, alphaTest: 0.35, side: THREE.DoubleSide });
    this.bbMat = mat;
    const plane = new THREE.Mesh(new THREE.PlaneGeometry(w, h), mat);
    plane.position.y = h / 2;
    this.bbPlane = plane;
    this.billboard.add(plane);
    // soft contact shadow blob
    const blob = new THREE.Mesh(new THREE.CircleGeometry(0.85, 20),
      new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.22 }));
    blob.rotation.x = -Math.PI / 2; blob.position.y = 0.02;
    this.bbBlob = blob;
    this.billboard.add(blob);
    this.root.add(this.billboard);
  }

  // procedurally painted iris texture: limbal ring, radiating fibers,
  // warm-to-bright radial gradient and a soft inner glow around the pupil
  // clean, illustration-style cartoon eye painted on a transparent canvas:
  // dark almond outline, smooth amber iris, big pupil, crisp catchlights.
  // Rendered UNLIT so it always reads like the artwork regardless of scene light.
  _eyeTexture() {
    const S = 256, cv = document.createElement('canvas'); cv.width = cv.height = S;
    const x = cv.getContext('2d'), c = S / 2;
    const ellipse = (cx, cy, rx, ry, rot) => { x.beginPath(); x.ellipse(cx, cy, rx, ry, rot || 0, 0, 7); x.fill(); };

    // 1) soft dark outline — rounder, friendlier almond
    x.fillStyle = '#2a1608';
    ellipse(c, c, S * 0.37, S * 0.45);

    // 2) big amber iris, vivid vertical gradient (deep top → glowing bottom)
    const ig = x.createLinearGradient(0, S * 0.1, 0, S * 0.92);
    ig.addColorStop(0, '#9a4e08');
    ig.addColorStop(0.4, '#ef9d1f');
    ig.addColorStop(0.78, '#ffc740');
    ig.addColorStop(1, '#ffe98c');
    x.fillStyle = ig;
    ellipse(c, c + S * 0.01, S * 0.315, S * 0.4);

    // 3) glow ring just inside the rim (bottom brighter) for a jewel-like look
    x.save(); x.beginPath(); x.ellipse(c, c + S * 0.01, S * 0.315, S * 0.4, 0, 0, 7); x.clip();
    const rg = x.createRadialGradient(c, c + S * 0.14, S * 0.05, c, c + S * 0.1, S * 0.42);
    rg.addColorStop(0, 'rgba(255,236,170,0.0)');
    rg.addColorStop(0.7, 'rgba(255,225,140,0.0)');
    rg.addColorStop(1, 'rgba(255,240,180,0.7)');
    x.fillStyle = rg; x.fillRect(0, 0, S, S);
    // lid shadow across the top
    const sg = x.createLinearGradient(0, S * 0.08, 0, S * 0.46);
    sg.addColorStop(0, 'rgba(70,32,4,0.6)'); sg.addColorStop(1, 'rgba(70,32,4,0)');
    x.fillStyle = sg; x.fillRect(0, 0, S, S); x.restore();

    // 4) big round pupil
    x.fillStyle = '#1c0d05';
    ellipse(c, c + S * 0.04, S * 0.165, S * 0.235);

    // 5) warm reflected-light crescent at the bottom of the pupil
    x.save(); x.beginPath(); x.ellipse(c, c + S * 0.04, S * 0.165, S * 0.235, 0, 0, 7); x.clip();
    x.strokeStyle = 'rgba(255,206,110,0.95)'; x.lineWidth = S * 0.035;
    x.beginPath(); x.ellipse(c, c + S * 0.07, S * 0.13, S * 0.19, 0, Math.PI * 0.12, Math.PI * 0.88); x.stroke();
    x.restore();

    // 6) cute catchlights — one BIG glossy shine top-left, a soft round one
    //    bottom-right, and a little four-point sparkle up top
    x.fillStyle = '#ffffff';
    ellipse(c - S * 0.085, c - S * 0.14, S * 0.105, S * 0.125);          // big shine
    x.fillStyle = 'rgba(255,255,255,0.95)';
    ellipse(c + S * 0.085, c + S * 0.105, S * 0.05, S * 0.058);          // lower soft shine
    // sparkle (4-point star)
    const star = (cx, cy, r) => {
      x.fillStyle = '#fffaf0'; x.save(); x.translate(cx, cy);
      x.beginPath();
      for (let i = 0; i < 4; i++) {
        const a = i * Math.PI / 2;
        x.lineTo(Math.cos(a) * r, Math.sin(a) * r);
        x.lineTo(Math.cos(a + Math.PI / 4) * r * 0.32, Math.sin(a + Math.PI / 4) * r * 0.32);
      }
      x.closePath(); x.fill(); x.restore();
    };
    star(c + S * 0.04, c - S * 0.235, S * 0.055);
    star(c - S * 0.165, c + S * 0.05, S * 0.03);

    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace !== undefined ? THREE.SRGBColorSpace : tex.colorSpace;
    tex.anisotropy = 8;
    return tex;
  }

  // toon ramp for a soft cel-painted look like the illustration
  _toonGradient() {
    const steps = [88, 150, 212, 255];
    const data = new Uint8Array(steps.length * 4);
    for (let i = 0; i < steps.length; i++) { data[i*4]=steps[i]; data[i*4+1]=steps[i]; data[i*4+2]=steps[i]; data[i*4+3]=255; }
    const tex = new THREE.DataTexture(data, steps.length, 1, THREE.RGBAFormat);
    tex.minFilter = THREE.NearestFilter; tex.magFilter = THREE.NearestFilter;
    tex.generateMipmaps = false; tex.needsUpdate = true;
    return tex;
  }

  // ── visual B: detailed chibi fox tuned closely to the illustration ──
  _buildModel() {
    const grad = this._toonGradient();
    const MT = (c, o) => new THREE.MeshToonMaterial(Object.assign({ color: c, gradientMap: grad }, o || {}));
    const BASIC = (c) => new THREE.MeshBasicMaterial({ color: c });
    // palette sampled from the artwork (vivid, warm orange)
    const ORANGE = 0xf3762a, ORANGE_D = 0xdd5e18, ORANGE_L = 0xfba85a,
          EAR_EDGE = 0xbf4a18, EAR_TIP = 0x8a4622;
    const CREAM = 0xfce8c8, WHITE = 0xfff6e9, PEACH2 = 0xfcc07e,
          NOSE = 0x2a1810, RED = 0xe83a26, RED_D = 0xc62a1f,
          AMBER = 0xf6a821, AMBER_HI = 0xfcd76a, EYE_RIM = 0x281307,
          PAD = 0xf2a0a6, FEET = 0x6e4a2e;
    const g = new THREE.Group();
    this.model = g;
    this.limbs = { ears: [], arms: [] };
    this.earBaseX = -0.06;

    // soft rounded fur tuft (capsule = rounded ends, no sharp spikes)
    const fur = (parent, x, y, z, rad, len, color, rx, ry, rz) => {
      const m = new THREE.Mesh(new THREE.CapsuleGeometry(rad * 0.82, Math.max(0.02, len * 0.6), 3, 8), MT(color));
      m.position.set(x, y, z); m.rotation.set(rx || 0, ry || 0, rz || 0); m.castShadow = true;
      parent.add(m); return m;
    };
    // sprinkle a soft coat of rounded fur lobes over a spherical region
    const furCoat = (parent, cx, cy, cz, R, count, colors, opts) => {
      const o = opts || {};
      for (let i = 0; i < count; i++) {
        const u = Math.random() * Math.PI * 2, v = (o.vMin || 0) + Math.random() * ((o.vMax || 1) - (o.vMin || 0));
        const ph = Math.acos(1 - 2 * v);
        const nx = Math.sin(ph) * Math.cos(u), ny = Math.cos(ph), nz = Math.sin(ph) * Math.sin(u);
        if (o.zMax !== undefined && nz > o.zMax) continue;   // skip front-facing fur
        const len = (o.len || 0.34) * (0.7 + Math.random() * 0.5);
        const m = new THREE.Mesh(new THREE.CapsuleGeometry((o.rad || 0.09) * (0.75 + Math.random() * 0.5), len * 0.55, 3, 8),
          MT(colors[(Math.random() * colors.length) | 0]));
        m.position.set(cx + nx * R, cy + ny * R * (o.sy || 1), cz + nz * R);
        // orient cone to point outward
        m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3(nx, ny, nz).normalize());
        m.castShadow = true;
        parent.add(m);
      }
    };

    // ── tiny hind feet peeking out at the bottom ──
    for (const sx of [-1, 1]) {
      const foot = new THREE.Mesh(new THREE.SphereGeometry(0.17, 12, 10), MT(FEET));
      foot.scale.set(1, 0.7, 1.35); foot.position.set(0.22 * sx, 0.12, 0.18); foot.castShadow = true;
      g.add(foot);
    }

    // ── plump body, orange back + huge fluffy white chest ──
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.78, 20, 18), MT(ORANGE));
    body.scale.set(0.96, 1.02, 0.92); body.position.y = 0.84; body.castShadow = true;
    g.add(body);
    const saddle = new THREE.Mesh(new THREE.SphereGeometry(0.7, 18, 16), MT(ORANGE_D));
    saddle.scale.set(0.9, 0.78, 0.86); saddle.position.set(0, 1.04, -0.12); g.add(saddle);
    const chest = new THREE.Mesh(new THREE.SphereGeometry(0.66, 20, 18), MT(WHITE));
    chest.scale.set(0.96, 1.18, 0.72); chest.position.set(0, 0.8, 0.34); chest.castShadow = true; g.add(chest);
    // smooth lower-chest lobe to keep the front full & rounded
    const chestLow = new THREE.Mesh(new THREE.SphereGeometry(0.46, 18, 16), MT(WHITE));
    chestLow.scale.set(1.02, 1.0, 0.78); chestLow.position.set(0, 0.5, 0.34); g.add(chestLow);
    // ── red neckerchief ──
    const band = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.64, 0.28, 20, 1, true), MT(RED, { side: THREE.DoubleSide }));
    band.position.y = 1.4; band.rotation.x = 0.08; g.add(band);
    const knot = new THREE.Mesh(new THREE.SphereGeometry(0.14, 10, 8), MT(RED)); knot.position.set(0.12, 1.28, 0.5); g.add(knot);
    for (const s of [-1, 1]) {
      const end = new THREE.Mesh(new THREE.ConeGeometry(0.13, 0.5, 6), MT(s < 0 ? RED : RED_D));
      end.position.set(0.12 + s * 0.06, 1.05, 0.5); end.rotation.x = 0.6; end.rotation.z = 0.3 * s; g.add(end);
    }

    // ── head (big) ──
    const head = new THREE.Group(); head.position.y = 1.82; g.add(head); this.limbs.head = head;
    const skull = new THREE.Mesh(new THREE.SphereGeometry(0.72, 20, 18), MT(ORANGE));
    skull.scale.set(1.05, 1.0, 0.95); skull.castShadow = true; head.add(skull);
    // lighter forehead blaze + brow marks like the art
    const blaze = new THREE.Mesh(new THREE.SphereGeometry(0.3, 14, 12), MT(ORANGE_L));
    blaze.scale.set(0.42, 0.7, 0.18); blaze.position.set(0, 0.22, 0.6); head.add(blaze);
    for (const sx of [-1, 1]) {
      const brow = new THREE.Mesh(new THREE.SphereGeometry(0.12, 10, 8), MT(ORANGE_L));
      brow.scale.set(1.3, 0.55, 0.3); brow.position.set(0.26 * sx, 0.3, 0.56); brow.rotation.z = -0.3 * sx; head.add(brow);
    }
    // cream cheeks / lower face (kept low so orange frames the face like a fox)
    const face = new THREE.Mesh(new THREE.SphereGeometry(0.56, 18, 16), MT(WHITE));
    face.scale.set(0.98, 0.66, 0.74); face.position.set(0, -0.3, 0.3); head.add(face);
    // white cheek puffs beside the muzzle
    for (const sx of [-1, 1]) {
      const cp = new THREE.Mesh(new THREE.SphereGeometry(0.27, 14, 12), MT(WHITE));
      cp.scale.set(0.85, 0.78, 0.72); cp.position.set(0.33 * sx, -0.2, 0.42); head.add(cp);
    }
    // muzzle + nose + big happy open smile with tongue
    const muzzle = new THREE.Mesh(new THREE.SphereGeometry(0.26, 14, 12), MT(WHITE));
    muzzle.scale.set(1, 0.82, 1.12); muzzle.position.set(0, -0.2, 0.56); head.add(muzzle);
    const nose = new THREE.Mesh(new THREE.SphereGeometry(0.12, 12, 10), MT(NOSE));
    nose.scale.set(1.3, 0.92, 1); nose.position.set(0, -0.12, 0.8); head.add(nose);
    // gentle closed smile — a soft upturned curve below the nose
    const smile = new THREE.Mesh(new THREE.TorusGeometry(0.11, 0.02, 8, 20, Math.PI * 0.95), MT(0x4a2412));
    smile.position.set(0, -0.28, 0.72); smile.rotation.z = Math.PI + Math.PI * 0.025; head.add(smile);
    // tiny nose-to-lip line
    const philtrum = new THREE.Mesh(new THREE.CapsuleGeometry(0.012, 0.08, 2, 6), MT(0x6a3a22));
    philtrum.position.set(0, -0.2, 0.78); head.add(philtrum);
    // glossy highlight on the nose
    const noseHi = new THREE.Mesh(new THREE.SphereGeometry(0.035, 8, 8), BASIC(0xece2dc));
    noseHi.position.set(-0.04, -0.07, 0.9); head.add(noseHi);
    // soft pink cheek blush
    for (const sx of [-1, 1]) {
      const blush = new THREE.Mesh(new THREE.CircleGeometry(0.13, 16),
        new THREE.MeshBasicMaterial({ color: 0xff9a86, transparent: true, opacity: 0.4 }));
      blush.position.set(0.42 * sx, -0.18, 0.52); blush.rotation.y = -0.5 * sx; head.add(blush);
    }
    // whiskers — thin pale strands sweeping out & back from the muzzle
    for (const sx of [-1, 1]) {
      for (let k = 0; k < 3; k++) {
        const wh = new THREE.Mesh(new THREE.CylinderGeometry(0.005, 0.012, 0.55, 4),
          new THREE.MeshBasicMaterial({ color: 0xfdf3ea, transparent: true, opacity: 0.7 }));
        const grp = new THREE.Group();
        grp.position.set(0.26 * sx, -0.18 - k * 0.05, 0.6);
        grp.rotation.y = (-0.5 - k * 0.12) * sx;   // sweep back
        grp.rotation.z = (0.12 - k * 0.12);          // slight up/down fan
        wh.rotation.z = Math.PI / 2;                 // lay horizontal
        wh.position.x = 0.28 * sx;                    // extend outward from the pivot
        grp.add(wh); head.add(grp);
      }
    }

    // ── clean illustration-style eyes: flat textured almonds, unlit ──
    const eyeTex = this._eyeTexture();
    this.eyes = [];
    for (const sx of [-1, 1]) {
      const eye = new THREE.Group();
      eye.position.set(0.255 * sx, 0.03, 0.6);
      eye.rotation.set(0.02, 0.1 * sx, 0);   // gentle outward tilt to sit on the rounded face
      head.add(eye); this.eyes.push(eye);

      // the eye itself — a gently convex dome so it nestles into the rounded
      // face (edges tuck under the skull → no floating gap). Unlit cartoon texture.
      const plate = new THREE.Group(); eye.add(plate); eye.userData.plate = plate;
      const dome = new THREE.PlaneGeometry(0.34, 0.44, 14, 14);
      { const p = dome.attributes.position, rx = 0.17, ry = 0.22, depth = 0.12;
        for (let i = 0; i < p.count; i++) {
          const nx = p.getX(i) / rx, ny = p.getY(i) / ry;
          p.setZ(i, Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny)) * depth);
        }
        p.needsUpdate = true; dome.computeVertexNormals();
      }
      const face = new THREE.Mesh(dome,
        new THREE.MeshBasicMaterial({ map: eyeTex, transparent: true, alphaTest: 0.5, depthWrite: true }));
      plate.add(face);
      // faint warm glow halo behind the eye for a lively, polished sparkle
      const glow = new THREE.Mesh(new THREE.CircleGeometry(0.22, 20),
        new THREE.MeshBasicMaterial({ color: 0xffcf6a, transparent: true, opacity: 0.22, blending: THREE.AdditiveBlending, depthWrite: false }));
      glow.position.z = -0.02; eye.add(glow);
    }
    // (cheeks kept smooth — fur strands removed)

    // ── huge tall ears: rusty edge, orange, peach + white inner, dark tip ──
    for (const sx of [-1, 1]) {
      const ear = new THREE.Group(); ear.position.set(0.36 * sx, 0.52, -0.02);
      const edge = new THREE.Mesh(new THREE.ConeGeometry(0.5, 1.75, 9), MT(EAR_EDGE));
      edge.scale.set(1, 1, 0.36); edge.position.y = 0.72; edge.castShadow = true; ear.add(edge);
      const outer = new THREE.Mesh(new THREE.ConeGeometry(0.42, 1.62, 9), MT(ORANGE));
      outer.scale.set(1, 1, 0.36); outer.position.set(0, 0.68, 0.05); ear.add(outer);
      const innerP = new THREE.Mesh(new THREE.ConeGeometry(0.3, 1.25, 9), MT(PEACH2));
      innerP.scale.set(1, 1, 0.36); innerP.position.set(0, 0.6, 0.1); ear.add(innerP);
      const innerW = new THREE.Mesh(new THREE.ConeGeometry(0.18, 0.95, 9), MT(WHITE));
      innerW.scale.set(1, 1, 0.36); innerW.position.set(0, 0.52, 0.14); ear.add(innerW);
      const tip = new THREE.Mesh(new THREE.ConeGeometry(0.2, 0.42, 9), MT(EAR_TIP));
      tip.scale.set(1, 1, 0.4); tip.position.y = 1.42; ear.add(tip);
      ear.rotation.z = -0.2 * sx; ear.rotation.x = this.earBaseX;
      head.add(ear); this.limbs.ears.push(ear);
    }

    // ── both front paws rest down naturally at the sides ──
    const rArm = new THREE.Group(); rArm.position.set(-0.44, 1.08, 0.36); g.add(rArm); this.raisedArm = rArm;
    const rUpper = new THREE.Mesh(new THREE.CapsuleGeometry(0.15, 0.42, 4, 8), MT(ORANGE));
    rUpper.position.y = -0.2; rArm.add(rUpper);
    const rPaw = new THREE.Mesh(new THREE.SphereGeometry(0.18, 14, 12), MT(WHITE));
    rPaw.scale.set(1.05, 0.92, 1.1); rPaw.position.set(0, -0.46, 0.06); rArm.add(rPaw);
    rArm.rotation.x = 0.18; rArm.rotation.z = 0.08;
    this.raisedFore = null;

    // ── resting front paw on the ground in front ──
    const lArm = new THREE.Group(); lArm.position.set(0.4, 1.05, 0.34); g.add(lArm); this.restArm = lArm;
    const lUpper = new THREE.Mesh(new THREE.CapsuleGeometry(0.15, 0.42, 4, 8), MT(ORANGE));
    lUpper.position.y = -0.2; lArm.add(lUpper);
    const lPaw = new THREE.Mesh(new THREE.SphereGeometry(0.19, 14, 12), MT(WHITE));
    lPaw.scale.set(1.1, 0.9, 1.1); lPaw.position.set(0, -0.44, 0.08); lArm.add(lPaw);
    lArm.rotation.x = 0.25;

    // ── ENORMOUS bushy tail curling up & around to the side (front-visible) ──
    const tail = new THREE.Group(); tail.position.set(0.12, 0.55, -0.5); tail.scale.setScalar(0.86); this.limbs.tail = tail;
    const segs = 14;
    for (let i = 0; i < segs; i++) {
      const tt = i / (segs - 1);
      const ang = tt * 2.7;
      const rad = tt > 0.84 ? Math.max(0.14, 0.6 - (tt - 0.84) * 2.0) : 0.32 + Math.sin(tt * Math.PI) * 0.5;
      const col = tt > 0.82 ? WHITE : (tt > 0.66 ? CREAM : ORANGE);
      // sweep: rise up behind the back, then curl up & over to the +x side
      const px = Math.sin(tt * Math.PI * 0.9) * 0.85 * tt;
      const py = Math.sin(ang) * 2.1 * tt;
      const pz = -0.36 - Math.cos(ang) * 1.0 * tt;
      const s = new THREE.Mesh(new THREE.SphereGeometry(rad, 16, 14), MT(col));
      s.castShadow = true; s.position.set(px, py, pz); tail.add(s);
      // cream underside lobe
      if (tt > 0.2 && tt < 0.8) {
        const u = new THREE.Mesh(new THREE.SphereGeometry(rad * 0.62, 14, 12), MT(tt > 0.55 ? WHITE : CREAM));
        u.position.set(px, py - rad * 0.5, pz + rad * 0.35); tail.add(u);
      }
    }
    g.add(tail);

    this.root.add(g);
  }

  setStyle(style) {
    this.style = style;
    if (this.billboard) this.billboard.visible = (style === 'billboard');
    if (this.model) this.model.visible = (style === 'model');
  }

  respawn() {
    this.pos.copy(this.lastSafe);
    this.pos.y += 1.5;
    this.vel.set(0, 0, 0);
  }

  // ── per-frame update ───────────────────────────────────────────
  update(dt, input, camYaw, scene) {
    // camera-relative movement basis
    const fwd = new THREE.Vector3(Math.sin(camYaw), 0, Math.cos(camYaw));
    const right = new THREE.Vector3(fwd.z, 0, -fwd.x);
    const wish = new THREE.Vector3()
      .addScaledVector(fwd, -input.y)   // input.y: -1 forward (away from camera)
      .addScaledVector(right, input.x);
    const wishLen = wish.length();
    if (wishLen > 1) wish.normalize();

    // horizontal accel toward wish*speed
    const targetVX = wish.x * this.moveSpeed;
    const targetVZ = wish.z * this.moveSpeed;
    const a = this.onGround ? this.accel : this.accel * 0.45;
    this.vel.x += (targetVX - this.vel.x) * Math.min(1, a * dt / this.moveSpeed);
    this.vel.z += (targetVZ - this.vel.z) * Math.min(1, a * dt / this.moveSpeed);

    // jump
    if (input.jumpPressed) {
      if (this.onGround) { this.vel.y = this.jumpV; this.onGround = false; this.jumps = 1; this.targetSquash = 1.25; }
      else if (this.jumps < 2) { this.vel.y = this.doubleJumpV; this.jumps = 2; this.targetSquash = 1.3; this._spinFlip = 1; }
    }

    // gravity
    this.vel.y -= this.gravity * dt;
    if (this.vel.y < -32) this.vel.y = -32;

    // integrate
    this.pos.x += this.vel.x * dt;
    this.pos.y += this.vel.y * dt;
    this.pos.z += this.vel.z * dt;

    // ground collision via downward ray against island tops
    const wasAir = !this.onGround;
    this.onGround = false;
    const origin = new THREE.Vector3(this.pos.x, this.pos.y + 1.2, this.pos.z);
    this.ray.set(origin, this.down);
    this.ray.far = 1.6 + Math.max(0, -this.vel.y) * dt + 0.4;
    const hits = this.ray.intersectObjects(World.colliders, false);
    if (hits.length && this.vel.y <= 0.001) {
      const gy = hits[0].point.y;
      if (this.pos.y <= gy + 0.05) {
        this.pos.y = gy;
        this.vel.y = 0;
        this.onGround = true;
        this.jumps = 0;
        if (wasAir) this.targetSquash = 0.7; // land squash
        this.lastSafe.copy(this.pos);
      }
    }

    // fell off the world
    if (this.pos.y < -25) this.respawn();

    // facing — turn toward horizontal velocity
    const hv = Math.hypot(this.vel.x, this.vel.z);
    this.speed01 = Math.min(1, hv / this.moveSpeed);
    if (hv > 0.6) {
      const targetFacing = Math.atan2(this.vel.x, this.vel.z);
      let d = targetFacing - this.facing;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      this.facing += d * Math.min(1, dt * 12);
    }

    this.root.position.copy(this.pos);
    this._animate(dt, camYaw);
  }

  _animate(dt, camYaw) {
    // squash/stretch easing back to neutral
    this.squash += (this.targetSquash - this.squash) * Math.min(1, dt * 14);
    this.targetSquash += (1 - this.targetSquash) * Math.min(1, dt * 6);

    if (this.style === 'model' && this.model) {
      const g = this.model;
      const t = performance.now() / 1000;
      g.rotation.y = this.facing;
      const sq = this.squash;
      g.scale.set(1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq));

      this.walkPhase += dt * (6 + this.speed01 * 10);
      const sw = Math.sin(this.walkPhase);
      const amp = this.speed01;
      // bouncy hop while moving + idle breathing
      const hop = this.onGround ? Math.abs(Math.sin(this.walkPhase)) * amp * 0.14 : 0;
      const idleBob = (1 - amp) * Math.sin(t * 2.5) * 0.04;
      g.position.y = hop + idleBob;
      // front paws swing gently with the walk
      if (this.raisedArm) {
        this.raisedArm.rotation.x = 0.18 - sw * 0.5 * amp;
      }
      if (this.restArm) {
        this.restArm.rotation.x = 0.25 + sw * 0.5 * amp;
      }
      if (this.restArm) {
        this.restArm.rotation.x = 0.25 + amp * sw * 0.2;
      }
      // tail sway (big and bouncy)
      if (this.limbs.tail) {
        this.limbs.tail.rotation.z = Math.sin(t * 2.6 + this.walkPhase * 0.4) * 0.16;
        this.limbs.tail.rotation.x = Math.sin(t * 2) * 0.07 + (this.onGround ? 0 : 0.2) + amp * 0.1;
        this.limbs.tail.rotation.y = Math.sin(t * 1.8) * 0.08;
      }
      // ears wiggle
      if (this.limbs.ears && this.limbs.ears.length) {
        this.limbs.ears[0].rotation.x = this.earBaseX + Math.sin(t * 4) * 0.05 + (this.onGround ? 0 : -0.16);
        this.limbs.ears[1].rotation.x = this.earBaseX + Math.sin(t * 4 + 1) * 0.05 + (this.onGround ? 0 : -0.16);
      }
      // head bob
      if (this.limbs.head) {
        this.limbs.head.rotation.x = -this.speed01 * 0.06 + Math.sin(t * 2) * 0.025;
        this.limbs.head.rotation.z = Math.sin(t * 1.6) * 0.02;
      }
      // occasional blink — squash the eye plates vertically for a moment
      if (this.eyes) {
        if (this._nextBlink === undefined) this._nextBlink = t + 2 + Math.random() * 3;
        let bl = 1;
        if (t > this._nextBlink) {
          const p = (t - this._nextBlink) / 0.12;        // blink lasts ~0.12s
          if (p >= 1) { this._nextBlink = t + 2.5 + Math.random() * 3.5; }
          else { bl = 1 - Math.sin(p * Math.PI); }        // 1→0→1
        }
        for (const e of this.eyes) {
          const plate = e.userData.plate;
          if (plate) plate.scale.y = 0.08 + 0.92 * bl;
        }
      }
    } else if (this.style === 'billboard' && this.billboard) {
      // face camera (cylindrical billboard)
      const dx = camYaw; // camera direction yaw; plane faces +z by default
      this.billboard.rotation.y = camYaw;
      // flip based on screen-space horizontal movement
      const right = new THREE.Vector3(Math.cos(camYaw), 0, -Math.sin(camYaw));
      const screenX = this.vel.x * right.x + this.vel.z * right.z;
      if (Math.abs(screenX) > 0.4) this._faceRight = screenX > 0;
      const sq = this.squash;
      const baseW = this._faceRight ? 1 : -1;
      this.bbPlane.scale.set(baseW / Math.sqrt(sq), sq, 1);
      // hop bob while moving
      const t = performance.now() / 1000;
      const hop = this.onGround ? Math.abs(Math.sin(t * 9)) * this.speed01 * 0.12 : 0;
      this.bbPlane.position.y = (2.7 / 2) + hop;
      // shadow blob scales with height off ground handled in main via shadow; keep simple
      this.bbBlob.rotation.y = -camYaw;
    }
  }
}

window.FoxCharacter = FoxCharacter;
