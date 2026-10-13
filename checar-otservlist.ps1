# Mythos - o que o otservlist.org ve do servidor, testado deste PC (de fora,
# como a lista testa) e da VPS. Rodado pelo checar-otservlist.bat.
param([string]$Vps = "root@82.38.28.137", [string]$Chave = "$env:USERPROFILE\.ssh\baiak", [string]$Dominio = "mythosot.com.br")
$ErrorActionPreference = "Continue"
$falhas = 0
function Ok($t) { Write-Host "  [ok]    $t" -ForegroundColor Green }
function Falha($t) { Write-Host "  [FALHA] $t" -ForegroundColor Red; $script:falhas++ }
function Aviso($t) { Write-Host "  [aviso] $t" -ForegroundColor Yellow }

Write-Host "== 1. Status na porta 7171 (o que o otservlist le)"
try {
    $tcp = New-Object Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 8000
    $tcp.Connect($Dominio, 7171)
    $s = $tcp.GetStream()
    [byte[]]$body = [byte[]](0xFF, 0xFF) + [Text.Encoding]::ASCII.GetBytes("info")
    [byte[]]$pkt = [BitConverter]::GetBytes([uint16]$body.Length) + $body
    $s.Write($pkt, 0, $pkt.Length)
    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 8192
    while (($n = $s.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    $tcp.Close()
    $xml = [Text.Encoding]::GetEncoding(28591).GetString($ms.ToArray())
    if ($xml -match "<tsqp") {
        Ok "o servidor respondeu o status"
        [xml]$x = $xml.Substring($xml.IndexOf("<"))
        $si = $x.tsqp.serverinfo; $pl = $x.tsqp.players; $ow = $x.tsqp.owner
        Write-Host ("        nome={0} ip={1} porta={2} pais={3} site={4} client={5}" -f $si.servername, $si.ip, $si.port, $si.location, $si.url, $si.client)
        Write-Host ("        online={0} max={1} recorde={2} dono={3} motd={4}" -f $pl.online, $pl.max, $pl.peak, $ow.name, $x.tsqp.motd)
        if ($si.ip -match '^(127\.|10\.|192\.168\.|25\.)') { Falha "o ip do config.lua ($($si.ip)) nao e publico: rode usar-dominio.bat" }
        elseif ($si.ip -ne $Dominio) { Aviso "o ip do config.lua e $($si.ip); no otservlist cadastre exatamente esse endereco" }
        else { Ok "ip do config.lua = $Dominio (cadastre esse endereco e a porta 7171)" }
        if ($ow.name -eq "OpenTibiaBR" -or $si.url -like "*opentibiabr*") { Falha "dono/site ainda sao os do OpenTibiaBR: rode atualizar-servidor.bat" } else { Ok "dono e site do Mythos" }
        if ([int]$pl.max -le 0) { Falha "maxPlayers = 0: rode atualizar-servidor.bat" } else { Ok "maximo de jogadores: $($pl.max)" }
    } else { Falha "a porta 7171 abriu mas nao respondeu o status" }
} catch { Falha "nao conectou em ${Dominio}:7171 ($($_.Exception.Message)). Porta fechada no firewall ou servidor fora do ar" }

Write-Host "== 2. Porta do jogo 7172"
try { $t = New-Object Net.Sockets.TcpClient; $t.Connect($Dominio, 7172); $t.Close(); Ok "7172 aberta" } catch { Falha "7172 fechada: ninguem entra no jogo" }

Write-Host "== 3. Site, login do client e download"
foreach ($u in @("https://$Dominio/", "https://$Dominio/index.php/account/create", "https://$Dominio/index.php/downloads")) {
    try { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 3; Ok "$u ($($r.StatusCode))" } catch { Falha "$u ($($_.Exception.Message))" }
}
try {
    $r = Invoke-WebRequest -Uri "https://$Dominio/login.php" -Method Post -Body '{"type":"cacheinfo"}' -ContentType "application/json" -UseBasicParsing -TimeoutSec 15
    if ($r.Content -match "playersonline") { Ok "login.php responde (o client entra por ele)" } else { Aviso "login.php respondeu algo estranho: $($r.Content.Substring(0, [Math]::Min(120, $r.Content.Length)))" }
} catch { Falha "login.php nao responde ($($_.Exception.Message))" }
try {
    $r = Invoke-WebRequest -Uri "https://github.com/murilobreve/mythos-client/releases/download/instalador/Mythos-Setup.exe" -Method Head -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5
    Ok "instalador Mythos-Setup.exe disponivel"
} catch { Falha "instalador do client nao baixa ($($_.Exception.Message))" }

Write-Host "== 4. Na VPS (firewall, portas, config)"
if (Test-Path $Chave) {
    $remote = 'cd /opt/brevesot; echo config:; grep -E ''^(ip|maxPlayers|ownerName|url|location|statusProtocolPort|loginProtocolPort|gameProtocolPort) *='' config.lua; echo portas:; ss -ltn | grep -E '':(7171|7172|80|443) ''; echo firewall:; ufw status 2>/dev/null | grep -E ''7171|7172|Status'' || echo sem-ufw; echo servico:; systemctl is-active canary'
    ssh -i $Chave $Vps $remote
} else { Aviso "chave SSH nao encontrada em $Chave: pulei a parte da VPS" }

Write-Host ""
if ($falhas -eq 0) { Write-Host "Tudo certo para cadastrar no otservlist: endereco $Dominio, porta 7171." -ForegroundColor Green }
else { Write-Host "$falhas problema(s) acima. Mande este texto para o Claude." -ForegroundColor Red }
