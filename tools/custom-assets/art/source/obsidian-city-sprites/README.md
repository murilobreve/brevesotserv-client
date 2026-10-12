# Obsidian city sprite pack

Black obsidian with dark purple stone accents and small warm reflections, matching the approved artwork. Generated with the built-in image-generation tool, then sliced and exported with nearest-neighbor sampling. These are PNG art assets for a developer to integrate, not a compiled client sprite database.

## Contents

| Folder | Unique sprites | Role |
| --- | ---: | --- |
| walls | 16 | 4 horizontal sections, 4 vertical profiles, 4 corner variants, 4 terminated sections |
| city-paving | 16 | Diagonal rectangular city paving |
| irregular-pavement | 16 | Compact irregular square/polygon paving |
| counter | 4 | Balcão: left end, middle A, middle B, right end |

All 52 sprites have separate 32 × 32 and 64 × 64 exports. Walls and counter preserve real alpha transparency; pavements are opaque. Original generated atlases, import atlases, placement previews, full generation prompts, and a machine-readable manifest are included.

## Selecting a resolution

Use `32x32/` for 32-pixel art cells, and `64x64/` for higher-resolution art. The 64-pixel exports are alternatives, not four times as many floor squares. Object art canvas size alone does not define collision, footprint, draw offset or height. The developer must configure those using the existing project's conventions. Source art is available for finer adjustments.

## Pavement placement

The two pavement sheets are continuous 4 × 4 ground patches sliced into 16 tiles. Numbering runs left to right, then top to bottom:

| | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- |
| Row 1 | 01 | 02 | 03 | 04 |
| Row 2 | 05 | 06 | 07 | 08 |
| Row 3 | 09 | 10 | 11 | 12 |
| Row 4 | 13 | 14 | 15 | 16 |

Place them in this order as one 4 × 4 brush/patch to preserve their internal stone boundaries. Do not randomly shuffle these tiles if continuous paving geometry matters. `placement-preview.png` shows that patch repeated 2 × 2, enlarged with nearest-neighbor sampling. Review outer patch seams in the editor; these are generated textures and do not provide a guaranteed edge-matched autotile system or grass transitions.

## Wall pieces

The wall atlas is 4 × 4: horizontal variants in row 1, vertical profiles in row 2, corner variants in row 3, and terminated variants in row 4. Filenames intentionally identify visual piece categories rather than claiming validated compass-direction connections. Inspect corner orientation and choose the correct piece in the target map editor. The vertical art is narrow; match its footprint to the wall system rather than stretching the image to fill a floor square.

All object sprites retain their atlas cell canvas, including transparent padding. Align the masonry base and join faces using the project's draw offsets. They need a final developer/artist pass for exact joins and corner geometry; they are not engine-tested interchangeable wall modules. Apply the same blocking properties as comparable walls in the existing project.

## Balcão / counter

Assemble horizontally: `counter_left` + `counter_middle_a` + `counter_middle_b` + `counter_right`. Repeat middle sections for a longer counter. The art follows the reference's two broad horizontal tabletop strips, recolored glossy obsidian with subtle purple accents. Counter sections have normalized 54 × 20 art regions at x=5, y=22 inside each 64 × 64 canvas; the 32-pixel exports scale those regions by one half. `assembly-preview.png` shows these art regions side by side with preview-only transparent padding removed. Import the individual sprite PNGs; the preview is not the sprite atlas. Account for the padding when aligning adjacent objects; refine the tabletop seam at joins in the editor. Keep it as a counter object and use the project's existing counter collision configuration.

## Import checklist

1. Import PNGs or use the atlas and zero-based row/column coordinates in `manifest.json`.
2. Assign your own sprite/item IDs; no client-version IDs are assumed.
3. Preserve alpha for objects and solid dark colors for pavement. Never color-key black to transparent.
4. Use nearest-neighbor sampling. Disable smoothing and avoid texture bleeding between atlas cells.
5. Configure ground/object categories, draw offsets, footprint and blocking using equivalent existing assets.
6. Review scale, joins, light direction and character overlap in the target client before release.

The exports are downsampled generated artwork, not hand-authored native-resolution sprites. File dimensions, alpha, sheet counts and ZIP integrity were checked; integration and gameplay behavior require the developer's target client.
