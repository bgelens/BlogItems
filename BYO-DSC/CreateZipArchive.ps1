Import-Module azure
$ConfigPath = '.\BringyourownDC.ps1'
Publish-AzureVMDscConfiguration -ConfigurationPath $ConfigPath -ConfigurationArchivePath "$ConfigPath.zip" -Force