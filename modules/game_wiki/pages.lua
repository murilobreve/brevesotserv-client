-- Mythos Wiki content. The numbers of the rarity pages come from the
-- server's rarity config (data-otservbr-global/scripts/rarity/00_config.lua)
-- and the engine's forge stack formulas; keep them in sync when that file is
-- rebalanced. Items, NPCs, spells, hunts and the Mythos systems come from the
-- server itself (wiki_catalog.lua) and need no sync.
--
-- A page is a list of blocks; wiki.lua turns each block type into widgets:
--   lead, p, h      text (lead is the larger intro paragraph)
--   note            framed text for a rule that is easy to miss
--   tierstrip       the four monster tiers side by side, same monster
--   tier            one tier: live preview with its shader and aura + stats
--   grades          the five item grades with a tinted item each
--   table           head + rows; a cell can be { text, color }
--   links           buttons to other pages
--   monsterlist     every monster of the server, searchable (monsters.lua,
--                   which also builds each monster's page)
--   itemlist        the items of some categories, a tab each (items.lua,
--                   which also builds each item's page)
--   imbuementlist   every imbuement, its levels and materials (items.lua)
--   npclist         every NPC on the map (npcs.lua, and each NPC's page)
--   npcrows         a list of NPCs with where they stand (npcs.lua)
--   spelllist       every spell, a tab per vocation (spells.lua)
--   huntlist        every hunt of the Hunts TP by level (monsters.lua)
--   cards           big links with a picture, for the home pages
--   ratesinfo, ascensaoinfo, tasksinfo, vipinfo
--                   the Mythos systems from the server's config (systems.lua)

-- this file runs again when the modules reload (changing the language does
-- it): its tables are UTF-8 once more, so wiki.lua must convert them again
WIKI_CONVERTED = false

-- example: a real roll of the server for each grade (scripts/rarity), on a
-- weapon; the grade's item is that weapon
WIKI_GRADES = {
    { key = 'uncommon', name = 'Communis', color = '#63c08a', frame = 1, item = 3271, shader = 'Rarity - Uncommon', bonuses = 1, band = '0% a 35%',
      example = { 'Spike Sword', '+6% Melee Skills' } },
    { key = 'rare', name = 'Rarus', color = '#4f8fe8', frame = 2, item = 3280, shader = 'Rarity - Rare', bonuses = 2, minBonuses = 1, band = '10% a 50%',
      example = { 'Fire Sword', '+19% Cleave Damage, +9% Melee Skills' } },
    { key = 'epic', name = 'Praeclarus', color = '#a679e6', frame = 3, item = 3071, shader = 'Rarity - Epic', bonuses = 3, minBonuses = 1, band = '15% a 70%',
      example = { 'Wand of Inferno', '+21% Exevo Gran Mas Flam Damage, +6% Critical Hit Chance, +3% Onslaught' } },
    { key = 'legendary', name = 'Legendarius', color = '#e2a443', frame = 4, item = 3288, shader = 'Rarity - Legendary', bonuses = 4, minBonuses = 1, band = '20% a 85%',
      example = { 'Magic Sword', '+40% Attack Spell Damage, +14% Melee Skills, +6% Critical Hit Chance, +4% Onslaught' } },
    { key = 'mythic', name = 'Mythicus', color = '#e8e4ff', frame = 5, item = 3296, shader = 'Rarity - Mythic', bonuses = 5, minBonuses = 1, band = '30% a 100%',
      example = { 'Warlord Sword', '+33% Melee Skills, +26 Attack, +22% Life Leech, +15% Critical Hit Chance, +5% Onslaught' } },
}

-- stack: forge stack the tier gives the monster. The engine turns it into
-- HP x(1 + (15*stack + 35)/100), attack x(1.35 + (stack-1)*0.1) and
-- experience x(stack + 10)/10; the tier's healthFactor multiplies the HP
-- again and rarity tiers get no forge defense.
WIKI_TIERS = {
    pale = {
        name = 'Pale', color = '#c9d6e3', shader = 'Rarity - Pale', outfit = 34, monster = 'Dragon',
        chance = '0,63%', hp = 'x2,94', attack = 'x1,75', defense = 'x1', xp = 'x1,5',
        loot = 'x3', rolls = '+1', gold = 'x10', affix = '0,75 por morte', skull = 'Branca',
        grades = { 66, 28, 5.2, 0.75, 0.05 },
        arrival = '"You sense something pale stirring..." e um brilho azul no corpo.',
    },
    ashen = {
        name = 'Ashen', color = '#9aa0a8', shader = 'Rarity - Ashen', outfit = 55, monster = 'Behemoth',
        chance = '0,44%', hp = 'x4,32', attack = 'x2,15', defense = 'x1', xp = 'x1,9',
        loot = 'x6', rolls = '+1', gold = 'x30', affix = '1,2 por morte', skull = 'Vermelha',
        grades = { 50, 33, 12.5, 3.9, 0.6 },
        arrival = 'Fogo no chão, fumaça em volta e "*the ground scorches*".',
    },
    obsidian = {
        name = 'Obsidian', color = '#9b7bff', shader = 'Rarity - Obsidian', outfit = 121, monster = 'Hydra',
        chance = '0,31%', hp = 'x6,56', attack = 'x2,65', defense = 'x1', xp = 'x2,4',
        loot = 'x12', rolls = '+2', gold = 'x50', affix = '1,5 por morte', skull = 'Preta',
        grades = { 33, 32, 23, 8, 4 },
        arrival = 'Explosões, anéis de morte e "IT HAS ARRIVED!".',
    },
    deathlord = {
        name = 'Lord of Death', color = '#e04848', shader = 'Rarity - Lord of Death', outfit = 25, monster = 'Minotaur',
        effect = 20,
        chance = '0,031%', hp = 'x8,64', attack = 'x3,30', defense = 'x1', xp = 'x2,5',
        loot = 'x20', rolls = '+3', gold = 'x50', affix = '3 por morte', skull = 'Preta',
        grades = { 20, 20, 20, 28, 12 },
        arrival = 'A luz some, o pentagrama preto aparece e tudo em volta morre.',
    },
}

WIKI_TIER_ORDER = { 'pale', 'ashen', 'obsidian', 'deathlord' }

local function gradeName(i)
    return { WIKI_GRADES[i].name, WIKI_GRADES[i].color }
end

local GRADE_HEAD = { 'Tier', 'Communis', 'Rarus', 'Praeclarus', 'Legendarius', 'Mythicus' }

local function gradeRow(label, color, weights)
    local row = { { label, color } }
    for i, w in ipairs(weights) do
        local text = w == 0 and '-' or (tostring(w):gsub('%.', ',') .. '%')
        table.insert(row, { text, w == 0 and '#5a5a5a' or WIKI_GRADES[i].color })
    end
    return row
end

-- the wiki has two halves, a tab each: what is Tibia's (creatures, items,
-- NPCs, spells: TibiaWiki's ground) and what only Mythos has
WIKI_SECTIONS = {
    { key = 'tibia', title = 'Wiki do Tibia', tab = 'Tibia', home = 'home' },
    { key = 'mythos', title = 'Wiki do Mythos', tab = 'Mythos', home = 'mythos' },
}

WIKI_GROUPS = {
    { section = 'tibia', title = 'Início', pages = { 'home' } },
    { section = 'tibia', title = 'Criaturas', pages = { 'monsters' } },
    { section = 'tibia', title = 'Itens', pages = { 'weapons', 'equipment', 'supplies', 'loot', 'otheritems', 'imbuements' } },
    { section = 'tibia', title = 'NPCs e quests', pages = { 'npcs', 'quests' } },
    { section = 'tibia', title = 'Magias', pages = { 'spells' } },
    { section = 'tibia', title = 'Hunts e viagem', pages = { 'hunts', 'travel' } },
    { section = 'mythos', title = 'Início', pages = { 'mythos' } },
    { section = 'mythos', title = 'Monstros raros', pages = { 'tiers', 'pale', 'ashen', 'obsidian', 'deathlord', 'huntboard' } },
    { section = 'mythos', title = 'Itens raros', pages = { 'items', 'grades', 'quality', 'pools' } },
    { section = 'mythos', title = 'Bônus', pages = { 'affixes', 'stacking', 'experience' } },
    { section = 'mythos', title = 'Sistemas Mythos', pages = { 'rates', 'hunttasks', 'ascensao', 'vip' } },
    { section = 'mythos', title = 'Loot', pages = { 'autoloot' } },
}

WIKI_PAGES = {}

-- ---------------------------------------------------------------- home pages

WIKI_PAGES.home = {
    menu = 'Página inicial',
    title = 'Wiki do Tibia',
    blocks = {
        { 'lead', 'As criaturas, os itens, os NPCs e as magias do nosso mundo, como na TibiaWiki, com os números direto do servidor: vida, XP, elementos, loot com as chances, quem dropa cada item e quanto um NPC paga por ele.' },
        { 'cards', {
            { page = 'monsters', title = 'Criaturas', text = 'Filtre por classe, fraqueza e pelo item que dropa.', outfit = 34 },
            { page = 'weapons', title = 'Armas', text = 'Ataque, defesa, level e vocação de cada arma.', item = 3288 },
            { page = 'equipment', title = 'Equipamentos', text = 'Capacetes, armaduras, calças, botas, escudos, anéis e amuletos.', item = 3381 },
            { page = 'supplies', title = 'Poções, runas e comida', text = 'Quem vende, por quanto e a magia de cada runa.', item = 239 },
            { page = 'loot', title = 'Loot', text = 'Os itens que os monstros dropam e quanto os NPCs pagam.', item = 3043 },
            { page = 'imbuements', title = 'Imbuements', text = 'Os três níveis de cada um, efeitos e materiais.', item = 3061 },
            { page = 'npcs', title = 'NPCs', text = 'Onde ficam e o que compram e vendem.', outfit = 128, colors = { 78, 69, 58, 76 } },
            { page = 'quests', title = 'Quests', text = 'As linhas de quests com NPCs e o que dão.', item = 2854 },
            { page = 'spells', title = 'Magias', text = 'Por vocação, com o cooldown real e como aprender.', item = 3155 },
            { page = 'hunts', title = 'Hunts', text = 'As hunts do Hunts TP por level, perto do seu.', outfit = 129, colors = { 95, 116, 121, 115 } },
        } },
        { 'h', 'Quem dropa um item?' },
        { 'p', 'Na lista de criaturas, escreva o nome do item em "Dropa o item": aparecem só as criaturas que o dropam, da maior chance para a menor, com a chance de cada uma. A página de cada item também mostra quem o dropa e quais NPCs compram e vendem.' },
        { 'links', { 'monsters', 'loot' } },
    },
}

WIKI_PAGES.mythos = {
    menu = 'Página inicial',
    title = 'Wiki do Mythos',
    blocks = {
        { 'lead', 'O que só o Mythos tem: monstros raros que voltam mais fortes, itens raros com bônus sorteados, o Hunt Board, as Hunt Tasks, a Ascensão e o VIP.' },
        { 'tierstrip' },
        { 'cards', {
            { page = 'tiers', title = 'Monstros raros', text = 'Pale, Ashen, Obsidian e Lord of Death: mais vida, XP e loot.', tier = 'obsidian' },
            { page = 'items', title = 'Itens raros', text = 'De Communis a Mythicus, com 1 a 5 bônus sorteados.', item = 3288, shader = 'Rarity - Legendary' },
            { page = 'affixes', title = 'Bônus', text = 'Cada bônus, quanto rola e como eles somam.', item = 3296, shader = 'Rarity - Mythic' },
            { page = 'huntboard', title = 'Hunt Board', text = 'Rates de XP e loot de cada monstro, sorteadas a cada 2 horas.', outfit = 121 },
            { page = 'hunttasks', title = 'Hunt Tasks', text = 'A task diária, a Trilha do Caçador e os Hunt Points.', item = 3043 },
            { page = 'ascensao', title = 'Ascensão', text = 'Os caminhos de cada vocação e seus skillshots.', item = 3155 },
            { page = 'rates', title = 'Rates e experiência', text = 'As rates do servidor e o que as aumenta.', item = 239 },
            { page = 'vip', title = 'VIP', text = 'O que o VIP dá e como conseguir.', item = 3381 },
            { page = 'autoloot', title = 'Autoloot', text = 'Como o loot vai sozinho para a sua bolsa.', item = 2854 },
        } },
    },
}

WIKI_PAGES.monsters = {
    menu = 'Todas as criaturas',
    title = 'Criaturas',
    blocks = {
        { 'lead', 'As criaturas do nosso mundo, como na TibiaWiki: vida, experiência, elementos, habilidades, comportamento e loot de cada uma, direto do servidor.' },
        { 'p', 'Filtre pelo nome, pelo item que ela dropa, pela classe do bestiário ou pela fraqueza, e clique no título de uma coluna para ordenar. "Gold/kill" é quanto uma kill rende em média vendendo o loot.' },
        { 'monsterlist' },
    },
}

-- ---------------------------------------------------------------- items

local function itemPage(id, menu, title, lead)
    return { menu = menu, title = title, blocks = { { 'lead', lead }, { 'itemlist', id } } }
end

WIKI_PAGES.weapons = itemPage('weapons', 'Armas', 'Armas', 'Todas as armas do servidor, com ataque, defesa, level e vocação. Clique numa arma para ver quem dropa, quem vende, quanto um NPC paga por ela e se pode vir rara.')
WIKI_PAGES.equipment = itemPage('equipment', 'Equipamentos', 'Equipamentos', 'Capacetes, armaduras, calças, botas, escudos, spellbooks, aljavas, amuletos e anéis, com os atributos de cada um.')
WIKI_PAGES.supplies = itemPage('supplies', 'Suprimentos', 'Poções, runas e comida', 'O que se gasta caçando: poções, runas e comida, com quem vende e o preço. A página de cada runa mostra a magia que a faz.')
WIKI_PAGES.loot = itemPage('loot', 'Loot', 'Loot', 'Os itens que os monstros do nosso mundo dropam, com o valor que os NPCs pagam. "Valor" ordena pelo que dá mais dinheiro.')
WIKI_PAGES.otheritems = itemPage('otheritems', 'Outros itens', 'Outros itens', 'Ferramentas, bolsas, fontes de luz, itens para domar montarias, imbuement scrolls, chaves e tokens que dá para conseguir aqui.')

WIKI_PAGES.imbuements = {
    menu = 'Imbuements',
    title = 'Imbuements',
    blocks = {
        { 'lead', 'Imbuements dão bônus temporários a armas e equipamentos com slots de imbuement. Cada um tem três níveis (Basic, Intricate e Powerful), e cada nível pede materiais que os monstros dropam.' },
        { 'p', 'A Morvena, em Ventera, vende todos os materiais e imbuement scrolls prontos, se você estiver com pressa. A página de cada material mostra quais monstros o dropam.' },
        { 'imbuementlist' },
    },
}

-- ---------------------------------------------------------------- NPCs and quests

WIKI_PAGES.npcs = {
    menu = 'Todos os NPCs',
    title = 'NPCs',
    blocks = {
        { 'lead', 'Todos os NPCs do mapa: onde ficam, o que fazem e o que vendem e compram. Busque por nome, cidade ou pelo que procura ("poções", "runas", "banco", "addons").' },
        { 'npclist' },
    },
}

WIKI_PAGES.quests = {
    menu = 'Quests',
    title = 'Quests com NPCs',
    blocks = {
        { 'lead', 'As linhas de missões dos NPCs, na ordem em que se faz cada uma. Fale com o NPC e diga a palavra destacada na fala dele (mission, task...). Clique num NPC para ver onde ele fica.' },
        { 'h', 'Trox Quest (10 missões)' },
        { 'npcrows', { { '1ª missão', 'Lenado' }, { '2ª missão', 'Hamax' }, { '3ª missão', 'Amareth' }, { '4ª missão', 'Trutth' }, { '5ª missão', 'Embermane' },
            { '6ª missão', 'Egon' }, { '7ª missão', 'Sirius Black' }, { '8ª missão', 'Hatuso' }, { '9ª missão', 'Marx' }, { '10ª missão', 'Rei Tiberius' },
            { 'Ajuda', 'Bazith' }, { 'Ajuda', 'Fray' }, { 'Ajuda', 'Lais' } } },
        { 'h', 'Brave Warriors (5 missões)' },
        { 'npcrows', { { '1ª missão', 'Perseu' }, { '2ª missão', 'Saprohem' }, { '3ª missão', 'Barbosa' }, { '4ª missão', 'Lost Marcos' }, { '5ª missão', 'Dorbin' } } },
        { 'h', 'Gladiators Missions (8 missões)' },
        { 'npcrows', { { '1ª missão', 'Dundara' }, { '2ª missão', 'Shiryu' }, { '3ª missão', 'Gaara' }, { '4ª missão', 'Saski' }, { '5ª missão', 'Viggo' },
            { '6ª missão', 'Helena' }, { '7ª missão', 'Anakin' }, { '8ª missão', 'Hue' } } },
        { 'h', 'Outras missões' },
        { 'npcrows', { { 'Demon Oak', 'Oldrak' }, { 'Fundadores', 'Meteor Furious' }, { 'Bem ou mal', 'Palimuth' }, { 'Bem ou mal', 'Yalaharian' },
            { 'Pirate hat', 'Lissy' }, { 'Winged Helmet', 'Thandruil' }, { 'Permissão', 'Walter' }, { 'Bozo', 'Bozo' }, { 'Bellatrix', 'Bellatrix Lestrange' },
            { 'Glooth Fairy', 'Flora' }, { 'Galaxy', 'Magnus' }, { 'Sala de prêmios', 'Floaten' } } },
    },
}

-- ---------------------------------------------------------------- Mythos systems
-- (systems.lua builds them from the server's config)

WIKI_PAGES.rates = {
    menu = 'Rates e experiência',
    title = 'Rates do servidor',
    blocks = {
        { 'lead', 'A experiência, as skills e o magic level sobem em estágios: quanto mais alto o level, menor a rate. Os números abaixo vêm direto da configuração do servidor.' },
        { 'ratesinfo' },
        { 'links', { 'experience', 'huntboard' } },
    },
}

WIKI_PAGES.hunttasks = {
    menu = 'Hunt Tasks',
    title = 'Hunt Tasks (Szuszkin)',
    blocks = {
        { 'lead', 'O Szuszkin, em Ventera, dá uma tarefa diária de caça e a Trilha do Caçador, uma sequência de monstros do mais fraco ao mais forte. As tarefas pagam experiência, Hunt Points e charm points; os pontos compram itens na loja dele.' },
        { 'tasksinfo' },
        { 'links', { 'hunts', 'npcs' } },
    },
}

WIKI_PAGES.ascensao = {
    menu = 'Ascensão',
    title = 'Ascensão',
    blocks = {
        { 'lead', 'A Ascensão é a árvore de poder de cada vocação: três caminhos com cinco círculos cada, que melhoram as suas magias e liberam uma magia nova por caminho.' },
        { 'ascensaoinfo' },
        { 'links', { 'spells' } },
    },
}

WIKI_PAGES.vip = {
    menu = 'VIP',
    title = 'Mythos VIP',
    blocks = {
        { 'lead', 'O Mythos VIP é um bônus mensal para a conta inteira, comprado com Mythos Coins.' },
        { 'vipinfo' },
    },
}

-- ---------------------------------------------------------------- spells

WIKI_PAGES.spells = {
    menu = 'Todas as magias',
    title = 'Magias',
    blocks = {
        { 'lead', 'Todas as magias de cada vocação com os números deste servidor: level, mana, cooldown e como aprender. As magias da sua vocação são suas ao chegar no level; as da Ascensão e da Roda do Destino têm o próprio caminho.' },
        { 'spelllist' },
    },
}

WIKI_PAGES.tiers = {
    menu = 'Como funciona',
    title = 'Monstros raros',
    blocks = {
        { 'lead', 'Qualquer monstro comum que você mata pode voltar dos mortos mais forte. O corpo treme, cinco avisos tocam no lugar e, 7 segundos depois, ele se levanta com um prefixo no nome, uma cor própria e um loot muito melhor.' },
        { 'tierstrip' },
        { 'h', 'As quatro camadas' },
        { 'table', widths = { 110, 64, 58, 58, 52, 52, 58 },
          head = { 'Tier', 'Chance', 'Vida', 'Ataque', 'XP', 'Loot', 'Ouro' },
          rows = {
              { { 'Pale', '#c9d6e3' }, '0,63%', 'x2,94', 'x1,75', 'x1,5', 'x3', 'x10' },
              { { 'Ashen', '#9aa0a8' }, '0,44%', 'x4,32', 'x2,15', 'x1,9', 'x6', 'x30' },
              { { 'Obsidian', '#9b7bff' }, '0,31%', 'x6,56', 'x2,65', 'x2,4', 'x12', 'x50' },
              { { 'Lord of Death', '#e04848' }, '0,031%', 'x8,64', 'x3,30', 'x2,5', 'x20', 'x50' },
          } },
        { 'p', 'Um monstro raro é mais forte só na vida: armadura e defesa são as do monstro normal, então o seu dano entra inteiro.' },
        { 'p', 'A chance é por morte de monstro. O sorteio começa pela camada mais alta, então um mesmo monstro nunca vira duas coisas ao mesmo tempo. Loot multiplica a chance de cada item da lista do próprio monstro nas rolagens extras, até no máximo 50% por rolagem, para o corpo não vir sempre com os mesmos itens; itens muito raros (abaixo de 0,3% de chance) não são multiplicados.' },
        { 'p', 'Ouro multiplica o ouro que o monstro dá normalmente: um Dragon Lord Obsidian deixa uns 4.600 de ouro em vez de uns 90. Ele vem em crystal e platinum coins.' },
        { 'p', 'O monstro que volta com tier não pertence a nenhum spawn: se ficar 5 minutos sem nenhum jogador a até 10 sqm, ele some.' },
        { 'h', 'Regras' },
        { 'p', 'A chance é a mesma para qualquer monstro comum. Um monstro raro que morre não volta de novo: matar um Pale não deixa um Ashen ou outro Pale mais provável. Bosses, summons e monstros de treino nunca voltam.' },
        { 'p', 'Só os monstros raros dão itens raros. Um monstro comum nunca dá.' },
        { 'p', 'Cada monstro raro lança a sua magia: o chão marca a área uns 3 segundos antes e o mapa fica na cor dele (azul gelado no Pale, brasa no Ashen, roxo escuro no Obsidian, escuro no Lord of Death). Saia da área marcada.' },
        { 'p', 'Todo o loot de um monstro raro vai para uma Loot Bag dentro do corpo. A bag não sai do corpo, só os itens de dentro.' },
        { 'p', 'Nada é anunciado para o servidor: só quem está perto vê os avisos.' },
        { 'p', 'Se o monstro estiver com rate alta no Hunt Board, as chances sobem. Veja a página do Hunt Board.' },
        { 'links', { 'pale', 'ashen', 'obsidian', 'deathlord', 'huntboard' } },
    },
}

local function tierPage(key, menu, extra)
    local tier = WIKI_TIERS[key]
    local blocks = {
        { 'tier', key },
        { 'h', 'Grau do item que ele dá' },
        { 'table', widths = { 90, 74, 60, 80, 86, 70 }, head = GRADE_HEAD,
          rows = { gradeRow(tier.name, tier.color, tier.grades) } },
    }
    for _, block in ipairs(extra) do
        table.insert(blocks, block)
    end
    return { menu = menu, title = tier.name, blocks = blocks }
end

WIKI_PAGES.pale = tierPage('pale', 'Pale', {
    { 'p', 'A camada mais comum: 0,63% das mortes (1 em 160). Tem quase o triplo da vida e o triplo de loot. Três vezes em cada quatro, ele deixa um item raro.' },
    { 'p', 'Ele tem caveira branca e uma cor fria, quase sem saturação.' },
    { 'links', { 'tiers', 'ashen' } },
})

WIKI_PAGES.ashen = tierPage('ashen', 'Ashen', {
    { 'p', 'Cinza de cinzas, com tons doentes de verde e violeta. Aparece em 0,44% das mortes (1 em 229), com caveira vermelha e fumaça em volta.' },
    { 'p', 'O loot é 6 vezes maior. Ele sempre deixa um item raro, e 20% das vezes deixa dois.' },
    { 'links', { 'pale', 'obsidian' } },
})

WIKI_PAGES.obsidian = tierPage('obsidian', 'Obsidian', {
    { 'p', 'Roxo e azul, com caveira preta. Aparece em 0,31% das mortes (1 em 320).' },
    { 'p', 'Ele sempre deixa um item raro, e metade das vezes deixa dois. O corpo tem 2 rolagens extras de loot. Um terço dos raros já sai Praeclarus ou melhor.' },
    { 'links', { 'ashen', 'deathlord' } },
})

WIKI_PAGES.deathlord = tierPage('deathlord', 'Lord of Death', {
    { 'p', 'O monstro mais raro do jogo: 1 em 3200 mortes, um décimo da chance do Obsidian. Deixa três itens raros, e 40% deles saem Legendarius ou Mythicus. Fica todo preto, com o pentagrama preto embaixo dele.' },
    { 'h', 'Quando ele chega' },
    { 'p', 'Todo outro monstro a até 6 sqm, no mesmo andar, morre na hora. Eles não dão loot nem XP e voltam pelo respawn normal. Bosses e summons de jogadores não morrem.' },
    { 'h', 'Se ele matar você' },
    { 'note', 'Em 70% das mortes, nem bless nem amulet of loss protegem. Você perde o backpack e todo container que estiver usando, e cada outro item equipado tem 30% de chance de cair no corpo.' },
    { 'p', 'Vale quando ele dá o último golpe ou quando foi quem mais causou dano. Nos outros 30% das vezes a morte segue a regra normal de bless e AOL.' },
    { 'h', 'O prêmio' },
    { 'p', 'Os três itens podem sair de qualquer grau, mas 40% deles saem Legendarius ou Mythicus, mesmo de monstro fraco. Se o monstro não tiver equipamento na lista de loot dele (um rato, por exemplo), o corpo recebe equipamentos comuns sorteados, já raros.' },
    { 'links', { 'obsidian', 'grades' } },
})

WIKI_PAGES.huntboard = {
    menu = 'Hunt Board e raros',
    title = 'Hunt Board e monstros raros',
    blocks = {
        { 'lead', 'A cada rotação do Hunt Board, alguns monstros ganham rate de XP acima de 1x. Esses monstros também viram raros com mais frequência.' },
        { 'h', 'A conta' },
        { 'p', 'Chance do raro = chance normal x (1 + (rate - 1) / 6). Na rate mais alta, 5x, a chance fica 1,67 vez maior. Rate 1x não muda nada.' },
        { 'table', widths = { 80, 90, 70, 70, 80, 100 },
          head = { 'Rate', 'Multiplicador', 'Pale', 'Ashen', 'Obsidian', 'Lord of Death' },
          rows = {
              { '1x', 'x1', '0,63%', '0,44%', '0,31%', '0,031%' },
              { '2x', 'x1,17', '0,73%', '0,51%', '0,36%', '0,036%' },
              { '3x', 'x1,33', '0,83%', '0,58%', '0,42%', '0,042%' },
              { '4x', 'x1,5', '0,94%', '0,66%', '0,47%', '0,047%' },
              { { '5x', '#ffd27a' }, { 'x1,67', '#ffd27a' }, '1,04%', '0,73%', '0,52%', '0,052%' },
          } },
        { 'h', 'Loot' },
        { 'p', 'O loot tem o seu próprio sorteio, separado da XP: de 1x a 3x. Um monstro pode estar com XP alta e loot normal, ou o contrário. Nenhum monstro fica abaixo de 1x: um terço fica em 1x, outro terço perto de 1,5x, e o resto vai ficando mais raro até 3x. Acima de 1x o monstro rola o loot mais vezes; itens únicos nunca saem duas vezes.' },
        { 'h', 'Força' },
        { 'p', 'Acima de 1x o monstro também fica mais forte: vida x (1 + (rate - 1) x 0,35) e dano x (1 + (rate - 1) x 0,15). A 4x ele tem 2,05 vezes a vida e bate 1,45 vez mais forte; a 5x, 2,4 vezes a vida e 1,6 vez o dano. É vida de verdade: o seu dano entra inteiro.' },
        { 'p', 'O Hunt Board (no painel Mythos, à direita) mostra a rate de cada monstro agora. A rotação muda a cada 2 horas.' },
        { 'p', 'A rate também aparece ao lado da barra de vida de cada monstro. A cor avisa o quanto ele está forte: cinza perto de 1x, amarelo perto de 2x, laranja perto de 3,5x e vermelho em 5x. A partir de 4x vem com um ponto de exclamação, como 4.6x!.' },
        { 'links', { 'tiers', 'experience' } },
    },
}

WIKI_PAGES.items = {
    menu = 'Item vira raro',
    title = 'Como um item vira raro',
    blocks = {
        { 'lead', 'Itens raros caem dos monstros raros (Pale, Ashen, Obsidian e Lord of Death) e de baús de quest. Eles têm de 1 a 5 bônus, uma cor própria e uma moldura com a cor do grau.' },
        { 'h', 'De onde vêm' },
        { 'table', widths = { 210, 300 },
          head = { 'Origem', 'Itens raros por morte' },
          rows = {
              { 'Monstro comum', 'Nunca: itens raros só caem de monstros raros' },
              { { 'Pale', '#c9d6e3' }, '0,75 (75% de chance de um)' },
              { { 'Ashen', '#9aa0a8' }, '1,2 (um sempre, 20% de chance de outro)' },
              { { 'Obsidian', '#9b7bff' }, '1,5 (um sempre, 50% de chance de outro)' },
              { { 'Lord of Death', '#e04848' }, '3' },
              { 'Recompensa de quest', '25% de chance' },
          } },
        { 'p', 'O bônus Rarity Find dos anéis e amuletos multiplica esses números. Monstros raros sempre pagam: se não houver equipamento no corpo, um equipamento da lista de loot do próprio monstro é escolhido.' },
        { 'p', 'Qual equipamento vira raro é sorteado entre todos os da lista de loot do monstro, não só entre os que caíram, e os itens que caem muito não dominam o sorteio. Um raro de Dragon é steel shield 14% das vezes (seriam 37% pela chance de drop) e dragon shield 6% (seria 0,6%). Itens muito raros da lista (abaixo de 0,3% de chance) ficam de fora desse sorteio, mas se um deles cair ele pode virar raro.' },
        { 'p', 'Itens com carga ou tempo de uso nunca viram raros: eles se gastam ou viram outro item, e o raro sumiria junto. Ficam de fora o ice rapier, as armas de glooth, as armas shimmer, void boots, tiara of power, firewalker boots, os rainbow shields e parecidos.' },
        { 'h', 'Como o item é sorteado' },
        { 'p', 'Primeiro sai o grau. O grau decide quantos bônus o item tem e em que parte da faixa de cada bônus o valor cai. Depois saem os bônus, sempre do tipo do item: espada rola bônus de corpo a corpo, wand rola magia, bota rola velocidade.' },
        { 'h', 'Cada item tem o seu jeito' },
        { 'p', 'Os bônus de um item dependem uns dos outros. O item sorteia uma força só, dentro da faixa do grau, e essa força é dividida entre os bônus ao acaso. Um bônus que leva uma parte grande deixa menos para os outros: uma espada com Attack muito alto costuma ter os outros bônus mais baixos, e outra espada do mesmo grau pode ter tudo equilibrado. Em média, cada grau continua com a mesma força.' },
        { 'h', 'Menos bônus, bônus mais fortes' },
        { 'p', 'O número de bônus também é sorteado. Um Mythicus pode ter de 1 a 5, e a força do grau é a mesma: com menos bônus, cada um recebe mais. Num Mythicus de 2 bônus, cada bônus fica em média com 86% da faixa; num de 5, com 44%.' },
        { 'p', 'Por isso um item com menos bônus pode passar do máximo da tabela de cada tipo de item, até 1,5 vez a faixa. Um bônus que vai de 1 a 20 (como Fire Resist num item de qualidade 0%) chega a:' },
        { 'table', widths = { 110, 70, 70, 70, 70, 70 }, head = { 'Grau', '1 bônus', '2 bônus', '3 bônus', '4 bônus', '5 bônus' },
          rows = {
              { { 'Rarus', '#4f8fe8' }, '15', '11', '', '', '' },
              { { 'Praeclarus', '#a679e6' }, '21', '21', '14', '', '' },
              { { 'Legendarius', '#e2a443' }, '25', '25', '23', '17', '' },
              { { 'Mythicus', '#e8e4ff' }, '30', '30', '30', '25', '20' },
          } },
        { 'table', widths = { 140, 74, 60, 80, 86, 70 }, head = { 'Quantos bônus', '1', '2', '3', '4', '5' },
          rows = {
              { { 'Communis', '#63c08a' }, '100%', '', '', '', '' },
              { { 'Rarus', '#4f8fe8' }, '45%', '55%', '', '', '' },
              { { 'Praeclarus', '#a679e6' }, '25%', '35%', '40%', '', '' },
              { { 'Legendarius', '#e2a443' }, '15%', '25%', '30%', '30%', '' },
              { { 'Mythicus', '#e8e4ff' }, '10%', '20%', '25%', '25%', '20%' },
          } },
        { 'p', 'Nenhum grau passa do teto que só o grau acima alcança, e nenhum bônus fica abaixo da metade do começo da faixa do grau (num Mythicus, nunca abaixo de 15% da faixa do bônus). Refazer o item na janela Rarity Bonuses sorteia tudo de novo, inclusive quantos bônus ele tem.' },
        { 'table', widths = { 140, 74, 60, 80, 86, 70 }, head = { 'Origem', 'Communis', 'Rarus', 'Praeclarus', 'Legendarius', 'Mythicus' },
          rows = {
              gradeRow('Quest', '#c8c8c8', { 40, 32, 18, 8, 2 }),
          } },
        { 'h', 'Qualquer monstro raro, qualquer grau' },
        { 'p', 'Todo monstro raro pode dar todos os graus, do rat ao demon. O que muda a chance é o tier: um Pale quase nunca dá Legendarius ou Mythicus, um Obsidian dá com frequência e o Lord of Death dá Legendarius ou Mythicus em 40% dos itens.' },
        { 'h', 'Bônus de quem achou' },
        { 'p', 'Quem matou o monstro tem o nome gravado no item ("Found by ..."). Enquanto essa pessoa usa o item, todos os bônus dele ficam 20% mais fortes. Para qualquer outro jogador, o item vale o valor que aparece na descrição.' },
        { 'h', 'Rolagem perfeita' },
        { 'p', 'Um bônus que cai exatamente no máximo da faixa é perfeito. Isso acontece mais ou menos uma vez a cada 100 mil itens, e o servidor inteiro fica sabendo. Mythicus também é anunciado para todos; Legendarius só para quem achou.' },
        { 'links', { 'grades', 'quality', 'pools', 'affixes' } },
    },
}

WIKI_PAGES.grades = {
    menu = 'Graus de raridade',
    title = 'Graus de raridade',
    blocks = {
        { 'lead', 'São cinco graus. Cada um tem uma cor no item e na moldura, um número máximo de bônus e uma faixa de valores. Quanto mais alto o grau, mais bônus o item pode ter e mais fortes eles são. Embaixo de cada grau, um exemplo real de arma sorteada pelo servidor.' },
        { 'grades' },
        { 'p', 'Um item pode ter menos bônus que o máximo do grau: o número também é sorteado, e com menos bônus cada um fica mais forte (a força do item é dividida entre eles).' },
        { 'p', 'A faixa diz de onde os valores saem dentro do mínimo e do máximo de cada bônus. Nos três graus de cima, os valores se concentram perto da parte de baixo da faixa e ficam cada vez mais raros perto do topo. Em um bônus de 1 a 20, metade dos Mythicus fica entre 7 e 10 e só uns 2% passam de 18.' },
        { 'p', 'Cada bônus rola sozinho: um item pode ter um bônus alto e os outros baixos.' },
        { 'links', { 'items', 'quality', 'pools' } },
    },
}

WIKI_PAGES.quality = {
    menu = 'Qualidade do item',
    title = 'Qualidade do item base',
    blocks = {
        { 'lead', 'Um raro feito de um item bom do Tibia é mais forte. Cada item tem uma qualidade de 0% a 100%, e ela aumenta a faixa dos bônus: um Legendarius de falcon plate passa um Mythicus de leather armor.' },
        { 'h', 'Como a qualidade é calculada' },
        { 'p', 'Metade vem do armor, da defesa ou do ataque do item (com o dano de elemento), comparado com os melhores do mesmo tipo: capacetes, armaduras, calças, botas, escudos e armas de uma e de duas mãos, cada um com os seus. 35% vêm do level exigido (level 400 conta tudo) e 15% dos slots de imbuement (dois contam tudo).' },
        { 'p', 'Wands, rods, armas de distância, anéis e amuletos não têm um valor desses no item, então usam o level (85%) e os slots (15%).' },
        { 'h', 'Quanto os bônus crescem' },
        { 'p', 'Dano, cura, leech, resistências, skills, magic level, vida e mana máximas, pierce e regen crescem até 3 vezes: x(1 + 2 x qualidade). Critical Hit Chance, Physical Resist, Hit Chance, o Attack das armas de distância, Speed, Cleave, Splinter, Long Shot, Frenzy, Vital Barrier, Onslaught, Momentum, Amplification, Experience, Loot, Rarity Find, Ally Healing e Physical Reflect crescem até 2 vezes. Attack Speed, Cooldown Reduction e Dodge Chance não mudam.' },
        { 'p', 'Armor, Defense e o Attack das armas corpo a corpo são uma parte do valor do próprio item: Armor de 10% a 80% do armor do item, Defense de 8% a 60% da defesa e Attack de 8% a 50% do ataque com o elemento. Uma leather armor ganha de +1 a +3 de armor; uma falcon plate, de +2 a +14.' },
        { 'table', widths = { 200, 100, 120 }, head = { 'Item', 'Qualidade', 'Bônus até' },
          rows = {
              { 'leather armor', '11%', 'x1,22' }, { 'plate armor', '28%', 'x1,56' },
              { 'magic plate armor', '62%', 'x2,24' }, { 'falcon plate', '95%', 'x2,91' },
              { 'soulshell', '100%', 'x3,00' }, { 'spike sword', '37%', 'x1,74' },
              { 'magic sword', '75%', 'x2,50' }, { 'demon shield', '51%', 'x2,02' },
              { 'wand of vortex', '10%', 'x1,21' }, { 'wand of inferno', '24%', 'x1,49' },
              { 'soulhexer', '100%', 'x3,00' }, { 'ethereal ring', '85%', 'x2,70' },
          } },
        { 'p', 'A descrição do item mostra a qualidade dele, por exemplo Base quality 95% (bonuses up to x2.91).' },
        { 'h', 'Limite de um item' },
        { 'p', 'Um item com todos os bônus do grau não passa de 2/3 do teto de um bônus: Healing Received para em 66%, uma resistência em 33%. Menos bônus continuam deixando os outros mais fortes: o limite sobe junto, e um Mythicus de um bônus só chega ao teto inteiro. Armor, Defense e Attack não passam do valor do próprio item, ou 1,5 vez com menos bônus.' },
        { 'h', 'Itens que você já tinha' },
        { 'p', 'Os raros que já existiam ganharam o multiplicador do item uma vez, no mesmo lugar da faixa, e nenhum bônus diminuiu. Um Armor, Defense ou Attack antigo maior que a nova faixa continua como estava.' },
        { 'p', 'O Finisher saiu: um item que tinha ganhou outro bônus do seu tipo no lugar, no mesmo lugar da faixa.' },
        { 'p', 'O Perfect Shot saiu: um arco ou besta que tinha ganhou Long Shot no lugar, no mesmo lugar da faixa.' },
        { 'p', 'Wand/Rod Damage subiu de 15%-150% para 30%-250%: as wands e rods que já existiam ganharam x5/3 nesse bônus, uma vez.' },
        { 'p', 'Espadas, machados e clavas agora rolam Melee Skills, que sobe sword, axe e club juntas. Um Sword, Axe ou Club antigo virou Melee Skills com o mesmo valor.' },
        { 'p', 'Os bônus de dano (skills, magic level, crítico, dano de magia, bônus de magia de dano, wand/rod, pierce, cleave, perfect shot e splinter) e Max Health e Max Mana ficaram 50% mais fortes, nas faixas e nos tetos. Os itens que já existiam ganharam x1,5 nesses bônus, uma vez. Healing Received, Life Leech, Mana Leech e os bônus de magia de cura ficaram como estavam.' },
        { 'links', { 'pools', 'affixes' } },
    },
}

local function poolTable(rows)
    return { 'table', widths = { 200, 110, 200 }, head = { 'Bônus', 'Faixa', 'Observação' }, rows = rows }
end

WIKI_PAGES.pools = {
    menu = 'O que cada item rola',
    title = 'O que cada item pode rolar',
    blocks = {
        { 'lead', 'Cada tipo de item tem a sua lista de bônus. Um item com 5 bônus nunca repete o mesmo bônus.' },
        { 'note', 'As faixas abaixo são as de um item de qualidade 0%. A qualidade do item base aumenta a maioria delas, até 3 vezes (página Qualidade do item).' },
        { 'h', 'Armas corpo a corpo' },
        poolTable({
            { 'Attack', '8% a 50%', 'do ataque da arma, com o elemento' }, { 'Melee Skills', '2% a 15%', 'sword, axe, club e porrada juntas; armas de punho: Fist Skill' },
            { 'Critical Hit Chance', '1% a 10%', '' }, { 'Critical Hit Damage', '2% a 38%', '' },
            { 'Life Leech', '1% a 12%', '' },
            { 'Attack Speed', '3% a 25%', 'duas mãos: 5% a 35%' }, { 'Cleave Damage', '5% a 23%', 'duas mãos: 8% a 38%' },
            { 'Attack Spell Damage', '5% a 23%', '' }, { 'Bônus de magia', '8% a 53%', 'até dois; knight (fist: monk); cura: 5% a 35%' },
            { 'Onslaught', '1% a 6%', 'golpe fatal, +60% de dano' },
        }),
        { 'h', 'Arcos e armas de distância' },
        poolTable({
            { 'Attack', '1 a 20', '' }, { 'Distance Skill', '2% a 15%', '' }, { 'Hit Chance', '1% a 15%', '' },
            { 'Critical Hit Chance', '1% a 10%', '' }, { 'Critical Hit Damage', '2% a 38%', '' },
            { 'Attack Speed', '3% a 25%', 'duas mãos: 5% a 35%' }, { 'Long Shot Damage', '4% a 20%', 'em monstros a 3 sqm ou mais' },
            { 'Splinter Chance', '5% a 23%', 'duas mãos: 8% a 18%' },
            { 'Attack Spell Damage', '5% a 23%', '' }, { 'Bônus de magia', '8% a 53%', 'até dois; paladin' },
            { 'Life Leech', '1% a 12%', '' }, { 'Mana Leech', '2% a 20%', '' },
            { 'Onslaught', '1% a 6%', 'golpe fatal, +60% de dano' },
        }),
        { 'h', 'Wands e rods' },
        poolTable({
            { 'Magic Level', '2% a 15%', '' }, { 'Mana Leech', '2% a 20%', '' }, { 'Critical Hit Chance', '2% a 15%', '' },
            { 'Critical Hit Damage', '8% a 60%', '' }, { 'Wand/Rod Damage', '30% a 250%', '' }, { 'Max Mana', '3% a 23%', '' },
            { 'Splinter Chance', '5% a 23%', '' }, { 'Cooldown Reduction', '2% a 14%', '' }, { 'Attack Speed', '3% a 25%', '' },
            { 'Resist Pierce', '8% a 45%', 'elemento da própria arma' }, { 'Ally Healing', '5% a 30%', 'só rods de druid' },
            { 'Attack Spell Damage', '5% a 23%', '' }, { 'Bônus de magia', '8% a 53%', 'até dois; wand: sorcerer, rod: druid; cura: 5% a 35%' },
            { 'Onslaught', '1% a 6%', 'golpe fatal, +60% de dano' },
        }),
        { 'h', 'Escudos' },
        poolTable({
            { 'Defense', '8% a 60%', 'da defesa do escudo' }, { 'Resistência', '1% a 20%', 'um elemento' }, { 'Healing Received', '5% a 30%', '' },
            { 'Max Health', '2% a 15%', '' }, { 'Physical Reflect', '1% a 15%', '' },
            { 'Vital Barrier', '2% a 10%', 'da vida máxima' },
        }),
        { 'h', 'Spellbooks' },
        poolTable({
            { 'Magic Level', '2% a 15%', '' }, { 'Max Mana', '3% a 23%', '' }, { 'Defense', '8% a 60%', 'da defesa do livro' },
            { 'Resistência', '1% a 20%', '' }, { 'Ally Healing', '5% a 30%', '' }, { 'Cooldown Reduction', '2% a 14%', '' },
            { 'Resist Pierce', '8% a 45%', 'elemento sorteado' }, { 'Attack Spell Damage', '5% a 23%', '' },
            { 'Bônus de magia', '8% a 53%', 'um; da vocação do livro; cura: 5% a 35%' },
            { 'Vital Barrier', '2% a 10%', 'da vida máxima' },
        }),
        { 'h', 'Capacetes, armaduras e calças' },
        poolTable({
            { 'Armor', '10% a 80%', 'do armor do item' }, { 'Resistência', '1% a 20%', 'pode vir duas' }, { 'Healing Received', '5% a 30%', '' },
            { 'Skill da vocação', '2% a 15%', 'ML, melee, distance ou fist' },
            { 'Dodge Chance', '1% a 6%', '' }, { 'Physical Reflect', '1% a 15%', '' }, { 'Cooldown Reduction', '2% a 14%', '' },
            { 'Speed', '5 a 50', 'só calças' }, { 'Vital Barrier', '1% a 6%', 'da vida máxima' },
            { 'Life Leech', '1% a 6%', 'só capacete e armadura' }, { 'Mana Leech', '1% a 10%', 'só capacete e armadura' },
            { 'Momentum', '2% a 16%', 'só capacete' }, { 'Transcendence', '1% a 2%', 'só calça' },
        }),
        { 'h', 'Botas' },
        poolTable({
            { 'Armor', '10% a 80%', 'do armor da bota' }, { 'Speed', '5 a 50', '' }, { 'Resistência', '1% a 20%', '' },
            { 'Healing Received', '5% a 30%', '' }, { 'Max Health', '2% a 15%', '' }, { 'Dodge Chance', '1% a 6%', '' },
            { 'Amplification', '5% a 35%', '' },
        }),
        { 'h', 'Anéis e amuletos' },
        { 'p', 'Só os que não têm carga nem tempo de uso.' },
        poolTable({
            { 'Max Health', '2% a 12%', '' }, { 'Max Mana', '3% a 18%', '' }, { 'Resistência', '1% a 12%', '' },
            { 'Experience', '2% a 10%', '' }, { 'Loot Chance', '2% a 15%', '' }, { 'Rarity Find Chance', '2% a 15%', '' },
            { 'Health per Regen Tick', '30 a 150', '' }, { 'Mana per Regen Tick', '30 a 150', '' },
            { 'Frenzy', '1% a 3%', 'por monstro morto, até 5' },
        }),
        { 'p', 'Physical Resist vai só até 10% na faixa base: é a resistência mais forte.' },
        { 'links', { 'quality', 'affixes', 'stacking' } },
    },
}

local function affixTable(rows)
    return { 'table', widths = { 120, 330, 60 }, head = { 'Bônus', 'O que faz', 'Teto' }, rows = rows }
end

WIKI_PAGES.affixes = {
    menu = 'Lista de bônus',
    title = 'Lista de bônus',
    blocks = {
        { 'lead', 'Todos os bônus que um item raro pode ter. O teto é o máximo que todos os seus itens juntos podem dar, já contando o bônus de quem achou. Na janela Rarity Bonuses e na roleta, o (i) ao lado de um bônus explica o que ele faz.' },
        { 'h', 'Ataque' },
        affixTable({
            { 'Attack', 'Ataque a mais na arma. Nas armas corpo a corpo é uma parte do ataque da própria arma.', '' },
            { 'Melee Skills', 'Porcentagem a mais em sword, axe, club e porrada (fist) ao mesmo tempo. Vem de espadas, machados, clavas e armaduras de knight.', '75%' },
            { 'Fist Skill', 'Porcentagem a mais em fist fighting. Vem das armas de punho e das armaduras de monk.', '75%' },
            { 'Distance Skill', 'Porcentagem a mais em distance.', '75%' },
            { 'Hit Chance', 'Chance de acerto a mais na arma de distância.', '' },
            { 'Critical Hit Chance', 'Chance de golpe crítico.', '50%' },
            { 'Critical Hit Damage', 'Dano a mais no golpe crítico.', '100%' },
            { 'Life Leech', 'Parte do dano volta como vida.', '35%' },
            { 'Mana Leech', 'Parte do dano volta como mana.', '40%' },
            { 'Attack Speed', 'Ataca mais rápido. Só vem da arma: até 50% numa arma de duas mãos Mythicus com poucos bônus.', '50%' },
            { 'Cleave Damage', 'Golpes corpo a corpo e magias corpo a corpo de alvo único (exori ico, exori gran ico, exori hur e os golpes de alvo único do monk) acertam os dois sqm ao lado do alvo com essa parte do dano.', '45%' },
            { 'Long Shot Damage', 'Dano a mais nos ataques e magias em monstros a 3 sqm ou mais de você. Vem de arcos e bestas.', '30%' },
            { 'Splinter Chance', 'Chance de o ataque básico de arma de distância, wand ou rod estilhaçar: o mesmo dano acerta todos os monstros nos 8 sqm em volta do alvo. Vale também com diamond, burst e poison arrow e viper star (no monstro atacado).', '38%' },
            { 'Wand/Rod Damage', 'Dano a mais no ataque de wand e rod. No máximo quadruplica o dano.', '300%' },
            { 'Resist Pierce', 'Tira pontos da resistência do monstro a um elemento, nunca abaixo de 0.', '90%' },
        }),
        { 'h', 'Magia' },
        affixTable({
            { 'Magic Level', 'Porcentagem do seu ML base. ML 100 com +5% vira 105.', '75%' },
            { 'Max Mana', 'Mana máxima a mais.', '52%' },
            { 'Cooldown Reduction', 'Cooldowns das magias mais curtos, e a espera entre duas magias de ataque ou de cura encurta metade disso (20% deixa os 2 s em 1,8 s). Vem de wands, rods, spellbooks, capacetes, armaduras e calças.', '20%' },
            { 'Ally Healing', 'Cura a mais em outro jogador (exura sio, mass healing). Não vale em você.', '40%' },
            { 'Attack Spell Damage', 'Dano a mais em todas as magias de ataque (as faladas, não runas). Vem das armas e dos spellbooks.', '60%' },
            { 'Bônus de magia', 'Dano a mais em uma magia ou runa, ou cura a mais se for magia de cura (teto 100%). Soma com Attack Spell Damage.', '150%' },
        }),
        { 'h', 'Bônus de magia por vocação' },
        { 'p', 'Cada arma só rola magias da vocação que usa ela. No item aparece com as palavras da magia, por exemplo +18% Exori Gran Damage ou +20% Exura Vita Healing. Espadas, machados e clavas rolam magias de knight, armas de punho de monk, arcos e bestas de paladin, wands de sorcerer, rods de druid, e spellbooks da vocação do livro.' },
        { 'table', widths = { 80, 430 }, head = { 'Vocação', 'Magias' },
          rows = {
              { 'Knight', 'exori, exori gran, exori ico, exori gran ico' },
              { 'Paladin', 'exevo mas san, exori gran con' },
              { 'Sorcerer', 'exevo gran mas flam, exevo gran mas vis, exevo vis hur, exevo gran flam hur; só wands: runas sudden death, great fireball e thunderstorm' },
              { 'Druid', 'exevo gran mas tera, exevo gran mas frigo, exevo gran frigo hur, exura gran mas res, exura vita e exura sio (cura); só rods: runas sudden death, avalanche e stone shower' },
              { 'Monk', 'exori gran mas pug, exori mas pug, exori gran pug, exori gran nia, exori mas nia, exori pug, exori med pug, exori nia, exori amp pug, exura gran tio e exura mas nia (cura)' },
          } },
        { 'h', 'Defesa' },
        affixTable({
            { 'Armor, Defense', 'Armor ou defesa a mais no item, uma parte do valor do próprio item.', '' },
            { 'Max Health', 'Vida máxima a mais.', '75%' },
            { 'Resistência', 'Menos dano de fire, earth, energy, ice, holy ou death.', '50%' },
            { 'Physical Resist', 'Menos dano físico. A mais forte e a mais rara.', '20%' },
            { 'Healing Received', 'Magias, runas e poções curam mais. Leech não conta.', '100%' },
            { 'Dodge Chance', 'Chance de desviar de um golpe.', '12%' },
            { 'Physical Reflect', 'Devolve parte do dano físico que um monstro causa em você.', '15%' },
            { 'Speed', 'Velocidade a mais. Vem de botas e calças.', '80' },
            { 'Vital Barrier', 'A cura que passa da vida cheia (magias, runas e poções, não leech) vira uma barreira que segura os próximos golpes, até essa parte da vida máxima, por 6 s. Vem de escudos, spellbooks, capacetes, armaduras e calças.', '20%' },
        }),
        { 'h', 'Anéis e amuletos' },
        affixTable({
            { 'Experience', 'XP a mais por monstro.', '15%' },
            { 'Loot Chance', 'Multiplica a chance de cada item do loot do monstro.', '20%' },
            { 'Rarity Find Chance', 'Multiplica a chance de um item virar raro.', '20%' },
            { 'Health per Regen Tick', 'Vida a mais em cada tick de regeneração.', '300' },
            { 'Mana per Regen Tick', 'Mana a mais em cada tick de regeneração.', '300' },
            { 'Frenzy', 'Cada monstro que você mata dá esse dano a mais por 8 s, até 5 vezes; matar de novo renova. Bom em hunt de muitos monstros, fraco em boss. Antes se chamava Momentum.', '5% (x5)' },
        }),
        { 'h', 'Bônus da Exaltation Forge' },
        { 'p', 'Os mesmos efeitos que a forja dá pelo tier do item. Um item raro não entra na forja, então em cada slot vale o tier ou o raro; os dois somam se vierem de slots diferentes (arma forjada e bota rara, por exemplo). A Ruse da forja é o Dodge Chance das armaduras.' },
        affixTable({
            { 'Onslaught', 'Chance de um golpe ou magia de ataque ser Fatal: 60% de dano a mais. Vem de armas, wands e rods (forja tier 10: 9%).', '9%' },
            { 'Momentum', 'Em combate, a cada 2 s, chance de tirar 2 s de todos os cooldowns. Vem de capacetes (forja tier 10: 24%).', '24%' },
            { 'Transcendence', 'Em combate, a cada 2 s, chance de virar o avatar da vocação por 7 s: 15% menos dano recebido e todo golpe crítico. Vem de calças (forja tier 10: 2,35%).', '3%' },
            { 'Amplification', 'Deixa Onslaught, Momentum e Transcendence (da forja ou de raros) e a Ruse da forja mais prováveis nessa porcentagem. Vem de botas (forja tier 10: 57%).', '50%' },
        }),
        { 'h', 'Resistências e a cor da gema' },
        { 'table', widths = { 120, 120 }, head = { 'Elemento', 'Nome no item' },
          rows = {
              { 'Fire', { 'Igneus', '#ff6a3d' } }, { 'Earth', { 'Terrenus', '#8bc34a' } },
              { 'Energy', { 'Fulmineus', '#b388ff' } }, { 'Ice', { 'Glacialis', '#4dd0e1' } },
              { 'Holy', { 'Sacer', '#ffe082' } }, { 'Death', { 'Mortifer', '#b07ad8' } },
              { 'Physical', { 'Corporalis', '#b0bec5' } },
          } },
        { 'h', 'Rarity XP: refazer o item' },
        { 'p', 'Matar um monstro Pale, Ashen, Obsidian ou Lord of Death dá Rarity XP para quem tem o loot: a experiência do monstro dividida por 100, vezes 1 (Pale), 2 (Ashen), 4 (Obsidian) ou 10 (Lord of Death). Um Pale Dragon dá 7, um Obsidian Dragon dá 28.' },
        { 'p', 'Também dá para comprar Rarity XP na loja de Hunt Tasks: 50 por 30 pontos ou 500 por 300.' },
        { 'p', 'Na janela Rarity Bonuses, cada item raro que você está usando tem o botão Refazer. Ele sorteia o item inteiro de novo, no mesmo grau: quantos bônus, quais bônus e os valores. O item, o grau e o nome de quem achou continuam. Os bônus antigos são perdidos e os novos podem sair melhores ou piores; não tem volta.' },
        { 'p', 'A roleta gira um espaço de bônus de cada vez. Um bônus aparece com o valor que teria se todos os espaços seguintes também tivessem bônus; cada espaço que cai em sem bônus deixa os bônus de cima mais fortes, até o valor real do item.' },
        { 'table', widths = { 160, 120 }, head = { 'Grau do item', 'Refazer' },
          rows = {
              { 'Communis', '20' }, { 'Rarus', '50' }, { 'Praeclarus', '125' },
              { 'Legendarius', '300' }, { 'Mythicus', '700' },
          } },
        { 'p', 'O preço também sobe com o level exigido do item: um item de level 400 custa o dobro, um de level 200 custa 1,5 vez, e um item sem level exigido custa o preço da tabela. Refazer um Mythicus de level 400 custa 1400.' },
        { 'p', 'A Store também vende Rarity XP na categoria Rarity: 500 por 250 coins, 1500 por 700 e 5000 por 2200.' },
        { 'h', 'Vender itens raros' },
        { 'p', 'Nenhum NPC compra item raro na janela de troca, nem no vender tudo, então um raro nunca é vendido sem querer. Para vender, fale hi e depois raros (ou rare) ao Gersao, no templo de Ventera.' },
        { 'p', 'Abre uma janela com os itens raros das suas mochilas que o Gersao compra, com os bônus de cada um e o preço: o que o Gersao paga pelo item comum, mais 300 gold, vezes o grau (Communis x1, Rarus x2, Praeclarus x3, Legendarius x4, Mythicus x5). Uma espada que ele compra por 100 sai por 400 Communis e 2.000 Mythicus. Marque um por um ou use os botões de grau (por exemplo, Communis marca todos os Communis), confira o total e clique em Vender marcados. O ouro vai para o banco.' },
        { 'p', 'Itens equipados não aparecem: tire o item do corpo antes. Se no meio da venda tiver um Legendarius, um Mythicus ou um item com rolagem perfeita, a confirmação avisa.' },
        { 'links', { 'stacking', 'pools' } },
    },
}

WIKI_PAGES.stacking = {
    menu = 'Como os bônus somam',
    title = 'Como os bônus somam',
    blocks = {
        { 'lead', 'Bônus em porcentagem de vários itens não se somam direto. Eles se combinam como a esquiva do Dota: cada item age sobre o que sobrou dos outros.' },
        { 'h', 'A conta' },
        { 'p', 'Total = 1 - (1 - a) x (1 - b) x (1 - c) ...' },
        { 'table', widths = { 220, 120, 120 }, head = { 'Itens', 'Soma direta', 'Total real' },
          rows = {
              { 'Dodge 4% + 4% + 4%', '12%', '11,5%' },
              { 'Fire Resist 20% + 20%', '40%', '36%' },
              { 'Critical Hit Chance 10% + 10%', '20%', '19%' },
              { 'Experience 8% + 8%', '16%', '15% (teto)' },
          } },
        { 'p', 'Bônus fixos, como Attack, Armor, Speed e Regen, somam direto. Depois de combinar, o total para no teto do bônus.' },
        { 'h', 'Com imbuements e a forja' },
        { 'p', 'Os bônus de raridade somam com os imbuements, e com a Exaltation Forge. Crit e leech da raridade se juntam aos do Strike e do Vampirism/Void.' },
        { 'note', 'A chance de crítico total pode chegar a 60%: os 10% do Strike mais até 50% da raridade.' },
        { 'h', 'Bônus de quem achou' },
        { 'p', 'Os 20% a mais do item que você mesmo achou entram antes do teto. Um item seu não passa do teto por causa disso.' },
        { 'links', { 'affixes', 'experience' } },
    },
}

WIKI_PAGES.experience = {
    menu = 'Experiência',
    title = 'Bônus de experiência',
    blocks = {
        { 'lead', 'Todos os bônus de XP multiplicam um ao outro. Nenhum deles anula outro.' },
        { 'table', widths = { 200, 160, 150 }, head = { 'Fonte', 'Bônus', 'Como entra' },
          rows = {
              { 'Monstro raro', 'x1,5 a x2,5', 'multiplica' },
              { 'Boosted creature', 'x2', 'multiplica, vale para a versão rara' },
              { 'Prey de XP', 'o valor do slot', 'multiplica' },
              { 'Anel ou amuleto raro', 'até +15%', 'multiplica' },
              { 'XP Boost e level baixo', 'o valor de cada', 'somam entre si' },
              { 'Stamina', 'a da sua stamina', 'multiplica' },
              { 'Rate do servidor', 'a do seu level', 'multiplica' },
              { 'Hunt Board', 'a rate do monstro', 'multiplica' },
          } },
        { 'h', 'Exemplo' },
        { 'p', 'Um Ashen Dragon (700 de XP base) que é o boosted creature do dia, com um anel de +10% e o Dragon a 2x no Hunt Board:' },
        { 'p', '700 x 1,9 x 2 x 1,1 x 2 = 5.852, e depois a stamina e a rate do servidor.' },
        { 'p', 'Monstros invocados por outros monstros não recebem a rate do Hunt Board.' },
        { 'links', { 'huntboard', 'stacking' } },
    },
}

-- ---------------------------------------------------------------- auto loot

WIKI_PAGES.autoloot = {
    menu = 'Auto Loot',
    title = 'Auto Loot',
    blocks = {
        { 'lead', 'O auto loot está ligado para todo mundo. Quando um monstro morre, o servidor pega o loot e coloca na sua bag sozinho, sem você clicar no corpo.' },
        { 'h', 'Quando o loot vai direto para a bag' },
        { 'p', 'Tudo isto precisa valer ao mesmo tempo:' },
        { 'table', widths = { 230, 290 }, head = { 'Regra', 'Se não valer' },
          rows = {
              { 'Você deu mais dano no monstro', 'Só quem deu mais dano recebe o auto loot. Se um summon seu deu a maior parte do dano, ninguém recebe' },
              { 'Dá para andar até o corpo', 'Corpo atrás de parede, num buraco ou em outro andar fica inteiro no chão' },
              { 'O item está com Pegar marcado', 'O item fica no corpo' },
              { 'Você aguenta o peso', 'O item fica no corpo, com o aviso de que está pesado demais' },
              { 'A bag de destino tem espaço', 'O item fica no corpo, com o aviso de que a bag está cheia' },
              { 'Não é um boss de reward chest', 'O loot do boss vai para o reward chest, como sempre' },
          } },
        { 'p', 'Os itens raros que caem dentro da caixa de raridade saem da caixa e vão para a bag como qualquer outro item.' },
        { 'h', 'Para qual bag vai' },
        { 'table', widths = { 40, 480 }, head = { '', 'O servidor tenta nesta ordem' },
          rows = {
              { '1', 'A loot pouch, se você tiver uma' },
              { '2', 'A bag que você escolheu para a categoria do item na janela Auto Loot (armas, poções, ouro...). Uma categoria com bag própria ganha da loot pouch' },
              { '3', 'A bag padrão (Unassigned Loot)' },
              { '4', 'A backpack principal, se "Usar a backpack principal se faltar bag" estiver marcado' },
          } },
        { 'p', 'Se nenhuma dessas existir, o item fica no corpo. Bags e backpacks que caem no loot não entram na loot pouch: vão para a bag da categoria ou para a backpack principal. Itens da Store vão para a Store Inbox.' },
        { 'h', 'Quando precisa clicar no corpo' },
        { 'p', 'Clique com o botão direito no corpo e escolha "Pegar loot do corpo". O servidor anda até o corpo e pega de novo tudo que está com Pegar marcado. Use depois de liberar espaço ou peso, ou quando o corpo estava longe ou atrás de alguma coisa.' },
        { 'p', '"Pegar loot do corpo" segue a mesma lista, então um item desmarcado continua no corpo. Para levar um item desmarcado, escolha "Abrir" e arraste o item para a sua bag.' },
        { 'h', 'Escolher o que pegar' },
        { 'p', 'Abra o painel Mythos e clique em Auto Loot. Com a busca vazia aparecem os seus drops recentes, cada um com a caixa Pegar. Para um item que ainda não caiu, digite o nome na busca.' },
        { 'p', 'Pegar marcado: o auto loot leva o item. Desmarcado: o item fica no corpo. A lista vale para o personagem e fica salva entre logins.' },
        { 'h', 'Pegar pelo preço do Gersao' },
        { 'p', 'Já vem ligado em 500: um personagem novo pega as moedas e todo item que o Gersao compra por 500 gold ou mais. Para mudar, digite outro valor em "Pegar se o Gersao paga >=", ou desmarque para escolher item por item. Cada item da lista mostra quanto o Gersao paga.' },
        { 'p', 'Moedas e itens raros (de Communis a Mythicus) são sempre pegos, mesmo abaixo do valor. Uma caixa Pegar que você muda na mão vale mais que o preço: dá para levar um item barato ou deixar um caro. Com a regra ligada, as listas Skipped e Accepted ficam paradas, e o botão de limpar apaga só essas exceções.' },
        { 'p', 'Do lado esquerdo da janela você escolhe a bag de cada categoria. Desmarque "Usar a backpack principal se faltar bag" se não quiser loot caindo solto na backpack principal.' },
    },
}

-- ---------------------------------------------------------------- hunts and travel

WIKI_PAGES.hunts = {
    menu = 'Hunts por nível',
    title = 'Hunts por nível',
    blocks = {
        { 'lead', 'Todas as hunts que o Hunts TP do Hunt Board alcança, do nível mais baixo ao mais alto. O nível é o recomendado pelas Hunt Tasks para o monstro; "Perto de" é a cidade mais perto da hunt.' },
        { 'p', '"Perto do meu level" mostra só as hunts de 55% a 110% do seu level, a mesma faixa que a tarefa diária usa. Clique num monstro para ver a página dele.' },
        { 'huntlist' },
        { 'links', { 'travel', 'huntboard' } },
    },
}

WIKI_PAGES.travel = {
    menu = 'Como se locomover',
    title = 'Como se locomover',
    blocks = {
        { 'lead', 'Ventera é a cidade principal. Do templo dá para ir a qualquer hunt, cidade ou evento sem andar muito.' },
        { 'h', 'No templo de Ventera' },
        { 'table', widths = { 150, 396 }, rows = {
            { { 'Teleportes', '#ffd27a' }, 'Leva ao prédio de teleports: a sala das hunts, o salão das Novas Hunts, a sala dos Iniciantes, os Eventos e, um andar abaixo, a sala das cidades.' },
            { { 'Trainers', '#ffd27a' }, 'Leva à sala de treino, para treinar skills com armas de exercício.' },
            { { 'Promotion', '#ffd27a' }, 'No andar de cima: o NPC Eremo vende a promoção da vocação.' },
            { { 'Bank System', '#ffd27a' }, 'O banco (NPC Rokyn).' },
            { { 'Vender Loot', '#ffd27a' }, 'O Gersao compra todo o loot pelo melhor preço.' },
        } },
        { 'h', 'Hunts TP' },
        { 'p', 'Na janela do Hunt Board, o Hunts TP leva direto até a hunt de qualquer monstro que tem teleport de hunt, sem passar pelas salas. É de graça, tem 30 segundos de espera entre um teleport e outro e só funciona fora de luta: numa área protegida ou sem o sinal de batalha, nunca com PZ. A janela de Hunt Tasks usa o mesmo teleport para a tarefa diária e para a Trilha do Caçador.' },
        { 'h', 'Cidades' },
        { 'p', 'A sala das cidades, no prédio de teleports, tem teleports para Melrose, Cidade Real, Carlin, Basco, Namrah, Paw Port, Storvik, Torvena, Astier e Pinegarden, além do Castle. Nas cidades, o teleport "Voltar" leva de volta para Ventera.' },
        { 'links', { 'hunts', 'npcs' } },
    },
}
