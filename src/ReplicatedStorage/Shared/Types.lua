--!strict

export type Profile = {
	XP: number,
	Level: number,
	Rank: string,
	RankPoints: number,
	HighestRank: string,
	SeriesKind: string,
	SeriesProgress: number,
	RankSchemaVersion: number,
	TotalKills: number,
	TotalDeaths: number,
	DonationCount: number,
	LastLoginTimestamp: number,
	-- Classes/economy (ClassSchema v1)
	Currency: number,
	UnlockedClasses: { [string]: boolean },
	EquippedClass: string,
	ClassSchemaVersion: number,
}

export type ClassCatalogEntry = {
	id: string,
	displayName: string,
	description: string,
	iconAssetId: string,
	price: number,
	owned: boolean,
	equipped: boolean,
}

export type ShopCatalogPayload = {
	balance: number,
	classes: { ClassCatalogEntry },
}

export type ShopBuyResult = {
	success: boolean,
	reason: string?,
	newBalance: number?,
}

export type ShopEquipResult = {
	success: boolean,
	reason: string?,
}

export type RankBrief = {
	name: string,
	tier: number,
}

export type KillFeedPayload = {
	puncher: { name: string, userId: number, rank: RankBrief },
	target: { name: string, userId: number, rank: RankBrief },
}

export type StreakKind = "Double" | "Triple" | "Dominating"

export type StreakPayload = {
	userId: number,
	name: string,
	kind: StreakKind,
	count: number,
}

export type LevelUpPayload = {
	userId: number,
	previousLevel: number,
	newLevel: number,
}

export type RankUpPayload = {
	userId: number,
	previousRank: RankBrief,
	newRank: RankBrief,
	promoted: boolean,
}

export type XPGainPayload = {
	puncherUserId: number,
	targetUserId: number,
	amount: number,
}

export type BrawlEventPayload =
	KillFeedPayload
	| StreakPayload
	| LevelUpPayload
	| RankUpPayload
	| XPGainPayload

export type BrawlEvent = {
	type: string,
	payload: BrawlEventPayload,
}

export type BrawlStateSnapshot = {
	state: string,
	damagePercent: number,
	level: number?,
	xp: number?,
	xpForNextLevel: number?,
	rank: RankBrief?,
	summary: SessionSummary?,
}

export type SeriesState = {
	kind: string,
	progress: number,
}

export type ArenaPlayerSnapshot = {
	userId: number,
	displayName: string,
	damagePercent: number,
	level: number,
	rank: RankBrief,
	series: SeriesState?,
}

export type ArenaStateSnapshot = {
	players: { ArenaPlayerSnapshot },
}

export type SessionSummary = {
	kills: number,
	timeAliveSeconds: number,
	xpGained: number,
	leveledUp: boolean,
	newLevel: number?,
	rankDelta: number?,
}

return {}
