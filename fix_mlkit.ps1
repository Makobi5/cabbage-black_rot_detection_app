# Path to pub cache
$pubCachePath = "$env:USERPROFILE\AppData\Local\Pub\Cache\hosted\pub.dev"

# Find all ML Kit packages
$mlkitPackages = Get-ChildItem -Path $pubCachePath -Directory | Where-Object { $_.Name -like "google_mlkit*" }

foreach ($package in $mlkitPackages) {
    $manifestPath = Join-Path -Path $package.FullName -ChildPath "android\src\main\AndroidManifest.xml"
    $buildGradlePath = Join-Path -Path $package.FullName -ChildPath "android\build.gradle"
    
    if (Test-Path $manifestPath) {
        Write-Host "Processing manifest for $($package.Name)..."
        
        # Read the manifest
        $manifestContent = Get-Content -Path $manifestPath -Raw
        
        # Extract package name from the manifest
        if ($manifestContent -match 'package="([^"]+)"') {
            $packageName = $matches[1]
            
            # Remove package attribute
            $newManifestContent = $manifestContent -replace 'package="[^"]+"', ''
            
            # Write back the manifest
            Set-Content -Path $manifestPath -Value $newManifestContent
            
            # Update build.gradle
            if (Test-Path $buildGradlePath) {
                $buildGradleContent = Get-Content -Path $buildGradlePath -Raw
                
                if ($buildGradleContent -notmatch 'namespace\s+["'']') {
                    # Add namespace to android section
                    $newBuildGradleContent = $buildGradleContent -replace '(android\s*\{)', "`$1`n    namespace `"$packageName`"`n"
                    
                    # Write back the build.gradle
                    Set-Content -Path $buildGradlePath -Value $newBuildGradleContent
                }
            }
            
            Write-Host "  Updated namespace for $packageName"
        }
    }
}

Write-Host "Done processing ML Kit packages."