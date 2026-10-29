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
    [switch]$SemEnviar,
    # so para teste com um servidor falso
    [string]$ApiBase = "https://api.github.com",
    [string]$UploadBase = "https://uploads.github.com"
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
Write-Host "Montando o instalador $saida.exe (versao $versao, pode levar alguns minutos)"

# o Inno Setup so diz "the system cannot find the path specified", sem dizer
# qual: antes dele, cada caminho que o mythos.iss abre (o antivirus ja tirou
# arquivos destas pastas)
$iss = Join-Path $Raiz "installer\mythos.iss"
$pastaInno = Split-Path -Parent $iscc
$doGit = @("installer\mythos.iss", "installer\wizard.bmp", "installer\wizard@2x.bmp", "installer\wizard-small.bmp", "installer\wizard-small@2x.bmp", "cmake\icon\otcicon.ico")
if (@($doGit | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Raiz $_)) }).Count -gt 0) {
    # a pasta installer ja sumiu do PC (antivirus): volta com a do git
    Info "a pasta installer sumiu: voltando com a do git"
    $antes = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git -C $Raiz checkout -- installer cmake/icon 2>&1 | Out-Null
    $ErrorActionPreference = $antes
}
$precisa = @(
    $Pasta,
    (Join-Path $Pasta $exe),
    $iss,
    (Join-Path $Raiz "installer\wizard.bmp"),
    (Join-Path $Raiz "installer\wizard@2x.bmp"),
    (Join-Path $Raiz "installer\wizard-small.bmp"),
    (Join-Path $Raiz "installer\wizard-small@2x.bmp"),
    (Join-Path $Raiz "cmake\icon\otcicon.ico"),
    $Dist,
    (Join-Path $pastaInno "Default.isl"),
    (Join-Path $pastaInno "Languages\BrazilianPortuguese.isl"),
    $env:TEMP
)
$faltam = @($precisa | Where-Object { -not $_ -or -not (Test-Path -LiteralPath $_) })
if ($faltam.Count -gt 0) {
    Write-Host "ERRO: o instalador precisa destes caminhos, que nao existem:" -ForegroundColor Red
    $faltam | ForEach-Object { Write-Host "  $_" }
    Write-Host "  (veja a quarentena do antivirus, ou reinstale o Inno Setup 6)"
    exit 1
}

# a saida inteira vai para dist\instalador.log; numa falha, o fim dela aparece
# aqui (o arquivo que ele estava lendo e o erro)
$log = Join-Path $Dist "instalador.log"
$argumentos = @("/DFonte=$Pasta", "/DExe=$exe", "/DCanal=$Canal", "/DVersao=$versao", "/DSaida=$saida", $iss)
$antes = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$saidaInno = @(& $iscc @argumentos 2>&1 | ForEach-Object { "$_" })
$codigo = $LASTEXITCODE
$ErrorActionPreference = $antes
[System.IO.File]::WriteAllLines($log, [string[]]$saidaInno)
if ($codigo -ne 0) {
    Write-Host "ERRO: o Inno Setup falhou (codigo $codigo). O fim do que ele disse:" -ForegroundColor Red
    $saidaInno | Select-Object -Last 25 | ForEach-Object { Write-Host "  $_" }
    Write-Host "  comando: `"$iscc`" $($argumentos -join ' ')"
    Write-Host "  tudo em: $log"
    exit 1
}
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
$api = "$ApiBase/repos/$Repositorio"

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

    # arquivos grandes: o Invoke-RestMethod do Windows carrega tudo na memoria
    # e a conexao cai no meio. O curl.exe (vem no Windows 10/11) manda em
    # partes e tenta de novo. O arquivo sobe com um nome provisorio e so
    # depois troca de lugar com o antigo, entao uma falha nao deixa a
    # release sem o arquivo.
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    function Enviar-Arquivo($arquivo, $nome) {
        $url = "$UploadBase/repos/$Repositorio/releases/$($release.id)/assets?name=$nome"
        if ($curl) {
            $saidaCurl = & $curl.Source -sS --fail-with-body --retry 3 --retry-delay 5 --connect-timeout 30 `
                -X POST -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" `
                -H "User-Agent: mythos-instalador" -H "Content-Type: application/octet-stream" `
                -T $arquivo $url 2>&1
            if ($LASTEXITCODE -ne 0) { throw "curl falhou ($LASTEXITCODE): $saidaCurl" }
            return ($saidaCurl | Out-String | ConvertFrom-Json)
        }
        return Invoke-RestMethod -Method Post -Headers $cabecalhos -Uri $url -InFile $arquivo -ContentType "application/octet-stream" -TimeoutSec 3600
    }

    foreach ($item in $enviar) {
        $provisorio = "enviando-$($item.Nome)"
        $release = Invoke-RestMethod -Headers $cabecalhos -Uri "$api/releases/$($release.id)"
        foreach ($velho in @($release.assets | Where-Object { $_.name -eq $provisorio })) {
            Invoke-RestMethod -Method Delete -Headers $cabecalhos -Uri "$api/releases/assets/$($velho.id)" | Out-Null
        }
        $tamanho = [math]::Round((Get-Item $item.Arquivo).Length / 1MB, 1)
        $novo = $null
        for ($tentativa = 1; $tentativa -le 3 -and -not $novo; $tentativa++) {
            Info "enviando $($item.Nome) ($tamanho MB), tentativa $tentativa..."
            try {
                $novo = Enviar-Arquivo $item.Arquivo $provisorio
            } catch {
                Info "  falhou: $($_.Exception.Message)"
                # um envio quebrado deixa um arquivo pela metade com o nome provisorio
                $release = Invoke-RestMethod -Headers $cabecalhos -Uri "$api/releases/$($release.id)"
                foreach ($velho in @($release.assets | Where-Object { $_.name -eq $provisorio })) {
                    Invoke-RestMethod -Method Delete -Headers $cabecalhos -Uri "$api/releases/assets/$($velho.id)" | Out-Null
                }
                if ($tentativa -lt 3) { Start-Sleep -Seconds 10 }
            }
        }
        if (-not $novo) { throw "nao consegui enviar o $($item.Nome) depois de 3 tentativas" }
        foreach ($velho in @($release.assets | Where-Object { $_.name -eq $item.Nome })) {
            Invoke-RestMethod -Method Delete -Headers $cabecalhos -Uri "$api/releases/assets/$($velho.id)" | Out-Null
        }
        $corpo = @{ name = $item.Nome } | ConvertTo-Json
        Invoke-RestMethod -Method Patch -Headers $cabecalhos -Uri "$api/releases/assets/$($novo.id)" -Body $corpo -ContentType "application/json" | Out-Null
        Info "  $($item.Nome) no ar"
    }
} catch {
    Write-Host ""
    Write-Host "Nao consegui mandar o instalador para o GitHub: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Para tentar de novo sem compilar, rode o montar-instalador.bat."
    Write-Host "Ou mande a mao os arquivos de $Dist em https://github.com/$Repositorio/releases (release '$Tag')"
    exit 0
}

Write-Host ""
Write-Host "Instalador no ar!" -ForegroundColor Green
Info "https://github.com/$Repositorio/releases/download/$Tag/$saida.exe"
