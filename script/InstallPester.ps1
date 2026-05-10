Install-PackageProvider -Name NuGet -Force
Install-Module -Name Pester -Force -SkipPublisherCheck

Write-Host "Pester installation completed successfully"
