local _, addon = ...

-- Encodes sync messages for the addon channel: AceSerializer, then LibDeflate
-- compression, then LibDeflate's channel-safe encoding. Every message is an
-- envelope { v = protocol version, k = kind, d = data table }. Pure apart from
-- those two libraries.
local Protocol = {}
addon.Protocol = Protocol

Protocol.VERSION = 1
-- Message kinds this version understands; others are ignored.
Protocol.KINDS = { digest = true, versions = true, want = true, records = true }
-- Target size of one records message before compression, in bytes. Larger
-- record sets are split into several self-contained messages.
Protocol.BATCH_BYTES = 2000

local function serializer()
    return LibStub("AceSerializer-3.0")
end

local function deflate()
    return LibStub("LibDeflate")
end

function Protocol.Encode(kind, data)
    local serialized = serializer():Serialize({ v = Protocol.VERSION, k = kind, d = data })
    return deflate():EncodeForWoWAddonChannel(deflate():CompressDeflate(serialized))
end

-- Returns kind, data; or nil and a reason ("malformed", "newer", "unknown").
-- Never raises, whatever the input.
function Protocol.Decode(message)
    if type(message) ~= "string" then
        return nil, "malformed"
    end
    local ok, envelope = pcall(function()
        local compressed = deflate():DecodeForWoWAddonChannel(message)
        local serialized = compressed and deflate():DecompressDeflate(compressed)
        if not serialized then
            return nil
        end
        local success, value = serializer():Deserialize(serialized)
        return success and value or nil
    end)
    if not ok or type(envelope) ~= "table" or type(envelope.v) ~= "number" or type(envelope.k) ~= "string"
        or type(envelope.d) ~= "table" then
        return nil, "malformed"
    end
    if envelope.v > Protocol.VERSION then
        return nil, "newer"
    end
    if not Protocol.KINDS[envelope.k] then
        return nil, "unknown"
    end
    return envelope.k, envelope.d
end

-- Splits `records` (id -> record) into batches of about `maxBytes` serialized
-- bytes each, in id order. A single record larger than the limit gets a batch
-- of its own. Each batch is self-contained, so receivers apply batches as they
-- arrive. AceComm splits and rejoins any single message over the 255-byte
-- channel limit.
function Protocol.Batch(records, maxBytes)
    maxBytes = maxBytes or Protocol.BATCH_BYTES
    local ids = {}
    for id in pairs(records) do
        table.insert(ids, id)
    end
    table.sort(ids)
    local batches, current, size = {}, nil, 0
    for _, id in ipairs(ids) do
        local recordSize = #serializer():Serialize(id, records[id])
        if not current or size + recordSize > maxBytes then
            current, size = {}, 0
            table.insert(batches, current)
        end
        current[id] = records[id]
        size = size + recordSize
    end
    return batches
end
