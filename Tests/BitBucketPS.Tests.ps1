#Requires -Modules PSScriptAnalyzer

Describe "BitbucketPS" {

    Import-Module (Join-Path $PSScriptRoot "../BitBucketPS") -Prefix "Bitbucket" -Force -ErrorAction Stop

    InModuleScope BitbucketPS {

        . "$PSScriptRoot/Shared.ps1"

        $projectRoot = "$PSScriptRoot/.."
        $moduleRoot = "$projectRoot/BitbucketPS"

        $manifestFile = "$moduleRoot/BitbucketPS.psd1"
        $changelogFile = if (Test-Path "$projectRoot/CHANGELOG.md") {
            "$projectRoot/CHANGELOG.md"
        }
        elseif (Test-Path "$moduleRoot/CHANGELOG.htm") {
            "$moduleRoot/CHANGELOG.htm"
        }
        $appveyorFile = if (Test-Path "$projectRoot/appveyor.yml") {
            "$projectRoot/appveyor.yml"
        }
        elseif (Test-Path "$projectRoot/../appveyor.yml") {
            "$projectRoot/../appveyor.yml"
        }

        Context "All required tests are present" {
            # We want to make sure that every .ps1 file in the Functions directory that isn't a Pester test has an associated Pester test.
            # This helps keep me honest and makes sure I'm testing my code appropriately.

            $publicFunctions = (Get-Module BitbucketPS).ExportedCommands.Keys

            It "Includes a test for each PowerShell public function in the module" {
                foreach ($function in $publicFunctions) {
                    $function = $function.Replace("Bitbucket","")
                    $expectedTestFile = Join-Path $PSScriptRoot "$function.Tests.ps1"
                    $expectedTestFile | Should Exist
                }
            }
            It "Includes a test for each PowerShell private function in the module" {
                $privateFunctionMissingTests = @()
                $functions = Get-Command -Module BitbucketPS | Where-Object {$_.name -notin $publicFunctions}
                foreach ($function in $functions.Name) {
                    $function = $function.Replace("Bitbucket","")
                    $expectedTestFile = Join-Path $PSScriptRoot "$function.Tests.ps1"
                    if (-not (Test-Path $expectedTestFile)) {
                        $privateFunctionMissingTests += $function
                    }
                }
                if ($privateFunctionMissingTests) {
                    Write-Warning ("It is recommended to have tests for the following private function:`n`t{0}" -f ($privateFunctionMissingTests -join "`n`t"))
                }
            }
        }

        Context "Manifest, changelog, and AppVeyor" {

            # These tests are...erm, borrowed...from the module tests from the Pester module.
            # I think they are excellent for sanity checking, and all credit for the following
            # tests goes to Dave Wyatt, the genius behind Pester.  I've just adapted them
            # slightly to match BitbucketPS.

            $manifest = $null
            foreach ($line in (Get-Content $changelogFile)) {
                if ($line -match "(?:version\:|\<h2.*?\>)(?<Version>(\d+\.){1,3}\d+)") {
                    $changelogVersion = $matches.Version
                    break
                }
            }

            foreach ($line in (Get-Content $appveyorFile)) {
                # (?<Version>()) - non-capturing group, but named Version. This makes it
                # easy to reference the inside group later.

                if ($line -match '^\D*(?<Version>(\d+\.){1,2}\d+).\{build\}') {
                    $appveyorVersion = $matches.Version
                    break
                }
            }

            It "Includes a valid manifest file" {
                {
                    $manifest = Test-ModuleManifest -Path $manifestFile -ErrorAction Stop -WarningAction SilentlyContinue
                } | Should Not Throw
            }

            # There is a bug that prevents Test-ModuleManifest from updating correctly when the manifest file changes. See here:
            # https://connect.microsoft.com/PowerShell/feedback/details/1541659/test-modulemanifest-the-psmoduleinfo-is-not-updated

            # As a temp workaround, we'll just read the manifest as a raw hashtable.
            # Credit to this workaround comes from here:
            # https://psescape.azurewebsites.net/pester-testing-your-module-manifest/
            $manifest = Invoke-Expression (Get-Content $manifestFile -Raw)

            It "Manifest file includes the correct root module" {
                $manifest.RootModule | Should Be 'BitbucketPS.psm1'
            }

            It "Manifest file includes the correct guid" {
                $manifest.Guid | Should Be 'd859fc87-50ef-406a-98a9-0355d55d1d4d'
            }

            It "Manifest file includes a valid version" {
                $manifest.ModuleVersion -as [Version] | Should Not BeNullOrEmpty
            }

            It "Includes a changelog file" {
                $changelogFile | Should Exist
            }

            It "Changelog includes a valid version number" {
                $changelogVersion                | Should Not BeNullOrEmpty
                $changelogVersion -as [Version]  | Should Not BeNullOrEmpty
            }

            It "Changelog version matches manifest version" {
                $manifest -like "$($changelogVersion.ModuleVersion)*" | Should Be $true
            }

            # Back to me! Pester doesn't use AppVeyor, as far as I know, and I do.

            It "Includes an appveyor.yml file" {
                $appveyorFile | Should Exist
            }

            It "Appveyor.yml file includes the module version" {
                $appveyorVersion               | Should Not BeNullOrEmpty
                $appveyorVersion -as [Version] | Should Not BeNullOrEmpty
            }

            It "Appveyor version matches manifest version" {
                $manifest -like "$($appveyorVersion.ModuleVersion)*" | Should Be $true
            }
        }

        Context "Style checking" {

            # This section is again from the mastermind, Dave Wyatt. Again, credit
            # goes to him for these tests.

            $files = @(
                Get-ChildItem $moduleRoot -Include *.ps*1
            )

            It 'Source files contain no trailing whitespace' {
                $badLines = @(
                    foreach ($file in $files) {
                        $lines = [System.IO.File]::ReadAllLines($file.FullName)
                        $lineCount = $lines.Count

                        for ($i = 0; $i -lt $lineCount; $i++) {
                            if ($lines[$i] -match '\s+$') {
                                'File: {0}, Line: {1}' -f $file.FullName, ($i + 1)
                            }
                        }
                    }
                )

                if ($badLines.Count -gt 0) {
                    throw "The following $($badLines.Count) lines contain trailing whitespace: `r`n`r`n$($badLines -join "`r`n")"
                }
            }

            It 'Source files contain wrong line endings (windows style)' {
                $badFiles = @(
                    foreach ($file in $files) {
                        $lines = Get-Content $file.FullName -Delim "`0"

                        foreach ($line in $lines) {
                            if ($line | Select-String "`r`n") {
                                'File: {0}' -f $file.FullName
                                break
                            }
                        }
                    }
                )

                if ($badFiles.Count -gt 0) {
                    throw "The following $($badFiles.Count) files contain the wrong type of line feed: `r`n`r`n$($badFiles -join "`r`n")"
                }
            }

            It 'Source files all end with a newline' {
                $badFiles = @(
                    foreach ($file in $files) {
                        $string = [System.IO.File]::ReadAllText($file.FullName)
                        if ($string.Length -gt 0 -and $string[-1] -ne "`n") {
                            $file.FullName
                        }
                    }
                )

                if ($badFiles.Count -gt 0) {
                    throw "The following files do not end with a newline: `r`n`r`n$($badFiles -join "`r`n")"
                }
            }
        }

        Context 'PSScriptAnalyzer Rules' {

            Import-Module (Join-Path $PSScriptRoot "../BitBucketPS") -Prefix "Bitbucket" -Force -ErrorAction Stop

            $analysis = Invoke-ScriptAnalyzer -Path "$moduleRoot" -Recurse -Settings "$projectRoot/PSScriptAnalyzerSettings.psd1"
            $scriptAnalyzerRules = Get-ScriptAnalyzerRule

            forEach ($rule in $scriptAnalyzerRules) {
                It "Should pass $rule" {
                    if (($analysis) -and ($analysis.RuleName -contains $rule)) {
                        $analysis | Where-Object RuleName -EQ $rule -OutVariable failures | Out-Default
                        $failures.Count | Should Be 0
                    }
                }
            }
        }
    }
}
