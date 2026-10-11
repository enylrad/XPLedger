'use strict';
/*
    XPLedger - Murloc companion pixel art.

    Every frame is composed from simple shapes (shaded ellipses and capsules)
    plus a few hand drawn stamps (eyes, fins, hats, props). Each part is drawn
    on its own layer and outlined before being stacked, which gives the dark
    contour between overlapping parts (arm over body, head over body...).

    The figure is drawn on a padded canvas, so it can be moved, sheared or
    sheared (staggering) before being cropped into its 32x32 cell.

    Sheet layout (one sheet per growth stage, 32x32 cells, 4 columns x 32 rows):
       0 idle      1 happy     2 party     3 fight     4 swim      5 sleep
       6 victory   7 relief    8 dead      9 ghost    10 revive   11 panic
      12 rest     13 dance    14 wave     15 fish     16 eat      17 yawn
      18 juggle   19 scratch  20 excited  21 jump     22-30 unused
    Row 31 holds the 8x8 effect icons (ICONS, 4 per row of the cell).
    The Lua side (UI/Pet/Sprite.lua) must use the same row order.
*/

const SIZE = 32;
const PAD = 10; // room around the cell while composing a figure

// Palette: one character per color, '.' is transparent.
const PALETTE = {
    K: [24, 38, 31, 255],    // outline
    G: [95, 174, 78, 255],   // skin
    g: [58, 124, 62, 255],   // skin shade
    h: [146, 212, 106, 255], // skin highlight
    B: [222, 222, 160, 255], // belly
    b: [184, 190, 120, 255], // belly shade
    W: [246, 246, 232, 255], // eye white
    P: [20, 20, 24, 255],    // pupil
    R: [228, 104, 62, 255],  // fins
    r: [176, 66, 42, 255],   // fin spines
    M: [112, 30, 44, 255],   // mouth
    T: [255, 255, 255, 255], // teeth
    S: [190, 198, 210, 255], // steel
    s: [118, 128, 142, 255], // steel shade
    w: [140, 92, 46, 255],   // wood
    Y: [244, 200, 76, 255],  // gold / party yellow / stars
    C: [79, 195, 247, 255],  // party blue (the XPLedger accent)
    Q: [255, 111, 181, 255], // party pink
    F: [128, 180, 216, 255], // fish
    f: [72, 114, 152, 255],  // fish fins
    L: [236, 236, 236, 255], // fishing line
    c: [150, 214, 255, 255], // sweat
    z: [0, 0, 0, 70],        // ground shadow
};

//------------------------------------------------------------------------------
// Canvas
//------------------------------------------------------------------------------

class Canvas {
    /** A SIZE x SIZE canvas that also accepts `pad` pixels on every side. */
    constructor(pad = 0) {
        this.pad = pad;
        this.width = SIZE + pad * 2;
        this.px = new Array(this.width * this.width).fill('.');
    }

    inside(x, y) {
        return x >= -this.pad && y >= -this.pad && x < SIZE + this.pad && y < SIZE + this.pad;
    }

    get(x, y) {
        if (!this.inside(x, y)) {
            return '.';
        }
        return this.px[(y + this.pad) * this.width + x + this.pad];
    }

    set(x, y, color) {
        if (this.inside(x, y)) {
            this.px[(y + this.pad) * this.width + x + this.pad] = color;
        }
    }

    /** Calls fn(x, y, color) for every pixel, padding included. */
    each(fn) {
        for (let y = -this.pad; y < SIZE + this.pad; y++) {
            for (let x = -this.pad; x < SIZE + this.pad; x++) {
                fn(x, y, this.get(x, y));
            }
        }
    }

    /** Copies the opaque pixels of another canvas, shifted by dx, dy. */
    draw(other, dx = 0, dy = 0) {
        other.each((x, y, color) => {
            if (color !== '.') {
                this.set(x + dx, y + dy, color);
            }
        });
        return this;
    }

    /** Adds a 1px contour around the opaque pixels (4-neighbourhood). */
    outline(color = 'K') {
        const result = new Canvas(this.pad);
        result.draw(this);
        this.each((x, y, c) => {
            if (c !== '.') {
                return;
            }
            const near = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([ox, oy]) => {
                const n = this.get(x + ox, y + oy);
                return n !== '.' && n !== color;
            });
            if (near) {
                result.set(x, y, color);
            }
        });
        this.px = result.px;
        return this;
    }

    /** Classic pixel art lighting: dark rim bottom-right, light rim top-left. */
    autoshade(base = 'G', dark = 'g', light = 'h') {
        const result = new Canvas(this.pad);
        result.draw(this);
        this.each((x, y, c) => {
            if (c !== base) {
                return;
            }
            if (this.get(x + 1, y) === '.' || this.get(x, y + 1) === '.') {
                result.set(x, y, dark);
            } else if (this.get(x - 1, y) === '.' && this.get(x, y - 1) === '.') {
                result.set(x, y, light);
            }
        });
        this.px = result.px;
        return this;
    }

    /** Opaque bounds: { minX, maxX, minY, maxY }, or null when empty. */
    bounds() {
        let box = null;
        this.each((x, y, c) => {
            if (c === '.') {
                return;
            }
            if (!box) {
                box = { minX: x, maxX: x, minY: y, maxY: y };
            }
            box.minX = Math.min(box.minX, x);
            box.maxX = Math.max(box.maxX, x);
            box.minY = Math.min(box.minY, y);
            box.maxY = Math.max(box.maxY, y);
        });
        return box;
    }

    /** Returns a copy leaning to the right (`amount` pixels per row above `pivotY`). */
    sheared(amount, pivotY = 30) {
        const result = new Canvas(this.pad);
        this.each((x, y, c) => {
            if (c !== '.') {
                result.set(x + Math.round((pivotY - y) * amount), y, c);
            }
        });
        return result;
    }
}

//------------------------------------------------------------------------------
// Shapes (continuous coordinates: the centre of pixel x is x + 0.5)
//------------------------------------------------------------------------------

function ellipse(canvas, cx, cy, rx, ry, colorAt) {
    for (let y = Math.floor(cy - ry - 1); y <= Math.ceil(cy + ry + 1); y++) {
        for (let x = Math.floor(cx - rx - 1); x <= Math.ceil(cx + rx + 1); x++) {
            const nx = (x + 0.5 - cx) / rx;
            const ny = (y + 0.5 - cy) / ry;
            if (nx * nx + ny * ny <= 1) {
                canvas.set(x, y, typeof colorAt === 'function' ? colorAt(nx, ny) : colorAt);
            }
        }
    }
}

/** Round shading for big volumes: light top-left, dark bottom-right. */
function roundShade(base, dark, light) {
    return (nx, ny) => {
        if (nx * 0.5 + ny * 0.85 > 0.62) {
            return dark;
        }
        if (-nx * 0.6 - ny * 0.75 > 0.5) {
            return light;
        }
        return base;
    };
}

function capsule(canvas, x1, y1, x2, y2, radius, color) {
    const minX = Math.floor(Math.min(x1, x2) - radius - 1);
    const maxX = Math.ceil(Math.max(x1, x2) + radius + 1);
    const minY = Math.floor(Math.min(y1, y2) - radius - 1);
    const maxY = Math.ceil(Math.max(y1, y2) + radius + 1);
    const lx = x2 - x1;
    const ly = y2 - y1;
    const length2 = lx * lx + ly * ly || 1;
    for (let y = minY; y <= maxY; y++) {
        for (let x = minX; x <= maxX; x++) {
            const px = x + 0.5;
            const py = y + 0.5;
            const t = Math.max(0, Math.min(1, ((px - x1) * lx + (py - y1) * ly) / length2));
            const dx = px - (x1 + lx * t);
            const dy = py - (y1 + ly * t);
            if (dx * dx + dy * dy <= radius * radius) {
                canvas.set(x, y, color);
            }
        }
    }
}

function line(canvas, x1, y1, x2, y2, color) {
    x1 = Math.round(x1); y1 = Math.round(y1); x2 = Math.round(x2); y2 = Math.round(y2);
    const dx = Math.abs(x2 - x1);
    const dy = -Math.abs(y2 - y1);
    const sx = x1 < x2 ? 1 : -1;
    const sy = y1 < y2 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
        canvas.set(x1, y1, color);
        if (x1 === x2 && y1 === y2) {
            break;
        }
        const e2 = 2 * err;
        if (e2 >= dy) { err += dy; x1 += sx; }
        if (e2 <= dx) { err += dx; y1 += sy; }
    }
}

/** Draws rows of palette characters with the top-left corner at x, y. */
function stamp(canvas, rows, x, y, mirror = false) {
    x = Math.round(x);
    y = Math.round(y);
    rows.forEach((row, oy) => {
        const chars = mirror ? row.split('').reverse() : row.split('');
        chars.forEach((color, ox) => {
            if (color !== '.') {
                canvas.set(x + ox, y + oy, color);
            }
        });
    });
}

/** Draws a stamp centred on cx, cy. */
function stampCentered(canvas, rows, cx, cy, mirror = false) {
    stamp(canvas, rows, cx - rows[0].length / 2, cy - rows.length / 2, mirror);
}

/** Builds full rows from left halves (the right half is the mirror). */
function symmetric(halves) {
    return halves.map((half) => half + half.split('').reverse().join(''));
}

//------------------------------------------------------------------------------
// Stamps (left side; the right side is mirrored)
//------------------------------------------------------------------------------

const EYES = {
    open: [
        '.KKKK.',
        'KWWWWK',
        'KWWPPK',
        'KWWPPK',
        'KWWWWK',
        '.KKKK.',
    ],
    // Both pupils to the same side (not mirrored).
    look: [
        '.KKKK.',
        'KWWWWK',
        'KPPWWK',
        'KPPWWK',
        'KWWWWK',
        '.KKKK.',
    ],
    // Looking down, at the experience bar.
    down: [
        '.KKKK.',
        'KWWWWK',
        'KWWWWK',
        'KWWPPK',
        'KWWPPK',
        '.KKKK.',
    ],
    wide: [
        '.KKKK.',
        'KWWWWK',
        'KWWWWK',
        'KWWPWK',
        'KWWWWK',
        '.KKKK.',
    ],
    happy: [
        '......',
        '......',
        '.KKKK.',
        'K....K',
        '......',
        '......',
    ],
    closed: [
        '......',
        '......',
        '......',
        'K....K',
        '.KKKK.',
        '......',
    ],
    angry: [
        'KK....',
        '.KKKKK',
        'KWWWPK',
        'KWWPPK',
        'KWWWWK',
        '.KKKK.',
    ],
    sad: [
        '....KK',
        '.KKK..',
        'KWWWWK',
        'KWWPPK',
        'KWWPPK',
        '.KKKK.',
    ],
    x: [
        '......',
        '.K..K.',
        '..KK..',
        '..KK..',
        '.K..K.',
        '......',
    ],
    spiral: [
        '.KKKK.',
        'KWWWWK',
        'KWKKWK',
        'KWKWWK',
        'KWWWKK',
        '.KKKK.',
    ],
};

// Eyes that look the same way on both sides instead of being mirrored.
const UNMIRRORED_EYES = { look: true, spiral: true };

const CRESTS = {
    small: symmetric([
        '...R',
        '..Rr',
        '.RRr',
        'RRrr',
    ]),
    big: symmetric([
        '...R',
        '..Rr',
        'R.Rr',
        'RRrr',
        'RrRr',
        'RRRR',
    ]),
};

const EARS = {
    small: [
        'R...',
        'RR..',
        'RrR.',
        '.RR.',
    ],
    big: [
        'R....',
        'RR...',
        'RrR..',
        'RrrR.',
        'RRrR.',
        '.RRR.',
    ],
};

const HELMET = symmetric([
    '.....SSSS',
    '...SSSSSS',
    '..SSSSSSS',
    '.SSSSSKSS',
    'sssssssss',
]);

const PARTY_HAT = [
    '..Q..',
    '..C..',
    '.CYC.',
    '.YCY.',
    'CYCYC',
    'CCCCC',
];

const PROPS = {
    mug: [
        'WWW.',
        'wwwS',
        'wYwS',
        'www.',
    ],
    fish: [
        'f.f',
        '.f.',
        'FFF',
        'FPF',
        'FFF',
        '.F.',
    ],
    fishBitten: [
        '...',
        '...',
        '.FF',
        'FPF',
        'FFF',
        '.F.',
    ],
    fishSide: [
        '.FFF.f',
        'FPFFff',
        '.FFF.f',
    ],
    sweat: [
        '.c',
        'cc',
        'cc',
    ],
    star: [
        '.Y.',
        'YYY',
        '.Y.',
    ],
    bobber: [
        'RR',
        'WW',
    ],
};

/** Mouth rows for a given width. */
function mouthRows(type, width, teeth) {
    const inner = width - 2;
    const run = (char, count) => char.repeat(Math.max(0, count));
    const teethRow = () => {
        const half = [];
        for (let i = 0; i < Math.ceil(inner / 2); i++) {
            half.push(i % 3 === 0 ? 'T' : 'M');
        }
        const right = half.slice(0, Math.floor(inner / 2)).reverse();
        return 'K' + half.join('') + right.join('') + 'K';
    };
    switch (type) {
        case 'closed':
            if (!teeth) {
                return ['K' + run('.', inner) + 'K', '.' + run('K', inner) + '.'];
            }
            return ['.' + run('K', inner) + '.', teethRow(), '.' + run('K', inner) + '.'];
        case 'open':
            return [
                '.' + run('K', inner) + '.',
                teeth ? teethRow() : 'K' + run('M', inner) + 'K',
                'K' + run('M', inner) + 'K',
                'K' + run('M', inner) + 'K',
                '.K' + run('M', inner - 2) + 'K.',
                '..' + run('K', inner - 2) + '..',
            ];
        case 'smile':
            return [
                'K' + run('.', inner) + 'K',
                '.KK' + run('.', inner - 4) + 'KK.',
                '...' + run('K', inner - 4) + '...',
            ];
        case 'frown':
            return [
                '...' + run('K', inner - 4) + '...',
                '.KK' + run('.', inner - 4) + 'KK.',
                'K' + run('.', inner) + 'K',
            ];
        case 'tongue': {
            const left = Math.floor((inner - 2) / 2) + 1;
            const right = inner - 2 - left;
            return [
                '.' + run('K', inner) + '.',
                'K' + run('M', inner) + 'K',
                '.' + run('K', left) + 'QQ' + run('K', right) + '.',
                run('.', left) + 'KQQK' + run('.', right),
                run('.', left + 1) + 'KK' + run('.', right + 1),
            ];
        }
        case 'o':
            return ['.KK.', 'KMMK', '.KK.'];
        case 'snore':
            return ['.KK.', 'KMMK', 'KMMK', '.KK.'];
        case 'yawn':
            return ['.KKKK.', 'KMMMMK', 'KMMMMK', 'KMMMMK', 'KMMMMK', '.KKKK.'];
        case 'chew':
            return ['.K.K.K', 'K.K.K.'];
        default:
            throw new Error('unknown mouth ' + type);
    }
}

//------------------------------------------------------------------------------
// Growth stages
//------------------------------------------------------------------------------

const STAGES = {
    // Hatchling: small body, huge head and eyes, no teeth.
    1: {
        head: { cx: 16, cy: 18, rx: 8.2, ry: 6.6 },
        body: { cx: 16, cy: 25, rx: 5.6, ry: 4.4 },
        belly: { cx: 16, cy: 26.2, rx: 3.4, ry: 2.8 },
        feet: { y: 29, dx: 3, rx: 2.2, ry: 1.6 },
        eyes: { x: 8, y: 14 },
        mouth: { y: 21, width: 8, teeth: false },
        crest: { rows: CRESTS.small, y: 9 },
        ears: { rows: EARS.small, x: 5, y: 15 },
        shoulder: { x: 11, y: 24.2 },
        arm: { radius: 1.3, reach: 0.7 },
        hat: { x: 17, y: 6 },
        weapon: { length: 8, tip: 'w' },
        shadow: 6,
    },
    // Grown murloc: big head, wide toothy mouth.
    2: {
        head: { cx: 16, cy: 14, rx: 10, ry: 8 },
        body: { cx: 16, cy: 23, rx: 7, ry: 6 },
        belly: { cx: 16, cy: 24.6, rx: 4.5, ry: 3.8 },
        feet: { y: 28.6, dx: 3.6, rx: 2.6, ry: 1.8 },
        eyes: { x: 8, y: 9 },
        mouth: { y: 16, width: 12, teeth: true },
        crest: { rows: CRESTS.big, y: 2 },
        ears: { rows: EARS.big, x: 2, y: 9 },
        shoulder: { x: 9.5, y: 20.5 },
        arm: { radius: 1.6, reach: 1 },
        hat: { x: 18, y: 1 },
        weapon: { length: 13, tip: 'S' },
        shadow: 8,
    },
};

// Veteran: the grown murloc with an iron helmet and a gilded spear.
STAGES[3] = Object.assign({}, STAGES[2], {
    crest: { rows: CRESTS.big, y: 0 },
    helmet: { rows: HELMET, x: 7, y: 4 },
    hat: { x: 18, y: 0 },
    weapon: { length: 13, tip: 'Y' },
});

//------------------------------------------------------------------------------
// Poses
//------------------------------------------------------------------------------

// Hand offsets from the shoulder for the LEFT arm (negative x = outwards);
// the right arm mirrors x.
const ARMS = {
    down: [-2, 4],
    up: [-5.5, -6],
    out: [-6, -1],
    stroke: [-4, 3.5],
    reach: [-4.5, -4],
    rest: [3, 3.5],
    fist: [-3, 1],
    hold: [-3, 1],
    thrust: [-4.5, -2],
    raise: [-4, -6],
    brow: [4.5, -9],
    scratch: [3, -12],
    scratch2: [1.5, -12.5],
    wave1: [-6, -8],
    wave2: [-3, -10],
    mouth: [4.5, -3.5],
    hip: [0.5, 1.5],
    flail1: [-6, -4],
    flail2: [-4, -9],
    stretch: [-2.5, -11],
    juggle1: [-4, -5],
    juggle2: [-3, -2.5],
    limp: [-5, 5.5],
};

const LEGS = {
    stand: [[0, 0], [0, 0]],
    kick1: [[-0.5, -1.5], [0.3, 0]],
    kick2: [[-0.3, 0], [0.5, -1.5]],
    sit: [[-1, 0.4], [1, 0.4]],
};

/** Fish positions (relative to the top of the head) for a juggling frame. */
function juggleFish(frame) {
    const positions = [];
    for (let i = 0; i < 3; i++) {
        const angle = (frame * 30 + i * 120) * Math.PI / 180;
        positions.push([Math.cos(angle) * 7, -1 - Math.sin(angle) * 3]);
    }
    return positions;
}

/** Draws the figure (without shadow) on a padded canvas. */
function drawFigure(S, pose) {
    // The head sinks a pixel when breathing out, more when knocked out.
    const lift = (pose.squash ? 1 : 0) + (pose.slump || 0);
    const figure = new Canvas(PAD);
    const layer = (draw, shade = true) => {
        const canvas = new Canvas(PAD);
        draw(canvas);
        if (shade) {
            canvas.autoshade();
        }
        figure.draw(canvas.outline());
    };
    const headTop = { x: S.head.cx, y: S.head.cy - S.head.ry + lift };

    // Feet (a ghost has a wavy tail instead).
    if (!pose.tail && pose.legs !== 'none') {
        const legs = LEGS[pose.legs || 'stand'];
        [-1, 1].forEach((side, i) => {
            const [ox, oy] = legs[i];
            layer((c) => ellipse(c, S.body.cx + side * S.feet.dx + ox, S.feet.y + oy,
                S.feet.rx + (pose.legs === 'sit' ? 0.4 : 0), S.feet.ry, 'G'));
        });
    }

    // Body with the belly.
    layer((c) => {
        const stretch = pose.tail !== undefined ? 1.5 : 0;
        ellipse(c, S.body.cx, S.body.cy + stretch, S.body.rx, S.body.ry + stretch, roundShade('G', 'g', 'h'));
        ellipse(c, S.belly.cx, S.belly.cy, S.belly.rx, S.belly.ry, roundShade('B', 'b', 'B'));
        if (pose.tail !== undefined) {
            // Scalloped hem, shifted every frame so it ripples.
            const box = c.bounds();
            for (let x = box.minX; x <= box.maxX; x++) {
                if ((((x + pose.tail) % 4) + 4) % 4 < 2) {
                    c.set(x, box.maxY, '.');
                }
            }
        }
    }, false);

    // Fins behind the head.
    layer((c) => {
        const crest = S.crest.rows;
        stamp(c, crest, Math.round(S.head.cx - crest[0].length / 2), S.crest.y + lift);
    }, false);
    layer((c) => {
        const ears = S.ears.rows;
        stamp(c, ears, S.ears.x, S.ears.y + lift);
        stamp(c, ears, SIZE - S.ears.x - ears[0].length, S.ears.y + lift, true);
    }, false);

    // Head.
    layer((c) => ellipse(c, S.head.cx, S.head.cy + lift, S.head.rx, S.head.ry, roundShade('G', 'g', 'h')), false);

    // Face.
    const eyesName = pose.eyes || 'open';
    const eyes = EYES[eyesName];
    stamp(figure, eyes, S.eyes.x, S.eyes.y + lift);
    stamp(figure, eyes, SIZE - S.eyes.x - eyes[0].length, S.eyes.y + lift, !UNMIRRORED_EYES[eyesName]);
    const mouth = mouthRows(pose.mouth || 'closed', S.mouth.width, S.mouth.teeth);
    stamp(figure, mouth, Math.round(16 - mouth[0].length / 2), S.mouth.y + lift);

    // Headwear.
    if (S.helmet) {
        layer((c) => stamp(c, S.helmet.rows, S.helmet.x, S.helmet.y + lift), false);
    }
    if (pose.hat) {
        layer((c) => stamp(c, PARTY_HAT, S.hat.x, S.hat.y + lift), false);
    }

    // Things around the head.
    if (pose.sweat) {
        layer((c) => stamp(c, PROPS.sweat, S.head.cx + S.head.rx - 3, S.head.cy - S.head.ry * 0.6 + lift), false);
    }
    if (pose.stars !== undefined) {
        const spots = pose.stars ? [[-7, -1], [0, -4], [7, -1]] : [[-4, -3], [4, -3]];
        layer((c) => spots.forEach(([ox, oy]) => stampCentered(c, PROPS.star, headTop.x + ox, headTop.y + oy)), false);
    }
    if (pose.juggle !== undefined) {
        layer((c) => juggleFish(pose.juggle).forEach(([ox, oy], i) => {
            stampCentered(c, PROPS.fishSide, headTop.x + ox, headTop.y + oy, i % 2 === 1);
        }), false);
    }

    // Arms, and what the right hand holds.
    const hand = (name, side) => {
        const [ox, oy] = ARMS[name];
        const sx = side < 0 ? S.shoulder.x : SIZE - S.shoulder.x;
        return {
            sx,
            sy: S.shoulder.y,
            hx: sx - side * ox * S.arm.reach,
            hy: S.shoulder.y + oy * S.arm.reach,
        };
    };
    const left = hand((pose.arms && pose.arms[0]) || 'down', -1);
    const right = hand((pose.arms && pose.arms[1]) || 'down', 1);

    if (pose.weapon) {
        const W = S.weapon;
        layer((c) => {
            const topX = right.hx + 2;
            const topY = right.hy - W.length + 4;
            line(c, right.hx + 0.5, right.hy + 4, topX, topY, 'w');
            if (W.tip === 'w') {
                ellipse(c, topX + 0.5, topY - 0.5, 1.4, 1.4, 'w');
            } else {
                stamp(c, ['.' + W.tip + '.', W.tip + W.tip + W.tip, '.' + W.tip + '.'],
                    Math.round(topX) - 1, Math.round(topY) - 3);
            }
        }, false);
    }

    if (pose.prop === 'rod') {
        const tipX = right.hx + 5;
        const tipY = right.hy - 12;
        layer((c) => line(c, right.hx, right.hy + 3, tipX, tipY, 'w'), false);
        if (pose.bobber) {
            line(figure, tipX + 1, tipY + 1, tipX + 1, pose.bobber - 1, 'L');
            layer((c) => stamp(c, PROPS.bobber, tipX + 1, pose.bobber), false);
        }
    } else if (pose.prop === 'mug') {
        layer((c) => stamp(c, PROPS.mug, right.hx - 1, right.hy - 3), false);
    } else if (pose.prop) {
        const rows = PROPS[pose.prop];
        layer((c) => stamp(c, rows, right.hx - 1, right.hy - rows.length + 1), false);
    }

    [left, right].forEach((arm) => {
        layer((c) => capsule(c, arm.sx, arm.sy, arm.hx, arm.hy, S.arm.radius, 'G'));
    });

    return figure;
}

function compose(stageId, pose) {
    const S = STAGES[stageId];
    const out = new Canvas();
    let figure = drawFigure(S, pose);
    const shadow = pose.noShadow ? 0 : S.shadow * ((pose.dy || 0) < 0 ? 0.7 : 1);

    if (pose.shear) {
        figure = figure.sheared(pose.shear);
    }

    // Ground shadow: stays on the ground while the murloc jumps.
    if (shadow > 0) {
        ellipse(out, 16 + (pose.dx || 0), 30.8, shadow, 1.2, 'z');
    }
    out.draw(figure, pose.dx || 0, pose.dy || 0);
    return out;
}

//------------------------------------------------------------------------------
// Animations (one sheet row each, 4 frames)
//------------------------------------------------------------------------------

const idle = { eyes: 'open', mouth: 'closed' };
const variant = (base, changes) => Object.assign({}, base, changes);

const relief = { eyes: 'closed', mouth: 'o', arms: ['down', 'brow'], sweat: true };
const panic = { eyes: 'wide', mouth: 'open', sweat: true };
const rest = { eyes: 'open', mouth: 'smile', legs: 'sit', arms: ['rest', 'hold'], prop: 'mug' };
const fishing = { eyes: 'open', mouth: 'closed', prop: 'rod', arms: ['fist', 'hold'], dx: -4 };
const dizzy = { eyes: 'spiral', mouth: 'o' };
const excited = { eyes: 'down', mouth: 'smile', arms: ['fist', 'fist'] };

const ANIMATIONS = [
    // 0 idle: breathe, blink, look around
    [
        idle,
        variant(idle, { squash: true }),
        variant(idle, { eyes: 'closed' }),
        variant(idle, { eyes: 'look', mouth: 'smile' }),
    ],
    // 1 happy: crouch and jump with the arms up
    [
        { eyes: 'happy', mouth: 'smile', squash: true },
        { eyes: 'happy', mouth: 'open', arms: ['up', 'up'], dy: -2 },
        { eyes: 'happy', mouth: 'open', arms: ['up', 'up'], dy: -1 },
        { eyes: 'happy', mouth: 'smile', arms: ['reach', 'reach'] },
    ],
    // 2 party: party hat, alternating cheers
    [
        { eyes: 'happy', mouth: 'open', hat: true, arms: ['up', 'down'] },
        { eyes: 'happy', mouth: 'open', hat: true, arms: ['up', 'up'], dy: -2 },
        { eyes: 'happy', mouth: 'open', hat: true, arms: ['down', 'up'] },
        { eyes: 'happy', mouth: 'smile', hat: true, arms: ['up', 'up'], dy: -1 },
    ],
    // 3 fight: spear ready, thrust, hop, raise
    [
        { eyes: 'angry', mouth: 'open', weapon: true, arms: ['fist', 'hold'] },
        { eyes: 'angry', mouth: 'open', weapon: true, arms: ['fist', 'thrust'] },
        { eyes: 'angry', mouth: 'closed', weapon: true, arms: ['fist', 'hold'], dy: -1 },
        { eyes: 'angry', mouth: 'open', weapon: true, arms: ['up', 'raise'] },
    ],
    // 4 swim: breaststroke and kicks, holding the breath
    [
        { eyes: 'open', mouth: 'o', arms: ['out', 'out'], legs: 'kick1' },
        { eyes: 'open', mouth: 'o', arms: ['stroke', 'stroke'], legs: 'kick2' },
        { eyes: 'open', mouth: 'o', arms: ['reach', 'reach'], legs: 'kick1', dy: -1 },
        { eyes: 'look', mouth: 'o', arms: ['out', 'out'], legs: 'kick2', dy: -1 },
    ],
    // 5 sleep: sitting, slow breathing and snoring
    [
        { eyes: 'closed', mouth: 'smile', arms: ['rest', 'rest'], legs: 'sit' },
        { eyes: 'closed', mouth: 'smile', arms: ['rest', 'rest'], legs: 'sit', squash: true },
        { eyes: 'closed', mouth: 'snore', arms: ['rest', 'rest'], legs: 'sit', squash: true },
        { eyes: 'closed', mouth: 'o', arms: ['rest', 'rest'], legs: 'sit' },
    ],
    // 6 victory: weapon up, little hops
    [
        { eyes: 'happy', mouth: 'open', weapon: true, arms: ['fist', 'raise'] },
        { eyes: 'happy', mouth: 'open', weapon: true, arms: ['up', 'raise'], dy: -2 },
        { eyes: 'happy', mouth: 'open', weapon: true, arms: ['up', 'raise'], dy: -1 },
        { eyes: 'happy', mouth: 'smile', weapon: true, arms: ['fist', 'raise'] },
    ],
    // 7 relief: wipe the brow, then breathe out
    [
        relief,
        variant(relief, { squash: true }),
        { eyes: 'closed', mouth: 'smile', squash: true },
        { eyes: 'open', mouth: 'smile' },
    ],
    // 8 dead: stagger, knees give way, knocked out (the last two frames loop)
    [
        { eyes: 'wide', mouth: 'o', arms: ['up', 'up'], shear: 0.15 },
        { eyes: 'x', mouth: 'open', arms: ['out', 'out'], legs: 'sit', slump: 1, shear: -0.12 },
        { eyes: 'x', mouth: 'tongue', arms: ['limp', 'limp'], legs: 'sit', slump: 3 },
        { eyes: 'x', mouth: 'tongue', arms: ['limp', 'out'], legs: 'sit', slump: 3, squash: true },
    ],
    // 9 ghost: sad, floating on a rippling tail (tinted by the addon)
    [
        { eyes: 'sad', mouth: 'frown', tail: 0, noShadow: true },
        { eyes: 'sad', mouth: 'frown', tail: 1, noShadow: true, arms: ['stroke', 'stroke'] },
        { eyes: 'sad', mouth: 'frown', tail: 2, noShadow: true, squash: true },
        { eyes: 'closed', mouth: 'frown', tail: 3, noShadow: true, arms: ['stroke', 'stroke'] },
    ],
    // 10 revive: dizzy, swaying, stars around the head
    [
        variant(dizzy, { dx: -1, stars: 0 }),
        variant(dizzy, { stars: 1 }),
        variant(dizzy, { dx: 1, stars: 0 }),
        variant(dizzy, { mouth: 'smile', stars: 1 }),
    ],
    // 11 panic: flailing and shaking
    [
        variant(panic, { arms: ['flail1', 'flail2'], dx: -1 }),
        variant(panic, { arms: ['flail2', 'flail1'], dx: 1 }),
        variant(panic, { arms: ['flail1', 'flail2'], dy: -1, sweat: false }),
        variant(panic, { arms: ['flail2', 'flail1'], mouth: 'o' }),
    ],
    // 12 rest: sitting with a mug, sipping
    [
        rest,
        variant(rest, { eyes: 'closed', mouth: 'closed', arms: ['rest', 'mouth'] }),
        variant(rest, { eyes: 'happy', squash: true }),
        variant(rest, { eyes: 'closed' }),
    ],
    // 13 dance: arms and hips side to side
    [
        { eyes: 'happy', mouth: 'smile', arms: ['up', 'hip'], legs: 'kick1', dx: -1 },
        { eyes: 'happy', mouth: 'open', arms: ['hip', 'up'], legs: 'kick2', dx: 1 },
        { eyes: 'happy', mouth: 'smile', arms: ['up', 'hip'], legs: 'kick2', dx: -1, dy: -1 },
        { eyes: 'happy', mouth: 'open', arms: ['hip', 'up'], legs: 'kick1', dx: 1, dy: -1 },
    ],
    // 14 wave: hello!
    [
        { eyes: 'open', mouth: 'smile', arms: ['down', 'wave1'] },
        { eyes: 'happy', mouth: 'smile', arms: ['down', 'wave2'] },
        { eyes: 'open', mouth: 'open', arms: ['down', 'wave1'] },
        { eyes: 'happy', mouth: 'open', arms: ['down', 'wave2'] },
    ],
    // 15 fish: cast, then wait while the bobber bobs
    [
        variant(fishing, { arms: ['down', 'raise'] }),
        variant(fishing, { bobber: 26 }),
        variant(fishing, { bobber: 26, eyes: 'look' }),
        variant(fishing, { bobber: 27, squash: true }),
    ],
    // 16 eat: show the fish, bite, chew
    [
        { eyes: 'happy', mouth: 'open', arms: ['fist', 'up'], prop: 'fish' },
        { eyes: 'open', mouth: 'open', arms: ['fist', 'mouth'], prop: 'fish' },
        { eyes: 'closed', mouth: 'chew', arms: ['fist', 'mouth'], prop: 'fishBitten' },
        { eyes: 'happy', mouth: 'chew', arms: ['rest', 'rest'], squash: true },
    ],
    // 17 yawn: stretch with the mouth wide open
    [
        { eyes: 'closed', mouth: 'yawn', arms: ['stretch', 'stretch'] },
        { eyes: 'closed', mouth: 'yawn', arms: ['stretch', 'stretch'], dy: -1 },
        { eyes: 'closed', mouth: 'yawn', squash: true },
        { eyes: 'closed', mouth: 'closed', squash: true },
    ],
    // 18 juggle: three fish around the head
    [
        { eyes: 'open', mouth: 'smile', arms: ['juggle1', 'juggle2'], juggle: 0 },
        { eyes: 'open', mouth: 'smile', arms: ['juggle2', 'juggle1'], juggle: 1 },
        { eyes: 'look', mouth: 'open', arms: ['juggle1', 'juggle2'], juggle: 2 },
        { eyes: 'open', mouth: 'smile', arms: ['juggle2', 'juggle1'], juggle: 3 },
    ],
    // 19 scratch: scratch the head, look aside
    [
        { eyes: 'look', mouth: 'closed', arms: ['down', 'scratch'] },
        { eyes: 'look', mouth: 'closed', arms: ['down', 'scratch2'] },
        { eyes: 'look', mouth: 'closed', arms: ['down', 'scratch'], squash: true },
        { eyes: 'closed', mouth: 'smile', arms: ['down', 'scratch2'] },
    ],
    // 20 excited: staring at the bar, fists clenched, hopping
    [
        excited,
        variant(excited, { mouth: 'open', dy: -1 }),
        variant(excited, { squash: true }),
        { eyes: 'happy', mouth: 'open', arms: ['up', 'up'], dy: -2 },
    ],
    // 21 jump: crouch, take off, peak, land (played once when the player
    // jumps; the addon lifts the whole sprite, so there is no dy here)
    [
        { eyes: 'closed', mouth: 'closed', squash: true },
        { eyes: 'open', mouth: 'o', arms: ['out', 'out'], legs: 'kick1', noShadow: true },
        { eyes: 'happy', mouth: 'smile', arms: ['up', 'up'], legs: 'kick2', noShadow: true },
        { eyes: 'open', mouth: 'closed', arms: ['reach', 'reach'], squash: true },
    ],
];

//------------------------------------------------------------------------------
// Effect icons (8x8, drawn in the first cell of the last row, left to right
// and top to bottom). The order must match ICONS in UI/Pet/Effects.lua.
//------------------------------------------------------------------------------

const ICONS = [
    // 0 heart
    [
        '.KK.KK..',
        'KQQKQQK.',
        'KQTQQQK.',
        'KQQQQQK.',
        '.KQQQK..',
        '..KQK...',
        '...K....',
        '........',
    ],
    // 1 music note
    [
        '...KK...',
        '...KYK..',
        '...KYYK.',
        '...KYKYK',
        '.KKKK.K.',
        'KYYYK...',
        'KYYYK...',
        '.KKK....',
    ],
    // 2 star
    [
        '...K....',
        '..KYK...',
        'KKKYKKK.',
        'KYYYYYK.',
        '.KYYYK..',
        'KYK.KYK.',
        'KK...KK.',
        '........',
    ],
    // 3 exclamation mark
    [
        '..KKK...',
        '..KYK...',
        '..KYK...',
        '..KYK...',
        '..KKK...',
        '..KYK...',
        '..KKK...',
        '........',
    ],
    // 4 Z
    [
        'KKKKKKK.',
        'KCCCCCK.',
        'KKKKCK..',
        '..KCK...',
        '.KCKKKK.',
        'KCCCCCK.',
        'KKKKKKK.',
        '........',
    ],
];

module.exports = { SIZE, PALETTE, STAGES, ANIMATIONS, ICONS, compose };
