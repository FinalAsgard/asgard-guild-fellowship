local _, addon = ...

-- What a person is willing to help guildmates with. Stored on their profile as
-- `helps`, a comma-separated list of topic tokens ("tanking,quests"), so it
-- syncs, persists, and is protected like the rest of the profile. Pure.
local Helping = {}
addon.Helping = Helping

-- Topic tokens, in display order.
Helping.TOPICS = {
    "newPlayers", "classQuestions", "tanking", "healing", "quests", "dungeons", "pvp", "professions", "mentoring",
}
Helping.LABELS = {
    newPlayers = "New players",
    classQuestions = "Class questions",
    tanking = "Tanking",
    healing = "Healing",
    quests = "Quests",
    dungeons = "Dungeons",
    pvp = "PvP",
    professions = "Professions",
    mentoring = "General mentoring",
}

-- The known topics in a stored value, deduplicated and in TOPICS order.
-- Unknown tokens (e.g. from a newer version) are ignored.
function Helping.Parse(value)
    local present = {}
    if type(value) == "string" then
        for token in value:gmatch("[^,%s]+") do
            present[token] = true
        end
    end
    local topics = {}
    for _, topic in ipairs(Helping.TOPICS) do
        if present[topic] then
            table.insert(topics, topic)
        end
    end
    return topics
end

-- The stored value for a list of topics ("" for none).
function Helping.Format(topics)
    return table.concat(Helping.Parse(table.concat(topics or {}, ",")), ",")
end

-- Whether a stored value includes `topic`.
function Helping.Has(value, topic)
    for _, known in ipairs(Helping.Parse(value)) do
        if known == topic then
            return true
        end
    end
    return false
end

-- Display labels for a stored value, in TOPICS order.
function Helping.Labels(value)
    local labels = {}
    for _, topic in ipairs(Helping.Parse(value)) do
        table.insert(labels, Helping.LABELS[topic])
    end
    return labels
end
