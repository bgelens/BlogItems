configuration MyNewDomain
{
param
(
    [String]$DomainName,

    [String]$SafeModePassword
)
    $secpasswd = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
    $SafemodeAdminCred = New-Object System.Management.Automation.PSCredential ("TempAccount", $secpasswd)

    Import-DscResource -ModuleName xActiveDirectory

    node localhost
    {
        WindowsFeature ADDS
        {
            Name =  'AD-Domain-Services'
            Ensure = 'Present'
        }

        WindowsFeature ADDSPoSh
        {
            Name = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
        }

        xADDomain MyNewDomain
        {
            DomainName = $DomainName
            SafemodeAdministratorPassword = $SafemodeAdminCred
            DomainAdministratorCredential = $SafemodeAdminCred # used to check if domain already exists. Domain Administrator will have password of local administrator
            DependsOn = '[WindowsFeature]ADDS','[WindowsFeature]ADDSPoSh'
        }
    }
}