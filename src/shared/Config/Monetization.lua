--!strict
-- Monetization tunables: the VIP game pass and the philanthropy ("Donate") developer product.
-- MonetizationService owns ProcessReceipt (developer products) and the VIP entitlement (game pass).
--
-- The ids below are real Roblox asset ids that must be created in the Creator Dashboard
-- (Monetization > Game Passes / Developer Products) and pasted in here. They start at 0 = unset;
-- the service short-circuits a 0 id so the game runs cleanly before the products exist.

local Monetization = {}

-- Most recent granted developer-product PurchaseIds kept per profile for idempotent receipts
-- (ProfileStore's documented pattern). FIFO-capped so the profile can't grow unbounded.
Monetization.MaxPurchaseCache = 100

-- VIP game pass. Ownership is resolved on join (MarketplaceService:UserOwnsGamePassAsync) and the
-- result is cached on the profile + mirrored to the player's "IsVip" attribute for client gating.
Monetization.VipGamePassId = 0 -- 0 = unset

-- VIP perks (the "aura buff"): VIP players earn more followers per photo.
Monetization.Vip = {
	PhotoMultiplier = 2, -- multiplies the photo follower reward for VIP players
}

-- Philanthropy "Donate" developer product: a purchase awards followers.
Monetization.DonateProductId = 0 -- 0 = unset
Monetization.DonateReward = 500 -- followers granted per Donate purchase

-- Developer-product reward lookup consumed by ProcessReceipt: developerProductId -> followerReward.
-- Derived from the named products above so each id/reward has a single source of truth.
Monetization.Products = {} :: { [number]: number }
if Monetization.DonateProductId > 0 then
	Monetization.Products[Monetization.DonateProductId] = Monetization.DonateReward
end

-- The phone Shop catalog, in display order. `kind` is the string the client sends in RequestPurchase;
-- the server maps it to the game pass / developer product to prompt.
Monetization.Shop = {
	{ kind = "Vip", emoji = "👑", label = "VIP Pass" },
	{ kind = "Donate", emoji = "💝", label = "Donate" },
}

return Monetization
