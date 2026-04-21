--!strict

local Constants = {
	Remotes = {
		Folder = "Remotes",
		Request = "BrawlRequest",
		State = "BrawlState",
	},
	Actions = {
		Punch = "Punch",
	},
	Combat = {
		PunchRange = 5,
		PunchDamage = 10,
		PunchCooldown = 0.4,
		KnockbackBase = 40,
		KnockbackGrowth = 1.5,
		KnockbackVertical = 35,
	},
	Arena = {
		YKillThreshold = -50,
		AxisLockValue = 0,
	},
	PlayerState = {
		InLobby = "InLobby",
		InArena = "InArena",
	},
	CharacterAttributes = {
		HitSeq = "BrawlHitSeq",
		EliminationSeq = "BrawlEliminationSeq",
	},
	Assets = {
		PunchAnimationId = "rbxassetid://105919524623967",
		PunchHitSound = {
			Id = "rbxassetid://139697578472716",
			Volume = 0.7,
			RollOffMinDistance = 10,
			RollOffMaxDistance = 80,
		},
		EliminationSound = {
			Id = "rbxassetid://76627054450785",
			Volume = 0.85,
		},
	},
}

return Constants
