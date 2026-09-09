data:extend({
	{
		type = "bool-setting",
		name = "nightfall-enabled",
		setting_type = "runtime-global",
		default_value = true,
		order = "a",
	},
	-- A list rather than a toggle, because the choice is per surface and the
	-- safe default is "only the planet whose look nobody came for".
	{
		type = "string-setting",
		name = "nightfall-surfaces",
		setting_type = "runtime-global",
		default_value = "nauvis",
		allow_blank = true,
		order = "b",
	},
	{
		type = "double-setting",
		name = "nightfall-night-brightness",
		setting_type = "runtime-global",
		default_value = 0.05,
		minimum_value = 0.0,
		maximum_value = 0.15, -- the engine default; above it there is no mod
		order = "c",
	},
	{
		type = "double-setting",
		name = "nightfall-cool-strength",
		setting_type = "runtime-global",
		default_value = 1.0,
		minimum_value = 0.0,
		maximum_value = 1.5,
		order = "d",
	},
	{
		type = "bool-setting",
		name = "nightfall-golden-hour",
		setting_type = "runtime-global",
		default_value = true,
		order = "e",
	},
	{
		type = "double-setting",
		name = "nightfall-golden-strength",
		setting_type = "runtime-global",
		default_value = 1.0,
		minimum_value = 0.0,
		maximum_value = 1.5,
		order = "f",
	},
	{
		type = "double-setting",
		name = "nightfall-solar-multiplier",
		setting_type = "runtime-global",
		default_value = 1.0,
		minimum_value = 0.5,
		maximum_value = 3.0,
		order = "g",
	},
})
