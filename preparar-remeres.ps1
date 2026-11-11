# Mythos - monta a pasta remeres-cliente\ que o Canary Map Editor (Remere's,
# repositorio murilobreve/remerescanary) pede como "Client directory": uma
# pasta com package.json e assets\ (catalog-content.json, appearances e os
# sprites). Junta os sprites do 15.25 (data\things\1525) com os itens
# proprios do Mythos (data\things\custom), para o editor mostrar tudo que
# o mapa usa. Rodado pelo preparar-remeres.bat.
$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot
$base = Join-Path $raiz "data\things\1525"
$custom = Join-Path $raiz "data\things\custom"
$saida = Join-Path $raiz "remeres-cliente"
$assets = Join-Path $saida "assets"

if (Test-Path $assets) { Remove-Item $assets -Recurse -Force }
New-Item -ItemType Directory -Force $assets | Out-Null

$catalogo = New-Object System.Collections.ArrayList
[void]$catalogo.Add([ordered]@{ type = "appearances"; file = "appearances-mythos.dat" })
$aparencias = New-Object IO.MemoryStream
foreach ($pasta in @($base, $custom)) {
    Write-Host "== copiando $pasta"
    $lista = Get-Content (Join-Path $pasta "catalog-content.json") -Raw | ConvertFrom-Json
    foreach ($e in $lista) {
        if ($e.type -eq "sprite") {
            [void]$catalogo.Add([ordered]@{ type = "sprite"; file = $e.file; spritetype = $e.spritetype; firstspriteid = $e.firstspriteid; lastspriteid = $e.lastspriteid; area = $e.area })
        } elseif ($e.type -eq "appearances") {
            # protobuf: dois arquivos de appearances colados viram um so com os itens dos dois
            $bytes = [IO.File]::ReadAllBytes((Join-Path $pasta $e.file))
            $aparencias.Write($bytes, 0, $bytes.Length)
        }
    }
    Copy-Item (Join-Path $pasta "sprites-*.bmp.lzma") $assets
}
[IO.File]::WriteAllBytes((Join-Path $assets "appearances-mythos.dat"), $aparencias.ToArray())
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $assets "catalog-content.json"), (ConvertTo-Json @($catalogo) -Depth 3), $utf8)
[IO.File]::WriteAllText((Join-Path $saida "package.json"), '{ "version": "15.25" }', $utf8)

$n = (Get-ChildItem $assets -Filter "sprites-*.bmp.lzma").Count
Write-Host ""
Write-Host "Pronto: $saida ($n folhas de sprites)."
Write-Host "No editor: File > Preferences > Client Version > Client directory = esta pasta."
