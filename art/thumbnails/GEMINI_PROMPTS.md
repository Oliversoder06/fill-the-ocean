# Thumbnail prompts for Gemini

Reference shots are in [scenes/](scenes/), staged and captured in the gameplay place (1104x568,
no HUD; the staging was temporary and the place was left unchanged).
Attach the listed PNG(s) to Gemini, paste the **style block** first, then the scene prompt.
Roblox thumbnails are 1920x1080 (16:9); the icon is 512x512 (1:1).

## Style block (paste first, every time)

```
You are making a high click-through-rate Roblox game thumbnail from the attached in-game screenshot.
Keep the game's identity: blocky Roblox characters (R15 avatars, classic bacon-hair), low-poly
mountains, tropical beach, sand-coloured dried seabed, bright turquoise water. Ignore and remove
the small grey "view cube" widget in the top-right corner of the screenshot. Re-render it as a
polished, glossy 3D promo render: saturated colours, strong warm sunlight from the upper left,
crisp rim light on characters, soft depth of field on the background, slight wide-angle lens.
Characters get big, exaggerated, readable facial expressions (cartoon Roblox faces: shock, smug,
determined, joy). One clear focal point, simple uncluttered background, high contrast between
subject and background. No UI, no watermarks, no Roblox logo. Text, if asked for, is huge, chunky,
white with a thick dark-navy outline and a slight drop shadow, max 4 words, never covering faces.
Output 16:9, 1920x1080.
```

## 1. "HE DRANK THE OCEAN" (main thumbnail, the story hook)
Attach: `01_bacon_drinks_ocean_low.png` (+ `08_bacon_closeup_sipping.png` for his face)
```
A gigantic, round, overstuffed bacon-hair Roblox character, as big as a mountain, sits on a
completely dried-up ocean floor sucking the very last puddle of sea water through a long bendy red
straw. His cheeks are puffed, eyes half closed with smug satisfaction, a drop of water on his chin.
The cracked, sandy seabed stretches to the horizon with stranded fish, a beached rubber duck and
dried seaweed. In the bottom-left foreground a tiny normal-sized Roblox player holds a tiny spoon
and stares up in total shock (jaw dropped, hands on head). Low camera angle looking up at the giant.
Big text top-right: "HE DRANK THE OCEAN!"
```

## 2. "FILL IT BACK" (player vs thief)
Attach: `02_player_faces_thief.png`
```
Over-the-shoulder shot from behind a Roblox player standing at the edge of a beach, holding a
comically small silver spoon raised like a sword. Far out on the empty, dried-up ocean floor sits
the enormous round bacon-hair with his straw, the last puddle almost gone. The player's face is
turned three-quarters toward the camera, determined and angry. Dust swirls over the dry seabed.
Text: "FILL IT BACK..." top, and "WITH A SPOON?!" bottom in yellow.
```

## 3. Before / After (empty vs full)
Attach: `03a_ocean_empty_wide.png` and `03b_ocean_full_wide.png`
```
Split the image diagonally from top-left to bottom-right with a jagged lightning-bolt divider.
Left half: the beach looking out at a completely EMPTY, dry, cracked ocean floor, desaturated and
hot, heat haze. Right half: the exact same view with the ocean FULL, sparkling turquoise water,
dolphins jumping, crabs on the sand, a little boat. A Roblox player stands on the divider line
pouring a huge bucket of water from the empty side into the full side. Labels: "0%" on the left
in red, "100%" on the right in bright green.
```

## 4. Spoon to Moon (progression)
Attach: `04_tool_progression.png`
```
A row of water-carrying tools lined up on a dried-up ocean floor, growing from left to right: a
tiny spoon, a cup, a wooden bucket, a clawfoot bathtub, an inflatable kiddie pool, a whole swimming
pool, a cargo ship and finally the full MOON, each one dramatically bigger than the last, every
item brimming and sloshing with water. A small Roblox player at the far left holds the spoon and
looks up at the Moon with wide, excited eyes. Low camera angle so the Moon towers over everything.
Big curved arrow sweeping from the spoon to the Moon. Text: "SPOON → MOON".
```

## 5. Pouring (core action)
Attach: `05_pour_bathtub.png`
```
Heroic low angle from the water's edge: a Roblox player on the beach lifts an overflowing white
clawfoot bathtub over their head and dumps a huge arcing waterfall of sparkling water into a
half-empty ocean. Big splash and spray where it lands, golden coins bursting out of the splash and
flying toward the camera. Player's face: gritted-teeth effort and joy. Bright blue sky.
Text: "+1,000,000 L" in the top-right corner, in a bubbly blue font with white outline.
```

## 6. Water Bomber (vehicles / late game)
Attach: `06a_water_bomber_drop.png` (+ `06b_firetruck_bomber_cheer.png` for the cheering player)
```
A bright yellow firefighting water-bomber plane swoops low over the ocean and dumps a massive
curtain of water from its belly, motion blur on the plane, spray everywhere. In the foreground on
the beach a red fire truck sprays its hose toward the sea while a Roblox player jumps and cheers
with both arms up. Dynamic tilted camera, speed lines. Text: "UNLOCK PLANES!".
```

## 7. Team carries the Moon (co-op)
Attach: `07_team_carries_moon.png`
```
Four Roblox friends march toward the camera down a beach between two wooden aqueducts, each holding
something huge over their heads: a bucket, a bathtub, a swimming pool, and in the middle one player
straining under the entire MOON. Water sloshes and drips off everything. Expressions: the Moon
carrier sweating and red-faced, the others laughing. Low hero angle, sun flare behind the Moon.
Text: "BRING FRIENDS!" across the top.
```

## 8. Face close-up (alt main thumbnail)
Attach: `08_bacon_closeup_sipping.png`
```
Extreme close-up of the giant bacon-hair's face filling the right two thirds of the frame, sucking
a red straw with cheeks puffed out, eyes looking sideways at the viewer with a guilty, smug grin.
On the left, small and far below, the dried-up ocean floor with a single tiny puddle at the end of
the straw. Text left: "WHERE'S THE OCEAN?!".
```

## Icon (512x512)
Attach: `01_bacon_drinks_ocean_low.png`
```
Square 1:1 Roblox game icon, 512x512. The giant round bacon-hair, centred, sucking a red straw
from a tiny puddle, cheeks puffed, smug. Plain bright turquoise-to-sky-blue radial background, a
thick white outline around the character so it pops at small size. No text.
```

## Tips
- Generate 3 to 4 variations of #1, #2 and #8 and A/B test them (Roblox thumbnail
  personalization tests up to 10 thumbnails).
- If Gemini drifts from the Roblox look, add: "keep characters blocky like Roblox R15 avatars;
  no realistic humans".
- If the text comes out wrong, generate it without text ("No text") and add the words yourself.
