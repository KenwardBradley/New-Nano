Start-Transcript -Path "U:\Scripts\Lab\NewNano.txt"
$StartTime = Get-Date

function Test-PathExists ($PathToCheck) {
    if (-not (Test-Path $PathToCheck)) {throw "$PathToCheck not found."}    
    }

function New-Nano
{
    [CmdletBinding()]
    Param
    (
        # Path to the Windows Server 2016 ISO
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        $ImagePath,

        # Working Directory
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        $WorkingDir,

        # Admin Password
        [SecureString]
        $AdminPassword = (ConvertTo-SecureString -AsPlainText "Password1" -Force),

        # Hyper-V Switch Name
        [String]
        $NetworkSwitch = "External",

        # Nano VM Name
        [String]
        $Name = "nano" + $(Get-Random -Minimum 1000 -Maximum 9999),
        
        # Processor Count
        [ValidateRange(1,256)]
        [int]
        $ProcessorCount = 1,

        # Memory Startup Bytes
        [ValidateRange(1,256GB)]
        [int64]
        $MemoryStartupBytes = 512MB
    )

    Begin
    {
    # Validate inputs
    #if (-not (Test-Path $ImagePath)) {throw "$ImagePath not found."}
    #Test-Path $WorkingDir -ErrorAction Stop


    }

    Process
    {
    # ref: https://technet.microsoft.com/en-us/library/mt126167.aspx
    
    $VirtualHardDiskPath = $(Get-VMHost).VirtualHardDiskPath
    $VirtualMachinePath = $(Get-VMHost).VirtualMachinePath
    $NewNanoPath = $VirtualHardDiskPath + $Name + ".vhdx"
    $StartingDir = (Get-Location).Path
    $MountObject = Mount-DiskImage -ImagePath $ImagePath -PassThru
    $MountDriveLetter = ($MountObject | Get-Volume).DriveLetter + ":"
    $NanoMount = $MountDriveLetter + "\NanoServer\"

    # copy the NanoServer dir to the working dir
    $NanoDir = $WorkingDir + "NanoServer\"
    Copy-Item -Path $NanoMount -Destination $NanoDir -Recurse -Force

    Set-Location $NanoDir -ErrorAction Stop

    Import-Module .\NanoServerImageGenerator -Verbose -ErrorAction Stop

    # create the VHD
    $NewNanoResult = New-NanoServerImage -DeploymentType Guest -Edition Standard -MediaPath $MountDriveLetter -BasePath .\Base -TargetPath $NewNanoPath -EnableRemoteManagementPort -ComputerName $Name -AdministratorPassword $AdminPassword -ErrorAction Stop

    # new VM from the VHD
    New-VM -Name $Name -VHDPath $NewNanoPath -MemoryStartupBytes $MemoryStartupBytes -SwitchName $NetworkSwitch -BootDevice VHD -Generation 2 -Path $VirtualMachinePath -ErrorAction Stop |
    Set-VM -DynamicMemory -ProcessorCount $ProcessorCount -Passthru -AutomaticStopAction ShutDown -AutomaticStartAction Nothing -ErrorAction Stop

    # finish up.
    $MountObject | Dismount-DiskImage
    "Starting $Name"
    Start-VM $Name

    while ((Get-VM $Name).State -ne "Running")
        {Start-Sleep 5}
    "$Name is Running."

    while ((Get-VM $Name).NetworkAdapters.Status[0] -ne "Ok") 
        {Start-Sleep 5}
    "Network adapter reporting Ok."

    $vm = Get-VM $Name
    $vm.NetworkAdapters | select VMName, SwitchName, Status, IPAddresses

    "Demonstrate that PowerShell Session works"
    $AdminUser = "$Name\Administrator"
    $cred = New-Object -Typename System.Management.Automation.PSCredential  -Argumentlist $AdminUser, $AdminPassword
    $pss = New-PSSession -ComputerName $vm.NetworkAdapters.IPAddresses[0] -Credential $cred
    Invoke-Command -Session $pss -ScriptBlock {Get-Service | where Status -EQ "Running"| Format-Table} 
    Remove-PSSession $pss

    # return to original directory
    Set-Location $StartingDir
    }
}

$NewNanoParams = @{
    ImagePath = "Z:\ISOs\WindowsServer\2016-preview\en_windows_server_2016_technical_preview_5_x64_dvd_8512312.iso";
    WorkingDir = "Z:\Scripts\Lab\";
    AdminPassword =  (ConvertTo-SecureString -AsPlainText "Password1" -Force);
    NetworkSwitch = "External"
    Name = "LabNano" + (Get-Random -Minimum 100 -Maximum 999);
    ProcessorCount = 1;
    MemoryStartupBytes = 512MB
    }

#
Measure-Command {
    New-Nano @NewNanoParams
    } | select TotalMinutes, TotalSeconds


Stop-Transcript