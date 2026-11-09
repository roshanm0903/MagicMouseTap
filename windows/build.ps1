$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$artifacts = Join-Path $root "artifacts"

dotnet run --project (Join-Path $root "MagicMouseTap.Tests\MagicMouseTap.Tests.csproj") -c Release
dotnet publish (Join-Path $root "MagicMouseTap.App\MagicMouseTap.App.csproj") `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -o (Join-Path $artifacts "win-x64")

Write-Host "Windows build: $artifacts\win-x64\MagicMouseTap.exe"
