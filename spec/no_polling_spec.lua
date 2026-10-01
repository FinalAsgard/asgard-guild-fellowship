-- The add-on is event-driven: none of its own code may poll with OnUpdate.
local manifestLuaFiles = require("support.manifest")

describe("add-on code", function()
    for _, path in ipairs(manifestLuaFiles("AsgardsGuildFellowship_Mainline.toc")) do
        it(path .. " does not use OnUpdate", function()
            local handle = assert(io.open(path, "r"))
            local source = handle:read("*a")
            handle:close()
            assert.is_nil(source:find("OnUpdate", 1, true))
        end)
    end
end)
