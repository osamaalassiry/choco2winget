# Get the list of installed Chocolatey packages
choco list  > chocolist.txt

# Read the Chocolatey package list file
$chocoPackages = Get-Content -Path .\chocolist.txt

foreach ($package in $chocoPackages) {
    # Remove version number and everything after it from package name
    $packageName = $package -replace ' v\d.*$'
	$packageName = $package -replace ' \d.*$'

    # Check if the package is available in Winget
    Write-Host "Checking package '$packageName' in Winget..."
    $wingetPackage = winget search $packageName
    Write-Host $wingetPackage

    if ($wingetPackage -match $packageName) {
        Write-Host "Package '$packageName' is available in both Chocolatey and Winget."

        # Confirm before uninstalling and reinstalling
        $confirmation = Read-Host "Do you want to uninstall it from Chocolatey and install it using Winget? (yes/no)"

        if ($confirmation -eq 'yes') {
            # Uninstall the package from Chocolatey
            choco uninstall $packageName -y

            # Install the package using Winget
            winget install $packageName
        }
    } else {
        Write-Host "Package '$packageName' is not available in Winget."
    }
}

# Delete the Chocolatey package list file
Remove-Item .\chocolist.txt