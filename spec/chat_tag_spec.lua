local Harness = require("support.wow")

local ChatTag = Harness.new():load("Core/ChatTag.lua").ChatTag

describe("ChatTag.Rule", function()
    it("tags an alt with the alias", function()
        assert.are.equal("[Zel]", ChatTag.Rule(false, "Zel", "Dresden"))
    end)

    it("tags an alt with the main's short name when there is no alias", function()
        assert.are.equal("[Dresden]", ChatTag.Rule(false, nil, "Dresden"))
    end)

    it("tags a main with its alias", function()
        assert.are.equal("[Zel]", ChatTag.Rule(true, "Zel", "Dresden"))
    end)

    it("does not tag a main without an alias", function()
        assert.is_nil(ChatTag.Rule(true, nil, "Dresden"))
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

    it("tags an alt", function()
        assert.are.equal("[Zel]", ChatTag.ForCharacter(store, "Malgen Zelwindran-Forever"))
    end)

    it("tags a main by its alias", function()
        assert.are.equal("[Zel]", ChatTag.ForCharacter(store, "Dresden Zelwindran-Forever"))
    end)

    it("does not tag an unknown character", function()
        assert.is_nil(ChatTag.ForCharacter(store, "Stranger-Forever"))
        assert.is_nil(ChatTag.ForCharacter(store, nil))
    end)
end)
