#!/usr/bin/env node
// Rebuild application branding from the approved Paper REFINED 04 raster masters.
// Requires sharp (0.35.5 used for the checked-in outputs). See assets/icon/README.md.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

const root = path.resolve(__dirname, '..');
const masters = path.join(root, 'assets/icon');
const macAssets = 'Sources/Glance/Assets.xcassets';
const outputs = [];

function source(logicalSize) {
  return path.join(masters, logicalSize <= 16 ? 'glance-16.png'
    : logicalSize <= 32 ? 'glance-32.png' : 'glance.png');
}

async function writeIcon(relativePath, pixels, logicalSize, inset = false) {
  // Match the existing macOS application's 824/1024 optical footprint.
  const artworkSize = inset ? Math.round(pixels * 824 / 1024) : pixels;
  const leading = Math.floor((pixels - artworkSize) / 2);
  const trailing = pixels - artworkSize - leading;
  let image = sharp(source(logicalSize)).resize(artworkSize, artworkSize, { kernel: 'lanczos3' });
  if (inset) image = image.extend({ top: leading, left: leading, bottom: trailing,
    right: trailing, background: { r: 0, g: 0, b: 0, alpha: 0 } });
  await image.png().toFile(path.join(root, relativePath));
  outputs.push({ relativePath, pixels, opaque: false });
}

async function main() {
  const catalog = JSON.parse(await fs.readFile(path.join(root, macAssets,
    'AppIcon.appiconset/Contents.json'), 'utf8'));
  for (const item of catalog.images) {
    const logicalSize = Number(item.size.split('x')[0]);
    const pixels = logicalSize * Number.parseInt(item.scale);
    await writeIcon(`${macAssets}/AppIcon.appiconset/${item.filename}`, pixels, logicalSize, true);
  }
  // Both Settings and About use Image("Glance"); no call-site changes are needed.
  for (const scale of [1, 2, 3]) {
    await writeIcon(`${macAssets}/Glance.imageset/picture@${scale}x.png`, 256 * scale, 256);
  }
  for (const scale of [1, 2]) {
    await writeIcon(`${macAssets}/menubar.imageset/menubar@${scale}x.png`, 22 * scale, 22, true);
  }

  const iosPath = 'Sources/GlanceiOS/Assets.xcassets/AppIcon.appiconset/icon_1024.png';
  // iOS applies its own mask. The native Paper export is full bleed, not a
  // rounded icon flattened onto a solid color (which would leave corner halos).
  const iosMaster = path.join(masters, 'glance-ios.png');
  const alpha = (await sharp(iosMaster).ensureAlpha().stats()).channels[3];
  if (alpha.min !== 255) throw new Error('The iOS master must be fully opaque');
  await sharp(iosMaster).resize(1024, 1024).removeAlpha().png().toFile(path.join(root, iosPath));
  outputs.push({ relativePath: iosPath, pixels: 1024, opaque: true });

  // Retain the legacy filenames so existing external links remain valid.
  await writeIcon('assets/iMonet-icon.png', 288, 288, true);
  await writeIcon('assets/iMonet-logo.png', 872, 872);

  for (const { relativePath, pixels, opaque } of outputs) {
    const metadata = await sharp(path.join(root, relativePath)).metadata();
    if (metadata.width !== pixels || metadata.height !== pixels || (opaque && metadata.hasAlpha)) {
      throw new Error(`Invalid icon output: ${relativePath}`);
    }
  }
  console.log(`Generated and validated ${outputs.length} application icon assets.`);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
