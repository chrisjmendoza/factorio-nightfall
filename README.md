# Nightfall

Vanilla nights are bright enough to work through. You build lamps because the
base looks better with them, not because you were struggling to see, and the
whole lighting system ends up as set dressing.

Nightfall makes night dark enough to matter and cold enough to notice. Unlit
ground genuinely falls away, moonlight turns blue while noon stays exactly as
neutral as it was, and dawn and dusk get a brief warm lift on the way through.

Nauvis only, unless you say otherwise.

## How it works

Two properties on the surface do all of it.

`min_brightness` is the floor the engine refuses to darken past — `0.15` by
default. Lowering it is the whole of "night is darker"; nothing else in the API
makes unlit ground go black.

`brightness_visual_weights` is the interesting one. The engine multiplies each
channel of the colour lookup table by `(1 - w) + brightness * w`, and since
brightness runs inversely to darkness, that is just:

```
channel multiplier = 1 - weight * darkness
```

Two things fall out of that shape, and the mod is built on both:

- A weight does **nothing at noon** and bites hardest at midnight. The neutral
  day end comes free — there is no risk of a mod like this tinting your
  afternoon.
- Every weight in `[0, 1]` **attenuates** rather than brightens, so no mixture
  of profiles can clip a channel. Cold light is made by taking red away, not by
  adding blue.

So the cool night profile weights red heavily and blue barely at all
(`r 0.55, g 0.32, b 0.04`), and the golden-hour profile is the same trick
pointed the other way (`r 0.02, g 0.14, b 0.42`).

The night profile ramps in monotonically with darkness. Golden hour is a
**hump** laid over it, peaking around `darkness 0.36` and gone by full night.
That is deliberately not a straight lerp between a day profile and a night one:
a plain interpolation only passes through warm as an accident of its endpoints
and never lingers there, which is exactly the part of a sunset that is worth
having. Darkness cannot tell dawn from dusk, which costs nothing — the warm lift
belongs at both ends of the day and looks the same at either.

Everything is re-evaluated once a second on an `on_nth_tick`. The light moves
slowly enough that anything more often is wasted work, and each property is only
written when it has actually drifted, so the mod does not dirty the save sixty
times a second.

## The part that matters: these changes live in your save

`min_brightness` and `brightness_visual_weights` are **surface state, not
rendering state**. They are written into the save file. A mod that sets them and
is then removed leaves the modified values behind permanently, and the player is
left with a world that looks broken and no way to tell which of forty mods did
it.

Nightfall treats that as the central problem rather than a footnote:

- The original values are **stashed on first touch**, once per surface, and
  never overwritten — so a value this mod wrote can never later be mistaken for
  one you chose.
- `on_configuration_changed` **hands every surface back its original and takes
  the baseline again**. Anything that changes the mod set or updates this mod
  lands there, and the profile constants may have moved with the update, so
  without this the stored originals would drift a little further from the truth
  each version.
- Turning **Enable Nightfall off** restores every surface immediately. This is
  the intended way out.
- Anything that stops being covered — a surface dropped from the list, a mod
  disabled — is restored on the next pass rather than abandoned mid-change.

**Before you remove the mod, turn it off in the settings** (or run
`/nightfall-reset`) and save. That is the only moment the mod can still give
your lighting back, because a removed mod does not get to run any code.

If it is already too late, the game will do it for you from the console. This
does not need Nightfall installed:

```
/c local s = game.player.surface
s.min_brightness = 0.15
s.brightness_visual_weights = {r = 0, g = 0, b = 0}
```

Those are the engine defaults for every surface on every planet — no prototype
in base or Space Age sets either property, so `0.15` and `{0, 0, 0}` are correct
everywhere. Note that using `/c` disables achievements for that save.

## Commands

| Command | Effect |
| --- | --- |
| `/nightfall-reset` | Hands every surface back the lighting it had before Nightfall touched it |
| `/nightfall-reset vanilla` | Forces the engine defaults instead, for a save where the stashed originals are themselves this mod's old output — a reinstall over a save a previous install had already darkened |
| `/nightfall-debug` | Darkness, both profile mixes, live and target weights, and the multiplier each channel is actually getting |

Neither reset stops the mod reapplying on the next pass; turn it off in the
settings for that.

## Settings

| Setting | Default | Effect |
| --- | --- | --- |
| Enable Nightfall | on | Turning it off restores every surface at once |
| Surfaces affected | `nauvis` | Comma-separated names, or `*` for all. Platforms are always skipped |
| Darkness of night | 0.05 | The brightness floor. Engine default is 0.15; 0 is pitch black |
| Coolness of moonlight | 1.0 | How far night is pushed toward blue. 0 darkens without tinting |
| Golden hour | on | The warm lift through dawn and dusk |
| Strength of golden hour | 1.0 | How warm those get |
| Solar power multiplier | 1.0 | Optional compensation; at 1.0 the property is never written |

### Why Nauvis only

Every Space Age planet has its own lighting character and its own day length —
Fulgora cycles in three minutes against the seven of Nauvis, Aquilo in twenty.
Restyling a planet somebody travelled to for how it looks is not a favour, so
the rest are opt-in by name.

### Two things worth knowing about darker nights

`min_brightness` feeds game mechanics, not just rendering. The API notes it
affects **solar power and biter spawn rates** as well as what you see, so a
darker night is not purely cosmetic. The solar multiplier setting is there if
you would rather not have the lighting change your power balance; leave it at
1.0 and Nightfall never touches that property at all.

The mod also pairs well with anything that makes light worth having —
personal lamps, lit walls, headlamps. Nightfall only changes the ambient level;
every light source in the game still works exactly as before, and is now doing
visible work.

## Building

```
python tools/pack.py Nightfall --deploy
```

Close Factorio first — it holds every mod zip open while it runs.

## Licence

MIT. See [LICENSE](LICENSE).
