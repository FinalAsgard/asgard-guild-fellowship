-- Guards the production manifests: both clients must load the same files, take
-- their version from the release tag, and only list files that exist.

local MANIFESTS = {
    { client = "Forever", file = "AsgardsGuildFellowship_Camelot.toc" },
    { client = "Retail", file = "AsgardsGuildFellowship_Mainline.toc" },
}

local function readManifest(path)
    local handle = assert(io.open(path, "r"), "missing manifest " .. path)
    local manifest = { fields = {}, files = {} }
    for line in handle:lines() do
        line = line:gsub("\r$", "")
        local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then
            manifest.fields[key] = value
        elseif line:match("%S") and not line:match("^#") then
            table.insert(manifest.files, line)
        end
    end
    handle:close()
    return manifest
end

local function fileExists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

describe("production manifests", function()
    local loaded = {}
    for _, entry in ipairs(MANIFESTS) do
        loaded[entry.client] = readManifest(entry.file)
    end

    for _, entry in ipairs(MANIFESTS) do
        local manifest = loaded[entry.client]

        it(entry.client .. " takes its version from the release tag", function()
            assert.are.equal("@project-version@", manifest.fields.Version)
        end)

        it(entry.client .. " declares its client", function()
            assert.are.equal(entry.client, manifest.fields["X-Client"])
        end)

        it(entry.client .. " declares at least one numeric interface", function()
            local interface = manifest.fields.Interface
            assert.is_truthy(interface and interface:match("^%d+[%d, ]*$"))
        end)

        it(entry.client .. " only loads files that exist", function()
            assert.is_true(#manifest.files > 0)
            for _, file in ipairs(manifest.files) do
                assert.is_true(fileExists((file:gsub("\\", "/"))), entry.client .. " loads missing " .. file)
            end
        end)
    end

    it("both clients load the same files in the same order", function()
        assert.are.same(loaded.Forever.files, loaded.Retail.files)
    end)

    it("both clients share every field except Interface and X-Client", function()
        local function shared(fields)
            local copy = {}
            for key, value in pairs(fields) do
                if key ~= "Interface" and key ~= "X-Client" then
                    copy[key] = value
                end
            end
            return copy
        end
        assert.are.same(shared(loaded.Forever.fields), shared(loaded.Retail.fields))
    end)
end)
