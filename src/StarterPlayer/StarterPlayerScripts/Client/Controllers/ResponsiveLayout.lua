--!strict

-- Módulo de layout responsivo para UIs Roblox. Estratégia "fixed geometry":
-- a UI é composta em resolução desktop (design reference 1280x720) e escalada
-- inteira via UIScale pra caber no safe viewport atual. Sem reflow estrutural
-- por device. Copia da skill `roblox-ui-creator` do projeto pet_tycoon.

local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

export type Metrics = {
	cameraViewport: Vector2,
	safeViewport: Vector2,
	insetTopLeft: Vector2,
	insetBottomRight: Vector2,
	width: number,
	height: number,
	aspectRatio: number,
	widthAlpha: number,
	heightAlpha: number,
	layoutAlpha: number,
	compact: boolean,
	phone: boolean,
	shortHeight: boolean,
	phoneLandscape: boolean,
}

local DEFAULT_CAMERA_VIEWPORT = Vector2.new(1280, 720)

local ResponsiveLayout = {}

function ResponsiveLayout.Clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

function ResponsiveLayout.InverseLerpClamped(value: number, minValue: number, maxValue: number): number
	if maxValue == minValue then
		return if value >= maxValue then 1 else 0
	end
	return ResponsiveLayout.Clamp01((value - minValue) / (maxValue - minValue))
end

function ResponsiveLayout.Lerp(minValue: number, maxValue: number, alpha: number): number
	return minValue + ((maxValue - minValue) * ResponsiveLayout.Clamp01(alpha))
end

function ResponsiveLayout.LerpInt(minValue: number, maxValue: number, alpha: number): number
	return math.floor(ResponsiveLayout.Lerp(minValue, maxValue, alpha) + 0.5)
end

function ResponsiveLayout.GetViewportMetrics(compactWidth: number?, wideWidth: number?): Metrics
	local insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
	local camera = Workspace.CurrentCamera
	local cameraViewport = if camera then camera.ViewportSize else DEFAULT_CAMERA_VIEWPORT
	local safeViewport = Vector2.new(
		math.max(320, cameraViewport.X - insetTopLeft.X - insetBottomRight.X),
		math.max(320, cameraViewport.Y - insetTopLeft.Y - insetBottomRight.Y)
	)

	local minWidth = if typeof(compactWidth) == "number" then compactWidth else 360
	local maxWidth = if typeof(wideWidth) == "number" then wideWidth else 1280
	local widthAlpha = ResponsiveLayout.InverseLerpClamped(safeViewport.X, minWidth, maxWidth)
	local shortHeight = safeViewport.Y <= 560
	local phoneLandscape = shortHeight and safeViewport.X > safeViewport.Y
	local heightAlpha = ResponsiveLayout.InverseLerpClamped(
		safeViewport.Y,
		if phoneLandscape then 320 else 520,
		if phoneLandscape then 720 else 960
	)

	return {
		cameraViewport = cameraViewport,
		safeViewport = safeViewport,
		insetTopLeft = insetTopLeft,
		insetBottomRight = insetBottomRight,
		width = safeViewport.X,
		height = safeViewport.Y,
		aspectRatio = safeViewport.X / math.max(safeViewport.Y, 1),
		widthAlpha = widthAlpha,
		heightAlpha = heightAlpha,
		layoutAlpha = math.min(widthAlpha, heightAlpha),
		compact = safeViewport.X <= 900,
		phone = safeViewport.X <= 760,
		shortHeight = shortHeight,
		phoneLandscape = phoneLandscape,
	}
end

function ResponsiveLayout.GetSafeCenterPosition(metrics: Metrics, yScale: number?): UDim2
	local verticalScale = if typeof(yScale) == "number" then yScale else 0.5
	return UDim2.fromOffset(
		math.floor(metrics.insetTopLeft.X + (metrics.safeViewport.X * 0.5) + 0.5),
		math.floor(metrics.insetTopLeft.Y + (metrics.safeViewport.Y * verticalScale) + 0.5)
	)
end

function ResponsiveLayout.GetFitScale(
	metrics: Metrics,
	designWidth: number,
	designHeight: number?,
	minScale: number?,
	maxScale: number?
): number
	local widthScale = if designWidth > 0 then metrics.safeViewport.X / designWidth else 1
	local heightScale = if typeof(designHeight) == "number" and designHeight > 0
		then metrics.safeViewport.Y / designHeight
		else widthScale

	return math.clamp(
		math.min(widthScale, heightScale),
		if typeof(minScale) == "number" then minScale else 0,
		if typeof(maxScale) == "number" then maxScale else math.huge
	)
end

function ResponsiveLayout.GetReferenceScale(
	metrics: Metrics,
	designWidth: number,
	designHeight: number,
	maxWidthRatio: number?,
	maxHeightRatio: number?,
	minScale: number?,
	maxScale: number?
): number
	local widthRatio = if typeof(maxWidthRatio) == "number" then maxWidthRatio else 1
	local heightRatio = if typeof(maxHeightRatio) == "number" then maxHeightRatio else 1
	local widthScale = if designWidth > 0 then (metrics.safeViewport.X * widthRatio) / designWidth else 1
	local heightScale = if designHeight > 0 then (metrics.safeViewport.Y * heightRatio) / designHeight else widthScale

	return math.clamp(
		math.min(widthScale, heightScale),
		if typeof(minScale) == "number" then minScale else 0,
		if typeof(maxScale) == "number" then maxScale else math.huge
	)
end

function ResponsiveLayout.GetMaxSafeSize(
	metrics: Metrics,
	maxWidthRatio: number?,
	maxHeightRatio: number?,
	minWidth: number?,
	minHeight: number?
): Vector2
	local widthRatio = if typeof(maxWidthRatio) == "number" then maxWidthRatio else 0.94
	local heightRatio = if typeof(maxHeightRatio) == "number"
		then maxHeightRatio
		else if metrics.phoneLandscape then 0.86 else if metrics.shortHeight then 0.9 else 0.94
	local minSafeWidth = if typeof(minWidth) == "number" then minWidth else 0
	local minSafeHeight = if typeof(minHeight) == "number" then minHeight else 0

	return Vector2.new(
		math.max(minSafeWidth, math.floor(metrics.safeViewport.X * widthRatio + 0.5)),
		math.max(minSafeHeight, math.floor(metrics.safeViewport.Y * heightRatio + 0.5))
	)
end

function ResponsiveLayout.ClampToSafeViewport(
	metrics: Metrics,
	desiredWidth: number,
	desiredHeight: number,
	maxWidthRatio: number?,
	maxHeightRatio: number?,
	minWidth: number?,
	minHeight: number?
): Vector2
	local maxSize = ResponsiveLayout.GetMaxSafeSize(
		metrics,
		maxWidthRatio,
		maxHeightRatio,
		minWidth,
		minHeight
	)

	return Vector2.new(
		math.floor(math.clamp(desiredWidth, if typeof(minWidth) == "number" then minWidth else 0, maxSize.X) + 0.5),
		math.floor(math.clamp(desiredHeight, if typeof(minHeight) == "number" then minHeight else 0, maxSize.Y) + 0.5)
	)
end

function ResponsiveLayout.GetViewportFitScale(
	metrics: Metrics,
	designWidth: number,
	designHeight: number,
	maxWidthRatio: number?,
	maxHeightRatio: number?,
	minScale: number?,
	maxScale: number?
): number
	local maxSafeSize = ResponsiveLayout.GetMaxSafeSize(metrics, maxWidthRatio, maxHeightRatio)
	local widthScale = if designWidth > 0 then maxSafeSize.X / designWidth else 1
	local heightScale = if designHeight > 0 then maxSafeSize.Y / designHeight else widthScale

	return math.clamp(
		math.min(widthScale, heightScale),
		if typeof(minScale) == "number" then minScale else 0,
		if typeof(maxScale) == "number" then maxScale else math.huge
	)
end

function ResponsiveLayout.EnsureUiScale(parent: Instance, name: string?): UIScale
	local scaleName = if typeof(name) == "string" and name ~= "" then name else "ResponsiveScale"
	local existing = parent:FindFirstChild(scaleName)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Name = scaleName
	uiScale.Parent = parent
	return uiScale
end

return ResponsiveLayout
