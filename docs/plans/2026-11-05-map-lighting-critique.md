# Map and Lighting Critique (2026-11-05)

From play-mode screenshots at player eye height (5.5 studs) and from above, in each stage, with the
real lighting (`client/Mood.luau`) at fill 0. Each stage was streamed in before shooting.

## The one big problem: the world doesn't look drained

The premise is "the evil sun evaporated all the water". At fill 0, every stage looks like a
pleasant, green late afternoon. Nothing says *heat* or *drought*, and nothing changes when you
fill the basin, so filling has no visual payoff beyond the water rising.

- **The dry and wet lighting looks are almost the same** in `Mood.luau`: saturation 0.30 vs 0.38,
  clock 16.4 vs 16.8, tint nearly white in both.
- **The grass is lush green from the start** in all three stages.
- **The villain isn't in the sky.** The sun is the default white disc, and the angry sun art exists
  but is only used in the shop.
- **The empty pool looks full.** At 0% the `Water` part sits at the bottom of the pool as a
  bright blue, glassy sheet, so the "drained" pool reads as a shallow filled one.
- **The lake and ocean beds are clean, flat sand.** They read as a sandy field and a beach, not a
  drained lakebed or seabed.

## Per stage

**Pool (backyard)**
- The yard is a big empty paved rectangle, and the pool is small in it (30×30 in a yard roughly
  90×130). The 80-stud trip crosses bare pavement.
- The well is a grey stone well in a modern backyard, which doesn't fit.
- Good: clear sightline from spawn to the pool, a strong house backdrop, a tidy walled shape.

**Lake (pine valley)**
- The pines are stair-stepped voxel blocks. They clash with the smooth round trees used
  elsewhere and look unfinished.
- From the spawn you can't see the lake at all: the dry bed is flat sand at almost ground level,
  so there's no destination on the horizon.
- The dock hovers over sand with nothing under it. That could be a nice "the water used to be
  here" clue, but right now it just looks misplaced.
- Good: the stepping-stone path reads as the route; the camp corner has life.

**Ocean (beach cove)**
- Same shape as the lake: a round crater ringed by trees. The ocean should feel huge and open,
  not like a bigger version of the lake.
- The basin walls are a salmon-pink terrain band, and the mountains are grey with a harsh green
  stripe. It reads as default terrain colours.
- Umbrellas, huts and the lifeguard tower sit inside the bowl. Check whether they're above the
  final waterline; if not, they'll vanish underwater, which is fine only if it's intended.
- The well is the same grey stone well as the pool and lake.
- Good: the boardwalk from spawn reads as the route, and the palm ring frames the space.

## Fixes, ranked by impact for the effort

> Status: fixes 1–3 were done on 2026-11-05 (`client/Mood.luau`, `server/Map.luau`). Fix 4 was done
> on 2026-11-05 as a billboard (`Vfx.SkySun`, held in the sun's direction by `client/Mood.luau`),
> because Roblox draws its own sun disc too bright for a face to read. Fixes 5–10 are still open.

**Code only (the agent can do these):**
1. **Make dry look dry.**
   - Push `Mood.DRY` to scorched: warm orange tint, low saturation (about 0.05), more haze and
     glare, bloom up.
   - Keep `WET` as today's look.
2. **The world greens up as you fill.**
   - Lerp terrain grass colours (`Terrain:SetMaterialColor` for `Grass` / `LeafyGrass`) from a
     dry yellow-brown to green with `Fill`, on the client, like the lighting.
   - This is the biggest single visual payoff for filling.
3. **Hide the water at 0%.** Make `Water` invisible (or a small dark puddle) when the fill is
   near 0, so a drained basin looks drained.

**Studio, owner (I can help through the Studio connection):**
4. **Angry sun in the sky.** Set `Lighting.Sky.SunTextureId` to the angry sun and make it larger.
   Needs a square, padded export of the art, because the current file is wider than it is tall
   and would squash.
5. **Drained-bed dressing** inside each basin, buried as the water rises (that burial is a payoff
   in itself):
   - Pool: crack decals on the floor tiles, a waterline stain, a deflated pool toy, a lost flip-flop.
   - Lake: cracked mud, a dark wet-sand ring, a stranded rowboat, a fish skeleton, a tyre, dried
     seaweed (art exists).
   - Ocean: a shipwreck, an anchor and chain, coral and starfish (shell and starfish art exist),
     a beached whale skeleton for the joke.
6. **A source that fits each stage** and can be seen from the basin:
   - Pool: a garden tap with a hose, or a big water barrel.
   - Lake: the hand pump the design already lists.
   - Ocean: something tall, like a water tower or a pipe sticking out of a dune.
7. **Ocean shape.** Open one side of the crater into a long, flat seabed running out to the
   horizon, so the ocean reads as endless. A lighthouse makes a landmark.
8. **Lake trees.** Swap the voxel pines for proper stylized pine models.
9. **Pool yard.** Either shrink the paved area or dress it along the route: lounge chairs, a BBQ,
   a garden gnome, an inflatable flamingo. Keep the straight line from well to pool clear.
10. **Terrain palette.** Set the terrain material colours (sand, rock, grass) to warm
    sunbaked-sea tones so the stages match the UI.

Suggested order: 1–3 first (code, fast, and they change how every minute looks), then 4, then
5–6 per stage starting with the pool (players see it first), then 7–10.
