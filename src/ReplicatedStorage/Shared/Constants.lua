--!strict

local Constants = {
	Remotes = {
		Folder = "Remotes",
		Request = "BrawlRequest",
		State = "BrawlState",
		Events = "BrawlEvents",
		Arena = "BrawlArenaState",
	},
	Actions = {
		Punch = "Punch",
		HeavyPunch = "HeavyPunch",
		DodgeRoll = "DodgeRoll",
		DI = "DI",
	},
	EventTypes = {
		KillFeed = "KillFeed",
		Streak = "Streak",
		LevelUp = "LevelUp",
		RankUp = "RankUp",
		SeriesEvent = "SeriesEvent",
		XPGain = "XPGain",
		FPGain = "FPGain",
	},
	Combat = {
		-- Frame data por move. Cada move tem 4 fases temporais:
		--   Startup  : windup antes da hitbox existir (nenhum hit possível)
		--   Active   : hitbox ativa (pode conectar; checado em Heartbeat a cada tick)
		--   Recovery : anim terminando; sem cancel — swing inteiro é committed
		--   ComboWindow : após recovery, ainda pode iniciar o próximo jab do zero
		-- Total "lockout sem encadear" = Startup + Active + Recovery.
		-- Hitstop no alvo = clamp(HitstopBase + damagePercentAlvo * HitstopScale, HitstopBase, HitstopMax).
		-- Hitstop no atacante = hitstopAlvo * HitstopAttackerRatio.
		-- LungeSpeed: studs/s aplicados ao longo do facing durante Startup+Active.
		-- Move locka WalkSpeed=0 e AutoRotate=false pela duração inteira (sem virar
		-- lateralmente no meio da anim) — direção é committed ao apertar M1.
		Moves = {
			-- HitstopScale: segundos de hitstop adicionados por 1% de damage do alvo.
			-- Jab: atinge cap em ~100% damage; Jab3/Heavy: cap em ~100% (mais peso mais rápido).
			-- Fórmula: hitstop = clamp(Base + damage% * Scale, Base, Max).
			Jab1 = {
				AnimationId = "rbxassetid://116333012742297",
				Damage = 7,
				Range = 5,
				BackOffset = 2,
				Height = 6,
				Depth = 2.5,
				CloseRadius = 3.5,
				Startup = 0.06,
				Active = 0.06,
				Recovery = 0.18,
				ComboWindow = 0.28,
				HitstopBase = 0.10,
				HitstopScale = 0.0010,
				HitstopMax = 0.20,
				HitstopAttackerRatio = 0.55,
				KnockbackMult = 0.55,
				LungeSpeed = 65,
				HitKind = "Light",
				Next = "Jab2",
				IsHeavy = false,
			},
			Jab2 = {
				AnimationId = "rbxassetid://111917829178320",
				Damage = 8,
				Range = 5,
				BackOffset = 2,
				Height = 6,
				Depth = 2.5,
				CloseRadius = 3.5,
				Startup = 0.07,
				Active = 0.06,
				Recovery = 0.20,
				ComboWindow = 0.28,
				HitstopBase = 0.11,
				HitstopScale = 0.0011,
				HitstopMax = 0.22,
				HitstopAttackerRatio = 0.55,
				KnockbackMult = 0.70,
				LungeSpeed = 65,
				HitKind = "Light",
				Next = "Jab3",
				IsHeavy = false,
			},
			Jab3 = {
				AnimationId = "rbxassetid://88502951126069",
				Damage = 15,
				Range = 6,
				BackOffset = 2,
				Height = 6,
				Depth = 2.5,
				CloseRadius = 3.8,
				Startup = 0.12,
				Active = 0.08,
				Recovery = 0.35,
				ComboWindow = 0,
				HitstopBase = 0.18,
				HitstopScale = 0.0016,
				HitstopMax = 0.34,
				HitstopAttackerRatio = 0.60,
				KnockbackMult = 1.35,
				LungeSpeed = 88,
				HitKind = "Light",
				Next = nil,
				IsHeavy = false,
			},
			Heavy = {
				AnimationId = "rbxassetid://83755342484641",
				Damage = 30,
				Range = 8,
				BackOffset = 2,
				Height = 6,
				Depth = 2.5,
				CloseRadius = 3.5,
				Startup = 0.32,
				Active = 0.10,
				Recovery = 0.50,
				ComboWindow = 0,
				HitstopBase = 0.20,
				HitstopScale = 0.0020,
				HitstopMax = 0.40,
				HitstopAttackerRatio = 0.60,
				KnockbackMult = 1.50,
				LungeSpeed = 48,
				HitKind = "Heavy",
				Next = nil,
				IsHeavy = true,
			},
		},
		InputBufferWindow = 0.15,
		DodgeRollCooldown = 3.0,
		DodgeRollDurationSeconds = 0.5,
		DodgeRollVelocityMultiplier = 1.5,
		DodgeRollAnimSpeedMultiplier = 2.0,
		DoubleJumpVelocity = 75,
		KnockbackBase = 40,
		KnockbackGrowth = 1.5,
		KnockbackVertical = 35,
		-- Rate limit: 3 jabs + heavy + dodge em ~1s é possível em combo agressivo.
		-- Margem pra 8 requests evita engasgo legítimo enquanto ainda bloqueia spam.
		-- DI tem rate limit próprio (menos agressivo).
		RateLimitWindow = 1.0,
		RateLimitMaxRequests = 8,
		-- Lunge block: se durante o impulso do soco encontrar outro char dentro
		-- desse raio (XY plane, só pra frente no eixo do facing), cancela o
		-- lunge pra char não atravessar o oponente. Hitbox ainda conecta (é
		-- resolvida server-side), o cancel só impede o "phase through".
		LungeBlockRadius = 3.5,
	},
	-- Lag compensation (B1): snapshot ring buffer das posições dos players no
	-- servidor, permitindo resolver hitbox contra a posição que o atacante
	-- *viu* ao atacar, não a posição atualizada depois que o request viajou.
	LagComp = {
		SnapshotHistorySeconds = 0.5,  -- quanto passado guardamos (30 snaps @ 60Hz)
		MaxRewindSeconds = 0.25,       -- rewind máximo aceito (anti-abuse)
	},
	-- Directional Influence (B2): input horizontal do alvo durante hitstop
	-- deflete o vetor de knockback. Se segura direção oposta ao KB, deflete
	-- pra cima (+15°); mesma direção → pra baixo (-10°). Escala linear com
	-- magnitude do input (joystick parcial = deflexão parcial).
	DI = {
		MaxAngleOppositeDeg = 15,
		MaxAngleSameDeg = -10,
		FreshnessSeconds = 0.5,
		-- Rate limit dedicado: cliente pode mandar re-updates durante hitstop
		-- se input muda; ~4 updates/s é o teto razoável.
		RateLimitMaxRequests = 4,
	},
	Arena = {
		YKillThreshold = -50,
		AxisLockValue = 0,
		KillAttributionWindow = 5.0,
		InvincibilityDuration = 1.0,
	},
	PlayerState = {
		InLobby = "InLobby",
		InArena = "InArena",
	},
	PlayerMovement = {
		WalkSpeed = 32,
		JumpHeight = 14.4,
		JumpPower = 100,
	},
	CollisionGroups = {
		Players = "BrawlPlayers",
		PlayersDodging = "BrawlPlayersDodging",
	},
	Tags = {
		JumpThroughPlatform = "BrawlJumpThrough",
		DonateKiosk = "BrawlDonateKiosk",
		FadingLabel = "BrawlFadingLabel",
	},
	CharacterAttributes = {
		HitSeq = "BrawlHitSeq",
		EliminationSeq = "BrawlEliminationSeq",
		LastHitterId = "BrawlLastHitterId",
		LastHitTime = "BrawlLastHitTime",
		InvincibleUntil = "BrawlInvincibleUntil",
		DamagePercent = "BrawlDamagePercent",
		KBVelocity = "BrawlKBVelocity",
		KBSeq = "BrawlKBSeq",
		ArenaActive = "BrawlArenaActive",
		HitKind = "BrawlHitKind",
		HitStopUntil = "BrawlHitStopUntil",
		HitStopSeq = "BrawlHitStopSeq",
		Level = "BrawlLevel",
		RankName = "BrawlRankName",
		RankTier = "BrawlRankTier",
	},
	XP = {
		Base = 20,
		TierBonusPercent = 0.30,
		LevelCurveMultiplier = 80,
		LevelCurveExponent = 1.4,
		LevelCurveExponentGrowth = 0.001,
	},
	Rank = {
		Tiers = {
			{ name = "Unranked",     threshold = 0 },
			{ name = "Bronze I",     threshold = 100 },
			{ name = "Bronze II",    threshold = 200 },
			{ name = "Bronze III",   threshold = 300 },
			{ name = "Silver I",     threshold = 400 },
			{ name = "Silver II",    threshold = 500 },
			{ name = "Silver III",   threshold = 600 },
			{ name = "Gold I",       threshold = 700 },
			{ name = "Gold II",      threshold = 800 },
			{ name = "Gold III",     threshold = 900 },
			{ name = "Platinum I",   threshold = 1000 },
			{ name = "Platinum II",  threshold = 1100 },
			{ name = "Platinum III", threshold = 1200 },
			{ name = "Diamond I",    threshold = 1300 },
			{ name = "Diamond II",   threshold = 1400 },
			{ name = "Diamond III",  threshold = 1500 },
			{ name = "Champion",     threshold = 1600 },
		},
		PointsPerTier = 100,
		DivisionRates = {
			Unranked = { kill = 20, death = 0 },
			Bronze   = { kill = 15, death = 1 },
			Silver   = { kill = 10, death = 3 },
			Gold     = { kill = 10, death = 5 },
			Platinum = { kill = 6,  death = 4 },
			Diamond  = { kill = 4,  death = 3 },
			Champion = { kill = 1,  death = 1 },
		},
		SeriesLength = 3,
		PromoFailLanding = 75,
		DemoteFailLanding = 25,
		DemoteSuccessLanding = 75,
	},
	Streak = {
		DoubleWindow = 5.0,
		TripleWindow = 8.0,
		DominatingThreshold = 5,
	},
	Donate = {
		ProductId = 3579571980,
		DisplayPrice = 100,
		ProductName = "Support the Dev",
	},
	FadingLabel = {
		NearDistance = 20,
		FarDistance = 80,
	},
	Analytics = {
		Events = {
			SessionStart = "session_start",
			SessionEnd = "session_end",
			Kill = "kill",
			LevelUp = "level_up",
			RankUp = "rank_up",
			Donate = "donate",
			EnterArena = "enter_arena",
			ReturnToLobby = "return_to_lobby",
		},
	},
	Assets = {
		RunAnimationId = "rbxassetid://105129044821151",
		DoubleJumpAnimationId = "rbxassetid://74399426620925",
		DodgeRollAnimationId = "rbxassetid://115857807557239",
		-- Hit reaction: uma das IDs é escolhida aleatoriamente a cada hit
		-- pra evitar repetição visual monotônica em combos.
		HitReactionAnimationIds = {
			"rbxassetid://115075492576917",
			"rbxassetid://76812069245659",
		},
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
	DataStore = {
		ProfileStoreName = "BrawlArenaProfiles_v1",
		PurchaseDataStoreName = "BrawlArenaPurchases_v1",
		RankingStorePrefix = "BrawlArenaRanking_v2_",
	},
	Ranking = {
		Modes = {
			Level = "Level",
			Kills = "Kills",
			MMR = "MMR",
		},
		ModeDisplay = {
			Level = { title = "TOP LEVEL", scoreSuffix = "", accent = Color3.fromRGB(80, 180, 255) },
			Kills = { title = "TOP KILLS", scoreSuffix = "", accent = Color3.fromRGB(255, 100, 100) },
			MMR = { title = "TOP RANKING", scoreSuffix = "", accent = Color3.fromRGB(200, 120, 255) },
		},
		TopN = 10,
		RefreshIntervalSeconds = 20,
		MinScoreToSubmit = 1,
	},
}

return Constants
