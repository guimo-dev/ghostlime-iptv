// Regenerates every icon from the SVG masters in this folder using headless Chrome.
// Run from the repo root: node branding/build_icons.mjs
// Needs Chrome at the default Windows path (or set CHROME_PATH). No npm packages.
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const brandingDir = dirname(fileURLToPath(import.meta.url));
const repoDir = resolve(brandingDir, '..');
const chrome = process.env.CHROME_PATH ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const workDir = mkdtempSync(join(tmpdir(), 'ghostlime-'));

/**
 * Renders an SVG as a crisp PNG of the given size with a transparent background.
 * @param {string} svgName File name of the SVG inside branding/.
 * @param {number} width Output width in pixels.
 * @param {number} height Output height in pixels.
 * @param {string} outPath Absolute path of the PNG to write (folders are created).
 * @returns {void}
 */
function render(svgName, width, height, outPath) {
  const svgUrl = pathToFileURL(join(brandingDir, svgName)).href;
  const htmlPath = join(workDir, `${svgName}-${width}x${height}.html`);
  writeFileSync(
    htmlPath,
    `<body style="margin:0"><img src="${svgUrl}" width="${width}" height="${height}" style="display:block">`,
  );
  mkdirSync(dirname(outPath), { recursive: true });
  execFileSync(
    chrome,
    [
      '--headless=new', '--disable-gpu', '--hide-scrollbars',
      '--default-background-color=00000000',
      `--window-size=${width},${height}`,
      `--screenshot=${outPath}`,
      pathToFileURL(htmlPath).href,
    ],
    { stdio: 'ignore' },
  );
}

/**
 * Packs PNG images into an ICO container (PNG-compressed entries).
 * @param {{size: number, png: Buffer}[]} images Entries, one per size.
 * @returns {Buffer} The bytes of the .ico file.
 */
function buildIco(images) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(images.length, 4);
  let offset = 6 + 16 * images.length;
  const entries = images.map(({ size, png }) => {
    const entry = Buffer.alloc(16);
    entry[0] = size === 256 ? 0 : size;
    entry[1] = size === 256 ? 0 : size;
    entry.writeUInt16LE(1, 4); // color planes
    entry.writeUInt16LE(32, 6); // bits per pixel
    entry.writeUInt32LE(png.length, 8);
    entry.writeUInt32LE(offset, 12);
    offset += png.length;
    return entry;
  });
  return Buffer.concat([header, ...entries, ...images.map((image) => image.png)]);
}

/**
 * Renders ghostlime.svg at several sizes and writes them as one ICO file.
 * @param {number[]} sizes Pixel sizes to include.
 * @param {string} outPath Absolute path of the .ico to write.
 * @returns {void}
 */
function renderIco(sizes, outPath) {
  const images = sizes.map((size) => {
    const pngPath = join(workDir, `ico-${size}.png`);
    render('ghostlime.svg', size, size, pngPath);
    return { size, png: readFileSync(pngPath) };
  });
  writeFileSync(outPath, buildIco(images));
}

const android = join(repoDir, 'android/app/src/main/res');
const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
const iosSet = join(repoDir, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');

// Windows
renderIco([16, 24, 32, 48, 64, 128, 256], join(repoDir, 'windows/runner/resources/app_icon.ico'));

// Android: legacy launcher icon (48 dp) and adaptive foreground (108 dp) per density.
for (const [density, scale] of Object.entries(densities)) {
  const dir = join(android, `mipmap-${density}`);
  render('ghostlime.svg', 48 * scale, 48 * scale, join(dir, 'ic_launcher.png'));
  render('ghostlime-foreground.svg', 108 * scale, 108 * scale, join(dir, 'ic_launcher_foreground.png'));
}
mkdirSync(join(android, 'mipmap-anydpi-v26'), { recursive: true });
writeFileSync(
  join(android, 'mipmap-anydpi-v26/ic_launcher.xml'),
  `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
`,
);
writeFileSync(
  join(android, 'values/ic_launcher_background.xml'),
  `<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#14151f</color>
</resources>
`,
);

// iOS: every size listed in Contents.json, from the full-bleed master.
const contents = JSON.parse(readFileSync(join(iosSet, 'Contents.json'), 'utf8'));
for (const { size, scale, filename } of contents.images) {
  const pixels = Math.round(parseFloat(size) * parseInt(scale, 10));
  render('ghostlime-square.svg', pixels, pixels, join(iosSet, filename));
}

// Linux window icon
render('ghostlime.svg', 256, 256, join(repoDir, 'linux/runner/resources/app_icon.png'));

// Web / brand kit
render('ghostlime.svg', 512, 512, join(brandingDir, 'ghostlime-512.png'));
render('ghostlime.svg', 192, 192, join(brandingDir, 'ghostlime-192.png'));
render('ghostlime.svg', 32, 32, join(brandingDir, 'favicon-32.png'));
render('ghostlime.svg', 16, 16, join(brandingDir, 'favicon-16.png'));
renderIco([16, 32], join(brandingDir, 'favicon.ico'));
render('ghostlime-square.svg', 180, 180, join(brandingDir, 'apple-touch-icon-180.png'));
render('og.svg', 1200, 630, join(brandingDir, 'ghostlime-og-1200x630.png'));
