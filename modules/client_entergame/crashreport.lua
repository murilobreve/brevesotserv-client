-- Sends what went wrong in the last session to the site, once, the next time
-- the game opens: the crash report the crash handler appends to
-- crashreport.log, and the log of a session that ended with a fatal error.
-- Players do not have to find and send any file.
CrashReport = {}

local REPORT_FILE = '/crashreport.log'
local SENT_KEY = 'crashreport-sent-bytes'
local MAX_SEND = 200000

local function endpoint()
    local site = Services and Services.website or ''
    if site == '' then
        return nil
    end
    return site:gsub('/+$', '') .. '/plugins/brevesot/crash.php'
end

local function readFile(path)
    if not g_resources.fileExists(path) then
        return nil
    end
    local ok, text = pcall(g_resources.readFileContents, path)
    if ok and type(text) == 'string' and text ~= '' then
        return text
    end
    return nil
end

local function post(kind, text, onSent)
    local url = endpoint()
    if not url or not g_http or not g_http.post then
        return
    end
    if #text > MAX_SEND then
        text = text:sub(-MAX_SEND)
    end
    local payload = {
        kind = kind,
        version = g_app.getVersion(),
        build = g_app.getBuildCommit and g_app.getBuildCommit() or '',
        os = g_app.getOs and g_app.getOs() or '',
        gpu = g_graphics.getVendor() .. ' | ' .. g_graphics.getRenderer() .. ' | ' .. g_graphics.getVersion(),
        report = text
    }
    HTTP.post(url, json.encode(payload), function(message, err)
        if err or type(message) ~= 'string' or not message:find('"ok"%s*:%s*true') then
            g_logger.warning('[crash report] not sent: ' .. tostring(err or message))
            return
        end
        g_logger.info('[crash report] sent (' .. kind .. ')')
        if onSent then
            onSent()
        end
    end, false)
end

function CrashReport.send()
    -- crash reports: only the part appended since the last one sent
    local report = readFile(REPORT_FILE)
    if report then
        local sent = g_settings.getNumber(SENT_KEY, 0)
        if sent > #report then
            sent = 0 -- the file was deleted or replaced
        end
        if #report > sent then
            local total = #report
            post('crash', report:sub(sent + 1), function()
                g_settings.set(SENT_KEY, total)
                g_settings.save()
            end)
        end
    end

    -- a fatal error ("The game cannot start: ...") ends the session without a
    -- crash: its log, kept as <name>-previous.log, says why
    local previous = readFile('/' .. g_app.getCompactName() .. '-previous.log')
    if previous and previous:find('%[critical%]') then
        post('fatal', previous)
    end
end

function CrashReport.init()
    -- after the window is up and the network stack is ready
    scheduleEvent(CrashReport.send, 5000)
end
