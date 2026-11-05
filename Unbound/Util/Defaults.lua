local addonName, ns = ...

local type = type
local pairs = pairs

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and copyTable(value) or value
    end
    return copy
end

-- Fills keys missing from `target` with deep copies of `defaults`.
-- Returns `target`.
local function applyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        local current = target[key]
        if current == nil then
            target[key] = type(value) == "table" and copyTable(value) or value
        elseif type(current) == "table" and type(value) == "table" then
            applyDefaults(current, value)
        end
    end
    return target
end

ns.ApplyDefaults = applyDefaults
