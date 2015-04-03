param
(
    [Parameter(Mandatory)]
    [System.String]$ConfigurationArchiveURL,

    [Parameter(Mandatory)]
    [System.String]$ConfigurationName,

    [System.String]$ConfigurationDataURL,

    [System.String]$ConfigurationArguments
)
$ErrorActionPreference = 'Stop'
$DSCDir = New-Item -Path c:\ -Name 'BringYourOwnDSC' -ItemType Directory -Force
Write-Output -InputObject $ConfigurationArguments
#region download zip
[System.String]$ArchiveName = $ConfigurationArchiveURL.split('/')[-1]
try
{
    Write-Output -InputObject "Downloading Configuration Archive $ArchiveName using URL: $ConfigurationArchiveURL"
    Invoke-WebRequest -Uri $ConfigurationArchiveURL `
                      -OutFile "$($DSCDir.PSPath)\$ArchiveName" `
                      -Verbose
    Write-Output -InputObject "Successfully downloaded Configuration Archive"
}
catch
{
    Write-Error -Message "Failed Downloading Configuration Archive $ArchiveName using URL: $ConfigurationArchiveURL" -Exception $_.exception
    throw $_
}
#endregion download zip

#region download configdata psd1
if ($ConfigurationDataURL -ne 'NA')
{
    Write-Output -InputObject "ConfigurationData URL specified. Attempting download"
    $ConfigDataExits = $true
    [System.String]$ConfigDataName = $ConfigurationDataURL.split('/')[-1]
    try
    {
        Write-Output -InputObject "Downloading Configuration Data $ConfigDataName using URL: $ConfigurationDataURL"
        Invoke-WebRequest -Uri $ConfigurationDataURL `
                          -OutFile "$($DSCDir.PSPath)\$ConfigDataName" `
                          -Verbose
        Write-Output -InputObject "Successfully downloaded Configuration data"
    }
    catch
    {
        Write-Error -Message "Failed Downloading Configuration data $ConfigDataName using URL: $ConfigurationDataURL" -Exception $_.exception
        throw $_
    }
}
else
{
    Write-Output -InputObject "ConfigurationData URL not specified"
    $ConfigDataExits = $false
}
#endregion download configdata psd1

#region unzip and install modules
Unblock-File -Path "$($DSCDir.PSPath)\$ArchiveName"
Expand-Archive -Path "$($DSCDir.PSPath)\$ArchiveName" -DestinationPath "$($DSCDir.fullname)\$($ArchiveName.trim('.ps1.zip'))" -Force
$Modules = Get-ChildItem -Path "$($DSCDir.PSPath)\$($ArchiveName.trim('.ps1.zip'))\" -Directory
foreach ($M in $Modules)
{
    if (Test-Path "C:\Program Files\WindowsPowerShell\Modules\$($M.Name)")
    {
        Write-Output -InputObject "DSC Resource Module $($M.Name) is already present. Checking if there is a version conflict"
        [version]$NewVersion = ((Get-Content -Path "$($M.PSPath)\$($M.Name).psd1" | Select-String "ModuleVersion").tostring()).substring(16).Replace("'", "")
        [version]$CurVersion = ((Get-Content -Path "C:\Program Files\WindowsPowerShell\Modules\$($M.Name)\$($M.Name).psd1"| Select-String "ModuleVersion").tostring()).substring(16).Replace("'", "")
        if ($NewVersion -ne $CurVersion)
        {
            Write-Output -InputObject "DSC Resource modules are not the same. Overwriting existing module with delivered module"
            Remove-Item -Path "C:\Program Files\WindowsPowerShell\Modules\$($M.Name)" -Recurse -Force
            Copy-Item -Path $M.PSPath -Destination 'C:\Program Files\WindowsPowerShell\Modules' -Recurse
        }
        else
        {
            Write-Output -InputObject "DSC Resource Module versions are the same"
        }
    }
    else
    {
        Copy-Item -Path $M.PSPath -Destination 'C:\Program Files\WindowsPowerShell\Modules' -Recurse
    }
}
#endregion unzip and install modules

#region call configuration and compile mof

#dot source configuration
Set-Location $DSCDir.fullname
Get-ChildItem -Path .\$($ArchiveName.trim('.ps1.zip')) -Filter *.ps1 | %{
    . $_.fullname
}
if ($ConfigDataExits)
{
    $Params = @{}
    $LoadConfigData = get-content .\$ConfigDataName -raw
    $Configdata = & ([scriptblock]::Create($LoadConfigData))
    $Params += @{ConfigurationData=$Configdata}
}
if ($ConfigurationArguments -ne 'NA')
{
    if (!($Params))
    {
        $Params = @{}
    }
    $splithash = $ConfigurationArguments.split(';')
    $confighash = $splithash | Out-String | ConvertFrom-StringData
    $Params += $confighash
    $params
    write-output ""
    $params.ConfigurationData
    write-output ""
    $params.ConfigurationData.AllNodes
}
if ($Params)
{
    try
    {
        & $ConfigurationName @Params
    }
    catch
    {
        $_.exception.message
        Write-Error -Message "Failed compiling MOF with additional parameters" -Exception $_.exception
        throw $_
    }
}
else
{
    try
    {
        & $ConfigurationName
    }
    catch
    {
        Write-Error -Message "Failed compiling MOF without additional parameters" -Exception $_.exception
        throw $_
    }
}
#endregion call configuration and compile mof

#region configure LCM
[DSCLocalConfigurationManager()]
Configuration LCM
{
    Settings
    {
        RefreshMode = 'Push'
        RebootNodeIfNeeded = $true
        ConfigurationMode = 'ApplyAndAutoCorrect'
    }
}
LCM
Set-DscLocalConfigurationManager -Path .\LCM
#endregion configure LCM

#region start dsc config
Start-DscConfiguration -Path .\$ConfigurationName -Force
#endregion start dsc config