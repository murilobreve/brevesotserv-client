-- Mythicum Wiki content. The numbers come from the server's rarity config
-- (data-otservbr-global/scripts/rarity/00_config.lua) and the engine's forge
-- stack formulas; keep them in sync when that file is rebalanced.
--
-- A page is a list of blocks; wiki.lua turns each block type into widgets:
--   lead, p, h      text (lead is the larger intro paragraph)
--   note            framed text for a rule that is easy to miss
--   tierstrip       the four monster tiers side by side, same monster
--   tier            one tier: live preview with its shader and aura + stats
--   grades          the five item grades with a tinted item each
--   table           head + rows; a cell can be { text, color }
--   links           buttons to other pages

WIKI_GRADES = {
    { key = 'uncommon', name = 'Communis', color = '#3ddc2e', frame = 1, item = 3264, shader = 'Rarity - Uncommon', bonuses = 1, band = '0% a 35%' },
    { key = 'rare', name = 'Rarus', color = '#3d9bff', frame = 2, item = 3369, shader = 'Rarity - Rare', bonuses = 2, band = '10% a 50%' },
    { key = 'epic', name = 'Praeclarus', color = '#b45cff', frame = 3, item = 3079, shader = 'Rarity - Epic', bonuses = 3, band = '15% a 70%' },
    { key = 'legendary', name = 'Legendarius', color = '#ff9a1f', frame = 4, item = 3409, shader = 'Rarity - Legendary', bonuses = 4, band = '20% a 85%' },
    { key = 'mythic', name = 'Mythicus', color = '#66f0ff', frame = 5, item = 3366, shader = 'Rarity - Mythic', bonuses = 5, band = '30% a 100%' },
}

-- stack: forge stack the tier gives the monster. The engine turns it into
-- HP x(1 + (15*stack + 35)/100), attack x(1.35 + (stack-1)*0.1),
-- defense x(1 + stack/10) and experience x(stack + 10)/10.
WIKI_TIERS = {
    pale = {
        name = 'Pale', color = '#c9d6e3', shader = 'Rarity - Pale', outfit = 34, monster = 'Dragon',
        chance = '2%', hp = 'x2,10', attack = 'x1,75', defense = 'x1,5', xp = 'x1,5',
        loot = 'x3', rolls = '+1', affix = '50%', skull = 'Branca',
        grades = { 60, 29, 9, 1.8, 0.2 },
        arrival = '"You sense something pale stirring..." e um brilho azul no corpo.',
    },
    ashen = {
        name = 'Ashen', color = '#9aa0a8', shader = 'Rarity - Ashen', outfit = 55, monster = 'Behemoth',
        chance = '1%', hp = 'x2,70', attack = 'x2,15', defense = 'x1,9', xp = 'x1,9',
        loot = 'x6', rolls = '+1', affix = '80%', skull = 'Vermelha',
        grades = { 45, 33, 15, 6, 1 },
        arrival = 'Fogo no chão, fumaça em volta e "*the ground scorches*".',
    },
    obsidian = {
        name = 'Obsidian', color = '#9b7bff', shader = 'Rarity - Obsidian', outfit = 121, monster = 'Hydra',
        chance = '0,5%', hp = 'x3,45', attack = 'x2,65', defense = 'x2,4', xp = 'x2,4',
        loot = 'x12', rolls = '+2', affix = '100%', skull = 'Preta',
        grades = { 27, 30, 25, 12, 6 },
        arrival = 'Explosões, anéis de morte e "IT HAS ARRIVED!".',
    },
    deathlord = {
        name = 'Lord of Death', color = '#e04848', shader = 'Rarity - Lord of Death', outfit = 25, monster = 'Minotaur',
        effect = 20,
        chance = '0,05%', hp = 'x3,60', attack = 'x2,75', defense = 'x2,5', xp = 'x2,5',
        loot = 'x20', rolls = '+3', affix = '100%', skull = 'Preta',
        grades = { 0, 0, 50, 32, 18 },
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

WIKI_GROUPS = {
    { title = 'Monstros raros', pages = { 'tiers', 'pale', 'ashen', 'obsidian', 'deathlord', 'huntboard' } },
    { title = 'Itens raros', pages = { 'items', 'grades', 'pools' } },
    { title = 'Bônus', pages = { 'affixes', 'stacking', 'experience' } },
    { title = 'Teleports', pages = { 'tp' } },
}

WIKI_PAGES = {}

WIKI_PAGES.tiers = {
    menu = 'Como funciona',
    title = 'Monstros raros',
    blocks = {
        { 'lead', 'Qualquer monstro comum que você mata pode voltar dos mortos mais forte. O corpo treme, cinco avisos tocam no lugar e, 7 segundos depois, ele se levanta com um prefixo no nome, uma cor própria e um loot muito melhor.' },
        { 'tierstrip' },
        { 'h', 'As quatro camadas' },
        { 'table', widths = { 110, 70, 60, 60, 60, 80 },
          head = { 'Tier', 'Chance', 'Vida', 'Ataque', 'XP', 'Loot' },
          rows = {
              { { 'Pale', '#c9d6e3' }, '2%', 'x2,10', 'x1,75', 'x1,5', 'x3' },
              { { 'Ashen', '#9aa0a8' }, '0,7%', 'x2,70', 'x2,15', 'x1,9', 'x6' },
              { { 'Obsidian', '#9b7bff' }, '0,5%', 'x3,45', 'x2,65', 'x2,4', 'x12' },
              { { 'Lord of Death', '#e04848' }, '0,05%', 'x3,60', 'x2,75', 'x2,5', 'x20' },
          } },
        { 'p', 'A chance é por morte de monstro. O sorteio começa pela camada mais alta, então um mesmo monstro nunca vira duas coisas ao mesmo tempo. Loot multiplica a chance de cada item da lista do próprio monstro; itens muito raros (abaixo de 0,3% de chance) não são multiplicados.' },
        { 'p', 'O monstro que volta com tier não pertence a nenhum spawn: se ficar 5 minutos sem nenhum jogador a até 10 sqm, ele some.' },
        { 'h', 'Regras' },
        { 'p', 'Um monstro raro que morre pode voltar de novo, com metade da chance. Bosses, summons e monstros de treino nunca voltam.' },
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
    { 'p', 'A camada mais comum: 2% das mortes. Tem o dobro da vida e o triplo de loot. Metade das vezes, um item que cair no corpo vira item raro.' },
    { 'p', 'Ele tem caveira branca e uma cor fria, quase sem saturação.' },
    { 'links', { 'tiers', 'ashen' } },
})

WIKI_PAGES.ashen = tierPage('ashen', 'Ashen', {
    { 'p', 'Cinza de cinzas, com tons doentes de verde e violeta. Aparece em 1% das mortes, com caveira vermelha e fumaça em volta.' },
    { 'p', 'O loot é 6 vezes maior e 80% das vezes um item do corpo vira raro.' },
    { 'links', { 'pale', 'obsidian' } },
})

WIKI_PAGES.obsidian = tierPage('obsidian', 'Obsidian', {
    { 'p', 'Roxo e azul, com caveira preta. Aparece em 0,5% das mortes (1 em 200).' },
    { 'p', 'Todo item que ele dá é raro, e o corpo tem 2 rolagens extras de loot. Um quarto dos itens já sai Praeclarus ou melhor.' },
    { 'links', { 'ashen', 'deathlord' } },
})

WIKI_PAGES.deathlord = tierPage('deathlord', 'Lord of Death', {
    { 'p', 'O monstro mais raro do jogo: 1 em 2000 mortes, um décimo da chance do Obsidian. Fica todo preto, com o pentagrama preto embaixo dele.' },
    { 'h', 'Quando ele chega' },
    { 'p', 'Todo outro monstro a até 6 sqm, no mesmo andar, morre na hora. Eles não dão loot nem XP e voltam pelo respawn normal. Bosses e summons de jogadores não morrem.' },
    { 'h', 'Se ele matar você' },
    { 'note', 'Em 70% das mortes, nem bless nem amulet of loss protegem. Você perde o backpack e todo container que estiver usando, e cada outro item equipado tem 30% de chance de cair no corpo.' },
    { 'p', 'Vale quando ele dá o último golpe ou quando foi quem mais causou dano. Nos outros 30% das vezes a morte segue a regra normal de bless e AOL.' },
    { 'h', 'O prêmio' },
    { 'p', 'O item nunca sai abaixo de Praeclarus, nem de monstro fraco. Se o monstro não tiver equipamento na lista de loot dele (um rato, por exemplo), o corpo recebe um equipamento comum sorteado, já raro.' },
    { 'links', { 'obsidian', 'grades' } },
})

WIKI_PAGES.huntboard = {
    menu = 'Hunt Board e raros',
    title = 'Hunt Board e monstros raros',
    blocks = {
        { 'lead', 'A cada rotação do Hunt Board, alguns monstros ganham rate de XP acima de 1x. Esses monstros também viram raros com mais frequência.' },
        { 'h', 'A conta' },
        { 'p', 'Chance do raro = chance normal x (1 + (rate - 1) / 6), até no máximo 2,5 vezes. Rate 1x ou menor não muda nada.' },
        { 'table', widths = { 80, 90, 70, 70, 80, 100 },
          head = { 'Rate', 'Multiplicador', 'Pale', 'Ashen', 'Obsidian', 'Lord of Death' },
          rows = {
              { '1x', 'x1', '2%', '0,7%', '0,5%', '0,05%' },
              { '2,5x', 'x1,25', '2,5%', '0,9%', '0,6%', '0,06%' },
              { '4x', 'x1,5', '3%', '1%', '0,75%', '0,075%' },
              { { '7x', '#ffd27a' }, { 'x2', '#ffd27a' }, '4%', '1,4%', '1%', '0,1%' },
              { '10x ou mais', 'x2,5', '5%', '1,75%', '1,25%', '0,125%' },
          } },
        { 'h', 'Loot' },
        { 'p', 'O loot segue a mesma conta: loot = 1 + (rate de XP - 1) / 3. Um monstro a 10x dá 4x de loot, a 4x dá 2x, e a 0,5x dá 0,8x. Acima de 1x o monstro rola o loot mais vezes; itens únicos nunca saem duas vezes.' },
        { 'p', 'O Hunt Board (no painel Mythicum, à direita) mostra a rate de cada monstro agora. A rotação muda a cada 2 horas.' },
        { 'links', { 'tiers', 'experience' } },
    },
}

WIKI_PAGES.items = {
    menu = 'Como um item vira raro',
    title = 'Como um item vira raro',
    blocks = {
        { 'lead', 'Itens raros caem de monstros e de baús de quest. Eles têm de 1 a 5 bônus, uma cor própria e uma moldura com a cor do grau.' },
        { 'h', 'De onde vêm' },
        { 'table', widths = { 210, 300 },
          head = { 'Origem', 'Chance de um equipamento virar raro' },
          rows = {
              { 'Monstro comum', '9% por morte, para um equipamento do corpo' },
              { { 'Pale', '#c9d6e3' }, '50%' },
              { { 'Ashen', '#9aa0a8' }, '80%' },
              { { 'Obsidian', '#9b7bff' }, '100%' },
              { { 'Lord of Death', '#e04848' }, '100%, nunca abaixo de Praeclarus' },
              { 'Recompensa de quest', '30%' },
          } },
        { 'p', 'O bônus Rarity Find dos anéis e amuletos multiplica essa chance. Monstros raros sempre pagam: se nenhum equipamento cair no corpo, um equipamento da lista de loot do próprio monstro é escolhido.' },
        { 'h', 'Como o item é sorteado' },
        { 'p', 'Primeiro sai o grau. O grau decide quantos bônus o item tem e em que parte da faixa de cada bônus o valor cai. Depois saem os bônus, sempre do tipo do item: espada rola bônus de corpo a corpo, wand rola magia, bota rola velocidade.' },
        { 'table', widths = { 140, 74, 60, 80, 86, 70 }, head = { 'Origem', 'Communis', 'Rarus', 'Praeclarus', 'Legendarius', 'Mythicus' },
          rows = {
              gradeRow('Monstro comum', '#c8c8c8', { 81, 17.5, 1.2, 0.25, 0.05 }),
              gradeRow('Quest', '#c8c8c8', { 40, 32, 18, 8, 2 }),
          } },
        { 'h', 'Qualquer monstro, qualquer grau' },
        { 'p', 'Todo monstro pode dar todos os graus, do rat ao demon. O que muda a chance é o tier: um monstro comum quase nunca dá Legendarius ou Mythicus, um Obsidian dá com frequência e o Lord of Death nunca dá menos que Praeclarus.' },
        { 'h', 'Bônus de quem achou' },
        { 'p', 'Quem matou o monstro tem o nome gravado no item ("Found by ..."). Enquanto essa pessoa usa o item, todos os bônus dele ficam 20% mais fortes. Para qualquer outro jogador, o item vale o valor que aparece na descrição.' },
        { 'h', 'Rolagem perfeita' },
        { 'p', 'Um bônus que cai exatamente no máximo da faixa é perfeito. Isso acontece mais ou menos uma vez a cada 100 mil itens, e o servidor inteiro fica sabendo. Mythicus também é anunciado para todos; Legendarius só para quem achou.' },
        { 'links', { 'grades', 'pools', 'affixes' } },
    },
}

WIKI_PAGES.grades = {
    menu = 'Graus de raridade',
    title = 'Graus de raridade',
    blocks = {
        { 'lead', 'São cinco graus. Cada um tem uma cor no item e na moldura, um número de bônus e uma faixa de valores.' },
        { 'grades' },
        { 'p', 'A faixa diz de onde os valores saem dentro do mínimo e do máximo de cada bônus. Nos três graus de cima, os valores se concentram perto da parte de baixo da faixa e ficam cada vez mais raros perto do topo. Em um bônus de 1 a 20, metade dos Mythicus fica entre 7 e 10 e só uns 2% passam de 18.' },
        { 'p', 'Cada bônus rola sozinho: um item pode ter um bônus alto e os outros baixos.' },
        { 'links', { 'items', 'pools' } },
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
        { 'h', 'Armas corpo a corpo' },
        poolTable({
            { 'Attack', '1 a 20', '' }, { 'Skill da arma', '1% a 10%', 'sword, axe, club ou fist' },
            { 'Crit Chance', '1% a 10%', '' }, { 'Crit Damage', '1% a 25%', '' },
            { 'Life Leech', '1% a 12%', '' }, { 'Finisher', '1% a 25%', '' },
            { 'Attack Speed', '3% a 15%', 'duas mãos: 5% a 20%' }, { 'Cleave', '3% a 15%', 'duas mãos: 5% a 25%' },
        }),
        { 'h', 'Arcos e armas de distância' },
        poolTable({
            { 'Attack', '1 a 20', '' }, { 'Distance', '1% a 10%', '' }, { 'Hit Chance', '1% a 15%', '' },
            { 'Crit Chance', '1% a 10%', '' }, { 'Crit Damage', '1% a 25%', '' }, { 'Range', '+1', '' },
            { 'Attack Speed', '3% a 15%', 'duas mãos: 5% a 20%' }, { 'Perfect Shot', '5 a 40', 'a 3, 4 ou 5 sqm' },
        }),
        { 'h', 'Wands e rods' },
        poolTable({
            { 'Magic Level', '1% a 10%', '' }, { 'Mana Leech', '2% a 20%', '' }, { 'Crit Chance', '2% a 15%', '' },
            { 'Crit Damage', '5% a 40%', '' }, { 'Wand Damage', '10% a 100%', '' }, { 'Max Mana', '2% a 15%', '' },
            { 'Cooldown', '2% a 10%', '' }, { 'Attack Speed', '3% a 15%', '' },
            { 'Pierce', '5% a 30%', 'elemento da própria arma' }, { 'Ally Heal', '5% a 30%', 'só rods de druid' },
        }),
        { 'h', 'Escudos' },
        poolTable({
            { 'Defense', '1 a 10', '' }, { 'Resistência', '1% a 20%', 'um elemento' }, { 'Last Stand', '1% a 25%', '' },
            { 'Healing', '1% a 20%', '' }, { 'Max Health', '1% a 10%', '' },
        }),
        { 'h', 'Spellbooks' },
        poolTable({
            { 'Magic Level', '1% a 10%', '' }, { 'Max Mana', '2% a 15%', '' }, { 'Defense', '1 a 10', '' },
            { 'Resistência', '1% a 20%', '' }, { 'Ally Heal', '5% a 30%', '' }, { 'Cooldown', '2% a 10%', '' },
            { 'Pierce', '5% a 30%', 'elemento sorteado' },
        }),
        { 'h', 'Capacetes, armaduras e calças' },
        poolTable({
            { 'Armor', '1 a 8', '' }, { 'Resistência', '1% a 20%', 'pode vir duas' }, { 'Healing', '1% a 20%', '' },
            { 'Last Stand', '1% a 25%', '' }, { 'Skill da vocação', '1% a 10%', 'ML, melee, distance ou fist' },
            { 'Dodge', '1% a 4%', '' }, { 'Reflect', '1% a 8%', '' }, { 'Emergency Heal', '5% a 20%', '' },
            { 'Cooldown Chance', '2% a 12%', '' },
        }),
        { 'h', 'Botas' },
        poolTable({
            { 'Armor', '1 a 4', '' }, { 'Speed', '2 a 20', '' }, { 'Resistência', '1% a 20%', '' },
            { 'Healing', '1% a 20%', '' }, { 'Max Health', '1% a 10%', '' }, { 'Dodge', '1% a 4%', '' },
        }),
        { 'h', 'Anéis e amuletos' },
        { 'p', 'Só os que não têm carga nem tempo de uso.' },
        poolTable({
            { 'Max Health', '1% a 8%', '' }, { 'Max Mana', '2% a 12%', '' }, { 'Resistência', '1% a 12%', '' },
            { 'Experience', '1% a 8%', '' }, { 'Loot', '1% a 10%', '' }, { 'Rarity Find', '1% a 10%', '' },
            { 'Health Regen', '1 a 5', '' }, { 'Mana Regen', '1 a 5', '' },
        }),
        { 'links', { 'affixes', 'stacking' } },
    },
}

local function affixTable(rows)
    return { 'table', widths = { 120, 330, 60 }, head = { 'Bônus', 'O que faz', 'Teto' }, rows = rows }
end

WIKI_PAGES.affixes = {
    menu = 'Lista de bônus',
    title = 'Lista de bônus',
    blocks = {
        { 'lead', 'Todos os bônus que um item raro pode ter. O teto é o máximo que todos os seus itens juntos podem dar, já contando o bônus de quem achou.' },
        { 'h', 'Ataque' },
        affixTable({
            { 'Attack', 'Ataque a mais na arma.', '' },
            { 'Sword, Axe, Club, Fist', 'Porcentagem a mais na skill.', '20%' },
            { 'Melee', 'Sword, axe e club ao mesmo tempo.', '20%' },
            { 'Distance', 'Porcentagem a mais em distance.', '20%' },
            { 'Hit Chance', 'Chance de acerto a mais na arma de distância.', '' },
            { 'Range', 'Um sqm a mais de alcance.', '' },
            { 'Crit Chance', 'Chance de golpe crítico.', '25%' },
            { 'Crit Damage', 'Dano a mais no golpe crítico.', '50%' },
            { 'Life Leech', 'Parte do dano volta como vida.', '25%' },
            { 'Mana Leech', 'Parte do dano volta como mana.', '30%' },
            { 'Finisher', 'Dano a mais em monstros com 25% de vida ou menos.', '40%' },
            { 'Attack Speed', 'Ataca mais rápido. Só vem da arma.', '24%' },
            { 'Cleave', 'Golpes corpo a corpo acertam os dois sqm ao lado do alvo com essa parte do dano.', '30%' },
            { 'Perfect Shot', 'Dano a mais quando o alvo está exatamente na distância do item.', '48' },
            { 'Wand Damage', 'Dano a mais no ataque de wand e rod. No máximo dobra o dano.', '100%' },
            { 'Pierce', 'Tira pontos da resistência do monstro a um elemento, nunca abaixo de 0.', '40%' },
        }),
        { 'h', 'Magia' },
        affixTable({
            { 'Magic Level', 'Porcentagem do seu ML base. ML 100 com +5% vira 105.', '20%' },
            { 'Max Mana', 'Mana máxima a mais.', '25%' },
            { 'Cooldown', 'Cooldowns das magias mais curtos.', '15%' },
            { 'Cooldown Chance', 'A cada ataque, chance de tirar 2 segundos de todos os cooldowns. No máximo uma vez por segundo.', '25%' },
            { 'Ally Heal', 'Cura a mais em outro jogador (exura sio, mass healing). Não vale em você.', '40%' },
        }),
        { 'h', 'Defesa' },
        affixTable({
            { 'Armor, Defense', 'Armor ou defesa a mais no item.', '' },
            { 'Max Health', 'Vida máxima a mais.', '20%' },
            { 'Resistência', 'Menos dano de fire, earth, energy, ice, holy ou death.', '40%' },
            { 'Physical Resist', 'Menos dano físico. A mais forte e a mais rara.', '20%' },
            { 'Healing', 'Magias, runas e poções curam mais. Leech não conta.', '40%' },
            { 'Last Stand', 'Menos dano recebido enquanto você está com 25% de vida ou menos. Um LAST STAND! vermelho, como o DODGE!, aparece quando ele age.', '40%' },
            { 'Dodge', 'Chance de desviar de um golpe.', '12%' },
            { 'Reflect', 'Devolve parte do dano físico que um monstro causa em você.', '20%' },
            { 'Emergency Heal', 'Ao cair para 25% de vida ou menos, cura essa parte da vida máxima de uma vez. Uma vez por minuto.', '25%' },
            { 'Speed', 'Velocidade a mais.', '40' },
        }),
        { 'h', 'Anéis e amuletos' },
        affixTable({
            { 'Experience', 'XP a mais por monstro.', '15%' },
            { 'Loot', 'Multiplica a chance de cada item do loot do monstro.', '20%' },
            { 'Rarity Find', 'Multiplica a chance de um item virar raro.', '20%' },
            { 'Health Regen', 'Vida a mais em cada tick de regeneração.', '10' },
            { 'Mana Regen', 'Mana a mais em cada tick de regeneração.', '10' },
        }),
        { 'h', 'Resistências e a cor da gema' },
        { 'table', widths = { 120, 120 }, head = { 'Elemento', 'Nome no item' },
          rows = {
              { 'Fire', { 'Igneus', '#ff6a3d' } }, { 'Earth', { 'Terrenus', '#8bc34a' } },
              { 'Energy', { 'Fulmineus', '#b388ff' } }, { 'Ice', { 'Glacialis', '#4dd0e1' } },
              { 'Holy', { 'Sacer', '#ffe082' } }, { 'Death', { 'Mortifer', '#b07ad8' } },
              { 'Physical', { 'Corporalis', '#b0bec5' } },
          } },
        { 'h', 'Rarity XP: refazer bônus' },
        { 'p', 'Matar um monstro Pale, Ashen, Obsidian ou Lord of Death dá Rarity XP para quem tem o loot: a experiência do monstro dividida por 100, vezes 1 (Pale), 2 (Ashen), 4 (Obsidian) ou 10 (Lord of Death). Um Pale Dragon dá 7, um Obsidian Dragon dá 28.' },
        { 'p', 'Na janela Rarity Bonuses, cada bônus de um item que você está usando tem dois botões. Reroll sorteia um novo valor para o mesmo bônus. Trocar troca o bônus por outro aleatório do mesmo tipo de item. Os outros bônus do item não mudam.' },
        { 'table', widths = { 120, 90, 90 }, head = { 'Grau do item', 'Reroll', 'Trocar' },
          rows = {
              { 'Communis', '25', '40' }, { 'Rarus', '60', '100' }, { 'Praeclarus', '150', '250' },
              { 'Legendarius', '350', '600' }, { 'Mythicus', '800', '1400' },
          } },
        { 'p', 'O preço também sobe com o level exigido do item: um item de level 400 custa o dobro, um de level 200 custa 1,5 vez, e um item sem level exigido custa o preço da tabela. Um Mythicus de level 400 custa 1600 no Reroll e 2800 no Trocar.' },
        { 'p', 'A Store também vende Rarity XP na categoria Rarity: 500 por 250 coins, 1500 por 700 e 5000 por 2200.' },
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
              { 'Crit Chance 10% + 10%', '20%', '19%' },
              { 'Experience 8% + 8%', '16%', '15% (teto)' },
          } },
        { 'p', 'Bônus fixos, como Attack, Armor, Speed e Regen, somam direto. Depois de combinar, o total para no teto do bônus.' },
        { 'h', 'Com imbuements e a forja' },
        { 'p', 'Os bônus de raridade somam com os imbuements, e com a Exaltation Forge. Crit e leech da raridade se juntam aos do Strike e do Vampirism/Void.' },
        { 'note', 'A chance de crítico total tem teto de 35%: os 10% do Strike mais até 25% da raridade.' },
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

-- ---------------------------------------------------------------- teleports
-- one page per city, from teleports.lua (generated from the map)

local tpGroup = WIKI_GROUPS[#WIKI_GROUPS]
local overviewRows = {}

for _, entry in ipairs(WIKI_TELEPORTS) do
    local id = 'tp_' .. entry.city:lower():gsub(' ', '_')
    local total, low, high = 0, math.huge, 0
    local blocks = {}
    for _, room in ipairs(entry.rooms) do
        total = total + room.teleports
        for _, hunt in ipairs(room.hunts) do
            low, high = math.min(low, hunt[2]), math.max(high, hunt[2])
        end
    end
    if #entry.rooms == 1 then
        table.insert(blocks, { 'lead', string.format('A sala de teleports de %s fica ao lado do templo, %s. São %d teleports, e a cela ao lado de cada um mostra o monstro da hunt.',
            entry.city, entry.rooms[1].floor, total) })
    else
        table.insert(blocks, { 'lead', string.format('%s tem %d salas de teleports perto do templo, com %d teleports ao todo. A cela ao lado de cada teleport mostra o monstro da hunt.',
            entry.city, #entry.rooms, total) })
    end
    for i, room in ipairs(entry.rooms) do
        if #entry.rooms > 1 then
            table.insert(blocks, { 'h', string.format('Sala %d, %s (%d teleports)', i, room.floor, room.teleports) })
        end
        table.insert(blocks, { 'hunts', room.hunts })
    end
    table.insert(blocks, { 'p', 'Nível sugerido é o mesmo que as hunt tasks usam. "Também tem" são os outros monstros mais comuns no caminho a partir de onde o teleport deixa você.' })
    table.insert(blocks, { 'links', { 'tp', 'huntboard' } })
    WIKI_PAGES[id] = { menu = entry.city, title = 'Teleports de ' .. entry.city, blocks = blocks }
    table.insert(tpGroup.pages, id)
    table.insert(overviewRows, { { entry.city, '#ffd27a' }, tostring(#entry.rooms), tostring(total), string.format('%d a %d', low, high), link = id })
end

WIKI_PAGES.tp = {
    menu = 'Salas de teleport',
    title = 'Salas de teleport',
    blocks = {
        { 'lead', 'Toda cidade tem uma sala de teleports perto do templo. Cada teleport leva direto para uma hunt, e o monstro na cela ao lado do teleport mostra qual é.' },
        { 'p', 'Clique numa cidade para ver todas as hunts dela, do nível mais baixo ao mais alto.' },
        { 'table', widths = { 150, 70, 100, 150 }, head = { 'Cidade', 'Salas', 'Teleports', 'Nível sugerido' }, rows = overviewRows },
        { 'p', 'Para quem está começando, Avante tem as hunts mais fracas (trolls, orcs, minotauros). Monstros com rate alta no Hunt Board valem mais XP e viram raros com mais frequência.' },
        { 'links', { 'tp_avante', 'huntboard' } },
    },
}
