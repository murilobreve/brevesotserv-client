-- Feedback and bug reports: a tab on the right edge of the game screen opens
-- a window where the player picks Bug, Idea or Feedback and writes it. The
-- server saves it with the character and the position, and the staff read
-- it on the website's monitoring page (scripts/feedback/feedback.lua).
--
-- Opcode OPCODE, JSON both ways:
--   client -> server { action = 'send', kind, message, client }
--   server -> client { action = 'result', ok, code, seconds, message }

local OPCODE = 129
local MAX_LENGTH = 1000

local GOOD = '#78d04c'
local BAD = '#e0604a'
local DIM = '#a39cbc'

local tab, window, closeEvent, waitEvent
local kind = 'bug'
local waiting = false

-- the fonts draw one glyph per byte (Latin-1); the server's JSON is UTF-8
local function latin1(text)
    return (tostring(text):gsub('[\194\195][\128-\191]', function(pair)
        local a, b = pair:byte(1, 2)
        return string.char((a - 194) * 64 + b)
    end))
end

-- the build and how it draws, for the staff when a bug shows only on one
local function clientInfo()
    local parts = {}
    local version = g_app.getVersion and g_app.getVersion() or ''
    if version ~= '' then
        parts[#parts + 1] = 'v' .. version
    end
    local commit = g_app.getBuildCommit and g_app.getBuildCommit() or ''
    if commit ~= '' then
        parts[#parts + 1] = commit:sub(1, 7)
    end
    local renderer = g_graphics.getRenderer and g_graphics.getRenderer() or ''
    if renderer:find('Direct3D') then
        parts[#parts + 1] = 'DirectX'
    elseif renderer ~= '' then
        parts[#parts + 1] = 'OpenGL'
    end
    return table.concat(parts, ' ')
end

local function setStatus(text, color)
    if window then
        window.status:setText(text or '')
        window.status:setColor(color or DIM)
    end
end

local function refreshCounter()
    if window then
        local length = #window.message:getText()
        window.counter:setText(string.format('%d / %d', length, MAX_LENGTH))
        window.counter:setColor(length >= MAX_LENGTH and BAD or '#6f688a')
    end
end

local function selectKind(id)
    kind = id
    if window then
        for _, other in ipairs({ 'bug', 'idea', 'feedback' }) do
            window[other]:setChecked(other == id)
        end
    end
end

function hide()
    removeEvent(closeEvent)
    closeEvent = nil
    removeEvent(waitEvent)
    waitEvent = nil
    waiting = false
    if window then
        window:destroy()
        window = nil
    end
    if tab then
        tab:setOn(false)
    end
end

function show()
    if not g_game.isOnline() then
        return
    end
    if window then
        window:raise()
        window.message:focus()
        return
    end
    window = g_ui.createWidget('FeedbackWindow', rootWidget)
    for _, id in ipairs({ 'bug', 'idea', 'feedback' }) do
        window[id].onClick = function()
            selectKind(id)
        end
    end
    selectKind(kind)
    window.message.onTextChange = refreshCounter
    refreshCounter()
    setStatus('')
    window:raise()
    window:focus()
    window.message:focus()
    if tab then
        tab:setOn(true)
    end
end

function toggle()
    if window then
        hide()
    else
        show()
    end
end

function send()
    if not window or waiting then
        return
    end
    local text = window.message:getText():gsub('^%s+', ''):gsub('%s+$', '')
    if #text < 5 then
        setStatus(tr('Write a few words about it first.'), BAD)
        return
    end
    local protocol = g_game.getProtocolGame()
    if not protocol then
        setStatus(tr('You are not in the game.'), BAD)
        return
    end
    protocol:sendExtendedJSONOpcode(OPCODE, {
        action = 'send',
        kind = kind,
        message = text:sub(1, MAX_LENGTH),
        client = clientInfo(),
    })
    waiting = true
    window.sendButton:setEnabled(false)
    setStatus(tr('Sending...'))
    -- no answer (an old server): let the player try again
    waitEvent = scheduleEvent(function()
        waitEvent = nil
        if waiting and window then
            waiting = false
            window.sendButton:setEnabled(true)
            setStatus(tr('The server did not answer. Try again in a moment.'), BAD)
        end
    end, 8000)
end

-- the server's answer in the player's language (message: its English)
local function answerText(data)
    if data.code == 'sent' then
        return tr('Sent to the staff. Thank you!')
    elseif data.code == 'short' then
        return tr('Write a few words about it first.')
    elseif data.code == 'wait' then
        return string.format(tr('Wait %d seconds before sending another report.'), tonumber(data.seconds) or 30)
    elseif data.code == 'limit' then
        return tr('You sent many reports today. Thank you! Try again tomorrow.')
    end
    return latin1(data.message or '')
end

local function onOpcode(protocol, opcode, data)
    if type(data) ~= 'table' or data.action ~= 'result' then
        return
    end
    removeEvent(waitEvent)
    waitEvent = nil
    waiting = false
    local message = answerText(data)
    if not window then
        modules.game_textmessage.displayGameMessage(message)
        return
    end
    window.sendButton:setEnabled(true)
    if data.ok then
        window.message:setText('')
        setStatus(message, GOOD)
        closeEvent = scheduleEvent(hide, 1800)
    else
        setStatus(message, BAD)
    end
end

local function createTab()
    if tab then
        return
    end
    local root = modules.game_interface.getRootPanel()
    tab = g_ui.createWidget('FeedbackTab', root)
    tab.face:setText(tr('Feedback'))
    tab:addAnchor(AnchorRight, 'gameMapPanel', AnchorRight)
    tab:addAnchor(AnchorVerticalCenter, 'gameMapPanel', AnchorVerticalCenter)
    -- a little above the middle: the Mythos bar lies over the bottom
    tab:setMarginTop(-60)
    tab:setTooltip(tr('Report a bug or send an idea to the staff'))
    tab.onClick = toggle
end

local function onGameEnd()
    hide()
end

function init()
    g_ui.importStyle('feedback')
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    connect(g_game, { onGameEnd = onGameEnd })
    createTab()
end

function terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    disconnect(g_game, { onGameEnd = onGameEnd })
    hide()
    if tab then
        tab:destroy()
        tab = nil
    end
end
