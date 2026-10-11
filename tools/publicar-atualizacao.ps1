# Mythos - publica uma versao nova do client para a atualizacao automatica
#
# Roda depois do empacotar-cliente.ps1 (o compilar-cliente.bat chama sozinho).
# Pega a pasta pronta (dist\Mythos), calcula o SHA-256 de cada arquivo e
# manda para o repositorio publico murilobreve/mythos-client:
#   objects\<sha256>          o conteudo de cada arquivo (so os que ainda nao estao la)
#   <canal>\manifest.json     a lista: caminho -> sha256, e o numero da versao
# O client, ao abrir, le o manifest.json e baixa so o que mudou. Tudo vem do
# GitHub: a VPS nao gasta banda nenhuma.
#
# Opcoes:
#   -Canal opengl|directx    qual client e este (padrao: opengl)
#   -Pasta <caminho>         pasta pronta (padrao: dist\Mythos)
#   -Repo <caminho>          copia local do mythos-client (padrao: %USERPROFILE%\mythos-client)
#   -SemEnviar               prepara tudo mas nao faz o git push (para testar)
param(
    [ValidateSet("opengl", "directx")]
    [string]$Canal = "opengl",
    [string]$Pasta = "",
    [string]$Repo = "",
    [string]$Remoto = "https://github.com/murilobreve/mythos-client.git",
    [switch]$SemEnviar
)

$ErrorActionPreference = "Stop"
function Info($msg) { Write-Host "  $msg" }
function Falhou($msg) { Write-Host ""; Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }

$Raiz = Split-Path -Parent $PSScriptRoot
if ($Pasta -eq "") { $Pasta = Join-Path $Raiz "dist\Mythos" }
if (-not (Test-Path $Pasta)) { Falhou "pasta do client nao encontrada: $Pasta (rode o empacotar antes)" }
$Pasta = (Resolve-Path $Pasta).Path.TrimEnd('\', '/')
if ($Repo -eq "") {
    $casa = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $Repo = Join-Path $casa "mythos-client"
}
$semBom = New-Object System.Text.UTF8Encoding $false

Write-Host ""
Write-Host "Publicando o client '$Canal' de $Pasta"

# ---------------------------------------------------------------- repositorio
if (-not (Test-Path (Join-Path $Repo ".git"))) {
    Info "baixando o repositorio $Remoto em $Repo"
    git clone -q $Remoto $Repo
    if ($LASTEXITCODE -ne 0) { Falhou "nao consegui clonar $Remoto" }
}
git -C $Repo rev-parse --verify -q HEAD *> $null
$repoVazio = ($LASTEXITCODE -ne 0)
if ($repoVazio) {
    # clone sem branch padrao: usa o main do GitHub se ele ja existir
    git -C $Repo fetch -q origin main *> $null
    if ($LASTEXITCODE -eq 0) { git -C $Repo checkout -q -B main origin/main } else { git -C $Repo checkout -q -B main }
} else {
    git -C $Repo checkout -q main
    git -C $Repo pull -q --ff-only origin main
    if ($LASTEXITCODE -ne 0) { Falhou "nao consegui atualizar $Repo (git pull)" }
}

$pastaCanal = Join-Path $Repo $Canal
$pastaObjetos = Join-Path $Repo "objects"
New-Item -ItemType Directory -Force -Path $pastaCanal, $pastaObjetos | Out-Null
$caminhoManifest = Join-Path $pastaCanal "manifest.json"

$versaoAntiga = 0
$arquivosAntigos = @{}
if (Test-Path $caminhoManifest) {
    $antigo = [System.IO.File]::ReadAllText($caminhoManifest) | ConvertFrom-Json
    $versaoAntiga = [int]$antigo.versao
    foreach ($p in $antigo.files.PSObject.Properties) {
        if ($p.Name -ne "versao.json") { $arquivosAntigos[$p.Name] = $p.Value.sha256 }
    }
}

# ---------------------------------------------------------------- arquivos
# fora da lista: os assets do Tibia (o client baixa e cuida deles sozinho),
# configuracoes e logs do jogador, e o que so serve para o Windows Explorer
function Ignorar($rel) {
    if ($rel -like "data/things/*" -and $rel -notlike "data/things/custom/*") { return $true }
    if ($rel -like "data/sounds/*") { return $true }
    if ($rel -like "*.log" -or $rel -like "*.pdb" -or $rel -like "*.part") { return $true }
    $nome = Split-Path -Leaf $rel
    return @("desktop.ini", "config.otml", "versao.json") -contains $nome
}

$arquivos = @{}
$tamanhoNovo = 0
Get-ChildItem -Path $Pasta -Recurse -Force -File | ForEach-Object {
    $rel = $_.FullName.Substring($Pasta.Length + 1).Replace('\', '/')
    if (Ignorar $rel) { return }
    $sha = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLower()
    $arquivos[$rel] = [ordered]@{ sha256 = $sha; size = $_.Length }
    $objeto = Join-Path $pastaObjetos $sha
    if (-not (Test-Path $objeto)) {
        Copy-Item -LiteralPath $_.FullName -Destination $objeto
        $script:tamanhoNovo += $_.Length
    }
}

$mudou = ($arquivos.Count -ne $arquivosAntigos.Count)
if (-not $mudou) {
    foreach ($k in $arquivos.Keys) {
        if ($arquivosAntigos[$k] -ne $arquivos[$k].sha256) { $mudou = $true; break }
    }
}
$versao = if ($mudou) { $versaoAntiga + 1 } else { $versaoAntiga }

# versao.json vai na pasta (e no zip / instalador) e tambem na lista: e o
# ultimo arquivo que o client troca, entao uma atualizacao que parou no meio
# tenta de novo na proxima vez que abrir
$infoLocal = [ordered]@{ canal = $Canal; versao = $versao } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText((Join-Path $Pasta "versao.json"), $infoLocal, $semBom)
$shaInfo = (Get-FileHash -Path (Join-Path $Pasta "versao.json") -Algorithm SHA256).Hash.ToLower()
Copy-Item -LiteralPath (Join-Path $Pasta "versao.json") -Destination (Join-Path $pastaObjetos $shaInfo) -Force
$arquivos["versao.json"] = [ordered]@{ sha256 = $shaInfo; size = (Get-Item (Join-Path $Pasta "versao.json")).Length }

# o zip do site tambem leva o versao.json
$zip = Join-Path (Split-Path -Parent $Pasta) ((Split-Path -Leaf $Pasta).Replace(' ', '-') + ".zip")
if (Test-Path $zip) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $arquivoZip = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $entrada = (Split-Path -Leaf $Pasta) + "/versao.json"
        $velha = $arquivoZip.GetEntry($entrada)
        if ($velha) { $velha.Delete() }
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arquivoZip, (Join-Path $Pasta "versao.json"), $entrada) | Out-Null
    } finally { $arquivoZip.Dispose() }
}

if (-not $mudou) {
    Write-Host ""
    Write-Host "Nada mudou desde a versao ${versao}: nao ha o que publicar." -ForegroundColor Yellow
    exit 0
}

$lista = [ordered]@{}
foreach ($k in ($arquivos.Keys | Sort-Object)) { $lista[$k] = $arquivos[$k] }
$manifest = [ordered]@{
    versao = $versao
    canal = $Canal
    data = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    files = $lista
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($caminhoManifest, $manifest, $semBom)

Info ("versao {0} -> {1}, {2} arquivos, {3} MB novos" -f $versaoAntiga, $versao, $arquivos.Count, [math]::Round($tamanhoNovo / 1MB, 1))

# ---------------------------------------------------------------- envio
git -C $Repo add -A
git -C $Repo commit -q -m "$Canal versao $versao"
if ($LASTEXITCODE -ne 0) { Falhou "git commit falhou em $Repo" }
if ($SemEnviar) {
    Write-Host ""
    Write-Host "Pronto (sem enviar). Para mandar: git -C `"$Repo`" push origin main"
    exit 0
}
git -C $Repo push -q -u origin main
if ($LASTEXITCODE -ne 0) { Falhou "git push falhou: confira se o seu usuario do GitHub tem acesso ao mythos-client" }

Write-Host ""
Write-Host "Versao $versao publicada!" -ForegroundColor Green
Info "os jogadores recebem ao abrir o client (o GitHub pode levar ate 5 minutos para mostrar)"
