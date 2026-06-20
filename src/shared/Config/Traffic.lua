--!strict
-- Ambient traffic tunables: ground cars (TrafficService) and air traffic (AirTrafficService).

local Traffic = {}

-- Ambient cars (TrafficService): decorative, server-driven traffic that random-walks the road network
-- (inner grid + perimeter loop + ramps + elevated ring), staying in lane and stopping for players.
Traffic.Traffic = {
	Cars = 16, -- cars roaming the whole network
	Speed = 26, -- cruising studs per second
	LaneOffset = 6, -- studs from the road centre into the right-hand lane
	TurnIn = 18, -- studs before a junction where the in-lane curve starts, keeping the turn local so the body stays off walkways
	StopDistance = 16, -- decelerate/stop for a player within this distance ahead, in-lane
	StuckSeconds = 30, -- if a car barely moves for this long, respawn it ahead on the road
	RespawnAhead = 24, -- studs to teleport a stuck car forward along its route (> StopDistance so it clears the blockage)
	BalloonSeconds = 10, -- how long the angry comic balloon shows over a respawned car
}

-- Ambient air traffic (AirTrafficService): a fixed fleet of decorative planes flying a continuous
-- airport lifecycle over the city -- takeoff roll, climb-out, an oval cruise circling the town,
-- descent, landing, taxi and park -- then looping. The horizontal flight track is a single ellipse
-- (Oval) whose +Z extreme is tangent to the runway centre, so takeoff and landing both line up with the
-- runway heading (+X). With Planes staggered evenly across TotalCycle, exactly one plane begins its
-- takeoff every TotalCycle/Planes seconds. The runway runs along X, centred on Zones.Airport.
Traffic.AirTraffic = {
	Planes = 3, -- fleet size; staggered evenly -> a takeoff every TotalCycle/Planes (100s)
	TotalCycle = 300, -- seconds for one plane's full lifecycle (5 minutes)
	Runway = {
		Length = 500, -- studs along X, centred on Zones.Airport
		Width = 30,
		Y = 1, -- runway driving-surface height above the apron platform
		-- Foundation apron: a built-up concrete island in the lake under the runway + taxiways, so the
		-- runway doesn't float on open water. Sized to also hold the taxi U-turns and the parking spot;
		-- offset toward +Z (the parking side). Depth reaches below the water surface so it reads as solid.
		Apron = { Length = 580, Width = 100, OffsetZ = 20, Depth = 10 },
	},
	GroundY = 2.5, -- plane pivot (belly) height while taxiing / on the runway
	CruiseAltitude = 130, -- plane pivot height while cruising, above Zones.Airport.Y (clears the ring + tall builds)
	Oval = {
		Ax = 320, -- ellipse half-width along X (spans the city's width)
		Az = 280, -- ellipse half-depth along Z; its +Z extreme touches the runway centreline (Az = airport gap)
		Laps = 5, -- cruise laps over the city between climb-out and descent
	},
	Bank = 16, -- degrees of roll banking into the oval (right) turn
	ClimbPitch = 12, -- degrees nose-up through the climb
	DescentPitch = 7, -- degrees nose-down through the descent
	Park = Vector3.new(150, 0, 46), -- parking-apron spot, offset from Zones.Airport
	-- Phase durations (seconds); these sum to TotalCycle. Cruise is the bulk.
	Phases = {
		TakeoffRoll = 7,
		Climb = 18,
		Cruise = 210,
		Descent = 22,
		LandingRoll = 9,
		TaxiPark = 13,
		ParkHold = 13,
		TaxiThreshold = 8,
	},
}

return Traffic
