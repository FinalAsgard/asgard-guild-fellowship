local Harness = require("support.wow")

local ChatTag = Harness.new():load("Core/ChatTag.lua").ChatTag

describe("ChatTag.Rule", function()
    it("tags an alt with the alias", function()
        assert.are.equal("Zel", ChatTag.Rule(false, "Zel", "Dresden"))
    end)

    it("tags an alt with the main's short name when there is no alias", function()
        assert.are.equal("Dresden", ChatTag.Rule(false, nil, "Dresden"))
    end)

    it("tags a main with its alias", function()
        assert.are.equal("Zel", ChatTag.Rule(true, "Zel", "Dresden"))
    end)

    it("does not tag a main without an alias", function()
        assert.is_nil(ChatTag.Rule(true, nil, "Dresden"))
    end)
end)

describe("ChatTag.Format", function()
    local function settings(overrides)
        local result = { brackets = "square", colored = false, color = { r = 1, g = 0.5, b = 0 } }
        for key, value in pairs(overrides or {}) do
            result[key] = value
        end
        return result
    end

    it("uses square brackets by default", function()
        assert.are.equal("[Zel]", ChatTag.Format("Zel", settings()))
    end)

    it("supports each bracket style", function()
        assert.are.equal("(Zel)", ChatTag.Format("Zel", settings({ brackets = "round" })))
        assert.are.equal("<Zel>", ChatTag.Format("Zel", settings({ brackets = "angle" })))
        assert.are.equal("Zel", ChatTag.Format("Zel", settings({ brackets = "none" })))
    end)

    it("falls back to square brackets for an unknown style", function()
        assert.are.equal("[Zel]", ChatTag.Format("Zel", settings({ brackets = "curly" })))
    end)

    it("colors the whole tag when enabled", function()
        assert.are.equal("|cffff8000[Zel]|r", ChatTag.Format("Zel", settings({ colored = true })))
    end)

    it("has defaults for every channel", function()
        for _, channel in ipairs(ChatTag.CHANNEL_ORDER) do
            assert.is_true(ChatTag.DEFAULTS.channels[channel])
        end
        for _, channel in pairs(ChatTag.CHANNELS) do
            assert.is_not_nil(ChatTag.DEFAULTS.channels[channel])
        end
    end)
end)

describe("ChatTag.ForCharacter", function()
    local person = { mainKey = "Dresden Zelwindran-Forever", alias = "Zel", shortName = "Dresden" }
    local store = {
        GetPerson = function(_, key)
            if key == "Dresden Zelwindran-Forever" or key == "Malgen Zelwindran-Forever" then
                return person
            end
        end,
    }

    it("names an alt's person", function()
        assert.are.equal("Zel", ChatTag.ForCharacter(store, "Malgen Zelwindran-Forever"))
    end)

    it("names a main by its alias", function()
        assert.are.equal("Zel", ChatTag.ForCharacter(store, "Dresden Zelwindran-Forever"))
    end)

    it("does not tag an unknown character", function()
        assert.is_nil(ChatTag.ForCharacter(store, "Stranger-Forever"))
        assert.is_nil(ChatTag.ForCharacter(store, nil))
    end)
end)
