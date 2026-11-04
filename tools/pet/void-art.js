'use strict';
/*
    XPLedger - Nihil, the Void hatchling companion (pixel art).

    A round, deep violet little Void creature with starry specks inside, two
    tiny horns, big shiny eyes, wispy tendril arms and three tendrils instead
    of legs. It plays the very same poses as the murloc (ANIMATIONS of
    murloc-art.js) and fills the same sheet rows.
*/

const M = require('./murloc-art');

const { SIZE, PAD, Canvas, ellipse, line, stamp, stampCentered, roundShade, mouthRows } = M;

// Colors on top of the murloc palette (same letters, so the shared stamps and
// props work unchanged).
const PALETTE = Object.assign({}, M.PALETTE, {
    K: [24, 12, 46, 255],    // outline
    G: [106, 70, 184, 255],  // body
    g: [68, 40, 130, 255],   // body shade
    h: [152, 118, 228, 255], // body highlight
    P: [16, 8, 30, 255],     // eyes
    q: [226, 120, 200, 255], // cheeks
    M: [52, 14, 60, 255],    // mouth
    e: [126, 236, 255, 255], // starry specks (Void glow)
    // Rage form only: the same Void, darker.
    V: [62, 36, 116, 255],   // body
    v: [40, 22, 80, 255],    // body shade
    u: [88, 58, 156, 255],   // body highlight, glint of the eyes
    s: [110, 86, 176, 255],  // faint specks
    d: [26, 12, 50, 255],    // smoke and claws, almost black
});

const VOID = {
    cx: 16,
    cy: 18,
    rx: 8.4,
    ry: 7.6,
    horns: { dx: 4.2, dy: -5.5, tipDx: 6, tipY: -10.5, base: 2, tip: 1.1 },
    eyes: { x: 10, dy: -4 },
    mouth: { dy: 2, width: 6 },
    cheeks: { x: 8, dy: 1 },
    arm: { dx: 7, dy: 0.5, base: 2.4, tip: 1.5, reach: 0.7 },
    tendrils: { xs: [-4, 0, 4], top: 5, bottom: 29.6, base: 2.5, tip: 1.4 },
    weapon: { length: 9, tip: 'e' },
    shadow: 7,
};

// A Void hatchling's arms float a bit further out than a murloc's.
const ARMS = Object.assign({}, M.ARMS, {
    down: [-3, 2.5],
    rest: [-2.5, 4],
});

// Big dark eyes with a shine (lit from the top left on both eyes).
const EYES = {
    open: ['.PP.', 'PWPP', 'PPPP', 'PPPP', '.PP.'],
    down: ['....', '.PP.', 'PWPP', 'PPPP', '.PP.'],
    wide: ['.PP.', 'PWPP', 'PWPP', 'PPPP', 'PPPP', '.PP.'],
    happy: ['....', '.KK.', 'K..K', '....'],
    closed: ['....', '....', 'K..K', '.KK.'],
    angry: ['K...', '.PPP', 'PWPP', 'PPPP', '.PP.'],
    sad: ['...K', '.PP.', 'PWPP', 'PPPP', '.PP.'],
    x: ['K..K', '.KK.', '.KK.', 'K..K'],
    spiral: ['.KK.', 'KWKK', 'KKWK', '.KK.'],
};
EYES.look = EYES.open;
const UNMIRRORED_EYES = { open: true, look: true, down: true, wide: true, spiral: true };
const EYE_SHIFT = { look: -1 };

// Starry specks inside the body, relative to its centre.
const SPECKS = [[-5, 3], [5, 4], [6, -2], [1, -6]];

/** A capsule whose radius shrinks from r1 at (x1, y1) to r2 at (x2, y2). */
function taper(canvas, x1, y1, r1, x2, y2, r2, color) {
    const reach = Math.max(r1, r2) + 1;
    const lx = x2 - x1;
    const ly = y2 - y1;
    const length2 = lx * lx + ly * ly || 1;
    for (let y = Math.floor(Math.min(y1, y2) - reach); y <= Math.ceil(Math.max(y1, y2) + reach); y++) {
        for (let x = Math.floor(Math.min(x1, x2) - reach); x <= Math.ceil(Math.max(x1, x2) + reach); x++) {
            const px = x + 0.5;
            const py = y + 0.5;
            const t = Math.max(0, Math.min(1, ((px - x1) * lx + (py - y1) * ly) / length2));
            const dx = px - (x1 + lx * t);
            const dy = py - (y1 + ly * t);
            const radius = r1 + (r2 - r1) * t;
            if (dx * dx + dy * dy <= radius * radius) {
                canvas.set(x, y, color);
            }
        }
    }
}

/** Mouth rows: the murloc's shapes, smaller; at rest a tiny smile. */
function voidMouth(type) {
    if (type === 'closed') {
        return ['K..K', '.KK.'];
    }
    return mouthRows(type, VOID.mouth.width, false);
}

/** Sideways sway of each tendril tip for a pose. */
function tendrilSway(pose) {
    if (pose.tail !== undefined) {
        const phase = [-1.5, 0, 1.5, 0][pose.tail % 4];
        return [phase, -phase, phase];
    }
    switch (pose.legs) {
        case 'kick1':
            return [-1.5, 1, -1];
        case 'kick2':
            return [1, -1, 1.5];
        case 'sit':
            return [-3, 0, 3];
        default:
            return [-1, 0, 1];
    }
}

function drawFigure(S, pose) {
    const lift = (pose.squash ? 1 : 0) + (pose.slump || 0);
    const cx = S.cx;
    const cy = S.cy + lift;
    const figure = new Canvas(PAD);
    const layer = (draw, shade = true) => {
        const canvas = new Canvas(PAD);
        draw(canvas);
        if (shade) {
            canvas.autoshade();
        }
        figure.draw(canvas.outline());
    };
    const headTop = { x: cx, y: cy - S.ry };

    // Tendril arms. One that stays outside is part of the silhouette; one
    // that crosses the body is thinner and gets its own contour.
    const hand = (name, side) => {
        const [ox, oy] = ARMS[name];
        const sx = cx + side * S.arm.dx;
        const sy = cy + S.arm.dy;
        const hx = sx - side * ox * S.arm.reach;
        const hy = sy + oy * S.arm.reach;
        const crosses = side * (hx + 0.5 - cx) < S.rx - 1.5;
        return {
            bx: cx + side * (S.rx - 1.5), by: sy, hx, hy, crosses,
            base: crosses ? 2 : S.arm.base,
        };
    };
    const left = hand((pose.arms && pose.arms[0]) || 'down', -1);
    const right = hand((pose.arms && pose.arms[1]) || 'down', 1);
    const drawArm = (c, arm) => taper(c, arm.bx, arm.by, arm.base, arm.hx, arm.hy, Math.min(arm.base, S.arm.tip), 'G');

    // Body: round belly-head, horns, tendrils and the arms outside.
    layer((c) => {
        [-1, 1].forEach((side) => {
            const H = S.horns;
            taper(c, cx + side * H.dx, cy + H.dy, H.base, cx + side * H.tipDx, cy + H.tipY, H.tip, 'G');
        });
        const sway = tendrilSway(pose);
        const T = S.tendrils;
        T.xs.forEach((ox, i) => {
            const bottom = pose.legs === 'sit' ? T.bottom - 1 : T.bottom;
            const length = i === 1 ? 0 : 0.6; // the middle one hangs a bit lower
            taper(c, cx + ox, cy + T.top, T.base, cx + ox * 1.15 + sway[i], bottom - length, T.tip, 'G');
        });
        [left, right].forEach((arm) => {
            if (!arm.crosses) {
                drawArm(c, arm);
            }
        });
        ellipse(c, cx, cy, S.rx, S.ry, roundShade('G', 'g', 'h'));
    });

    // Starry specks: the Void shining through.
    SPECKS.forEach(([ox, oy]) => {
        const x = Math.round(cx + ox);
        const y = Math.round(cy + oy);
        if (figure.get(x, y) === 'G' || figure.get(x, y) === 'g') {
            figure.set(x, y, 'e');
        }
    });

    // Face.
    const eyesName = pose.eyes || 'open';
    const eyes = EYES[eyesName];
    const eyesY = Math.round(cy + S.eyes.dy);
    const shift = EYE_SHIFT[eyesName] || 0;
    stamp(figure, eyes, S.eyes.x + shift, eyesY);
    stamp(figure, eyes, SIZE - S.eyes.x - eyes[0].length + shift, eyesY, !UNMIRRORED_EYES[eyesName]);
    const cheekY = Math.round(cy + S.cheeks.dy);
    stamp(figure, ['qq'], S.cheeks.x, cheekY);
    stamp(figure, ['qq'], SIZE - S.cheeks.x - 2, cheekY);
    const mouth = voidMouth(pose.mouth || 'closed');
    stamp(figure, mouth, Math.round(16 - mouth[0].length / 2), Math.round(cy + S.mouth.dy));

    if (pose.hat) {
        layer((c) => stamp(c, M.PARTY_HAT, 14, Math.round(headTop.y) - 5), false);
    }
    if (pose.sweat) {
        layer((c) => stamp(c, M.PROPS.sweat, cx + S.rx - 2, cy - S.ry + 2), false);
    }
    if (pose.stars !== undefined) {
        const spots = pose.stars ? [[-7, -1], [0, -4], [7, -1]] : [[-4, -3], [4, -3]];
        layer((c) => spots.forEach(([ox, oy]) => stampCentered(c, M.PROPS.star, headTop.x + ox, headTop.y + oy)), false);
    }
    if (pose.juggle !== undefined) {
        layer((c) => M.juggleFish(pose.juggle).forEach(([ox, oy], i) => {
            stampCentered(c, M.PROPS.fishSide, headTop.x + ox, headTop.y + oy - 1, i % 2 === 1);
        }), false);
    }

    // What the right hand holds: a little Void orb staff when fighting.
    if (pose.weapon) {
        const W = S.weapon;
        layer((c) => {
            const topX = right.hx + 2;
            const topY = right.hy - W.length + 4;
            line(c, right.hx + 0.5, right.hy + 3, topX, topY, 'w');
            stamp(c, ['.' + W.tip + '.', W.tip + W.tip + W.tip, '.' + W.tip + '.'],
                Math.round(topX) - 1, Math.round(topY) - 3);
        }, false);
    }
    if (pose.prop === 'rod') {
        const tipX = right.hx + 5;
        const rodTop = right.hy - 12;
        layer((c) => line(c, right.hx, right.hy + 3, tipX, rodTop, 'w'), false);
        if (pose.bobber) {
            line(figure, tipX + 1, rodTop + 1, tipX + 1, pose.bobber - 1, 'L');
            layer((c) => stamp(c, M.PROPS.bobber, tipX + 1, pose.bobber), false);
        }
    } else if (pose.prop === 'mug') {
        layer((c) => stamp(c, M.PROPS.mug, right.hx - 1, right.hy - 3), false);
    } else if (pose.prop) {
        const rows = M.PROPS[pose.prop];
        layer((c) => stamp(c, rows, right.hx - 1, right.hy - rows.length + 1), false);
    }

    // Arms in front of the body.
    [left, right].forEach((arm) => {
        if (arm.crosses) {
            layer((c) => drawArm(c, arm));
        }
    });

    return figure;
}

function compose(pose) {
    const S = VOID;
    const out = new Canvas();
    let figure = drawFigure(S, pose);
    const shadow = pose.noShadow ? 0 : S.shadow * ((pose.dy || 0) < 0 ? 0.7 : 1);
    if (pose.shear) {
        figure = figure.sheared(pose.shear);
    }
    if (shadow > 0) {
        ellipse(out, 16 + (pose.dx || 0), 30.8, shadow, 1.2, 'z');
    }
    out.draw(figure, pose.dx || 0, pose.dy || 0);
    return out;
}

//------------------------------------------------------------------------------
// Rage form: what Nihil turns into for a few seconds when it is clicked once
// too often. A hulking Void horror twice its size (64x64 frames, drawn at the
// same pixel size), all black and deep violet and almost symmetric: a smoke
// tail instead of tendrils, dark spikes on huge shoulders, long arms with
// claws, a small sunken head with Nihil's horns grown long, empty eyes with a
// faint violet glint, no mouth, and a hole of pure Void in its chest.
//------------------------------------------------------------------------------

const RAGE_SIZE = SIZE * 2;
const RAGE_PAD = 4;

// Elbow and hand of each arm pose, left side (the right one mirrors it).
const RAGE_ARMS = {
    down: { elbow: [10, 37], hand: [9, 48] },
    up: { elbow: [7, 23], hand: [9, 11] },
    out: { elbow: [7, 31], hand: [10, 42] },
};

// The four frames (sheet order): hunched as it appears, the roar, and the
// menacing sway it loops on (only the smoke moves).
const RAGE = [
    { arms: 'down', hunch: 2, tail: 0 },
    { arms: 'up', hunch: 0, tail: 1 },
    { arms: 'out', hunch: 0, tail: 2 },
    { arms: 'out', hunch: 0, tail: 3 },
];

// Faint specks on the torso, relative to the chest (mirrored).
const RAGE_SPECKS = [[-11, -4], [-7, 6], [-14, 1], [-5, -8]];

// Left eye (the right one mirrors it): empty, with a faint glint, narrowed
// by a frown.
const RAGE_EYE = ['KK....', '.KKK..', 'PsPPKK', 'PPPPPP', '.PPPP.'];

/** Three dark claws at the end of an arm, pointing away from the elbow. */
function claws(c, elbow, hand) {
    const dx = hand[0] - elbow[0];
    const dy = hand[1] - elbow[1];
    const length = Math.hypot(dx, dy) || 1;
    const ux = dx / length;
    const uy = dy / length;
    [-0.55, 0, 0.55].forEach((spread) => {
        const ax = ux * Math.cos(spread) - uy * Math.sin(spread);
        const ay = ux * Math.sin(spread) + uy * Math.cos(spread);
        taper(c, hand[0] + ax * 2, hand[1] + ay * 2, 1.4, hand[0] + ax * 7, hand[1] + ay * 7, 0.5, 'd');
    });
}

function composeRage(frame) {
    const out = new Canvas(0, RAGE_SIZE);
    const figure = new Canvas(RAGE_PAD, RAGE_SIZE);
    const layer = (draw, base = 'V', dark = 'v', light = 'u') => {
        const canvas = new Canvas(RAGE_PAD, RAGE_SIZE);
        draw(canvas);
        canvas.autoshade(base, dark, light);
        figure.draw(canvas.outline());
    };
    const shade = roundShade('V', 'v', 'u');
    const cx = 32;
    const chestY = 33 + frame.hunch;
    const shoulderY = chestY - 7;
    const headY = chestY - 13 + frame.hunch;

    // Smoke tail swirling up from a pool of Void on the ground.
    const sway = [-2, 0, 2, 0][frame.tail % 4];
    layer((c) => {
        ellipse(c, cx, 59.5, 12, 3, 'v');
        taper(c, cx + sway, 57, 3, cx - sway * 0.5, chestY + 9, 7, 'v');
        [[-5, 52, 2.4], [5, 52, 2.4], [-6, 46, 2.2], [6, 46, 2.2], [-10, 57, 2], [10, 57, 2]].forEach(([ox, y, r], i) => {
            ellipse(c, cx + ox + (i % 2 ? -sway : sway) * 0.5, y, r, r * 0.8, 'v');
        });
    }, 'v', 'd', 'V');

    // Dark spikes behind the shoulders.
    const spikes = [[-17, -3, -27, -16], [-12, -6, -16, -20], [-6, -7, -5, -16]];
    layer((c) => spikes.forEach(([x1, y1, x2, y2]) => [-1, 1].forEach((side) => {
        taper(c, cx + side * x1, shoulderY + y1, 2.6, cx + side * x2, shoulderY + y2, 0.6, 'v');
    })), 'v', 'd', 'V');

    // Hulking torso, huge shoulders and long arms in one layer (no seams).
    const pose = RAGE_ARMS[frame.arms];
    const arms = [-1, 1].map((side) => {
        const at = ([x, y]) => [side < 0 ? x : RAGE_SIZE - x, y + frame.hunch];
        return { shoulder: [cx + side * 13, shoulderY], elbow: at(pose.elbow), hand: at(pose.hand) };
    });
    layer((c) => {
        arms.forEach(({ shoulder, elbow, hand }) => {
            taper(c, shoulder[0], shoulder[1], 5.5, elbow[0], elbow[1], 3.6, 'V');
            taper(c, elbow[0], elbow[1], 3.6, hand[0], hand[1], 2.6, 'V');
            ellipse(c, hand[0], hand[1], 3.2, 3, 'V');
        });
        ellipse(c, cx, chestY - 1, 15, 9.5, shade);
        taper(c, cx, chestY + 4, 10, cx, chestY + 11, 6.5, 'V');
        [-1, 1].forEach((side) => ellipse(c, cx + side * 13, shoulderY, 8.5, 7, shade));
    });
    layer((c) => arms.forEach(({ elbow, hand }) => claws(c, elbow, hand)), 'd', 'P', 'v');

    // Small sunken head with Nihil's horns, grown long and curved.
    layer((c) => [-1, 1].forEach((side) => {
        taper(c, cx + side * 5, headY - 4, 2.4, cx + side * 10, headY - 11, 1.6, 'V');
        taper(c, cx + side * 10, headY - 11, 1.6, cx + side * 10, headY - 18, 0.6, 'V');
    }));
    layer((c) => ellipse(c, cx, headY, 9, 7, shade));

    // A hole of pure Void in the chest, with faint stars inside.
    ellipse(figure, cx, chestY + 1, 5.4, 4.6, 'K');
    ellipse(figure, cx, chestY + 1, 4.4, 3.6, 'P');
    [[-2, 0], [2, 2], [1, -1]].forEach(([ox, oy]) => figure.set(cx + ox, chestY + 1 + oy, 's'));

    // Faint specks, mirrored.
    RAGE_SPECKS.forEach(([ox, oy]) => [-1, 1].forEach((side) => {
        const x = Math.round(cx + side * ox - (side > 0 ? 1 : 0));
        const y = Math.round(chestY + oy);
        if (['V', 'v', 'u'].includes(figure.get(x, y))) {
            figure.set(x, y, 's');
        }
    }));

    // Empty eyes. No mouth.
    const eyeY = headY - 3;
    stamp(figure, RAGE_EYE, cx - 8, eyeY);
    stamp(figure, RAGE_EYE, cx + 2, eyeY, true);

    ellipse(out, cx, 61.5, 14, 1.8, 'z');
    out.draw(figure);
    return out;
}

//------------------------------------------------------------------------------
// Collapse: the way into the rage form (and back out of it). Nihil curls up
// and is crushed into a dense ball of Void, which then bursts open like a
// tiny big bang. Ordinary 32x32 frames: the addon shrinks them while they
// play, then swaps to the rage form as it expands.
//------------------------------------------------------------------------------

// Centre of the ball in the cell (the addon spreads its particles from there).
const BALL = { x: 16, y: 18 };

const COLLAPSE = [
    { stage: 0 }, // Nihil, fed up, clenching its fists
    { stage: 1 }, // curled up into an angry ball
    { stage: 2 }, // darkening as it is crushed
    { stage: 3 }, // a dense orb of Void, about to burst
];

function composeCollapse(frame) {
    if (frame.stage === 0) {
        return compose({ eyes: 'angry', mouth: 'frown', arms: ['fist', 'fist'], squash: true });
    }
    const out = new Canvas();
    const ball = new Canvas(PAD);
    const radius = [0, 8, 7, 6][frame.stage];
    if (frame.stage === 1) {
        // Still itself: body colours, frowning, horns tucked in.
        ellipse(ball, BALL.x, BALL.y, radius, radius, roundShade('G', 'g', 'h'));
        [-1, 1].forEach((side) => taper(ball, BALL.x + side * 3, BALL.y - 6, 1.6, BALL.x + side * 5, BALL.y - 9, 0.8, 'G'));
        ball.outline();
        const eye = ['K...', '.PPP', 'PPPP', '.PP.'];
        stamp(ball, eye, BALL.x - 5, BALL.y - 3);
        stamp(ball, eye, BALL.x + 1, BALL.y - 3, true);
    } else {
        // Crushed into Void: a dark core with a violet rim and a few specks.
        ellipse(ball, BALL.x, BALL.y, radius, radius, (nx, ny) => {
            const d = Math.hypot(nx, ny);
            if (d > 0.82) {
                return nx * 0.5 + ny * 0.85 > 0.4 ? 'g' : 'G';
            }
            return d > 0.55 || frame.stage === 2 ? 'v' : 'P';
        });
        ball.outline();
        const specks = frame.stage === 2 ? [[-3, -2], [2, 3], [3, -3]] : [[-2, -1], [1, 2]];
        specks.forEach(([ox, oy]) => ball.set(BALL.x + ox, BALL.y + oy, 's'));
    }
    ellipse(out, 16, 30.8, radius * 0.8, 1.1, 'z');
    out.draw(ball);
    return out;
}

module.exports = { PALETTE, compose, RAGE, RAGE_SIZE, composeRage, COLLAPSE, composeCollapse };
