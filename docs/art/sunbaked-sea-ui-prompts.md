# Sunbaked Sea: image prompts for the UI

One prompt per image the shop and HUD need. Style: `sunbaked-sea`
(`C:\RobloxDev\library\ui\styles\sunbaked-sea\style.md`).

## How to use these

1. **Paste the STYLE block first, then the image's prompt.** AI image tools forget everything
   between prompts, so the style has to be repeated every time. That is what keeps the images matching.
2. **Generate at 1024 x 1024** (or the closest size the tool allows), then crop and resize to the
   **Final size** listed.
3. **Remove the magenta background** (Photopea: Magic Wand on the magenta, then Delete) and
   export as PNG with transparency.
4. **Check the image against the rules** before keeping it: same outline colour and thickness, light
   coming from the top, no text unless the prompt asks for it, nothing cut off at the edges.
5. **Upload to Roblox** and put each image's asset id in `C:\RobloxDev\library\ui\icons.md`.

Two terms used below:
- **Tintable**: drawn in white and greys so Roblox can recolour it (`ImageColor3`). One drawing
  becomes several colours. The outline stays dark after recolouring.
- **9-slice**: the image stretches to any size without its corners warping
  (`ScaleType = Slice`, `SliceCenter` = the margins given). The corners must fit inside the
  margins, and the middle and edge strips must be plain, because they get stretched.

---

## STYLE (paste before every prompt)

> Hand-painted cartoon game UI asset for a bright, goofy Roblox simulator game about refilling the
> dried-up oceans. Chunky, thick, toy-like shapes with soft rounded forms. Every shape has a bold,
> uniform dark navy outline (#1B2A3A), the same thickness all the way around, drawn like confident
> hand inking: clean, with a very slight organic wobble, never perfectly vector-geometric and never
> sketchy. Flat cel-shaded painting: one flat base colour and a solid darker shadow band along the
> bottom edge (about 15% of the height) so it looks raised and chunky. No gradient, no highlight
> band, no shine spots, no sparkles. Light always comes
> from the top. Saturated, warm, cheerful colours. Front-facing, centred, fully inside the canvas
> with even empty margin around it, nothing cropped. Isolated on a flat solid magenta (#FF00FF)
> background with no shadow, glow, scenery or floor. No text, no letters, no numbers, no watermark,
> no signature. No realistic photo textures, no 3D render look, no noise, no blur.

Colour reference (use only these unless a prompt says otherwise):
dry sand #E8C48A, baked crack brown #9A6B3F, sun rim cream #FFF1C9, deep water #1F5FA8,
shallow water #3FA9E0, foam white #FFFFFF, outline navy #1B2A3A, coral red #FF5A4E,
sunny orange #FFB23F, sea teal #2FC7B0, locked slate #3A4A5C.

**Edges, by group:**
- **Dry things** (frame, cracks, sun, shell): irregular, slightly wobbly outer silhouette,
  like dried mud.
- **Wet things** (panels, tiles, buttons, tags): smooth, clean rounded rectangles.
- **Icons**: bold simplified chunky shapes.

The difference between dry and wet edges is the point of the style.

---

## A. Frames, panels and buttons (9-slice)

### A1. Main menu frame (dried seabed)
Final size: **1024 x 640**. 9-slice margins: **120 px** on every side. Not tintable.

> A wide rectangular picture-frame border made of cracked, sun-baked dry seabed mud, seen straight
> on. The border band is thick (about 110 px of 1024) with rounded outer corners (radius about 90 px). The
> outer silhouette is slightly irregular and wobbly like dried clay, with tiny chips taken out of the
> edge. The fill is warm dry sand #E8C48A with a soft painted gradient, fine darker speckles, and a few
> short, thick hand-painted crack lines in baked brown #9A6B3F that stay inside the four corners only.
> A thin cream #FFF1C9 lighter rim runs along the inner edge of the border, and the inner edge is a clean
> rounded rectangle. A thick darker brown #9A6B3F shadow lip runs under the bottom edge so the frame
> looks like a raised slab. The centre of the frame is completely empty and filled with flat
> magenta #FF00FF. The top, bottom, left and right edge strips are plain sand with only even speckles
> (no cracks, no details) so they can stretch.

### A2. Crack decals (set of 3)
Final size: **256 x 256** each, used on top of the frame wherever you want. Not tintable.

> Three separate hand-painted dry-mud crack marks laid out in a row with space between them: one
> short zig-zag crack, one Y-shaped forking crack, one small cluster of three branching cracks.
> Thick, tapered, chunky crack lines in baked brown #9A6B3F with a thin cream #FFF1C9 highlight along
> their top edges, as if carved into dry clay. No outline around them. Nothing else in the image.

### A3. Inner panel (deep water)
Final size: **512 x 512**. 9-slice margins: **64 px**. Not tintable.

> A smooth rounded-rectangle panel (corner radius about 56 px of 512), filled with deep ocean blue
> #1F5FA8 with a gentle top-to-bottom gradient that gets slightly darker near the bottom. Two or three
> very faint, soft lighter wave-ripple lines drawn only in the four corners. A thick navy #1B2A3A
> outline. A darker navy shadow lip about 14 px tall runs under the bottom edge so it looks raised.
> The middle and the straight edge strips are plain, smooth colour with no details.

### A4. Tile (tintable)
Final size: **256 x 256**. 9-slice margins: **48 px**. Tintable: shallow blue for normal tiles,
slate for locked ones.

> A chunky square button tile with rounded corners (radius about 36 px of 256), drawn only in white and
> light greys: a near-white #F2F2F2 base with a soft vertical gradient, a pure white highlight band
> along the top edge, a mid-grey #BDBDBD shadow band along the bottom inside edge, and a small white
> shine spot top-left. Thick navy #1B2A3A outline, clean smooth edges, and a navy shadow lip about
> 10 px tall under the bottom. Middle is plain.

### A5. Selection ring
Final size: **256 x 256**. 9-slice margins: **48 px**. Goes over a tile when it is selected.
Tintable.

> A rounded-square outline ring only (corner radius about 40 px of 256), hollow in the middle (magenta
> showing through). The ring is pure white, about 14 px thick, with a soft white outer glow, plus two
> small four-point sparkle stars on the top-right corner. No fill inside.

### A6. Category name tag (tintable pill)
Final size: **512 x 128**. 9-slice margins: **64 px** left and right, **40 px** top and bottom.
Tintable: sunny orange for Tool, sea teal for Speed.

> A wide horizontal pill-shaped capsule with fully rounded ends, drawn in white and light greys with
> the cel-shading from the style (white top highlight band, light grey base, mid-grey bottom shadow
> band, small shine top-left). Thick navy #1B2A3A outline with smooth clean edges. Navy shadow lip
> under the bottom. Plain in the middle, no icon, no text.

### A7. Tab button (tintable)
Final size: **384 x 128**. 9-slice margins: **48 px**. Tintable: shallow blue when active, sand
when not.

> A wide chunky rounded-rectangle button (corner radius about 36 px), slightly taller at the bottom
> like a raised keycap. White and light-grey cel-shading as in the style, thick navy #1B2A3A outline,
> clean smooth edges, a navy bottom lip about 12 px tall. Plain in the middle, no text.

### A8. Big action button (Buy, tintable)
Final size: **512 x 160**. 9-slice margins: **64 px** left and right, **48 px** top and bottom.
Tintable: coral red when you can buy, slate when you can't.

> A big fat chunky rounded-rectangle game button (corner radius about 44 px), looking squishy and
> very pressable. White and light-grey cel-shading with a strong white glossy highlight stripe across
> the top third and a clear mid-grey shadow band at the bottom inside edge. Thick navy #1B2A3A
> outline, clean smooth edges, a thick navy bottom lip about 16 px tall. Plain in the middle, no text.

### A9a. Close button: sun-hot X
Final size: **128 x 128**. Not 9-slice. Not tintable.

> A chunky square close button with rounded corners, coral red #FF5A4E with cel-shading, thick navy
> outline and bottom lip. In the centre a bold white X with a navy outline. The button gives off a
> soft sunny orange #FFB23F heat glow and three tiny wavy heat lines above it, as if it is
> sun-scorched hot.

### A9b. Close button: life ring
Final size: **128 x 128**. Not 9-slice. Not tintable.

> A cartoon life ring (life buoy) seen straight on: a fat donut with four alternating segments, coral
> red #FF5A4E and white, cel-shaded with a top highlight and bottom shadow, thick navy outline. The
> hole in the middle shows deep blue #1F5FA8, and inside the hole is a small bold white X with a navy
> outline. A short bit of rope loops around the outer edge.

---

## B. Small icons

### B1. Coin
Final size: **128 x 128**.

> A chunky cartoon gold coin seen slightly tilted, sunny orange-gold #FFB23F with a thick rim, a
> raised water-drop emblem stamped in the centre, a big white shine streak, thick navy outline, and a
> darker gold edge showing the coin's thickness at the bottom.

### B2. Level pip: full and empty (2 images)
Final size: **64 x 64** each.

> Full: a small fat cartoon water droplet, shallow blue #3FA9E0 with a bright white shine spot, soft
> lighter top and deeper blue bottom, thick navy outline.
> Empty: the exact same droplet shape and outline, but the inside is a dry dark slate #3A4A5C with a
> faint crack line across it.

### B3. Lock
Final size: **128 x 128**.

> A chunky cartoon padlock: a fat rounded slate-grey #8C99A8 body with a navy keyhole, a thick grey
> shackle on top, cel-shaded with a top highlight, thick navy outline.

### B4. Unknown tool ("???")
Final size: **256 x 256**.

> A round mystery badge: a dark slate #2A3746 circle with a soft inner shadow, a big chunky
> light-grey question mark in the centre with a navy outline, and three tiny sparkle stars around
> it. Mysterious but playful.

---

## C. Decorations (stuck on the frame corners)

### C1. Starfish
Final size: **256 x 256**.

> A chubby five-armed cartoon starfish with rounded arm tips, coral red #FF5A4E with cel-shading,
> small cream #FFF1C9 bumps dotted along each arm, thick navy outline, tilted about 15 degrees.

### C2. Scallop shell
Final size: **256 x 256**.

> A fan-shaped scallop seashell with six rounded ridges, cream #FFF1C9 with soft sandy #E8C48A
> shading between the ridges, the ridge lines in baked brown #9A6B3F, two small ear flaps at the
> base, thick navy outline, slightly dry and chalky looking.

### C3. Dried seaweed and water drops
Final size: **256 x 160**.

> A small clump of three wilted, droopy cartoon seaweed strands in sea teal #2FC7B0 with one side
> dried and curled, plus two fat shiny water droplets in shallow blue #3FA9E0 beside it, thick navy
> outlines.

---

## D. Upgrade icons

Final size: **512 x 512** each. These matter most, because the spoon-to-Moon ladder is the hook.

Add this to every prompt in this group, after the STYLE block:

> Single object game item icon, seen from a three-quarter view slightly from above and tilted about
> 10 degrees to the right, filling about 80% of the canvas. Any container shown holding water is
> filled to the brim with shallow blue #3FA9E0 water with a white foam shine.

### Tools, in ladder order
1. **Spoon**: A plain shiny silver spoon (light steel grey #CFD8E3 with white shine) holding one
   tiny wobbly blob of water in its bowl. Sad and too small for the job.
2. **Cup**: A chunky white ceramic mug with a fat round handle and a thin coral red stripe around
   the rim, full of water.
3. **Jug**: A round-bellied glass water jug with a handle, slightly blue-tinted glass, full of
   water, a little splash at the spout.
4. **Watering Can**: A sea-teal #2FC7B0 metal watering can with a long spout and a round sprinkler
   head, a few droplets falling from the head.
5. **Bucket**: A coral red #FF5A4E plastic bucket with a grey metal handle, full of sloshing water
   with one splash over the side.
6. **Barrel**: A fat wooden barrel with two dark metal hoops, open on top and full of water. The
   wood is warm brown, not the frame's sand.
7. **Bathtub**: A white clawfoot bathtub with four sunny orange feet, a little rubber duck floating
   on the full water.
8. **Hot Tub**: A round wooden hot tub full of bubbling water with small steam curls and bubbles.
9. **Kiddie Pool**: A round inflatable kiddie pool with fat puffy rings in coral red and white,
   full of water, a beach ball sitting on the rim.
10. **Fire Truck**: A chunky, short, toy-like cartoon fire truck, coral red with a white ladder and
    a fat hose spraying a jet of water. No logos or lettering.
11. **Swimming Pool**: A small rectangular in-ground swimming pool tile seen from above at an angle,
    with a chrome ladder and a diving board, full of bright water with light ripples.
12. **Water Tower**: A tall cartoon water tower on four stilt legs, a round sea-teal tank with a
    pointy cone roof, water leaking from a small spigot.
13. **Tanker Truck**: A chunky cartoon tanker truck with a long silver cylinder tank and a stubby
    cab, a hose hanging off the back dripping water. No logos or lettering.
14. **Cargo Ship**: A chunky toy-like cargo ship with a deep blue hull, a white cabin, and colourful
    stacked containers, its whole deck flooded and overflowing with water.
15. **Rain Cloud**: A fat fluffy white-and-grey cartoon rain cloud with a determined little face,
    heavy fat raindrops pouring out of the bottom.
16. **Iceberg**: A big chunky iceberg with flat faceted sides in white and pale ice blue, a small
    part above a strip of water and a larger part below, a little dripping.
17. **Waterfall**: A chunky cliff of sandy rock with a wide waterfall pouring off it into a
    splashing foam pool at the bottom, as a compact, self-contained object.
18. **Hurricane**: A swirling cartoon hurricane spiral seen from slightly above, white and grey
    clouds spinning around a calm eye, with rain and water whipped around the edges.
19. **Glacier**: A huge slab of chunky glacier ice with layered blue-white stripes, flat top with a
    bit of snow, its front edge melting into streams of water.
20. **The Moon**: A big round cartoon moon, cream-grey with chunky craters, a smug sleepy face, and
    a fishing rope tied around it, scooping up a huge wave of ocean water along its bottom edge. The
    funniest and most epic icon of the set.

### Speed upgrades
21. **Swift Feet**: A brown leather boot with a chunky sole, two little white feathered wings on the
    ankle, and three white speed lines trailing behind it.
22. **Quick Hands**: An open cartoon hand in a cupped scooping pose, light skin tone #F5C69A, three
    curved motion lines around it and a few water droplets flying off the fingertips.

---

## E. Optional extras

- **Category icons for the name tags** reuse D1 Spoon (Tool) and D21 Swift Feet (Speed), shrunk to
  96 x 96.
- **Tab icons** (Upgrades, Tool Ladder, Stats), each **128 x 128**:
  - Upgrades: a green-teal arrow pointing up with a coin.
  - Tool Ladder: a short wooden ladder with a spoon on the bottom rung and a moon on the top rung.
  - Stats: a clipboard with a rising water-level bar.

### E1. Upgrades button (shield badge)
**Final size:** 256 x 256, transparent. The owner's reference: a shield-shaped badge, a big green
arrow shooting up and away from the viewer, two leaves at the base and a coin. Drawn in this style so
it sits with the hotbar and bars. "UPGRADES" and "TAB" are TextLabels added in Roblox (white with a
navy outline, like the rest of the HUD), so the image has no text; leave room for them.

> A chunky shield-shaped game badge, wider at the top with softly rounded corners and a rounded
> point at the bottom, in deep water blue (#1F5FA8) with a thick sun rim cream (#FFF1C9) border
> and the bold navy outline around everything, the solid darker band along its bottom edge so it
> looks raised like a toy. Bursting out of the badge, a big fat 3D arrow in bright sea green
> (#2FC7B0) pointing up and away from the viewer in strong perspective: the arrowhead large and
> close at the top left, the shaft narrowing as it goes back into the badge, with a flat lighter
> green top face and a darker green side face. The arrowhead breaks out past the top edge of the
> shield. A small round gold coin (#FFB23F) with a navy outline sits on the badge's lower right,
> overlapping the arrow's base. Two chunky rounded leaves in leafy green fan out from behind the
> bottom of the shield, one to each side. Keep the lower third of the shield plain and uncluttered
> (a label goes over it) and the top-right corner clear (a small key tag goes there).

## Still to upload
Every image above. Put each id in `C:\RobloxDev\library\ui\icons.md` once it is uploaded.
