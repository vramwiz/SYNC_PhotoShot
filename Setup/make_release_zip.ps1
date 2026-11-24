param(
    [string]$ReleaseDirectory,
    [string]$XxhsumPath
)

# SYNC_ParticleFX / SYNC_Mine由来。既存AUF2の梱包と末尾バージョンのハッシュ更新。
# ビルド・ホスト起動・ネットワークへの公開は行わない。
# Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
$ErrorActionPreference = 'Stop'
$packageName = 'SYNC_PhotoShot'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseDirectory) { $ReleaseDirectory = 'C:\ProgramData\aviutl2\Plugin\SYNC_PhotoShot' }
$pluginName = "$packageName.auf2"
$pluginPath = Join-Path $ReleaseDirectory $pluginName
if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "Release plugin not found: $pluginPath. Build the Win64 Release configuration first."
}

if (-not $XxhsumPath) {
    $XxhsumPath = Join-Path $projectDir 'Win64\Dependencies\xxHash-0.8.4\xxhsum.exe'
    if (-not (Test-Path -LiteralPath $XxhsumPath -PathType Leaf)) {
        $xxhsum = Get-Command xxhsum.exe -CommandType Application -ErrorAction SilentlyContinue
        if (-not $xxhsum) { throw 'xxhsum.exe is required. See setup\README.md.' }
        $XxhsumPath = $xxhsum.Source
    }
}
$XxhsumPath = (Resolve-Path -LiteralPath $XxhsumPath).ProviderPath

$catalogPath = Join-Path $PSScriptRoot "$packageName.catalog.json"
$zipPath = Join-Path $PSScriptRoot "$packageName.zip"
$tempBase = Join-Path $PSScriptRoot ('.release-' + [guid]::NewGuid().ToString('N'))
$tempPlugin = "$tempBase-plugin.tmp"
$tempZip = "$tempBase-zip.tmp"
$tempCatalog = "$tempBase-catalog.tmp"
$catalogBackup = "$tempBase-previous-catalog.tmp"
$packageFiles = [ordered]@{
    $pluginName = $tempPlugin
    'README.md' = Join-Path $PSScriptRoot 'README.md'
    'LICENSE.md' = Join-Path $projectDir 'LICENSE.md'
    'THIRD_PARTY_NOTICES.md' = Join-Path $projectDir 'THIRD_PARTY_NOTICES.md'
    'Source/Lib/Smartphone/LICENSE.SYNC_Mine.txt' = Join-Path $projectDir 'Source\Lib\Smartphone\LICENSE.SYNC_Mine.txt'
    'ThirdParty/LICENSE.AviUtl2-SDK.txt' = Join-Path $projectDir 'ThirdParty\LICENSE.AviUtl2-SDK.txt'
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class PhotoShotReleaseResources
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(string file, IntPtr handle, uint flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindResource(IntPtr module, string name, IntPtr type);

    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr module);

    public static bool ContainsLegacyShutterResource(string file)
    {
        // Read the resource directory without running the DLL.
        const uint LoadAsDataFile = 0x00000002;
        const uint LoadAsImageResource = 0x00000020;
        IntPtr module = LoadLibraryEx(file, IntPtr.Zero, LoadAsDataFile | LoadAsImageResource);
        if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            string[] names = { "PHOTOSHOT_SMARTPHONE", "PHOTOSHOT_COMPACT",
                               "PHOTOSHOT_DSLR", "PHOTOSHOT_INSTANT" };
            foreach (string name in names)
                if (FindResource(module, name, (IntPtr)10) != IntPtr.Zero) return true;
            return false;
        }
        finally { FreeLibrary(module); }
    }
}
'@
$lock = [Threading.Mutex]::new($false, 'Local\VRAMWIZ.SYNC_PhotoShot.ReleaseZip')
$ownsLock = $false
try {
    try { $ownsLock = $lock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw 'Another release ZIP is being created. Run the batch again.' }

    $catalogSource = [IO.File]::ReadAllText($catalogPath)
    $catalog = [object[]]($catalogSource | ConvertFrom-Json)
    if (-not $catalogSource.TrimStart().StartsWith('[') -or $catalog.Count -ne 1 -or
        $catalog[0].id -cne "VRAMWIZ.$packageName" -or $catalog[0].name -cne '写真撮影') {
        throw 'The catalog must be an array containing the PhotoShot package once.'
    }
    $source = $catalog[0].installer.source.github
    if ($source.owner -cne 'vramwiz' -or $source.repo -cne $packageName -or
        $source.pattern -cne '^SYNC_PhotoShot\.zip$') {
        throw 'The catalog must download SYNC_PhotoShot.zip from vramwiz/SYNC_PhotoShot.'
    }
    $install = @($catalog[0].installer.install)
    if ($install.Count -ne 3 -or $install[0].action -cne 'download' -or
        $install[1].action -cne 'extract' -or $install[2].action -cne 'copy' -or
        $install[2].from -cne "{tmp}/$packageName" -or
        $install[2].to -cne "{pluginsDir}/$packageName") {
        throw 'The catalog install destination does not match the ZIP layout.'
    }
    # ユーザーデータを巻き込まないよう、同梱したファイルだけを削除対象にする。
    $expectedUninstall = @($packageFiles.Keys | ForEach-Object { "{pluginsDir}/$packageName/$_" })
    $uninstall = @($catalog[0].installer.uninstall)
    if ($uninstall.Count -ne $expectedUninstall.Count -or
        @($uninstall | Where-Object action -cne 'delete').Count -ne 0 -or
        @(Compare-Object $expectedUninstall @($uninstall.path) -CaseSensitive).Count -ne 0) {
        throw 'The catalog uninstall files do not match the ZIP contents.'
    }
    if (@($catalog[0].version).Count -eq 0) { throw 'The catalog has no release version.' }
    $version = $catalog[0].version[-1]
    if (-not $version.version -or $version.release_date -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw 'Set a release tag and YYYY-MM-DD release_date in the last catalog version.'
    }
    [datetime]::ParseExact($version.release_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) | Out-Null
    $pluginEntry = @($version.file | Where-Object path -ceq "{pluginsDir}/$packageName/$pluginName")
    if ($pluginEntry.Count -ne 1) { throw 'The last catalog version must list the installed AUF2 once.' }

    # ハッシュとZIPには同じコピーを使い、処理中の再ビルドによる不一致を防ぐ。
    Copy-Item -LiteralPath $pluginPath -Destination $tempPlugin
    if ([PhotoShotReleaseResources]::ContainsLegacyShutterResource($tempPlugin)) {
        throw 'The AUF2 contains legacy MP3 shutter resources. Build the current Win64 Release before packaging.'
    }
    $hashOutput = & $XxhsumPath -H128 --tag $tempPlugin
    if ($LASTEXITCODE -ne 0 -or ($hashOutput -join "`n") -notmatch ' = ([0-9a-f]{32})\s*\z') {
        throw 'Could not calculate the AUF2 XXH3-128 hash.'
    }
    $hash = $Matches[1].ToLowerInvariant()

    foreach ($file in $packageFiles.Values) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Package file not found: $file" }
    }
    $zip = [IO.Compression.ZipFile]::Open($tempZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $packageFiles.GetEnumerator()) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.Value, "$packageName/$($file.Key)", [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally { $zip.Dispose() }

    if ([IO.File]::ReadAllText($catalogPath) -cne $catalogSource) {
        throw 'Catalog changed during packaging. Run the batch again.'
    }
    if ($pluginEntry[0].XXH3_128 -cne $hash) {
        $pluginEntry[0].XXH3_128 = $hash
        $json = ConvertTo-Json -InputObject $catalog -Depth 12
        [IO.File]::WriteAllText($tempCatalog, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($tempCatalog, $catalogPath, $catalogBackup)
    }
    try {
        if ([IO.File]::Exists($zipPath)) { [IO.File]::Replace($tempZip, $zipPath, [NullString]::Value) }
        else { [IO.File]::Move($tempZip, $zipPath) }
    }
    catch {
        if ([IO.File]::Exists($catalogBackup)) {
            [IO.File]::Replace($catalogBackup, $catalogPath, [NullString]::Value)
        }
        throw
    }
    if ([IO.File]::Exists($catalogBackup)) { [IO.File]::Delete($catalogBackup) }
}
finally {
    if ($ownsLock) { $lock.ReleaseMutex() }
    $lock.Dispose()
    foreach ($tempPath in @($tempPlugin, $tempZip, $tempCatalog)) {
        [IO.File]::Delete($tempPath)
    }
}

Write-Output "Created $zipPath"
Write-Output "Catalog $catalogPath ($($version.version), XXH3_128=$hash)"
