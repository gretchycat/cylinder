@tool
extends RefCounted

# Keep palettes intentionally small.  A species should normally have
# 3–6 closely related colors rather than arbitrary random RGB values.

# Vegetation: choose colors that differ mainly in value/saturation.
const GRASS_DARK := Color("#28551F")
const GRASS_MID := Color("#3E7A2D")
const GRASS_LIGHT := Color("#6FAF45")

# Stems/leaves should generally be darker and less saturated than flowers.
const STEM_DARK := Color("#24552A")
const LEAF_MID := Color("#3B7D32")

# Neutral stone palette with slate and mossy rock tones.
const ROCK_WARM := Color(0.42, 0.44, 0.50, 1.0)
const ROCK_NEUTRAL := Color(0.40, 0.44, 0.50, 1.0)
const ROCK_COOL := Color(0.36, 0.42, 0.50, 1.0)
const ROCK_MOSSY := Color("#FFAA66")

# Mushroom stems and caps.
const MUSHROOM_STEM := Color("#D6C3A1")
const MUSHROOM_CAP_RED := Color("#9D3D35")
const MUSHROOM_CAP_BROWN := Color("#70503B")
const MUSHROOM_CAP_CREAM := Color("#C8B98C")

# Flower colors.  Keep these somewhat muted; the environment should not
# become a field of neon dots.
const FLOWER_RED := Color("#C44B48")
const FLOWER_YELLOW := Color("#D8B83E")
const FLOWER_BLUE := Color("#668FC4")
const FLOWER_PURPLE := Color("#8B6BA8")
const FLOWER_WHITE := Color("#D9D5C5")
const FLOWER_ORANGE := Color("#D9854B")

# Crop/grain.
const CROP_STEM := Color("#6D7D32")
const CROP_HEAD := Color("#C8A83E")

# Shrubs.
const SHRUB_DARK := Color("#254C24")
const SHRUB_MID := Color("#356A2E")
const SHRUB_LIGHT := Color("#538A3C")

# When adding a new biome/species, start with one of these groups rather
# than inventing colors independently.
const FLOWER_COLORS: Array[Color] = [
	FLOWER_RED, FLOWER_YELLOW, FLOWER_BLUE,
	FLOWER_PURPLE, FLOWER_WHITE, FLOWER_ORANGE
]

const ROCK_COLORS: Array[Color] = [
	ROCK_WARM, ROCK_NEUTRAL, ROCK_COOL, ROCK_MOSSY
]

const MUSHROOM_CAP_COLORS: Array[Color] = [
	MUSHROOM_CAP_RED, MUSHROOM_CAP_BROWN, MUSHROOM_CAP_CREAM
]
