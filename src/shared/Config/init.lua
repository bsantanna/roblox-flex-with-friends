--!strict
-- Tunable values for Flex-with-Friends. Magic numbers live here, not in services.
-- See doc/002_implementation_plan.md.
--
-- This module is a thin aggregator: each domain's tunables live in a sibling module (Player, World,
-- Farm, Traffic, ...) and are re-exported here so callers keep using a single `Config.<Domain>`
-- namespace. Splitting keeps each domain small enough to load on its own; assigning each key
-- explicitly (rather than merging) preserves luau's field typing for every consumer.

local Player = require(script.Player)
local Economy = require(script.Economy)
local World = require(script.World)
local Npc = require(script.Npc)
local Outfit = require(script.Outfit)
local Ui = require(script.Ui)
local TrafficCfg = require(script.Traffic)

local Config = {}

-- Player persistence + progression (Player.lua)
Config.DataStoreName = Player.DataStoreName
Config.ProfileTemplate = Player.ProfileTemplate
Config.Decay = Player.Decay

-- Follower economy (Economy.lua)
Config.Travel = Economy.Travel
Config.Photo = Economy.Photo
Config.Invite = Economy.Invite

-- World layout, ground, roads (World.lua)
Config.Zones = World.Zones
Config.Places = World.Places
Config.Terrain = World.Terrain
Config.Terminal = World.Terminal
Config.Roads = World.Roads

-- Green belt (Forest.lua) + farm (Farm.lua)
Config.Forest = require(script.Forest)
Config.Farm = require(script.Farm)

-- Ambient traffic, ground + air (Traffic.lua)
Config.Traffic = TrafficCfg.Traffic
Config.AirTraffic = TrafficCfg.AirTraffic
Config.HeliTraffic = TrafficCfg.HeliTraffic

-- NPC minigame framework + roster (Npc.lua)
Config.Minigame = Npc.Minigame
Config.Npc = Npc.Npc

-- Quest 002 "The Pilot's Forgotten Packages" tunables (Quest.lua)
Config.Quest = require(script.Quest)

-- Gym equipment (Gym.lua)
Config.Gym = require(script.Gym)

-- The gym friends (12 NPCs, 4 types x 3) and their AI/dialog tunables live in a submodule;
-- GymFriendService spawns them and runs their branching dialog.
Config.GymFriends = require(script.GymFriends)

-- NPC outfit default + create-your-friend editor (Outfit.lua)
Config.DefaultNpcOutfit = Outfit.DefaultNpcOutfit
Config.OutfitEditor = Outfit.OutfitEditor

-- Client HUD: dev console + cellphone (Ui.lua)
Config.DevConsole = Ui.DevConsole
Config.UI = Ui.UI

-- Flower clusters scattered across the Home zone (Flower.lua)
Config.Flower = require(script.Flower)

return Config
