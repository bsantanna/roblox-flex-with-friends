--!strict
-- Pure idempotency helpers for developer-product receipts (MonetizationService), free of Roblox
-- globals so they're Lune-testable. Mirrors ProfileStore's documented PurchaseId-cache pattern:
-- a capped FIFO list of granted PurchaseIds lives in Profile.Data; a purchase is granted exactly
-- once, then the ProcessReceipt response yields until that id shows up in the saved copy.

local Receipts = {}

-- True when this purchaseId has not yet been granted (absent from the live cache).
function Receipts.shouldGrant(cache: { string }, purchaseId: string): boolean
	return table.find(cache, purchaseId) == nil
end

-- Record a granted purchaseId, evicting oldest entries first so the cache stays within maxSize
-- (FIFO). Call only after shouldGrant returned true.
function Receipts.record(cache: { string }, purchaseId: string, maxSize: number)
	while #cache >= maxSize do
		table.remove(cache, 1)
	end
	table.insert(cache, purchaseId)
end

-- True when the purchaseId is present in the last-saved copy of the cache (i.e. persisted).
function Receipts.isSaved(savedCache: { string }?, purchaseId: string): boolean
	return savedCache ~= nil and table.find(savedCache, purchaseId) ~= nil
end

return Receipts
