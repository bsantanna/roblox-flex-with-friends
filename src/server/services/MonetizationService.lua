--!strict
-- MonetizationService: the single owner of Robux purchases. Handles MarketplaceService.ProcessReceipt
-- for philanthropy developer products idempotently (ProfileStore's documented PurchaseId-cache
-- pattern -- grant once, then yield the receipt response until the id is confirmed saved), and
-- resolves the VIP game-pass entitlement on join. Follower grants route through FollowerService
-- (the single writer); VIP perks are read by other services via :IsVip(player). Tunables live in
-- Config.Monetization. See doc/002_implementation_plan.md (Next release / B. Monetization & VIP).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local Net = require(ReplicatedStorage.Shared.Net)
local Receipts = require(ReplicatedStorage.Shared.Logic.Receipts)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.PlayerProfile

local MonetizationService = {}

local requestPurchase: RemoteEvent
local purchaseResult: RemoteEvent

-- Resolve VIP ownership once per join and cache it on the profile + a player attribute (so clients
-- can gate UI without a round-trip). UserOwnsGamePassAsync is the authority; the cached flag is a
-- convenience that re-syncs every join.
local function resolveVip(player: Player, profile: Profile)
	local gamePassId = Config.Monetization.VipGamePassId
	if gamePassId > 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		if ok then
			profile.Data.IsVip = owns
		else
			Log.warn("Monetization", `UserOwnsGamePassAsync failed for {player.Name}: {owns}`)
		end
	end
	player:SetAttribute("IsVip", profile.Data.IsVip == true)
end

-- True if the player owns VIP (cached from the join-time resolve). Other services call this to
-- apply VIP perks (e.g. PhotoService's follower multiplier).
function MonetizationService:IsVip(player: Player): boolean
	local profile = DataService:GetProfile(player)
	return profile ~= nil and profile.Data.IsVip == true
end

-- Awards the followers for a philanthropy developer product. Runs inside the receipt's grant
-- pcall; raising aborts the grant and Roblox retries later (NotProcessedYet).
local function grantProduct(player: Player, productId: number)
	local reward = Config.Monetization.Products[productId]
	assert(reward ~= nil, `no philanthropy product configured for id {productId}`)
	FollowerService:Award(player, reward, "philanthropy")
	Analytics.event(player, "Purchase", reward, "philanthropy")
	purchaseResult:FireClient(player, "Donate", true)
end

-- ProfileStore idempotent receipt handling: grant once into the capped PurchaseId cache, then yield
-- until that id is confirmed in LastSavedData before acknowledging PurchaseGranted. Mirrors the
-- vendored ProfileStore/docs/devproducts pattern.
local function purchaseIdCheckAsync(profile: Profile, purchaseId: string, grant: () -> ()): Enum.ProductPurchaseDecision
	if not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local cache = profile.Data.PurchaseIdCache

	if Receipts.shouldGrant(cache, purchaseId) then
		local ok, err = pcall(grant :: any)
		if not ok then
			Log.warn("Monetization", `failed to grant receipt {purchaseId}: {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		Receipts.record(cache, purchaseId, Config.Monetization.MaxPurchaseCache)
	end

	if Receipts.isSaved(profile.LastSavedData.PurchaseIdCache, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Wait for the grant to persist so a crash can't lose it.
	while profile:IsActive() do
		local lastSaved = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == lastSaved then
			profile.OnAfterSave:Wait()
		end
		if Receipts.isSaved(profile.LastSavedData.PurchaseIdCache, purchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if profile:IsActive() then
			task.wait(10)
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- The profile may still be loading right after a join; wait for it (or the player leaving).
	local profile = DataService:GetProfile(player)
	while profile == nil and player.Parent == Players do
		task.wait()
		profile = DataService:GetProfile(player)
	end
	if profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if Config.Monetization.Products[receiptInfo.ProductId] == nil then
		Log.warn("Monetization", `no product configured for id {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return purchaseIdCheckAsync(profile, tostring(receiptInfo.PurchaseId), function()
		grantProduct(player, receiptInfo.ProductId)
	end)
end

-- The Shop sends a purchase kind; the server prompts the matching real Robux purchase. Inputs are
-- validated (rule 4): a non-string or unknown kind, or an unset id, is a no-op.
local function onRequestPurchase(player: Player, kind: unknown)
	if type(kind) ~= "string" then
		return
	end
	if kind == "Vip" then
		local id = Config.Monetization.VipGamePassId
		if id > 0 and not MonetizationService:IsVip(player) then
			MarketplaceService:PromptGamePassPurchase(player, id)
		end
	elseif kind == "Donate" then
		local id = Config.Monetization.DonateProductId
		if id > 0 then
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end
end

-- VIP entitlement is granted the moment the game pass is bought (no rejoin needed). The flag is
-- persisted on the profile and re-resolved every join, so it survives across sessions.
local function onGamePassFinished(player: Player, gamePassId: number, purchased: boolean)
	if not purchased or gamePassId ~= Config.Monetization.VipGamePassId then
		return
	end
	local profile = DataService:GetProfile(player)
	if profile then
		profile.Data.IsVip = true
		player:SetAttribute("IsVip", true)
		purchaseResult:FireClient(player, "Vip", true)
	end
end

function MonetizationService:Init()
	requestPurchase = Net.Event("RequestPurchase")
	purchaseResult = Net.Event("PurchaseResult")
end

function MonetizationService:Start()
	DataService:OnProfileLoaded(resolveVip)
	MarketplaceService.ProcessReceipt = processReceipt
	requestPurchase.OnServerEvent:Connect(onRequestPurchase)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onGamePassFinished)
end

return MonetizationService
