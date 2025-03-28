$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
$downloadsFolder = Join-Path $scriptFolder "Downloads"
$logFilePath = Join-Path $scriptFolder "testlog.txt"


Start-Transcript -Path $logFilePath
$packageName = "cefsharp.winforms"




if (!(Test-Path $downloadsFolder)) {
    New-Item -ItemType Directory -Path $downloadsFolder | Out-Null
}


function Download-Package {
    param(
        [string]$Name  
    )

    $Name = $Name.ToLower();

    $packageDownloadUrl = "https://www.nuget.org/api/v2/package/$Name"

    $apiUrlNuget = "https://api.nuget.org/v3-flatcontainer/$Name/index.json"

    $response = Invoke-RestMethod -Uri $apiUrlNuget
    $latestVersion = $response.versions[-1]  
    $Version = $latestVersion

    # write-Host "Latest NuGet Version: $latestVersion"

    $destination = Join-Path $downloadsFolder "$Name.$Version.nupkg"

    if (!(Test-Path $destination)) {

        try {

            $webClient = New-Object System.Net.WebClient
            write-Host "Downloading $Name with it's latest Version: $latestVersion"
            $webClient.DownloadFile($packageDownloadUrl, $destination)
            write-Host "Successfully downloaded $Name $latestVersion"
            

    	    if ($Name -match "chromiumembeddedframework.runtime") {
                $global:CefRunTimeVersion=$Version
                return $true
            }
            if ($Name -match "cefsharp.common") {
               
               $global:CefsharpCommonVersion=$Version
            }
            if ($Name -match "cefsharp.winforms") {
               $global:CefsharpWinformsVersion=$Version
            }
             
            

            # use catalog url from meta data
            $metadataUrl = "https://api.nuget.org/v3/registration5-gz-semver2/$Name/$Version.json"

	        $response = Invoke-RestMethod -Uri $metadataUrl 
            # Write-Host $response
            # $response.catalogEntry

            #$catalogEntryUrl = "https://api.nuget.org/v3/catalog0/data/2025.03.23.09.24.33/$($Name).$($Version).json"

            $catalogEntryUrl = $response.catalogEntry

             write-Host "Checking Dependencies of $Name $latestVersion"

            $catalogData = Invoke-RestMethod -Uri $catalogEntryUrl

            $dependencyGroups = $catalogData.dependencyGroups
            Process-Dependencies -DependencyGroups $dependencyGroups
            
            return $true
        } catch {
            Write-Host ":x: Failed to download: $Name ($Version)" 
            Write-Host "Error Message: $($_.Exception.Message)"
            Write-Host "Stack Trace: $($_.Exception.StackTrace)"
            return $false
        }
    } else {
        Write-Host ":open_file_folder: Package already downloaded: $Name"
        return $true
    }
}


function Process-Dependencies {
    param(
        [array]$DependencyGroups
    )

    if ($DependencyGroups -and $DependencyGroups.Count -gt 0) {
        foreach ($group in $DependencyGroups) {
            $dependencies = @()
            if ($group.dependencies -is [array]) {
                $dependencies = $group.dependencies
            } elseif ($group.dependencies) {
                $dependencies = @($group.dependencies)
            }

            foreach ($dep in $dependencies) {
                $depName = $dep.id
                $rawVersion = $dep.range
                # Clean version specification
                $depVersion = $rawVersion -replace '[\[\]()]', '' -split ',' | Select-Object -First 1
                $depVersion = $depVersion.Trim()
               
               
                try {
                    $indexUrl = "https://api.nuget.org/v3-flatcontainer/$depName/index.json"
                    $versions = (Invoke-RestMethod -Uri $indexUrl -ErrorAction Stop).versions

                    if ($versions -contains $depVersion) {
                        Download-Package -Name $depName | Out-Null
                    } else {
                        Write-Host "Version $depVersion not found for $depName. Available versions: $($versions -join ', ')"
                    }
                } catch {
                    Write-Host " Error verifying $depName $($_.Exception.Message)" 
                }
            }
        }
    } else {
        
        Write-Host "No dependencies found for $packageName ($packageVersion)."
        
    }
}

if (Download-Package -Name $packageName) {
   
}



# Extraction binaries part

# Write-Host "CefSharp.WinForms Version: $CefsharpWinformsVersion"
# Write-Host "CefSharp.Common Version: $CefsharpCommonVersion"
# Write-Host "ChromiumEmbeddedFramework Runtime Version: $CefRunTimeVersion"


# $downloadsFolder = Join-Path $env:USERPROFILE "Downloads"
# Write-Host "hi : $downloadsFolder"
$destinationFolder = Join-Path $downloadsFolder "cef_extracted"
$finalFolder = Join-Path $scriptFolder "cef"


if (!(Test-Path $destinationFolder)) { New-Item -ItemType Directory -Path $destinationFolder | Out-Null }
if (!(Test-Path $finalFolder)) { New-Item -ItemType Directory -Path $finalFolder | Out-Null }


$nupkgFiles = Get-ChildItem -Path $downloadsFolder -Filter "*.nupkg"

if ($nupkgFiles.Count -eq 0) {
    Write-Host "No .nupkg files found in the Downloads folder."
    exit
} else {
    # Write-Host "Yes, .nupkg files found in the Downloads folder."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem


foreach ($file in $nupkgFiles) {
    $tempExtractPath = Join-Path $destinationFolder ($file.BaseName)
    
    if (!(Test-Path $tempExtractPath)) {
        New-Item -ItemType Directory -Path $tempExtractPath | Out-Null
    }
    
    Write-Host "Extracting: $($file.Name)"
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($file.FullName, $tempExtractPath)
    } catch {
        Write-Host "Error extracting $($file.Name): $_"
    }
}



$subFoldersToCopy = @(
    "chromiumembeddedframework.runtime.win-x64.$CefRunTimeVersion\runtimes\win-x64\native",
    "chromiumembeddedframework.runtime.win-x64.$CefRunTimeVersion\build",
    "cefsharp.common.$CefsharpCommonVersion\CefSharp\x64",
    "cefsharp.common.$CefsharpCommonVersion\lib\net462",
    "cefsharp.winforms.$CefsharpWinformsVersion\lib\net462"
   
)


foreach ($relativePath in $subFoldersToCopy) {
    $subFolder = Join-Path $destinationFolder $relativePath
    
    if (Test-Path $subFolder) {
        $files = Get-ChildItem -Path $subFolder -File
        foreach ($file in $files) {
            $destFilePath = Join-Path $finalFolder $file.Name
            try {
                Copy-Item -Path $file.FullName -Destination $destFilePath -Force
            } catch {
                Write-Host "Error copying $($file.FullName): $_"
            }
        }
    } else {
        Write-Host "Folder not found: $subFolder"
    }
}

$LocaleFolder = Join-Path $finalFolder "locales"
$LocaleFolderToCopy = Join-Path $destinationFolder "chromiumembeddedframework.runtime.win-x64.$CefRunTimeVersion\CEF\win-x64\locales"
if (!(Test-Path $LocaleFolder)) { New-Item -ItemType Directory -Path $LocaleFolder | Out-Null }

$files = Get-ChildItem -Path $LocaleFolderToCopy -File

foreach ($file in $files) {
      $destFilePath = Join-Path $LocaleFolder $file.Name
     try {
         Copy-Item -Path $file.FullName -Destination $destFilePath -Force
     } catch {
         Write-Host "Error copying $($file.FullName): $_"
     }
}

Remove-Item -Path $destinationFolder -Recurse -Force 
Remove-Item -Path $downloadsFolder -Recurse -Force
Stop-Transcript



