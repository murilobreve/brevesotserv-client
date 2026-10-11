# Mythos - monta o instalador (Mythos-Setup.exe) e manda para o GitHub
#
# Roda depois do publicar-atualizacao.ps1 (o compilar-cliente.bat chama).
# Precisa do Inno Setup 6, gratis: https://jrsoftware.org/isdl.php
# O instalador e o .zip vao para a release "instalador" do repositorio
# publico murilobreve/mythos-client; o site aponta para la, entao baixar o
# client tambem nao gasta a banda da VPS.
#
# Opcoes:
#   -Canal directx|opengl    qual client (padrao: opengl)
#   -Pasta <caminho>         pasta pronta (padrao: dist\Mythos)
#   -SemEnviar               so monta o instalador, nao manda para o GitHub
param(
    [ValidateSet("opengl", "directx")]
    [string]$Canal = "opengl",
    [string]$Pasta = "",
    [string]$Repositorio = "murilobreve/mythos-client",
    [string]$Tag = "instalador",
    [switch]$SemEnviar
)

$ErrorActionPreference = "Stop"
function Info($msg) { Write-Host "  $msg" }

$Raiz = Split-Path -Parent $PSScriptRoot
if ($Pasta -eq "") { $Pasta = Join-Path $Raiz "dist\Mythos" }
$Pasta = (Resolve-Path $Pasta).Path.TrimEnd('\', '/')
$Dist = Split-Path -Parent $Pasta

$exe = @(Get-ChildItem -Path $Pasta -File -Filter "*.exe" | Where-Object { $_.Name -like "Mythos*" })
if ($exe.Count -eq 0) { Write-Host "ERRO: nao achei o Mythos*.exe em $Pasta" -ForegroundColor Red; exit 1 }
$exe = $exe[0].Name

$versao = "1"
$infoPath = Join-Path $Pasta "versao.json"
if (Test-Path $infoPath) { $versao = [string]([System.IO.File]::ReadAllText($infoPath) | ConvertFrom-Json).versao }

if ($Canal -eq "directx") {
    $saida = "Mythos-Setup"
    $zipNome = "Mythos-DirectX.zip"
} else {
    $saida = "Mythos-Setup-OpenGL"
    $zipNome = "Mythos-OpenGL.zip"
}

# ---------------------------------------------------------------- Inno Setup
$iscc = @(
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
    Write-Host ""
    Write-Host "O Inno Setup 6 nao esta instalado, entao o instalador ficou de fora." -ForegroundColor Yellow
    Write-Host "Baixe gratis em https://jrsoftware.org/isdl.php e rode de novo."
    Write-Host "(a atualizacao automatica ja foi publicada; so falta o instalador)"
    exit 0
}

Write-Host ""
Write-Host "Montando o instalador $saida.exe (versao $versao)"
& $iscc /Q "/DFonte=$Pasta" "/DExe=$exe" "/DCanal=$Canal" "/DVersao=$versao" "/DSaida=$saida" (Join-Path $Raiz "installer\mythos.iss")
if ($LASTEXITCODE -ne 0) { Write-Host "ERRO: o Inno Setup falhou" -ForegroundColor Red; exit 1 }
$setup = Join-Path $Dist "$saida.exe"
Info ("instalador: {0} ({1} MB)" -f $setup, [math]::Round((Get-Item $setup).Length / 1MB, 1))

if ($SemEnviar) { exit 0 }

# ---------------------------------------------------------------- GitHub
# usa o mesmo login do GitHub que o git ja tem salvo neste PC
$credencial = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = ($credencial | Where-Object { $_ -like "password=*" } | Select-Object -First 1)
if (-not $token) {
    Write-Host ""
    Write-Host "Nao achei o login do GitHub salvo no git." -ForegroundColor Yellow
    Write-Host "Mande o $setup a mao: https://github.com/$Repositorio/releases (release '$Tag')"
    exit 0
}
$token = $token.Substring(9)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$cabecalhos = @{
    Authorization = "Bearer $token"
    Accept = "application/vnd.github+json"
    "User-Agent" = "mythos-instalador"
}
$api = "https://api.github.com/repos/$Repositorio"

try {
    try {
        $release = Invoke-RestMethod -Headers $cabecalhos -Uri "$api/releases/tags/$Tag"
    } catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            $corpo = @{ tag_name = $Tag; name = "Instalador do Mythos"; body = "Instalador e client do Mythos. Baixe em https://mythosot.com.br"; make_latest = "true" } | ConvertTo-Json
            $release = Invoke-RestMethod -Method Post -Headers $cabecalhos -Uri "$api/releases" -Body $corpo -ContentType "application/json"
        } else { throw }
    }

    $enviar = @(@{ Arquivo = $setup; Nome = "$saida.exe" })
    $zipLocal = Join-Path $Dist ((Split-Path -Leaf $Pasta).Replace(' ', '-') + ".zip")
    if (Test-Path $zipLocal) {
        # o zip e montado antes da publicacao: poe nele o versao.json que a
        # publicacao gravou na pasta, senao o client do zip se acha velho
        if (Test-Path $infoPath) {
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $nomeNoZip = (Split-Path -Leaf $Pasta) + "/versao.json"
            $zip = [System.IO.Compression.ZipFile]::Open($zipLocal, [System.IO.Compression.ZipArchiveMode]::Update)
            try {
                foreach ($velho in @($zip.Entries | Where-Object { $_.FullName -eq $nomeNoZip })) { $velho.Delete() }
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $infoPath, $nomeNoZip) | Out-Null
            } finally {
                $zip.Dispose()
            }
        }
        $enviar += @{ Arquivo = $zipLocal; Nome = $zipNome }
    }

    foreach ($item in $enviar) {
        foreach ($velho in @($release.assets | Where-Object { $_.name -eq $item.Nome })) {
            Invoke-RestMethod -Method Delete -Headers $cabecalhos -Uri "$api/releases/assets/$($velho.id)" | Out-Null
        }
        Info "enviando $($item.Nome)..."
        $url = "https://uploads.github.com/repos/$Repositorio/releases/$($release.id)/assets?name=$($item.Nome)"
        Invoke-RestMethod -Method Post -Headers $cabecalhos -Uri $url -InFile $item.Arquivo -ContentType "application/octet-stream" | Out-Null
    }
} catch {
    Write-Host ""
    Write-Host "Nao consegui mandar o instalador para o GitHub: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Mande o $setup a mao: https://github.com/$Repositorio/releases (release '$Tag')"
    exit 0
}

Write-Host ""
Write-Host "Instalador no ar!" -ForegroundColor Green
Info "https://github.com/$Repositorio/releases/download/$Tag/$saida.exe"
