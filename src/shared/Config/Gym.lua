--!strict
-- Gym equipment on the CentralBuilding's opened first floor. GymService builds each station from
-- primitives (like SceneryService); the station is placed at an absolute world position on the
-- first-floor surface (y=23) facing Yaw degrees (0 looks -Z). Positions are tuned by looking in
-- Studio. The Phase-2 NPC spawner reads this same table to post a gym-goer at each station.
type GymStation = { Kind: string, Position: Vector3, Yaw: number }

local Gym = {
	Stations = {
		-- Cardio, nearest the spiral-stair entrance (stair occupies X[-33,-14], Z[-37,-19]); the two
		-- centre columns are left open here as the walk-in corridor. Treadmills/bikes face south
		-- (Yaw 180) so their consoles greet players coming up the stair.
		{ Kind = "ExerciseBike", Position = Vector3.new(-50, 23, -47), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-39, 23, -47), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-5, 23, -47), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-50, 23, -59), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-39, 23, -59), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-5, 23, -59), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-50, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-39, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-28, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-16, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-5, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-50, 23, -83), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-39, 23, -83), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-28, 23, -83), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-16, 23, -83), Yaw = 180 },
		{ Kind = "WaterCooler", Position = Vector3.new(-5, 23, -83), Yaw = 0 },
		-- Strength, mid hall.
		{ Kind = "WeightBench", Position = Vector3.new(-50, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-39, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-28, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-16, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-5, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-50, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-39, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-28, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-16, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-5, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-50, 23, -119), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-39, 23, -119), Yaw = 0 },
		-- Floor / stretching, north end.
		{ Kind = "Mat", Position = Vector3.new(-28, 23, -119), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-16, 23, -119), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-5, 23, -119), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-50, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-39, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-28, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-16, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-5, 23, -131), Yaw = 0 },
		-- Water coolers framing the entrance on the two side pads.
		{ Kind = "WaterCooler", Position = Vector3.new(-48, 23, -28), Yaw = 0 },
		{ Kind = "WaterCooler", Position = Vector3.new(-6, 23, -28), Yaw = 0 },
		-- Mirror walls flush against the west wall, facing east into the hall (clear of the entrance).
		{ Kind = "MirrorWall", Position = Vector3.new(-56, 23, -75), Yaw = 90 },
		{ Kind = "MirrorWall", Position = Vector3.new(-56, 23, -110), Yaw = 90 },
	} :: { GymStation },
}

return Gym
