param(
    [string]$Configuration = "Release",
    [string]$ArtifactName = "Noboard-Windows-x64-preview"
)

$ErrorActionPreference = "Stop"
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$project = Join-Path $windowsRoot "src\AkangVoiceInput.App\AkangVoiceInput.App.csproj"
$artifactsRoot = Join-Path $windowsRoot "artifacts"
$publishDirectory = Join-Path $artifactsRoot "win-x64"
$archive = Join-Path $artifactsRoot "$ArtifactName.zip"
$checksum = "$archive.sha256"

$resolvedArtifactsRoot = [IO.Path]::GetFullPath($artifactsRoot)
$resolvedPublishDirectory = [IO.Path]::GetFullPath($publishDirectory)
if (-not $resolvedPublishDirectory.StartsWith($resolvedArtifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean a publish directory outside windows/artifacts."
}

New-Item -ItemType Directory -Force -Path $artifactsRoot | Out-Null
if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}
if (Test-Path -LiteralPath $checksum) {
    Remove-Item -LiteralPath $checksum -Force
}

dotnet publish $project `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output $publishDirectory `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

Compress-Archive -Path (Join-Path $publishDirectory "*") -DestinationPath $archive -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksum -Value "$hash  $([IO.Path]::GetFileName($archive))" -Encoding ascii

Write-Output "Archive: $archive"
Write-Output "SHA256: $hash"
