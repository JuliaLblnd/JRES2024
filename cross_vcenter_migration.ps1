<#
.SYNOPSIS
Cross vCenter VM migration script

.Description
Migrate a VM across 2 different vCenter. 
Retrieve corresponding storage and network on destination for hot migration.

.PARAMETER VM
Specify the name of VM to migrate.
Mendatory.

.PARAMETER Source
Specify Source VMware vCenter Server (hostname or ip).

.PARAMETER Destination
Specify Destination VMware vCenter Server (hostname or ip).

.PARAMETER Cluster
Specify Destination Cluster Name.

.PARAMETER Credential
PSCredential to connect to server.
Use `Import-Clixml` in parentheses `()` to import credential from file (See Examples).
Not Mendatory. Asked if not provided.

.EXAMPLE
.\cross_vcenter_migration.ps1 -VM myVM -Source vc1.example.com -Destination vc2.example.com -Cluster cluster1
Credential will be requested

.EXAMPLE
.\cross_vcenter_migration.ps1 -VM myVM -Source vc1.example.com -Destination vc2.example.com -Cluster cluster1 -Credential (Import-Clixml -Path creds.xml)
Import credential from file.  
To export credential, use `Get-Credential | Export-Clixml creds.xml`

#>

Param(
    [Parameter(Mandatory=$true)]
    [String] $VM,
    
    [Parameter(Mandatory=$false)]
    [Alias("src")]
    [String] $Source = 'vc1.example.com',
    
    [Parameter(Mandatory=$false)]
    [Alias("dst","dest")]
    [String] $Destination = 'vc2.example.com',
    
    [Parameter(Mandatory=$false)]
    [String] $Cluster = 'wld-1',
    
    [Parameter(Mandatory=$false)]
    [Alias("cred","creds")]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = $(Get-Credential)
)

# Remove Module Hyper-V from context to prevent Cmdlet conflict
if ($null -ne (Get-Module Hyper-V)) { Remove-Module Hyper-V }
Import-Module VMware.VimAutomation.Core
Import-Module VMware.VimAutomation.Vds
Import-Module VMware.PowerCLI.VCenter
Import-Module VMware.VimAutomation.Common

# Define SSL Certificats Thumbprint for all vCenters used
$SslThumbprints = @{
    "vc1.example.com" = "12:34:56:38:9A:BC:DE:F0:12:34:56:78:9A:BC:DE:F0:12:34:56:78";
    "vc2.example.com" = "12:34:56:38:9A:BC:DE:F0:12:34:56:78:9A:BC:DE:F0:12:34:56:78";
    "vc3.example.com" = "12:34:56:38:9A:BC:DE:F0:12:34:56:78:9A:BC:DE:F0:12:34:56:78"
}
# Pour récupérer la thumbprint en bash : 
# openssl s_client -connect vc1.example.com:443 < /dev/null 2>/dev/null | openssl x509 -fingerprint -noout -in /dev/stdin

$Src_vCenter = Connect-VIServer $Source -Credential $Credential
Write-Host "Logged-in to source vCenter $($Src_vCenter.Name)."
$SourceVM = (Get-VM $VM -Server $Src_vCenter)

if ($SourceVM.Count -gt 1) {
    Write-Host "Found more than 1 VM matching the given name" -ForegroundColor "yellow"
    exit 1
}

$Dest_vCenter = Connect-VIServer $Destination -Credential $Credential
Write-Host "Logged-in to destination vCenter $($Dest_vCenter.Name)."

## Get Destination vCenter SSL Certificat Thumbprint
# $Dest_SslThumbprint = ((Get-VIMachineCertificate -VCenterOnly -Server $Dest_vCenter).Certificate.Thumbprint.ToUpper() -split '(..)' -ne '' -join ':')
$Dest_SslThumbprint = $SslThumbprints[$Dest_vCenter.Name]

$Dest_folder = (Get-Datacenter -Server $Dest_vCenter -Cluster $Cluster | Get-Folder -NoRecursion -Type VM | Get-Folder -NoRecursion -Name "Migrated virtual machines" -ErrorAction Ignore)
if ($null -eq $Dest_folder) {
    $Dest_folder = (Get-Datacenter -Server $Dest_vCenter -Cluster $Cluster | Get-Folder -NoRecursion -Type VM | New-Folder -Name "Migrated virtual machines")
}
$Dest_Cluster = Get-Cluster -Server $Dest_vCenter -Name $Cluster
$Dest_pool = Get-ResourcePool -Location $Dest_Cluster
$Dest_VDSwitches = Get-VMHost -Location $Dest_Cluster | Get-VDSwitch

$VmPath_DsName = ($SourceVM.ExtensionData.Config.Files.VmPathName | Select-String -Pattern '^\[(.+)\]').Matches[0].Groups[1].Value
$Dest_Datastore = Get-Datastore -Name $VmPath_DsName -Server $Dest_vCenter

Write-Host ""
Write-Host "VM Relocation '$($SourceVM.Name)'"
Write-Host "Source vCenter      : $($Src_vCenter.Name)"
Write-Host "Destination vCenter : $($Dest_vCenter.Name)"
Write-Host "Destination Cluster : $($Dest_Cluster.Name)"
Write-Host "SSL Thumbprint of Destination vCenter: $($Dest_SslThumbprint)"
Write-Host ""
Write-Host "VM Config File Path         : $($SourceVM.ExtensionData.Config.Files.VmPathName)"
Write-Host "Source      Datastore Name  : $($VmPath_DsName)"
Write-Host "Destination Datastore Name  : $($Dest_Datastore.Name)"
Write-Host "Destination Datastore MoRef : $($Dest_Datastore.ExtensionData.MoRef.Value)"
Write-Host ""

# Service Locator
$serviceLocCreds = New-Object VMware.Vim.ServiceLocatorNamePassword
$serviceLocCreds.Username = $Credential.GetNetworkCredential().UserName
$serviceLocCreds.Password = $Credential.GetNetworkCredential().Password
$serviceLoc = New-Object VMware.Vim.ServiceLocator
$serviceLoc.InstanceUuid  = $Dest_vCenter.InstanceUuid
$serviceLoc.Url           = ("https://" + $Dest_vCenter.ServiceUri.Host)
$serviceLoc.Credential    = $serviceLocCreds
$serviceLoc.SslThumbprint = $Dest_SslThumbprint

# Relocation Specification
$relocSpec = New-Object VMware.Vim.VirtualMachineRelocateSpec
$relocSpec.datastore = $Dest_Datastore.ExtensionData.MoRef
$relocSpec.folder    = $Dest_folder.ExtensionData.MoRef
$relocSpec.pool      = $Dest_pool.ExtensionData.MoRef
$relocSpec.service   = $serviceLoc
$relocSpec.deviceChange = New-Object VMware.Vim.VirtualDeviceConfigSpec[]($SourceVM.ExtensionData.Network.Count)
$relocSpec.disk = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator[](($SourceVM.ExtensionData.Config.Hardware.Device | Where-Object {$_ -is [VMware.Vim.VirtualDisk]}).Count)

$devices = $SourceVM.ExtensionData.Config.Hardware.Device

$iNic = 0
$iDisk = 0
foreach ($device in $devices) {
    if($device -is [VMware.Vim.VirtualEthernetCard]) {
        $Src_PortgroupKey = $device.Backing.Port.PortgroupKey
        $Src_PortGroup  = (Get-VDPortGroup -Server $Src_vCenter | Where-Object {$_.Key -eq $Src_PortgroupKey})
        $Dest_PortGroup = Get-VDPortgroup -VDSwitch $Dest_VDSwitches -Name $Src_PortGroup.Name
        $Dest_VDSwitch = Get-VDSwitch -RelatedObject $Dest_PortGroup

        $relocSpec.deviceChange[$iNic] = New-Object VMware.Vim.VirtualDeviceConfigSpec
        $relocSpec.deviceChange[$iNic].Operation = "edit"
        $relocSpec.deviceChange[$iNic].Device = $device
        $relocSpec.deviceChange[$iNic].Device.Backing = New-Object VMware.Vim.VirtualEthernetCardDistributedVirtualPortBackingInfo
        $relocSpec.deviceChange[$iNic].Device.Backing.Port = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $relocSpec.deviceChange[$iNic].Device.Backing.Port.PortgroupKey = $Dest_PortGroup.Key
        $relocSpec.deviceChange[$iNic].Device.Backing.Port.SwitchUuid = $Dest_VDSwitch.ExtensionData.Uuid

        $iNic++
        Write-Host "NIC Relocation '$($device.DeviceInfo.Label)'"
        Write-Host "Source      VDSwitch Name   : $((Get-VDSwitch -RelatedObject $Src_PortGroup).Name)"
        Write-Host "Destination VDSwitch Name   : $($Dest_VDSwitch.Name)"
        Write-Host "Source      PortGroup Name  : $($Src_PortGroup.Name)"
        Write-Host "Destination PortGroup Name  : $($Dest_PortGroup.Name)"
        Write-Host "Source      PortGroup MoRef : $($Src_PortGroup.ExtensionData.MoRef.Value)"
        Write-Host "Destination PortGroup MoRef : $($Dest_PortGroup.ExtensionData.MoRef.Value)"
        Write-Host ""
    }
    elseif($device -is [VMware.Vim.VirtualDisk]) {
        $Src_DiskDS = Get-Datastore -Server $Src_vCenter -Id $device.Backing.Datastore.ToString()
        $Dest_DiskDS = Get-Datastore -Server $Dest_vCenter -Name $Src_DiskDS.Name

        $relocSpec.disk[$iDisk] = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator
        $relocSpec.disk[$iDisk].DiskId = $device.Key
        $relocSpec.disk[$iDisk].Datastore = $Dest_DiskDS.Extensiondata.MoRef
        # $relocSpec.disk[$iDisk].diskBackingInfo = New-Object VMware.Vim.VirtualDiskFlatVer2BackingInfo
        $relocSpec.disk[$iDisk].diskBackingInfo = New-Object $device.Backing.GetType().ToString()
        $relocSpec.disk[$iDisk].diskBackingInfo.DiskMode        = $device.Backing.DiskMode
        $relocSpec.disk[$iDisk].diskBackingInfo.ThinProvisioned = $device.Backing.ThinProvisioned
        $relocSpec.disk[$iDisk].diskBackingInfo.EagerlyScrub    = $device.Backing.EagerlyScrub
        $relocSpec.disk[$iDisk].diskBackingInfo.FileName        = ''

        $iDisk++
        Write-Host "Disk Relocation '$($device.DeviceInfo.Label)'"
        Write-Host "Source      Datastore Name  : $($Src_DiskDS.Name)"
        Write-Host "Destination Datastore Name  : $($Dest_DiskDS.Name)"
        Write-Host "Source      Datastore MoRef : $($Src_DiskDS.ExtensionData.MoRef.Value)"
        Write-Host "Destination Datastore MoRef : $($Dest_DiskDS.ExtensionData.MoRef.Value)"
        Write-Host ""
    }
}

Write-Host ""
Write-Host "Press Enter to continue, Ctrl+C to exit" -NoNewline
Start-Sleep -Milliseconds 200
Read-Host
Write-Host "CONTINUE TO MIGRATE VM" -ForegroundColor "red"
Write-Host "PRESS ENTER TO CONTINUE, CTRL+C TO EXIT" -ForegroundColor "red" -NoNewline
Start-Sleep -Milliseconds 200
Read-Host

$taskMoRef = $SourceVM.Extensiondata.RelocateVM_Task($relocSpec, "defaultPriority")
Write-Host "Relocate VM Task Started." -ForegroundColor "green"
Write-Host "Task ID (MoRef): $($taskMoRef.ToString())"
$task = (Get-Task -Id $taskMoRef -ErrorAction Ignore).ExtensionData
$lastState = $null

while ($task -is [VMware.Vim.Task]) {
    if ($null -eq $task.Info -or $null -eq $task.Info.State) {
        Write-Host "No task info" -ForegroundColor red
        break
    }

    if ($task.Info.State -eq [VMware.Vim.TaskInfoState]::queued -And $lastState -ne "Queued") {
        $lastState = "Queued"
        Write-Host "Queued"
    }

    if ($task.Info.State -eq [VMware.Vim.TaskInfoState]::running) {
        if ($task.Info.Progress -ne $lastState) {
            Write-Host ("Progress: " + $task.Info.Progress + "%")
        }
        $lastState = $task.Info.Progress
    }

    if ($task.Info.State -eq [VMware.Vim.TaskInfoState]::success) {
        Write-Host "Success" -ForegroundColor green
        exit 0
        break
    }

    if ($task.Info.State -eq [VMware.Vim.TaskInfoState]::error) {
        Write-Host "Error" -ForegroundColor red
        if ($task.Info.Error.localizedMessage) {
            Write-Host $task.Info.Error.localizedMessage -ForegroundColor red
        }
        exit 1
        break
    }

    # Start-Sleep -Milliseconds 250
    Start-Sleep -Milliseconds 50
    $task = (Get-Task -Id $taskMoRef -ErrorAction Ignore).ExtensionData
}
