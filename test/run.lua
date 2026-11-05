-- DIY test runner for Lua 5.1.
-- Usage, from the repository root:
--   lua test/run.lua                       run every test/test_*.lua
--   lua test/run.lua test/test_defaults.lua  run selected files
-- Exit code 0 = all passed, 1 = failures.

---@diagnostic disable: undefined-global

local ADDON_NAME = "Unbound"
local TOC_PATH = ADDON_NAME .. "/" .. ADDON_NAME .. ".toc"

local write = io.write

-- TOC ------------------------------------------------------------------------

local function readToc()
    local toc = { files = {}, metadata = {}, savedVariables = {} }
    local file = io.open(TOC_PATH, "r")
    if not file then
        write("Cannot open " .. TOC_PATH .. ". Run from the repository root: lua test/run.lua\n")
        os.exit(1)
    end
    for line in file:lines() do
        line = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local key, value = line:match("^##%s*([^:]-)%s*:%s*(.-)$")
        if key then
            toc.metadata[key] = value
        elseif line ~= "" and not line:find("^#") and line:find("%.lua$") then
            toc.files[#toc.files + 1] = ADDON_NAME .. "/" .. line:gsub("\\", "/")
        end
    end
    file:close()
    for name in (toc.metadata.SavedVariables or ""):gmatch("[^,%s]+") do
        toc.savedVariables[#toc.savedVariables + 1] = name
    end
    return toc
end

local toc = readToc()

dofile("test/wowstubs.lua")

-- Loads every .lua file from the TOC, in order, into a fresh namespace.
function loadAddon()
    WowStub.reset(toc.savedVariables, toc.metadata)
    local ns = {}
    for _, path in ipairs(toc.files) do
        local chunk = assert(loadfile(path))
        chunk(ADDON_NAME, ns)
    end
    return ns
end

-- Assertions -----------------------------------------------------------------

local function show(value, depth)
    depth = depth or 0
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    if depth > 3 then return "{...}" end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i, key in ipairs(keys) do
        parts[i] = "[" .. show(key) .. "] = " .. show(value[key], depth + 1)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in pairs(a) do
        if not deepEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function contains(haystack, needle)
    if type(haystack) == "string" then
        return haystack:find(needle, 1, true) ~= nil
    end
    for _, value in pairs(haystack) do
        if deepEqual(value, needle) then return true end
    end
    return false
end

function expect(actual)
    -- Level 3 points the error at the test line that called the matcher.
    local function check(ok, message)
        if not ok then error(message, 3) end
    end
    return {
        toEqual = function(expected)
            check(deepEqual(actual, expected), "expected " .. show(expected) .. ", got " .. show(actual))
        end,
        toBe = function(expected)
            check(actual == expected, "expected the same value as " .. show(expected) .. ", got " .. show(actual))
        end,
        toBeNil = function()
            check(actual == nil, "expected nil, got " .. show(actual))
        end,
        toBeTruthy = function()
            check(actual, "expected a truthy value, got " .. show(actual))
        end,
        toBeFalsy = function()
            check(not actual, "expected a falsy value, got " .. show(actual))
        end,
        toContain = function(needle)
            check(contains(actual, needle), "expected " .. show(actual) .. " to contain " .. show(needle))
        end,
        toError = function(pattern)
            local ok, err = pcall(actual)
            check(not ok, "expected function to throw")
            if pattern then
                check(tostring(err):find(pattern, 1, true), "expected error containing " .. show(pattern)
                    .. ", got " .. show(err))
            end
        end,
    }
end

-- Structure ------------------------------------------------------------------

local names = {}
local scopes = {}
local passed, failed = 0, 0
local failures = {}

local function resetScopes()
    names = {}
    scopes = { { before = {}, after = {} } }
end

function describe(name, fn)
    names[#names + 1] = name
    scopes[#scopes + 1] = { before = {}, after = {} }
    fn()
    scopes[#scopes] = nil
    names[#names] = nil
end

function beforeEach(fn)
    local hooks = scopes[#scopes].before
    hooks[#hooks + 1] = fn
end

function afterEach(fn)
    local hooks = scopes[#scopes].after
    hooks[#hooks + 1] = fn
end

function it(name, fn)
    local ok, err = pcall(function()
        for i = 1, #scopes do
            for _, hook in ipairs(scopes[i].before) do hook() end
        end
        fn()
    end)
    for i = #scopes, 1, -1 do
        for _, hook in ipairs(scopes[i].after) do
            local hookOk, hookErr = pcall(hook)
            if ok and not hookOk then ok, err = false, hookErr end
        end
    end

    if ok then
        passed = passed + 1
        write(".")
    else
        failed = failed + 1
        write("F")
        local path = table.concat(names, " > ")
        failures[#failures + 1] = (path ~= "" and path .. " > " or "") .. name .. "\n    " .. tostring(err)
    end
end

-- Discovery & run ------------------------------------------------------------

local function findTestFiles()
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local command = isWindows and 'dir /b /on "test\\test_*.lua" 2>nul' or "ls -1 test/test_*.lua 2>/dev/null"
    local pipe = io.popen(command)
    for line in pipe:lines() do
        files[#files + 1] = isWindows and ("test/" .. line) or line
    end
    pipe:close()
    table.sort(files)
    return files
end

local testFiles = #arg > 0 and { unpack(arg) } or findTestFiles()
if #testFiles == 0 then
    write("No test files found.\n")
    os.exit(1)
end

for _, path in ipairs(testFiles) do
    write(path .. " ")
    resetScopes()
    local chunk, loadErr = loadfile(path)
    if chunk then
        local ok, runErr = pcall(chunk)
        if not ok then loadErr = runErr end
    end
    if loadErr then
        failed = failed + 1
        failures[#failures + 1] = path .. " (load error)\n    " .. tostring(loadErr)
        write("E")
    end
    write("\n")
end

if #failures > 0 then
    write("\nFailures:\n")
    for i, failure in ipairs(failures) do
        write(i .. ") " .. failure .. "\n")
    end
end

write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
