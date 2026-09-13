Import-Module "$PSScriptRoot\..\tools\LinuxImage\CSweet.LinuxImage.psd1" -Force

InModuleScope CSweet.LinuxImage {
    Describe 'Shared Linux image provisioning' {
        BeforeEach {
            $script:fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:imageProfile = Join-Path $script:fixture 'profile'
            $script:artifacts = Join-Path $script:fixture 'artifacts'
            $script:output = Join-Path $script:fixture 'image.vhdx'
            $script:calls = @()
            New-Item -ItemType Directory -Path $script:imageProfile, "$script:artifacts/tools/packer-1.15.4" -Force | Out-Null
            Set-Content -LiteralPath "$script:imageProfile/user-data.pkrtpl" -Value 'key: ${ssh_public_key}'
            Set-Content -LiteralPath "$script:imageProfile/provision-guest.sh" -Value '# guest profile'
            Set-Content -LiteralPath "$script:artifacts/tools/packer-1.15.4/packer.exe" -Value 'test tool, never executed'
            Mock Assert-ImageHost {}
            Mock New-ImageSeed { Set-Content -LiteralPath $OutputPath -Value 'seed fixture' }
            Mock Invoke-CSweetDownload {
                if ($OutFile) { [IO.File]::WriteAllText($OutFile, 'verified iso fixture'); return }
                $digest = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('verified iso fixture'))).Replace('-','').ToLowerInvariant()
                return ($digest + '  ubuntu-24.04.4-live-server-amd64.iso')
            }
            Mock Invoke-ImageTool {
                $script:calls += ,@($Arguments)
                if ($Executable -like '*ssh-keygen.exe') {
                    Set-Content -LiteralPath ($Arguments[-1] + '.pub') -Value 'ssh-ed25519 fixture-public-key'
                    Set-Content -LiteralPath $Arguments[-1] -Value 'fixture-private-key'
                }
                if ($Arguments[0] -eq 'build') {
                    $directory = ($Arguments | Where-Object { $_ -like '-var=output_directory=*' }).Substring(22)
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    Set-Content -LiteralPath "$directory/guest.vhdx" -Value 'built disk fixture'
                }
            }
            $script:prepare = { param($payload) Set-Content -LiteralPath "$payload/guest" -Value 'guest fixture' }
        }

        It 'builds either workload profile through the same validated pipeline and returns the disk digest' {
            foreach ($service in @('csweet-agent-guest.service', 'csweet-compute-guest.service')) {
                $result = New-CSweetLinuxHyperVImage -ProfileDirectory $script:imageProfile -PreparePayload $script:prepare `
                    -GuestServiceName $service -ArtifactDirectory $script:artifacts -OutputPath "$script:output-$service.vhdx" -ReportProgress {}
                $result.GuestService | Should Be $service
                $result.Sha256 | Should Be (Get-FileHash -LiteralPath $result.ImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
                ($script:calls[-1] -contains "-var=guest_service=$service") | Should Be $true
                $script:calls[-2][0] | Should Be 'validate'
            }
            @(Get-ChildItem -LiteralPath $script:artifacts -Filter 'packer_ed25519*' -Recurse).Count | Should Be 0
        }

        It 'keeps the actual nested Hyper-V export path below the Windows path limit' {
            New-CSweetLinuxHyperVImage -ProfileDirectory $script:imageProfile -PreparePayload $script:prepare -GuestServiceName 'guest.service' -ArtifactDirectory $script:artifacts -OutputPath $script:output -ReportProgress {} | Out-Null
            $name = ($script:calls[-1] | Where-Object { $_ -like '-var=vm_name=*' }).Substring(13)
            $directory = ($script:calls[-1] | Where-Object { $_ -like '-var=output_directory=*' }).Substring(22)
            $exportDisk = Join-Path $directory ($name + '\Virtual Hard Disks\' + $name + '.vhdx')
            ($name.Length -le 20) | Should Be $true
            ($exportDisk.Length -lt 240) | Should Be $true
        }
        It 'refuses to overwrite an existing image before invoking the host or payload' {
            Set-Content -LiteralPath $script:output -Value 'existing Office image'
            { New-CSweetLinuxHyperVImage -ProfileDirectory $script:imageProfile -PreparePayload { throw 'must not run' } `
                -GuestServiceName 'guest.service' -ArtifactDirectory $script:artifacts -OutputPath $script:output } | Should Throw 'already exists'
            (Get-Content -LiteralPath $script:output -Raw).Trim() | Should Be 'existing Office image'
            Assert-MockCalled Assert-ImageHost -Times 0 -Exactly -Scope It
        }

        It 'fails before provisioning for a malformed profile' {
            Remove-Item -LiteralPath "$script:imageProfile/provision-guest.sh"
            { New-CSweetLinuxHyperVImage -ProfileDirectory $script:imageProfile -PreparePayload $script:prepare `
                -GuestServiceName 'guest.service' -ArtifactDirectory $script:artifacts -OutputPath $script:output } | Should Throw 'Missing image profile'
            Assert-MockCalled Assert-ImageHost -Times 0 -Exactly -Scope It
        }

        It 'does not build after validation failure and restores environment and temporary keys' {
            $beforePlugin = $env:PACKER_PLUGIN_PATH
            $beforeCache = $env:PACKER_CACHE_DIR
            Mock Invoke-ImageTool { throw 'invalid Packer plan' } -ParameterFilter { $Arguments[0] -eq 'validate' }
            { New-CSweetLinuxHyperVImage -ProfileDirectory $script:imageProfile -PreparePayload $script:prepare `
                -GuestServiceName 'guest.service' -ArtifactDirectory $script:artifacts -OutputPath $script:output -ReportProgress {} } | Should Throw 'invalid Packer plan'
            Test-Path -LiteralPath $script:output | Should Be $false
            $env:PACKER_PLUGIN_PATH | Should Be $beforePlugin
            $env:PACKER_CACHE_DIR | Should Be $beforeCache
            @(Get-ChildItem -LiteralPath $script:artifacts -Filter 'packer_ed25519*' -Recurse).Count | Should Be 0
            Assert-MockCalled Invoke-ImageTool -Times 0 -Exactly -Scope It -ParameterFilter { $Arguments[0] -eq 'build' }
            $lock = [IO.File]::Open("$script:artifacts/image-build.lock", 'Open', 'ReadWrite', 'None')
            $lock.Dispose()
        }

        It 'rejects a concurrent build without running its payload' {
            $lock = [IO.File]::Open("$script:artifacts/image-build.lock", 'OpenOrCreate', 'ReadWrite', 'None')
            try {
                { New-CSweetLinuxHyperVImage -ProfileDirectory $script:imageProfile -PreparePayload { throw 'must not run' } `
                    -GuestServiceName 'guest.service' -ArtifactDirectory $script:artifacts -OutputPath $script:output } | Should Throw
                Assert-MockCalled Invoke-ImageTool -Times 0 -Exactly -Scope It
            } finally { $lock.Dispose() }
        }

        It 'requires an exact official image checksum' {
            Mock Invoke-CSweetDownload { return (('a' * 64) + '  different.iso') }
            { New-CSweetLinuxHyperVImage -ProfileDirectory $script:imageProfile -PreparePayload $script:prepare `
                -GuestServiceName 'guest.service' -ArtifactDirectory $script:artifacts -OutputPath $script:output -ReportProgress {} } | Should Throw 'checksum'
            Assert-MockCalled Invoke-ImageTool -Times 0 -Exactly -Scope It -ParameterFilter { $Arguments[0] -eq 'build' }
        }
    }
}
