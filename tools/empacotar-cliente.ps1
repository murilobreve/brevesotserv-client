# Baiak Breves - monta a pasta do client para download e gera o .zip
#
# Uso (normalmente pelo empacotar-cliente.bat, na raiz do projeto):
#   powershell -ExecutionPolicy Bypass -File tools\empacotar-cliente.ps1
# Opcoes:
#   -Exe <caminho>   executavel a usar (padrao: otclient.exe da raiz)
#   -SemAssets       nao inclui data\things e data\sounds (o client baixa
#                    os assets sozinho na primeira vez que abrir)
#
# Resultado:
#   dist\Baiak Breves\    pasta pronta para jogar
#   dist\BaiakBreves.zip  essa mesma pasta zipada, para o site
param(
    [string]$Exe = "",
    [switch]$SemAssets
)

$ErrorActionPreference = "Stop"

$Nome = "Baiak Breves"
$ZipNome = "BaiakBreves.zip"

$Raiz = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Raiz "dist"
$Pasta = Join-Path $Dist $Nome
$Zip = Join-Path $Dist $ZipNome

function Info($msg) { Write-Host "  $msg" }

# ---------------------------------------------------------------- executavel
if ($Exe -eq "") {
    $candidatos = @(Get-ChildItem -Path $Raiz -File -Filter "*.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "otclient*.exe" } |
        Sort-Object LastWriteTime -Descending)
    if ($candidatos.Count -eq 0) {
        Write-Host ""
        Write-Host "ERRO: nao achei o otclient.exe na raiz do projeto ($Raiz)." -ForegroundColor Red
        Write-Host "Compile o client antes (ele gera o otclient.exe na raiz) ou use -Exe <caminho>."
        exit 1
    }
    $Exe = $candidatos[0].FullName
}
if (-not (Test-Path $Exe)) {
    Write-Host "ERRO: executavel nao encontrado: $Exe" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Montando '$Nome' em $Pasta"
Info "executavel: $Exe"

# ---------------------------------------------------------------- pasta limpa
if (Test-Path $Pasta) {
    # desktop.ini / pasta com atributo de sistema: limpa os atributos antes
    Get-ChildItem -Path $Pasta -Force -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
    try { (Get-Item $Pasta -Force).Attributes = 'Directory' } catch {}
    Remove-Item -Path $Pasta -Recurse -Force
}
New-Item -ItemType Directory -Path $Pasta -Force | Out-Null

# ---------------------------------------------------------------- arquivos
Copy-Item -Path $Exe -Destination (Join-Path $Pasta "$Nome.exe")

# DLLs ao lado do exe (so existem em builds dinamicos)
Get-ChildItem -Path (Split-Path -Parent $Exe) -File -Filter "*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item -Path $_.FullName -Destination $Pasta; Info "dll: $($_.Name)" }

foreach ($arquivo in @("init.lua", "config.ini", "servidor.ini", "cacert.pem")) {
    $origem = Join-Path $Raiz $arquivo
    if (Test-Path $origem) {
        Copy-Item -Path $origem -Destination $Pasta
    } else {
        Info "aviso: $arquivo nao existe, pulando"
    }
}

# pastas do client; logs, configuracoes e arquivos de git ficam de fora
$ignorar = @(".gitignore", ".gitkeep", "*.log", "config.otml")
foreach ($dir in @("data", "modules", "mods")) {
    $origem = Join-Path $Raiz $dir
    if (-not (Test-Path $origem)) { continue }
    $destino = Join-Path $Pasta $dir
    Copy-Item -Path $origem -Destination $destino -Recurse
    foreach ($padrao in $ignorar) {
        Get-ChildItem -Path $destino -Recurse -Force -File -Filter $padrao -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }
}

$things = Join-Path $Pasta "data\things"
$sounds = Join-Path $Pasta "data\sounds"
if ($SemAssets) {
    foreach ($d in @($things, $sounds)) {
        # data\things\custom holds the server's own assets (custom mount): keep it
        Get-ChildItem -Path $d -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "custom" } | Remove-Item -Recurse -Force
    }
    Info "assets fora do pacote (o client baixa na primeira vez)"
} else {
    $temAssets = @(Get-ChildItem -Path $things -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "README.md" -and $_.FullName -notlike "*\things\custom\*" }).Count -gt 0
    if ($temAssets) {
        Info "assets incluidos (data\things)"
    } else {
        Info "sem assets em data\things: o client baixa na primeira vez que abrir"
    }
}

# ---------------------------------------------------------------- icone
$icone = Join-Path $Raiz "cmake\icon\otcicon.ico"
if (Test-Path $icone) {
    Copy-Item -Path $icone -Destination (Join-Path $Pasta "icone.ico")
}

# desktop.ini: faz a pasta mostrar o icone no Windows Explorer
$desktopIni = Join-Path $Pasta "desktop.ini"
Set-Content -Path $desktopIni -Encoding Unicode -Value @(
    "[.ShellClassInfo]",
    "IconResource=icone.ico,0",
    "IconFile=icone.ico",
    "IconIndex=0",
    "InfoTip=$Nome"
)

# ---------------------------------------------------------------- leia-me
Set-Content -Path (Join-Path $Pasta "LEIA-ME.txt") -Encoding UTF8 -Value @(
    "$Nome",
    "",
    "Como jogar:",
    "  1. Extraia esta pasta para onde quiser (Area de Trabalho, Documentos...).",
    "     Evite 'Arquivos de Programas': o client precisa gravar arquivos na pasta.",
    "  2. Abra '$Nome.exe'.",
    "  3. Na primeira vez o client pode baixar os arquivos do jogo; aguarde.",
    "",
    "Trocar o servidor (IP):",
    "  Abra 'servidor.ini' no Bloco de Notas, mude a linha 'ip = ...' e salve."
)

# ---------------------------------------------------------------- atributos (so Windows)
$ehWindows = ($env:OS -eq "Windows_NT")
if ($ehWindows) {
    # o Windows so le o desktop.ini se a pasta tiver o atributo ReadOnly/System
    (Get-Item $desktopIni -Force).Attributes = 'Hidden, System'
    (Get-Item (Join-Path $Pasta "icone.ico") -Force).Attributes = 'Hidden'
    $dirItem = Get-Item $Pasta -Force
    $dirItem.Attributes = $dirItem.Attributes -bor [System.IO.FileAttributes]::ReadOnly
}

# ---------------------------------------------------------------- zip
if (Test-Path $Zip) { Remove-Item -Path $Zip -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipStream = [System.IO.File]::Open($Zip, [System.IO.FileMode]::CreateNew)
$arquivoZip = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $base = (Resolve-Path $Dist).Path.TrimEnd('\', '/')
    Get-ChildItem -Path $Pasta -Recurse -Force -File | ForEach-Object {
        # caminho dentro do zip sempre com "/" (funciona em qualquer extrator)
        $relativo = $_.FullName.Substring($base.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $arquivoZip, $_.FullName, $relativo, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $arquivoZip.Dispose()
    $zipStream.Dispose()
}

$tamanhoMb = [math]::Round((Get-Item $Zip).Length / 1MB, 1)
Write-Host ""
Write-Host "Pronto!" -ForegroundColor Green
Info "pasta: $Pasta"
Info "zip  : $Zip ($tamanhoMb MB)"
Write-Host ""
Write-Host "Suba o $ZipNome na pagina de downloads do site."
