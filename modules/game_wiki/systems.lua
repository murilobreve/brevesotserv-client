-- Pages of the Mythos systems built from the server's config, so they never
-- go out of date (data-otservbr-global/scripts/website/wiki_catalog.lua):
-- the rates and experience stages, the Ascensão paths of each vocation, the
-- Hunt Tasks and the VIP. Each comes once per session, when its page opens.

local ASK_AGAIN = 2500
local answers = {} -- action -> the server's answer
local askedAt = {}
local ascensaoVocation = 1

local WARM, DIM, PURPLE, GOLD = '#f3dcae', '#9789b3', '#a679e6', '#e2c35a'

local function T(text, ...)
    return WIKI_TEXT.T(text, ...)
end

local function L(text)
    return WIKI_TEXT.latin1(tostring(text or ''))
end

local function num(n)
    return WIKI_TEXT.num(n)
end

-- 1.2 -> "1,2"
local function decimal(n)
    local text = string.format('%.2f', tonumber(n) or 0):gsub('0+$', ''):gsub('%.$', '')
    return (text:gsub('%.', ','))
end

-- the server's answer to `action`, asked for once (nil while it comes)
local function ask(action)
    if not answers[action] and (not askedAt[action] or g_clock.millis() - askedAt[action] > ASK_AGAIN) then
        askedAt[action] = g_clock.millis()
        WIKI_REQUEST({ action = action })
    end
    return answers[action]
end

local function loading(parent)
    g_ui.createWidget('WikiText', parent):setText(T('Carregando...'))
end

local function heading(parent, text)
    g_ui.createWidget('WikiHeading', parent):setText(text)
end

local function paragraph(parent, text)
    g_ui.createWidget('WikiText', parent):setText(text)
end

local function tableOf(parent, widths, head, rows)
    WIKI_BUILDERS.table(parent, { 'table', widths = widths, head = head, rows = rows })
end

-- { min, max, multiplier } -> "1 a 8", "1401 ou mais"
local function stageRange(stage)
    local min, max = tonumber(stage[1]) or 0, tonumber(stage[2]) or 0
    if max <= 0 then
        return T('%s ou mais', num(min))
    end
    return T('%s a %s', num(min), num(max))
end

-- ---------------------------------------------------------------- rates

function WIKI_BUILDERS.ratesinfo(parent)
    local d = ask('rates')
    if not d then
        return loading(parent)
    end
    if d.useStages then
        heading(parent, T('Experiência por level'))
        local rows = {}
        for _, stage in ipairs(d.experience or {}) do
            table.insert(rows, { stageRange(stage), { T('%sx', decimal(stage[3])), GOLD } })
        end
        tableOf(parent, { 200, 346 }, { T('Level'), T('Rate de XP') }, rows)
        paragraph(parent, T('A rate vale para a experiência base de cada monstro, antes dos outros bônus (veja Bônus de experiência).'))

        heading(parent, T('Skills e magic level'))
        local skills, magic = d.skills or {}, d.magic or {}
        local rows2 = {}
        for i = 1, math.max(#skills, #magic) do
            local skill, mlevel = skills[i], magic[i]
            table.insert(rows2, {
                skill and stageRange(skill) or '-', skill and { T('%sx', decimal(skill[3])), GOLD } or '-',
                mlevel and stageRange(mlevel) or '-', mlevel and { T('%sx', decimal(mlevel[3])), GOLD } or '-',
            })
        end
        tableOf(parent, { 140, 133, 140, 133 }, { T('Skill'), T('Rate'), T('Magic level'), T('Rate') }, rows2)
        paragraph(parent, T('A rate de skill depende do nível da skill que está subindo, e a de magic level do seu magic level.'))
    else
        heading(parent, T('Rates'))
        tableOf(parent, { 200, 346 }, nil, {
            { T('Experiência'), T('%sx', num(d.rateExp)) },
            { T('Skills'), T('%sx', num(d.rateSkill)) },
            { T('Magic level'), T('%sx', num(d.rateMagic)) },
        })
    end

    heading(parent, T('Outras rates'))
    local speedup = function(rate)
        local value = tonumber(rate) or 1
        if math.abs(value - 1) < 0.001 then
            return T('normal')
        end
        return value > 1 and T('%sx mais rápido', decimal(value)) or T('%sx mais lento', decimal(1 / value))
    end
    tableOf(parent, { 200, 346 }, nil, {
        { T('Loot'), T('%sx: a chance de cada item é multiplicada por %s', num(d.loot), num(d.loot)) },
        { T('Respawn'), T('%sx', num(d.spawn)) },
        { T('Cooldown das magias'), T('dividido por %s', decimal(d.spellCooldown)) },
        { T('Velocidade de ataque'), speedup(d.attackSpeed) },
        { T('Treino com armas de exercício'), speedup(d.exercise) },
    })
end

-- ---------------------------------------------------------------- Ascensão

function WIKI_BUILDERS.ascensaoinfo(parent)
    local d = ask('ascensao')
    if not d then
        return loading(parent)
    end
    local costs = {}
    for i, cost in ipairs(d.circleCost or {}) do
        table.insert(costs, T('%dº círculo: %d', i, cost))
    end
    paragraph(parent, T('No level %d você ganha o primeiro ponto de Ascensão, e mais 1 a cada %d levels. Cada vocação tem três caminhos de 5 círculos, comprados em ordem (%s pontos). Com pontos sobrando, uma relíquia custa %d (só uma por vez). O primeiro reset é de graça; os outros custam %s gold por ponto gasto. O botão Ascensão na barra Mythos abre a janela.',
        d.startLevel or 0, d.levelsPerPoint or 0, table.concat(costs, ', '), d.relicCost or 0, num(d.resetGold)))

    local vocations = d.vocations or {}
    local tabs = g_ui.createWidget('WikiLinks', parent)
    for i, vocation in ipairs(vocations) do
        local tab = g_ui.createWidget('BrevesTab', tabs)
        tab:setWidth(104)
        tab:setText(L(vocation.name))
        tab:setChecked(i == ascensaoVocation)
        tab.onClick = function()
            ascensaoVocation = i
            refresh('ascensao')
        end
    end
    local vocation = vocations[ascensaoVocation] or vocations[1]
    if not vocation then
        return
    end
    for _, path in ipairs(vocation.paths or {}) do
        heading(parent, T('%s  -  %s (%s)', L(path.name), L(path.title), L(path.kind)))
        local rows = {}
        local skillshot = path.skillshot or {}
        if (skillshot.words or '') ~= '' then
            table.insert(rows, { { T('Magia do caminho'), WARM }, { T('%s (%s), liberada no 1º círculo', L(skillshot.label), L(skillshot.words)), PURPLE }, link = 's:' .. L(skillshot.name) })
            if (skillshot.use or '') ~= '' then
                table.insert(rows, { { T('Como usar'), WARM }, L(skillshot.use) })
            end
        end
        for i, circle in ipairs(path.circles or {}) do
            table.insert(rows, { { T('%dº  %s', i, L(circle.name)), WARM }, L(circle.desc), link = (circle.spell or '') ~= '' and ('s:' .. L(circle.spell)) or nil })
            if (circle.use or '') ~= '' then
                table.insert(rows, { { T('Como usar'), WARM }, L(circle.use) })
            end
        end
        tableOf(parent, { 170, 376 }, nil, rows)
    end
    if #(vocation.relics or {}) > 0 then
        heading(parent, T('Relíquias'))
        local rows = {}
        for _, relic in ipairs(vocation.relics) do
            table.insert(rows, { { L(relic.name), WARM }, L(relic.desc) })
        end
        tableOf(parent, { 170, 376 }, nil, rows)
    end
    local titles = {}
    for _, path in ipairs(vocation.paths or {}) do
        table.insert(titles, { { L(path.title), PURPLE }, T('%s completo', L(path.name)) })
    end
    for _, hybrid in ipairs(vocation.hybrids or {}) do
        local a, b = tostring(hybrid[1]):match('^(%w+)%+(%w+)$')
        local names = {}
        for _, path in ipairs(vocation.paths or {}) do
            if path.id == a or path.id == b then
                table.insert(names, L(path.name))
            end
        end
        table.insert(titles, { { L(hybrid[2]), PURPLE }, T('%s completos', table.concat(names, ' + ')) })
    end
    if #titles > 0 or (vocation.grandTitle or '') ~= '' then
        heading(parent, T('Títulos'))
        if (vocation.grandTitle or '') ~= '' then
            table.insert(titles, { { L(vocation.grandTitle), GOLD }, T('os três caminhos completos') })
        end
        tableOf(parent, { 200, 346 }, nil, titles)
        paragraph(parent, T('Com uma relíquia, o título ganha "Ascended" na frente.'))
    end
end

-- ---------------------------------------------------------------- Hunt Tasks

function WIKI_BUILDERS.tasksinfo(parent)
    local d = ask('systems')
    if not d then
        return loading(parent)
    end
    local t = d.tasks
    if type(t) ~= 'table' then
        return paragraph(parent, T('As Hunt Tasks estão desligadas.'))
    end
    heading(parent, T('Tarefa diária'))
    local window = t.window or { 0, 0 }
    tableOf(parent, { 200, 346 }, nil, {
        { T('Monstro'), T('Sorteado entre os que têm level recomendado de %d%% a %d%% do seu', math.floor((window[1] or 0) * 100 + 0.5), math.floor((window[2] or 0) * 100 + 0.5)) },
        { T('Kills'), T('%d a %d (mais spawns, mais kills)', t.kills[1] or 0, t.kills[2] or 0) },
        { T('Experiência'), T('%d%% do que falta para o próximo level', math.floor((t.experience or 0) * 100 + 0.5)) },
        { T('Hunt Points'), T('%d, mais %d por dia seguido (até +%d)', t.points or 0, t.streakBonus or 0, (t.streakBonus or 0) * (t.streakMax or 0)) },
        { T('Monstro em alta'), T('Com XP %sx ou mais no Hunt Board, os pontos dobram', decimal(t.hot)) },
        { T('Charm points'), T('%d', t.charms or 0) },
        { T('Trocar o monstro'), T('%d vez de graça por dia; depois, level x %s gold', t.freeRerolls or 0, num(t.rerollGold)) },
    })
    heading(parent, T('Trilha do Caçador'))
    paragraph(parent, T('Uma corrente fixa de %d monstros, do %s até o %s. Cada passo pede de %s a %s kills, dá %d%% de um level, Hunt Points e charm points; a cada %d passos vem um bônus de %d pontos e %d charm points.',
        t.trailSteps or 0, L(t.trailFirst), L(t.trailLast), num(t.trailKills[1]), num(t.trailKills[2]), math.floor((t.trailExperience or 0) * 100 + 0.5),
        t.milestoneEvery or 0, t.milestonePoints or 0, t.milestoneCharms or 0))
    paragraph(parent, T('A janela de Hunt Tasks leva até o monstro da tarefa e da trilha pelo mesmo teleport do Hunts TP (%d segundos de espera, só fora de luta).', t.cooldown or 0))
    heading(parent, T('Loja do Szuszkin'))
    local rows = {}
    for _, offer in ipairs(t.shop or {}) do
        table.insert(rows, { { T('%s pontos', num(offer[2])), GOLD }, L(offer[3]) })
    end
    tableOf(parent, { 110, 436 }, nil, rows)
    paragraph(parent, T('Diga shop para o Szuszkin ou abra a janela de Hunt Tasks para comprar.'))
end

-- ---------------------------------------------------------------- VIP

local VIP_BONUS = {
    { 'experience', 'Experiência', '+%d%%' },
    { 'loot', 'Loot', '+%d%%' },
    { 'skill', 'Skills', '+%d%% de treino' },
    { 'huntPoints', 'Hunt Points', '+%d%%' },
    { 'rarityXp', 'Rarity XP', '+%d%% dos monstros raros' },
    { 'rareMonster', 'Monstros raros', '+%d%% de chance (relativa)' },
    { 'blessDiscount', 'Blessings', '%d%% mais baratas' },
}

function WIKI_BUILDERS.vipinfo(parent)
    local d = ask('systems')
    if not d then
        return loading(parent)
    end
    local v = d.vip
    if type(v) ~= 'table' then
        return paragraph(parent, T('O VIP está desligado.'))
    end
    heading(parent, T('O que o VIP dá'))
    local rows = {}
    for _, entry in ipairs(VIP_BONUS) do
        local value = tonumber((v.bonus or {})[entry[1]])
        if value and value > 0 then
            table.insert(rows, { T(entry[2]), { T(entry[3], value), GOLD } })
        end
    end
    if (tonumber(v.extraFreeRerolls) or 0) > 0 then
        table.insert(rows, { T('Hunt Tasks'), { T('+%d troca grátis da tarefa diária por dia', v.extraFreeRerolls), GOLD } })
    end
    if #(v.mounts or {}) > 0 then
        local mounts = {}
        for _, name in ipairs(v.mounts) do
            table.insert(mounts, L(name))
        end
        table.insert(rows, { T('Montarias'), { table.concat(mounts, ', '), GOLD } })
    end
    tableOf(parent, { 160, 386 }, nil, rows)
    paragraph(parent, T('As montarias do VIP ficam com você enquanto o VIP durar.'))
    heading(parent, T('Planos'))
    local plans = {}
    for _, plan in ipairs(v.plans or {}) do
        local days = tonumber(plan[1]) or 0
        table.insert(plans, { days >= 365 and T('12 meses') or (days >= 30 and T('%d %s', math.floor(days / 30), days >= 60 and T('meses') or T('mês')) or T('%d dias', days)), { T('%s Mythos Coins', num(plan[2])), GOLD } })
    end
    tableOf(parent, { 160, 386 }, nil, plans)
    paragraph(parent, T('Compre na Store do jogo ou na página VIP do site. O VIP vale para a conta toda.'))
end

-- ---------------------------------------------------------------- server

local PAGES = { rates = { 'rates' }, ascensao = { 'ascensao' }, systems = { 'hunttasks', 'vip' } }

for action, pageIds in pairs(PAGES) do
    WIKI_HANDLERS[action] = function(data)
        answers[action] = data
        for _, id in ipairs(pageIds) do
            refresh(id)
        end
    end
end

WikiSystems = {}

function WikiSystems.reset()
    answers, askedAt, ascensaoVocation = {}, {}, 1
end
