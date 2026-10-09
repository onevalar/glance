# Glance application icon

Approved design: **浮雕折景 · REFINED 04**, 2026-10-09.
[Paper source](https://app.paper.design/file/01M4A5RBCWZTDJ3A3K7PVW4ASZ/p-2-0).

- `glance.svg` / `glance.png`: approved full-detail artwork; PNG is 1024 × 1024.
- `glance-16.*` / `glance-32.*`: approved optical variants, exported at 256 × 256 for Retina generation.
- `glance-ios.*`: the same artwork with an opaque, square background. iOS supplies the final corner mask.

The PNG masters are exported directly by Paper. Use them for production resizing: generic SVG renderers differ from Paper in gradient and filter rendering. SVGs are retained as editable sources.

Regenerate assets with Node.js and `sharp` (version 0.35.5 used here):

```sh
node scripts/generate-icons.cjs
```

If `sharp` is installed outside the project, set `NODE_PATH` to its parent `node_modules` directory. No npm dependencies are needed by the Swift application itself.

The generator updates the macOS app icon catalog (10 sizes), Settings/About brand images (3 scales), menu bar images (2 scales), the iOS/iPadOS icon, and both standalone legacy `assets/iMonet-{icon,logo}.png` paths. macOS app icons keep the original 824/1024 optical footprint. The old iMonet application screenshots and video are historical references, not icon resources.
