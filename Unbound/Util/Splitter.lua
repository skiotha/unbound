local addonName, ns = ...

local byte = string.byte
local sub = string.sub
local find = string.find
local rep = string.rep
local type = type

local MAX_MESSAGE_BYTES = 255
local NO_COLOUR = { prefix = "", depth = 0 }

local function failure(message, position)
    return nil, message .. " at byte " .. position .. "."
end

local function isWhitespace(value)
    return value == 32 or (value >= 9 and value <= 13)
end

local function characterBytes(value)
    if value < 128 then return 1 end
    if value < 224 then return 2 end
    if value < 240 then return 3 end
    return 4
end

local function validateText(text)
    local position = 1
    while position <= #text do
        local first = byte(text, position)
        local width = characterBytes(first)
        if first < 128 then
            if (first < 32 and not isWhitespace(first)) or first == 127 then
                return failure("Unsupported control character", position)
            end
        else
            if first < 194 or first > 244 then
                return failure("Invalid UTF-8", position)
            end
            for offset = 1, width - 1 do
                local continuation = byte(text, position + offset)
                if not continuation or continuation < 128 or continuation > 191 then
                    return failure("Invalid UTF-8", position)
                end
            end
            local second = byte(text, position + 1)
            if (first == 224 and second < 160) or (first == 237 and second > 159)
                or (first == 240 and second < 144) or (first == 244 and second > 143) then
                return failure("Invalid UTF-8", position)
            end
        end
        position = position + width
    end
    return true
end

-- Escaped pipes are literal text, never the start of a closing delimiter.
local function findEscapeEnd(text, position, ending)
    while position <= #text do
        local pipe = find(text, "|", position, true)
        if not pipe then return nil end
        local code = sub(text, pipe + 1, pipe + 1)
        if code == ending then return pipe end
        if code ~= "|" then return nil end
        position = pipe + 2
    end
end

local function tokenize(text)
    local atoms = {}
    local colour = NO_COLOUR
    local link
    local position = 1

    local function addAtom(first, last, whitespace)
        if link then return end
        atoms[#atoms + 1] = { first = first, last = last, colour = colour, whitespace = whitespace }
    end

    while position <= #text do
        local first = byte(text, position)
        if first ~= 124 then
            local last = position + characterBytes(first) - 1
            addAtom(position, last, isWhitespace(first))
            position = last + 1
        else
            local code = sub(text, position + 1, position + 1)
            if code == "|" then
                addAtom(position, position + 1, false)
                position = position + 2
            elseif code == "c" then
                local opening
                if sub(text, position + 2, position + 2) == "n" then
                    opening = sub(text, position):match("^|cn[%w_]+:")
                else
                    opening = sub(text, position, position + 9):match("^|c%x%x%x%x%x%x%x%x$")
                end
                if not opening then return failure("Malformed colour opening", position) end
                local prefix = colour.prefix .. opening
                local depth = colour.depth + 1
                if #prefix + depth * 2 >= MAX_MESSAGE_BYTES then
                    return failure("Colour overhead leaves no room within 255 bytes", position)
                end
                colour = { prefix = prefix, depth = depth, parent = colour, position = position }
                position = position + #opening
            elseif code == "r" then
                if colour == NO_COLOUR or (link and colour == link.colour) then
                    return failure("Unmatched colour reset", position)
                end
                colour = colour.parent
                position = position + 2
            elseif code == "H" then
                if link then return failure("Nested hyperlink", position) end
                local ending = findEscapeEnd(text, position + 2, "h")
                if not ending or not sub(text, position + 2, ending - 1):match("^[%w_]+:") then
                    return failure("Malformed hyperlink payload", position)
                end
                link = { first = position, colour = colour }
                position = ending + 2
            elseif code == "h" then
                if not link then return failure("Unmatched hyperlink end", position) end
                if colour ~= link.colour then
                    return failure("Unclosed colour inside hyperlink", position)
                end
                local start = link.first
                link = nil
                addAtom(start, position + 1, false)
                position = position + 2
            elseif code == "T" or code == "A" then
                local ending = findEscapeEnd(text, position + 2, code == "T" and "t" or "a")
                if not ending or ending == position + 2 then
                    return failure("Malformed texture or atlas escape", position)
                end
                addAtom(position, ending + 1, false)
                position = ending + 2
            else
                return failure("Unsupported escape '" .. sub(text, position, position + 1) .. "'", position)
            end
        end
    end

    if link then return failure("Unclosed hyperlink", link.first) end
    if colour ~= NO_COLOUR then return failure("Unclosed colour", colour.position) end
    return atoms
end

-- Returns chunks, or nil and an explanatory error; never returns partial output.
local function splitText(text)
    if type(text) ~= "string" then return nil, "Text must be a string." end
    local valid, err = validateText(text)
    if not valid then return nil, err end
    local atoms
    atoms, err = tokenize(text)
    if not atoms then return nil, err end

    local chunks = {}
    local start = 1
    while start <= #atoms do
        while start <= #atoms and atoms[start].whitespace do start = start + 1 end
        if start > #atoms then break end

        local first = atoms[start]
        local prefix = first.colour.prefix
        local lastFit, wordEnd
        local scan = start
        while scan <= #atoms do
            local atom = atoms[scan]
            if atom.whitespace and lastFit then wordEnd = lastFit end
            local size = #prefix + atom.last - first.first + 1 + atom.colour.depth * 2
            if size > MAX_MESSAGE_BYTES then break end
            if not atom.whitespace then lastFit = scan end
            scan = scan + 1
        end
        if not lastFit then
            return failure("Indivisible text or markup exceeds 255 bytes", first.first)
        end
        if scan <= #atoms and wordEnd then lastFit = wordEnd end

        -- Original markup between atoms stays untouched. Only the open stack at
        -- each chunk boundary is reconstructed, including nested colour resets.
        local last = atoms[lastFit]
        chunks[#chunks + 1] = prefix .. sub(text, first.first, last.last) .. rep("|r", last.colour.depth)
        start = lastFit + 1
    end
    return chunks
end

ns.SplitText = splitText
ns.MAX_MESSAGE_BYTES = MAX_MESSAGE_BYTES
