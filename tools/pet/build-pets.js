'use strict';
/*
    Builds the sprite sheets of the XPLedger companions.

      node tools/pet/build-pets.js [--rows=6-11] [--scale=5]

    Writes Media/Pet/<Species>.tga (128x1024, uncompressed 32-bit TGA that the
    game can load) for the murloc and the Void hatchling, and tools/pet/preview.png,
    every sheet enlarged on a checkerboard to review the art.
*/

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const murloc = require('./murloc-art');
const voidling = require('./void-art');

const { SIZE, ANIMATIONS, ICONS } = murloc;

// File name, palette and drawing of every species. The order matters only
// for the preview. A new species is more than a drawing: it also needs its
// own phrases, written for its personality, in every locale (see "Adding a
// new pet" in UI/Pet/Talk.lua). `rage` is the optional bigger form the
// species turns into when it is clicked too much: frames of rageSize pixels
// drawn by rage(frame), plus the `collapse` frames that lead into it.
const SPECIES = [
    { file: 'Murloc', palette: murloc.PALETTE, compose: murloc.compose },
    {
        file: 'Void', palette: voidling.PALETTE, compose: voidling.compose,
        rage: voidling.composeRage, rageFrames: voidling.RAGE, rageSize: voidling.RAGE_SIZE,
        collapse: voidling.composeCollapse, collapseFrames: voidling.COLLAPSE,
    },
];

const COLUMNS = 4;
const ROWS = 32;
const WIDTH = SIZE * COLUMNS;
const HEIGHT = SIZE * ROWS;
// The rage form fills rows 22-25 and its collapse row 26 (see the sheet
// layout in murloc-art.js).
const RAGE_ROW = 22;
const RAGE_ROWS = 4;
const COLLAPSE_ROW = 26;
// Preview options: --rows=6-11 shows only those rows, --scale=5 the zoom.
const args = Object.fromEntries(process.argv.slice(2).map((arg) => arg.replace(/^--/, '').split('=')));
const [firstRow, lastRow] = (args.rows || `0-${COLLAPSE_ROW}`).split('-').map(Number);
const PREVIEW_SCALE = Number(args.scale) || 3;

const root = path.resolve(__dirname, '..', '..');
const mediaDir = path.join(root, 'Media', 'Pet');

const ICON_SIZE = 8;
const ICON_ROW = ROWS - 1;

function putPixel(rgba, x, y, color, palette) {
    if (color === '.') {
        return;
    }
    const rgb = palette[color];
    if (!rgb) {
        throw new Error(`unknown color '${color}'`);
    }
    const offset = (y * WIDTH + x) * 4;
    rgba[offset] = rgb[0];
    rgba[offset + 1] = rgb[1];
    rgba[offset + 2] = rgb[2];
    rgba[offset + 3] = rgb[3];
}

/** Renders one species into an RGBA buffer (top-left origin). */
function renderSheet(species) {
    const rgba = Buffer.alloc(WIDTH * HEIGHT * 4);
    ANIMATIONS.forEach((frames, row) => {
        frames.forEach((pose, column) => {
            const canvas = species.compose(pose);
            for (let y = 0; y < SIZE; y++) {
                for (let x = 0; x < SIZE; x++) {
                    putPixel(rgba, column * SIZE + x, row * SIZE + y, canvas.get(x, y), species.palette);
                }
            }
        });
    });
    // Rage form: big frames, as many per row band as fit.
    if (species.rage) {
        const size = species.rageSize;
        const perBand = WIDTH / size;
        species.rageFrames.forEach((frame, index) => {
            const canvas = species.rage(frame);
            const left = (index % perBand) * size;
            const top = RAGE_ROW * SIZE + Math.floor(index / perBand) * size;
            if (top + size > (RAGE_ROW + RAGE_ROWS) * SIZE) {
                throw new Error('the rage form does not fit in its rows');
            }
            for (let y = 0; y < size; y++) {
                for (let x = 0; x < size; x++) {
                    putPixel(rgba, left + x, top + y, canvas.get(x, y), species.palette);
                }
            }
        });
        species.collapseFrames.forEach((frame, column) => {
            const canvas = species.collapse(frame);
            for (let y = 0; y < SIZE; y++) {
                for (let x = 0; x < SIZE; x++) {
                    putPixel(rgba, column * SIZE + x, COLLAPSE_ROW * SIZE + y, canvas.get(x, y), species.palette);
                }
            }
        });
    }
    // Effect icons, the same on every sheet (always in the murloc colors).
    const perRow = SIZE / ICON_SIZE;
    ICONS.forEach((rows, index) => {
        const left = (index % perRow) * ICON_SIZE;
        const top = ICON_ROW * SIZE + Math.floor(index / perRow) * ICON_SIZE;
        rows.forEach((row, y) => row.split('').forEach((color, x) => putPixel(rgba, left + x, top + y, color, murloc.PALETTE)));
    });
    return rgba;
}

/** Uncompressed true color TGA, bottom-left origin, 8 bits of alpha. */
function encodeTGA(rgba, width, height) {
    const header = Buffer.alloc(18);
    header[2] = 2;
    header.writeUInt16LE(width, 12);
    header.writeUInt16LE(height, 14);
    header[16] = 32;
    header[17] = 0x08;
    const pixels = Buffer.alloc(width * height * 4);
    for (let y = 0; y < height; y++) {
        const source = (height - 1 - y) * width * 4;
        for (let x = 0; x < width; x++) {
            const s = source + x * 4;
            const d = (y * width + x) * 4;
            pixels[d] = rgba[s + 2];
            pixels[d + 1] = rgba[s + 1];
            pixels[d + 2] = rgba[s];
            pixels[d + 3] = rgba[s + 3];
        }
    }
    return Buffer.concat([header, pixels]);
}

const CRC_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) {
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        }
        table[n] = c >>> 0;
    }
    return table;
})();

function crc32(buffer) {
    let crc = 0xffffffff;
    for (const byte of buffer) {
        crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([length, body, crc]);
}

function encodePNG(rgba, width, height) {
    const header = Buffer.alloc(13);
    header.writeUInt32BE(width, 0);
    header.writeUInt32BE(height, 4);
    header[8] = 8;
    header[9] = 6;
    const raw = Buffer.alloc((width * 4 + 1) * height);
    for (let y = 0; y < height; y++) {
        rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
    }
    return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        pngChunk('IHDR', header),
        pngChunk('IDAT', zlib.deflateSync(raw)),
        pngChunk('IEND', Buffer.alloc(0)),
    ]);
}

/** Every sheet side by side, enlarged, over a checkerboard. */
function renderPreview(sheets) {
    const gap = 8;
    const usedRows = lastRow - firstRow + 1;
    const width = (WIDTH * sheets.length + gap * (sheets.length - 1)) * PREVIEW_SCALE;
    const height = SIZE * usedRows * PREVIEW_SCALE;
    const out = Buffer.alloc(width * height * 4);
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const d = (y * width + x) * 4;
            const sheetX = Math.floor(x / PREVIEW_SCALE);
            const sheetY = Math.floor(y / PREVIEW_SCALE) + firstRow * SIZE;
            const index = Math.floor(sheetX / (WIDTH + gap));
            const localX = sheetX - index * (WIDTH + gap);
            let r = 40, g = 40, b = 48;
            if (localX < WIDTH) {
                const cellEdge = localX % SIZE === 0 || sheetY % SIZE === 0;
                const checker = (Math.floor(localX / 4) + Math.floor(sheetY / 4)) % 2;
                r = g = b = cellEdge ? 150 : (checker ? 205 : 225);
                const s = (sheetY * WIDTH + localX) * 4;
                const alpha = sheets[index][s + 3] / 255;
                r = Math.round(r * (1 - alpha) + sheets[index][s] * alpha);
                g = Math.round(g * (1 - alpha) + sheets[index][s + 1] * alpha);
                b = Math.round(b * (1 - alpha) + sheets[index][s + 2] * alpha);
            }
            out[d] = r;
            out[d + 1] = g;
            out[d + 2] = b;
            out[d + 3] = 255;
        }
    }
    return encodePNG(out, width, height);
}

fs.mkdirSync(mediaDir, { recursive: true });
const sheets = SPECIES.map((species) => {
    const rgba = renderSheet(species);
    const file = path.join(mediaDir, `${species.file}.tga`);
    fs.writeFileSync(file, encodeTGA(rgba, WIDTH, HEIGHT));
    console.log('wrote', path.relative(root, file));
    return rgba;
});
const previewFile = path.join(__dirname, 'preview.png');
fs.writeFileSync(previewFile, renderPreview(sheets));
console.log('wrote', path.relative(root, previewFile));
