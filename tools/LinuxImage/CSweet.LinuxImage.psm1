# Installer-owned image provisioning; never expose script blocks or host paths to agents.
Set-StrictMode -Version Latest

function Invoke-ImageTool {
    param([string] $Executable, [string[]] $Arguments)
    & $Executable @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Image build tool failed with exit code $LASTEXITCODE." }
}

function Get-ImageChecksum {
    param([string] $Text, [string] $FileName)
    $match = [regex]::Match($Text, ('(?im)^([0-9a-f]{64})\s+\*?' + [regex]::Escape($FileName) + '\s*$'))
    if (-not $match.Success) { throw "The published checksum for $FileName was not found." }
    return $match.Groups[1].Value.ToLowerInvariant()
}

function Invoke-CSweetDownload {
    param([uri] $Uri, [string] $Purpose, [string] $OutFile)
    try {
        if ($OutFile) { Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile; return }
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri
        if ($response.Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($response.Content) }
        return [string]$response.Content
    } catch { throw "$Purpose could not be downloaded from $($Uri.GetLeftPart([UriPartial]::Authority)). $($_.Exception.Message)" }
}

function Assert-ImageHost {
    param([string] $SwitchName)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run the Linux image builder from an Administrator PowerShell prompt.'
    }
    Import-Module Hyper-V -ErrorAction Stop
    if ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -ne 'Enabled') { throw 'Enable Hyper-V and restart Windows before building an image.' }
    if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) { throw "Hyper-V switch '$SwitchName' does not exist." }

}

function New-ImageSeed {
    param([string] $SourceDirectory, [string] $OutputPath)
    & (Join-Path $PSScriptRoot 'New-CSweetNoCloudSeedIso.ps1') -SourceDirectory $SourceDirectory -OutputPath $OutputPath | Out-Null
}

function New-CSweetLinuxHyperVImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProfileDirectory,
        [Parameter(Mandatory)][scriptblock] $PreparePayload,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+\.service$')][string] $GuestServiceName,
        [Parameter(Mandatory)][string] $ArtifactDirectory,
        [Parameter(Mandatory)][string] $OutputPath,
        [string] $SwitchName = 'Default Switch',
        [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string] $UbuntuVersion = '24.04.4',
        [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string] $PackerVersion = '1.15.4',
        [scriptblock] $ReportProgress = { param($phase, $message) Write-Host $message }
    )
    $ErrorActionPreference = 'Stop'
    $output = [IO.Path]::GetFullPath($OutputPath)
    if ([IO.Path]::GetExtension($output) -ine '.vhdx') { throw 'OutputPath must name a VHDX file.' }
    # Never replace an existing template, including one belonging to Office.
    if (Test-Path -LiteralPath $output) { throw 'The image already exists. Choose a new output path.' }
    $imageProfileDirectory = (Resolve-Path -LiteralPath $ProfileDirectory).Path
    foreach ($file in @('user-data.pkrtpl', 'provision-guest.sh')) {
        if (-not (Test-Path -LiteralPath (Join-Path $imageProfileDirectory $file) -PathType Leaf)) { throw "Missing image profile file: $file" }
    }
    Assert-ImageHost -SwitchName $SwitchName

    $artifactRoot = [IO.Path]::GetFullPath($ArtifactDirectory)
    $toolRoot = Join-Path $artifactRoot 'tools'
    $cacheRoot = Join-Path $artifactRoot 'cache'
    New-Item -ItemType Directory -Path $toolRoot, $cacheRoot -Force | Out-Null
    # Shared cache preparation and builds have one owner. A concurrent request fails promptly.
    $buildLock = [IO.File]::Open((Join-Path $artifactRoot 'image-build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $runRoot = Join-Path $artifactRoot ('image-' + [guid]::NewGuid().ToString('N'))
    $payload = Join-Path $runRoot 'payload'
    $seed = Join-Path $runRoot 'seed'
    $key = Join-Path $runRoot 'packer_ed25519'
    $seedIso = Join-Path $runRoot 'cidata.iso'
    $packerOutput = Join-Path $runRoot 'out'
    $vmName = 'csw-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
    $exportDisk = Join-Path $packerOutput ($vmName + '\Virtual Hard Disks\' + $vmName + '.vhdx')
    if ($exportDisk.Length -ge 240) { $buildLock.Dispose(); throw 'The image build directory is too long for Hyper-V export.' }
    $oldPluginPath = $env:PACKER_PLUGIN_PATH
    $oldCachePath = $env:PACKER_CACHE_DIR
    try {
        New-Item -ItemType Directory -Path $payload, $seed -Force | Out-Null
        $sshKeygen = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe'
        if (-not (Test-Path -LiteralPath $sshKeygen -PathType Leaf)) {
            & $ReportProgress 'install-openssh' 'Installing the temporary image-build SSH client.'
            $capability = Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0'
            if ($capability.RestartNeeded) { throw 'Restart Windows after installing the OpenSSH client.' }
        }
        $packerRoot = Join-Path $toolRoot "packer-$PackerVersion"
        $packer = Join-Path $packerRoot 'packer.exe'
        if (-not (Test-Path -LiteralPath $packer -PathType Leaf)) {
            & $ReportProgress 'download-packer' 'Downloading and verifying the pinned Packer image builder.'
            $archiveName = "packer_${PackerVersion}_windows_amd64.zip"
            $archivePath = Join-Path $cacheRoot $archiveName
            $baseUrl = "https://releases.hashicorp.com/packer/$PackerVersion"
            $checksums = Invoke-CSweetDownload -Uri "$baseUrl/packer_${PackerVersion}_SHA256SUMS" -Purpose 'The published HashiCorp Packer checksums'
            $expected = Get-ImageChecksum $checksums $archiveName
            if (-not (Test-Path -LiteralPath $archivePath) -or (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
                Invoke-CSweetDownload -Uri "$baseUrl/$archiveName" -Purpose 'The pinned HashiCorp Packer archive' -OutFile $archivePath
            }
            if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) { throw 'The Packer archive failed SHA-256 verification.' }
            Expand-Archive -LiteralPath $archivePath -DestinationPath $packerRoot -Force
        }
        & $ReportProgress 'publish-guest' 'Preparing the Linux guest software.'
        & $PreparePayload $payload | Out-Host
        if (@(Get-ChildItem -LiteralPath $payload -File -Recurse).Count -eq 0) { throw 'The image profile produced no guest payload.' }
        # Windows PowerShell 5 drops empty native arguments; PowerShell 7 preserves them.
        $emptyPassphrase = if ($PSVersionTable.PSVersion.Major -ge 7) { '' } else { '""' }
        Invoke-ImageTool $sshKeygen @('-q', '-t', 'ed25519', '-N', $emptyPassphrase, '-f', $key)
        $publicKey = (Get-Content -LiteralPath "$key.pub" -Raw).Trim()
        if ($publicKey -notmatch '^ssh-ed25519\s+') { throw 'The temporary Packer public key is invalid.' }
        $userData = Get-Content -LiteralPath (Join-Path $imageProfileDirectory 'user-data.pkrtpl') -Raw
        if (-not $userData.Contains('${ssh_public_key}')) { throw 'The NoCloud profile is missing the SSH key placeholder.' }
        $utf8 = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText((Join-Path $seed 'user-data'), $userData.Replace('${ssh_public_key}', $publicKey), $utf8)
        [IO.File]::WriteAllText((Join-Path $seed 'meta-data'), "instance-id: csweet-linux-image`nlocal-hostname: csweet-linux-image`n", $utf8)
        New-ImageSeed -SourceDirectory $seed -OutputPath $seedIso
        if (-not (Test-Path -LiteralPath $seedIso -PathType Leaf)) { throw 'The NoCloud seed ISO was not created.' }
        & $ReportProgress 'resolve-ubuntu' 'Verifying the official Ubuntu installation image checksum.'
        $ubuntuFile = "ubuntu-$UbuntuVersion-live-server-amd64.iso"
        $ubuntuBase = "https://releases.ubuntu.com/$UbuntuVersion"
        $checksums = Invoke-CSweetDownload -Uri "$ubuntuBase/SHA256SUMS" -Purpose 'The published Ubuntu image checksums'
        $checksum = Get-ImageChecksum $checksums $ubuntuFile
        # Own the large download so Windows setup reports progress and retries do not depend on Packer's getter.
        $ubuntuIso = Join-Path $cacheRoot $ubuntuFile
        if (-not (Test-Path -LiteralPath $ubuntuIso -PathType Leaf) -or
            (Get-FileHash -LiteralPath $ubuntuIso -Algorithm SHA256).Hash -ine $checksum) {
            & $ReportProgress 'download-ubuntu' 'Downloading the official Ubuntu installation image.'
            Invoke-CSweetDownload -Uri "$ubuntuBase/$ubuntuFile" -Purpose 'The Ubuntu installation image' -OutFile $ubuntuIso
        }
        if ((Get-FileHash -LiteralPath $ubuntuIso -Algorithm SHA256).Hash -ine $checksum) { throw 'The Ubuntu installation image failed SHA-256 verification.' }
        $template = Join-Path $PSScriptRoot 'linux-guest.pkr.hcl'
        $env:PACKER_PLUGIN_PATH = Join-Path $toolRoot 'packer-plugins'
        $env:PACKER_CACHE_DIR = Join-Path $cacheRoot 'packer'
        New-Item -ItemType Directory -Path $env:PACKER_PLUGIN_PATH, $env:PACKER_CACHE_DIR -Force | Out-Null
        & $ReportProgress 'prepare-packer' 'Preparing the pinned Hyper-V image builder.'
        Invoke-ImageTool $packer @('init', $template)
        $variables = @(
            "-var=iso_url=$ubuntuIso", "-var=iso_checksum=sha256:$checksum",
            "-var=switch_name=$SwitchName", "-var=ssh_private_key_file=$key", "-var=seed_iso_path=$seedIso",
            "-var=payload_directory=$payload", "-var=provision_script=$imageProfileDirectory/provision-guest.sh",
            "-var=guest_service=$GuestServiceName", "-var=output_directory=$packerOutput",
            "-var=vm_name=$vmName"
        )
        Invoke-ImageTool $packer (@('validate') + $variables + @($template))
        & $ReportProgress 'build-guest' 'Ubuntu is installing in a Secure Boot VM. This can take 10-30 minutes.'
        Invoke-ImageTool $packer (@('build', '-color=false') + $variables + @($template))
        $disks = @(Get-ChildItem -LiteralPath $packerOutput -Filter '*.vhdx' -File -Recurse)
        if ($disks.Count -ne 1) { throw "Expected one built VHDX, but found $($disks.Count)." }
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($output)) -Force | Out-Null
        [IO.File]::Copy($disks[0].FullName, $output, $false)
        $digest = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
        & $ReportProgress 'guest-complete' "Linux image created: $output (sha256:$digest)"
        # A build receipt records bytes, not release certification or execution authority.
        [pscustomobject]@{ ImagePath = $output; Sha256 = $digest; UbuntuVersion = $UbuntuVersion; GuestService = $GuestServiceName }
    } finally {
        $env:PACKER_PLUGIN_PATH = $oldPluginPath
        $env:PACKER_CACHE_DIR = $oldCachePath
        try {
            foreach ($file in @($key, "$key.pub")) {
                if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
            }
        } finally { $buildLock.Dispose() }
    }
}
Export-ModuleMember -Function New-CSweetLinuxHyperVImage
