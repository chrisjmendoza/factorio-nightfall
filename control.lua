-- Nightfall: nights that are actually dark, and actually cold-coloured.
--
-- Two surface properties do all the work:
--
--   min_brightness            the floor the engine refuses to darken past, so
--                             lowering it is what lets unlit ground go black.
--   brightness_visual_weights bends the colour lookup table per channel as the
--                             light falls, which is what makes that darkness
--                             read as moonlight rather than as someone having
--                             pulled the gamma down.
--
-- Both are saved surface state, not rendering state. A mod that sets them and
-- then vanishes leaves the player in a permanently broken-looking world with
-- nothing to point at, so every write here is paired with a stashed original
-- and several ways to get it back. See "Giving it back" below.

-- Engine defaults, from the 2.0 runtime docs for LuaSurface. No prototype can
-- set either one -- nothing in base or Space Age mentions them -- so every
-- surface on every planet starts here regardless of which planet it is. That
-- makes them a safe target for /nightfall-reset vanilla in the one case the
-- stashed originals cannot be trusted: a reinstall over a save that the
-- previous install had already modified.
local VANILLA_MIN_BRIGHTNESS = 0.15
local VANILLA_WEIGHTS = {r = 0, g = 0, b = 0}
local VANILLA_SOLAR = 1.0

local UPDATE_INTERVAL = 60 -- ticks between passes; the light moves slowly
local EPSILON = 0.0005 -- below this a rewrite is not worth dirtying the save

-- Channel weights, before the strength settings scale them.
--
-- The engine multiplies each LUT channel by `(1 - w) + brightness * w`. With
-- brightness running inversely to darkness that reduces to `1 - w * darkness`,
-- and two consequences fall out of it that shape everything below:
--
--   * a weight does nothing at noon and bites hardest at midnight, so the day
--     end of the curve stays neutral for free;
--   * every weight in [0, 1] attenuates rather than brightens, so no mixture
--     of the two profiles can blow a channel out.
--
-- Cool: red falls fastest and blue barely moves, which is moonlight.
-- Golden: the same trick pointed the other way, held to a narrow band.
local COOL_WEIGHTS = {r = 0.55, g = 0.32, b = 0.04}
local GOLDEN_WEIGHTS = {r = 0.02, g = 0.14, b = 0.42}

-- The darkness bands the two profiles live in. Darkness cannot tell dawn from
-- dusk, which costs nothing here: the warm lift belongs at both ends of the
-- day and looks the same at either.
local GOLDEN_BAND = {0.10, 0.62}
local NIGHT_BAND = {0.40, 0.88}

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function smoothstep(x, low, high)
	local t = clamp((x - low) / (high - low), 0, 1)
	return t * t * (3 - 2 * t)
end

-- A smooth 0 -> 1 -> 0 hump across a band, for an effect that belongs at a
-- moment in the cycle rather than at one end of it.
local function hump(x, low, high)
	if x <= low or x >= high then return 0 end
	return math.sin((x - low) / (high - low) * math.pi)
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Reads the weights back as a plain r/g/b table. A ColorModifier may
-- legitimately arrive in either the named or the array form, and an omitted
-- channel means zero.
local function read_weights(surface)
	local w = surface.brightness_visual_weights or {}
	return {
		r = w.r or w[1] or 0,
		g = w.g or w[2] or 0,
		b = w.b or w[3] or 0,
	}
end

local function weights_differ(a, b)
	return math.abs(a.r - b.r) > EPSILON
		or math.abs(a.g - b.g) > EPSILON
		or math.abs(a.b - b.b) > EPSILON
end

-- Which surfaces Nightfall is allowed to touch.
--
-- Every planet in Space Age has its own day length and its own lighting
-- character -- Fulgora cycles in three minutes against the seven of Nauvis --
-- so restyling all of them by default would be a fair way to ruin a planet the
-- player came to for how it looks. The setting names surfaces explicitly and
-- starts at Nauvis alone; "*" opts the rest in.
local function surface_is_covered(name)
	local list = trim(settings.global["nightfall-surfaces"].value)
	if list == "*" then return true end

	name = name:lower()
	for entry in list:gmatch("[^,]+") do
		if trim(entry):lower() == name then return true end
	end
	return false
end

-- Space platforms have no day to speak of, so they are skipped before the
-- setting is consulted.
local function surface_is_eligible(surface)
	if not (surface and surface.valid) then return false end
	if surface.platform then return false end
	return surface_is_covered(surface.name)
end

-- Giving it back -------------------------------------------------------------
--
-- storage.originals[surface_index] holds what a surface looked like before the
-- first write to it, and doubles as the record of which surfaces are ours to
-- hand back. It is written once per surface and never updated, so a value this
-- mod wrote can never be mistaken for one the player chose.

local function stash_original(surface)
	if storage.originals[surface.index] then return end

	storage.originals[surface.index] = {
		name = surface.name,
		min_brightness = surface.min_brightness,
		weights = read_weights(surface),
		solar_power_multiplier = surface.solar_power_multiplier,
	}
end

local function restore(surface_index, to_vanilla)
	local original = storage.originals[surface_index]
	local surface = game.get_surface(surface_index)

	if surface and surface.valid then
		if to_vanilla or not original then
			surface.min_brightness = VANILLA_MIN_BRIGHTNESS
			surface.brightness_visual_weights = VANILLA_WEIGHTS
			surface.solar_power_multiplier = VANILLA_SOLAR
		else
			surface.min_brightness = original.min_brightness
			surface.brightness_visual_weights = original.weights
			surface.solar_power_multiplier = original.solar_power_multiplier
		end
	end

	storage.originals[surface_index] = nil
end

local function restore_all(to_vanilla)
	-- Collected first, because restore() clears entries as it goes.
	local held = {}
	for surface_index in pairs(storage.originals) do
		held[#held + 1] = surface_index
	end
	for _, surface_index in pairs(held) do
		restore(surface_index, to_vanilla)
	end
	return #held
end

-- Driving it -----------------------------------------------------------------

-- The colour cast for a given darkness, as a ColorModifier.
--
-- The night profile ramps in monotonically; the golden one is a hump laid over
-- it, which is the whole reason this is not a straight lerp between two
-- profiles. A plain interpolation only passes through warm on its way to cool
-- as an accident of the endpoints, and never lingers there.
local function weights_for(darkness)
	local night = smoothstep(darkness, NIGHT_BAND[1], NIGHT_BAND[2])
		* settings.global["nightfall-cool-strength"].value

	local golden = 0
	if settings.global["nightfall-golden-hour"].value then
		golden = hump(darkness, GOLDEN_BAND[1], GOLDEN_BAND[2])
			* settings.global["nightfall-golden-strength"].value
	end

	-- Clamped because the two strengths are independent, and a player who
	-- raises both could otherwise ask for a weight above 1 -- which is a
	-- negative multiplier, a channel driven past black.
	return {
		r = clamp(COOL_WEIGHTS.r * night + GOLDEN_WEIGHTS.r * golden, 0, 1),
		g = clamp(COOL_WEIGHTS.g * night + GOLDEN_WEIGHTS.g * golden, 0, 1),
		b = clamp(COOL_WEIGHTS.b * night + GOLDEN_WEIGHTS.b * golden, 0, 1),
	}
end

local function update_surface(surface)
	stash_original(surface)

	-- min_brightness is a floor, not a curve: during the day the computed
	-- brightness sits far above it and the clamp never fires. Interpolating it
	-- against darkness the way the colour is interpolated would look like it
	-- was doing something while in fact being theatre, so it is written once
	-- and left alone until the setting moves.
	local target_min = settings.global["nightfall-night-brightness"].value
	if math.abs(surface.min_brightness - target_min) > EPSILON then
		surface.min_brightness = target_min
	end

	local target_weights = weights_for(surface.darkness)
	if weights_differ(read_weights(surface), target_weights) then
		surface.brightness_visual_weights = target_weights
	end

	-- Written only when it actually differs, so a save that never asks for a
	-- solar change never has one set by this mod.
	local target_solar = settings.global["nightfall-solar-multiplier"].value
	if math.abs(surface.solar_power_multiplier - target_solar) > EPSILON then
		surface.solar_power_multiplier = target_solar
	end
end

-- The single entry point. Hands back every surface that is no longer ours,
-- then drives the ones that are. Comparing against the live surface value
-- rather than against a record of the last write means an outside change --
-- another mod, a console command -- is corrected on the next pass instead of
-- being silently kept.
local function reconcile()
	local enabled = settings.global["nightfall-enabled"].value

	for surface_index in pairs(storage.originals) do
		local surface = game.get_surface(surface_index)
		if not enabled or not surface_is_eligible(surface) then
			restore(surface_index)
		end
	end

	if not enabled then return end

	for _, surface in pairs(game.surfaces) do
		if surface_is_eligible(surface) then
			update_surface(surface)
		end
	end
end

script.on_nth_tick(UPDATE_INTERVAL, reconcile)

script.on_init(function()
	storage.originals = {}
	reconcile()
end)

-- The requirement this mod is built around. Anything that changes the mod set
-- or this version lands here, and the profile constants above may have moved
-- with it, so every surface is handed back its stashed original and the
-- baseline is taken again from those clean values. Without this the originals
-- would drift a little further from the truth with every update.
script.on_configuration_changed(function()
	storage.originals = storage.originals or {}
	restore_all()
	storage.originals = {}
	reconcile()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	if event.setting:find("^nightfall%-") then
		reconcile()
	end
end)

script.on_event(defines.events.on_surface_created, function()
	reconcile()
end)

-- The surface is already gone, so there is nothing to hand back -- only a
-- stale entry to drop before it outlives the thing it describes.
script.on_event(defines.events.on_surface_deleted, function(event)
	storage.originals[event.surface_index] = nil
end)

-- Commands -------------------------------------------------------------------

local function say(command, message)
	local player = command.player_index and game.get_player(command.player_index)
	if player then
		player.print(message)
	else
		game.print(message)
	end
end

commands.add_command("nightfall-reset",
	"Hand every surface back its original lighting. Add the word vanilla to force the engine defaults instead.",
	function(command)
		local to_vanilla = trim(command.parameter or ""):lower() == "vanilla"

		if to_vanilla then
			-- Covers the one case the stash cannot: a reinstall over a save the
			-- previous install had already darkened, where the originals taken
			-- on first run are themselves this mod's old output.
			for _, surface in pairs(game.surfaces) do
				if not surface.platform then
					surface.min_brightness = VANILLA_MIN_BRIGHTNESS
					surface.brightness_visual_weights = VANILLA_WEIGHTS
					surface.solar_power_multiplier = VANILLA_SOLAR
				end
			end
			storage.originals = {}
			say(command, "[Nightfall] Every surface reset to the engine defaults "
				.. "(min_brightness 0.15, no colour weighting). Turn the mod off in "
				.. "the settings to stop it reapplying.")
			return
		end

		local count = restore_all()
		say(command, string.format(
			"[Nightfall] Restored %d surface(s) to their original lighting. Turn the "
			.. "mod off in the settings to stop it reapplying.", count))
	end)

commands.add_command("nightfall-debug",
	"Report what Nightfall is doing to the surface you are standing on",
	function(command)
		local player = command.player_index and game.get_player(command.player_index)
		local surface = player and player.surface or game.surfaces[1]
		if not surface then return end

		local darkness = surface.darkness
		local target = weights_for(darkness)
		local original = storage.originals[surface.index]

		say(command, string.format(
			"[Nightfall] surface %s (index %d) | enabled %s | eligible %s | platform %s",
			surface.name, surface.index,
			tostring(settings.global["nightfall-enabled"].value),
			tostring(surface_is_eligible(surface)),
			tostring(surface.platform ~= nil)))
		say(command, string.format(
			"  darkness %.3f -> night mix %.2f, golden mix %.2f",
			darkness,
			smoothstep(darkness, NIGHT_BAND[1], NIGHT_BAND[2]),
			settings.global["nightfall-golden-hour"].value
				and hump(darkness, GOLDEN_BAND[1], GOLDEN_BAND[2]) or 0))

		local live = read_weights(surface)
		say(command, string.format(
			"  weights live r%.3f g%.3f b%.3f | target r%.3f g%.3f b%.3f",
			live.r, live.g, live.b, target.r, target.g, target.b))
		-- The multiplier each channel is actually getting right now, which is
		-- the number that explains what is on screen.
		say(command, string.format(
			"  channel multipliers r%.3f g%.3f b%.3f",
			1 - live.r * darkness, 1 - live.g * darkness, 1 - live.b * darkness))
		say(command, string.format(
			"  min_brightness %.3f (vanilla %.2f) | solar x%.2f",
			surface.min_brightness, VANILLA_MIN_BRIGHTNESS,
			surface.solar_power_multiplier))

		if original then
			say(command, string.format(
				"  stashed original: min_brightness %.3f, weights r%.3f g%.3f b%.3f, solar x%.2f",
				original.min_brightness, original.weights.r, original.weights.g,
				original.weights.b, original.solar_power_multiplier))
		else
			say(command, "  stashed original: none -- this surface is untouched")
		end
	end)
