-- Reads the Lua files a manifest loads, in order, as repository paths. XML
-- entries (the embedded libraries) are skipped.
return function(manifest)
    local files = {}
    for line in io.lines(manifest) do
        line = line:gsub("\r$", "")
        if line:match("%.lua$") and not line:match("^#") then
            table.insert(files, (line:gsub("\\", "/")))
        end
    end
    return files
end
