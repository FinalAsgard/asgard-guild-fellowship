-- Loads the real, pure-Lua embedded libraries the sync protocol uses
-- (AceSerializer, LibDeflate) with their own LibStub, once per test run.

local FILES = {
    "Libs/Ace3/LibStub/LibStub.lua",
    "Libs/Ace3/AceSerializer-3.0/AceSerializer-3.0.lua",
    "Libs/LibDeflate/LibDeflate.lua",
}

local libs
return function()
    if not libs then
        local env = setmetatable({}, { __index = _G })
        env._G = env
        for _, path in ipairs(FILES) do
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            chunk()
        end
        libs = {
            ["AceSerializer-3.0"] = env.LibStub("AceSerializer-3.0"),
            LibDeflate = env.LibStub("LibDeflate"),
        }
    end
    return libs
end
