$sharedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositories = Split-Path -Parent $sharedRoot
Import-Module "$sharedRoot/tools/LinuxImage/CSweet.LinuxImage.psd1" -Force

Describe 'Office and compute image adapters' {
    BeforeEach {
        $global:csweetImageAdapterstage = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $global:csweetImageAdapterobservedService = $null
        $global:csweetImageAdapterobservedProfile = $null
        $global:csweetImageAdapterprojects = @()
        New-Item -ItemType Directory -Path $global:csweetImageAdapterstage | Out-Null
        Mock Import-Module {}
        Mock New-CSweetLinuxHyperVImage {
            $global:csweetImageAdapterobservedService = $GuestServiceName
            $global:csweetImageAdapterobservedProfile = $ProfileDirectory
            & $PreparePayload $global:csweetImageAdapterstage
            [pscustomobject]@{ ImagePath = (Join-Path $global:csweetImageAdapterstage 'test.vhdx'); Sha256 = ('a' * 64) }
        }
        function global:dotnet {
            $projectPath = [string]$args[1]
            $name = [IO.Path]::GetFileNameWithoutExtension($projectPath)
            $global:csweetImageAdapterprojects += $name
            $destination = [string]$args[([array]::IndexOf($args, '-o') + 1)]
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $destination $name) -Value 'published fixture'
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        Remove-Item Function:\global:dotnet -ErrorAction SilentlyContinue
        Remove-Variable -Name csweetImageAdapterstage,csweetImageAdapterobservedService,csweetImageAdapterobservedProfile,csweetImageAdapterprojects -Scope Global -ErrorAction SilentlyContinue
    }

    It 'stages all three Office guests and keeps the legacy output contract' {
        $result = & "$repositories/CSweet.Office/scripts/windows/New-CSweetHyperVTestGuest.ps1" -IsolationRoot $sharedRoot
        $result | Should Be (Join-Path $global:csweetImageAdapterstage 'test.vhdx')
        $global:csweetImageAdapterobservedService | Should Be 'csweet-agent-guest.service'
        $global:csweetImageAdapterobservedProfile | Should Be "$repositories\CSweet.Office\build\windows-hyperv"
        foreach ($guest in @('CSweet.Office.RuntimeGuest', 'CSweet.Office.BuilderGuest', 'CSweet.Office.ToolchainGuest')) {
            Test-Path -LiteralPath (Join-Path $global:csweetImageAdapterstage "$guest.bin") | Should Be $true
            $global:csweetImageAdapterprojects -contains $guest | Should Be $true
        }
    }

    It 'stages the compute guest and its installer and emits a build receipt' {
        $result = & "$repositories/csweet/scripts/New-ComputeLinuxImage.ps1" -IsolationRoot $sharedRoot
        $result | Should Be (Join-Path $global:csweetImageAdapterstage 'test.vhdx')
        $global:csweetImageAdapterobservedService | Should Be 'csweet-compute-guest.service'
        Test-Path -LiteralPath (Join-Path $global:csweetImageAdapterstage 'guest/CSweet.Compute.Guest') | Should Be $true
        Test-Path -LiteralPath (Join-Path $global:csweetImageAdapterstage 'Install-ComputeGuestLinux.sh') | Should Be $true
        $receipt = Get-Content -LiteralPath ($result + '.build.json') -Raw | ConvertFrom-Json
        $receipt.Sha256 | Should Be ('a' * 64)
        $global:csweetImageAdapterprojects.Count | Should Be 1
    }
}
