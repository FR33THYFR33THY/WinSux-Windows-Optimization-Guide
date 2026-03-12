        # SCRIPT RUN AS ADMIN
        If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
        {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit}
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.PrivateData.ProgressBackgroundColor = "Black"
        $Host.PrivateData.ProgressForegroundColor = "White"
        Clear-Host

        # SCRIPT CHECK INTERNET
        if (!(Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-Host "Internet Connection Required`n" -ForegroundColor Red
        Pause
        exit
        }

        # SCRIPT SILENT
        $progresspreference = 'silentlycontinue'

        # FUNCTION FASTER DOWNLOADS
        function Get-FileFromWeb {
        param ([Parameter(Mandatory)][string]$URL, [Parameter(Mandatory)][string]$File)
        try {
        $Request = [System.Net.HttpWebRequest]::Create($URL)
        $Response = $Request.GetResponse()
        if ($Response.StatusCode -eq 401 -or $Response.StatusCode -eq 403 -or $Response.StatusCode -eq 404) { throw "401, 403 or 404 '$URL'." }
        if ($File -match '^\.\\') { $File = Join-Path (Get-Location -PSProvider 'FileSystem') ($File -Split '^\.')[1] }
        if ($File -and !(Split-Path $File)) { $File = Join-Path (Get-Location -PSProvider 'FileSystem') $File }
        if ($File) { $FileDirectory = $([System.IO.Path]::GetDirectoryName($File)); if (!(Test-Path($FileDirectory))) { [System.IO.Directory]::CreateDirectory($FileDirectory) | Out-Null } }
        [long]$FullSize = $Response.ContentLength
        [byte[]]$Buffer = new-object byte[] 1048576
        [long]$Total = [long]$Count = 0
        $Reader = $Response.GetResponseStream()
        $Writer = new-object System.IO.FileStream $File, 'Create'
        do {
        $Count = $Reader.Read($Buffer, 0, $Buffer.Length)
        $Writer.Write($Buffer, 0, $Count)
        $Total += $Count
        } while ($Count -gt 0)
        }
        finally {
        $Reader.Close()
        $Writer.Close()
        }
        }

        # FUNCTION RUN AS TRUSTED INSTALLER
        function Run-Trusted([String]$command) {
        Stop-Service -Name TrustedInstaller -Force -ErrorAction SilentlyContinue
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='TrustedInstaller'"
        $DefaultBinPath = $service.PathName
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
        $base64Command = [Convert]::ToBase64String($bytes)
        sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -encodedcommand $base64Command" | Out-Null
        sc.exe start TrustedInstaller | Out-Null
        sc.exe config TrustedInstaller binpath= "`"$DefaultBinPath`"" | Out-Null
        Stop-Service -Name TrustedInstaller -Force -ErrorAction SilentlyContinue
        }

		# FUNCTION MODERN FILE PICKER
    	function Show-ModernFilePicker {
    	param(
    	[ValidateSet('Folder', 'File')]
    	$Mode,
    	[string]$fileType
    	)
    	if ($Mode -eq 'Folder') {
    	$Title = 'Select Folder'
    	$modeOption = $false
    	$Filter = "Folders|`n"
    	}
    	else {
    	$Title = 'Select File'
    	$modeOption = $true
    	if ($fileType) {
    	$Filter = "$fileType Files (*.$fileType) | *.$fileType|All files (*.*)|*.*"
    	}
    	else {
    	$Filter = 'All Files (*.*)|*.*'
    	}
    	}
    	$AssemblyFullName = 'System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'
    	$Assembly = [System.Reflection.Assembly]::Load($AssemblyFullName)
    	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    	$OpenFileDialog.AddExtension = $modeOption
    	$OpenFileDialog.CheckFileExists = $modeOption
    	$OpenFileDialog.DereferenceLinks = $true
    	$OpenFileDialog.Filter = $Filter
    	$OpenFileDialog.Multiselect = $false
    	$OpenFileDialog.Title = $Title
    	$OpenFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    	$OpenFileDialogType = $OpenFileDialog.GetType()
    	$FileDialogInterfaceType = $Assembly.GetType('System.Windows.Forms.FileDialogNative+IFileDialog')
    	$IFileDialog = $OpenFileDialogType.GetMethod('CreateVistaDialog', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($OpenFileDialog, $null)
    	$null = $OpenFileDialogType.GetMethod('OnBeforeVistaDialog', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($OpenFileDialog, $IFileDialog)
    	if ($Mode -eq 'Folder') {
    	[uint32]$PickFoldersOption = $Assembly.GetType('System.Windows.Forms.FileDialogNative+FOS').GetField('FOS_PICKFOLDERS').GetValue($null)
    	$FolderOptions = $OpenFileDialogType.GetMethod('get_Options', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($OpenFileDialog, $null) -bor $PickFoldersOption
    	$null = $FileDialogInterfaceType.GetMethod('SetOptions', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($IFileDialog, $FolderOptions)
    	}
    	$VistaDialogEvent = [System.Activator]::CreateInstance($AssemblyFullName, 'System.Windows.Forms.FileDialog+VistaDialogEvents', $false, 0, $null, $OpenFileDialog, $null, $null).Unwrap()
    	[uint32]$AdviceCookie = 0
    	$AdvisoryParameters = @($VistaDialogEvent, $AdviceCookie)
    	$AdviseResult = $FileDialogInterfaceType.GetMethod('Advise', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($IFileDialog, $AdvisoryParameters)
    	$AdviceCookie = $AdvisoryParameters[1]
    	$Result = $FileDialogInterfaceType.GetMethod('Show', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($IFileDialog, [System.IntPtr]::Zero)
    	$null = $FileDialogInterfaceType.GetMethod('Unadvise', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($IFileDialog, $AdviceCookie)
    	if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
    	$FileDialogInterfaceType.GetMethod('GetResult', @('NonPublic', 'Public', 'Static', 'Instance')).Invoke($IFileDialog, $null)
    	}
    	return $OpenFileDialog.FileName
    	}

        Write-Host "youtube.com/FR3" -ForegroundColor White -NoNewline; Write-Host "3THY`n" -ForegroundColor Cyan

        Write-Host "7Z`n"
        ## explorer "https://www.7-zip.org"

# download 7zip
Get-FileFromWeb -URL "https://www.7-zip.org/a/7z2301-x64.exe" -File "$env:SystemRoot\Temp\7 Zip.exe"

# install 7zip
Start-Process -Wait "$env:SystemRoot\Temp\7 Zip.exe" -ArgumentList "/S"

# set config for 7zip
cmd /c "reg add `"HKEY_CURRENT_USER\Software\7-Zip\Options`" /v `"ContextMenu`" /t REG_DWORD /d `"259`" /f >nul 2>&1"
cmd /c "reg add `"HKEY_CURRENT_USER\Software\7-Zip\Options`" /v `"CascadedMenu`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# cleaner 7zip start menu shortcut path
Move-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\7-Zip\7-Zip File Manager.lnk" -Destination "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\7-Zip" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

        Write-Host "CHROME`n"
        ## explorer "https://www.google.com/intl/en_us/chrome"

# download google chrome
Get-FileFromWeb -URL "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" -File "$env:SystemRoot\Temp\Chrome.msi"

# install google chrome
Start-Process -Wait "$env:SystemRoot\Temp\Chrome.msi" -ArgumentList "/quiet"

# install ublock origin lite
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist`" /v `"1`" /t REG_SZ /d `"ddkjiahejlhfcafbddmgiahcphecmpfh;https://clients2.google.com/service/update2/crx`" /f >nul 2>&1"

# add chrome policies
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Google\Chrome`" /v `"HardwareAccelerationModeEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Google\Chrome`" /v `"BackgroundModeEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SOFTWARE\Policies\Google\Chrome`" /v `"HighEfficiencyModeEnabled`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

# remove logon chrome
cmd /c "reg delete `"HKLM\Software\Microsoft\Active Setup\Installed Components\{8A69D345-D564-463c-AFF1-A69D9E530F96}`" /f >nul 2>&1"

# remove chrome services
$services = Get-Service | Where-Object { $_.Name -match 'Google' }
foreach ($service in $services) {
cmd /c "sc stop `"$($service.Name)`" >nul 2>&1"
cmd /c "sc delete `"$($service.Name)`" >nul 2>&1"
}

# remove chrome scheduled tasks
Get-ScheduledTask | Where-Object {$_.Taskname -match 'GoogleUpdateTaskMachineCore'} | Unregister-ScheduledTask -Confirm:$false
Get-ScheduledTask | Where-Object {$_.Taskname -match 'GoogleUpdateTaskMachineUA'} | Unregister-ScheduledTask -Confirm:$false
Get-ScheduledTask | Where-Object {$_.Taskname -match 'GoogleUpdaterTaskSystem'} | Unregister-ScheduledTask -Confirm:$false

        # FUNCTION SHOW-MENU
        function show-menu {
        Clear-Host
        Write-Host "INSTALL GRAPHICS DRIVERS" -ForegroundColor Yellow
        Write-Host "SELECT YOUR SYSTEM'S GPU`n" -ForegroundColor Yellow
        Write-Host " 1.  NVIDIA" -ForegroundColor Green
        Write-Host " 2.  AMD" -ForegroundColor Red
        Write-Host " 3.  INTEL" -ForegroundColor Blue
        Write-Host " 4.  SKIP`n"
        }
        :MainLoop while ($true) {
        show-menu
        $choice = Read-Host " "
        if ($choice -match '^[1-4]$') {
        switch ($choice) {
        1 {

        Clear-Host

        Write-Host "DOWNLOAD NVIDIA GPU DRIVER`n" -ForegroundColor Yellow
    	## explorer "https://www.nvidia.com/en-us/drivers"
		## shell:appsFolder\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel

# download driver
Start-Sleep -Seconds 5
Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://www.nvidia.com/en-us/drivers"
Wait-Process -Name chrome

        Write-Host "SELECT DOWNLOADED DRIVER`n" -ForegroundColor Yellow

# select driver
Start-Sleep -Seconds 5
$InstallFile = Show-ModernFilePicker -Mode File

        Write-Host "DEBLOATING DRIVER`n"

# extract driver with 7zip
& "C:\Program Files\7-Zip\7z.exe" x "$InstallFile" -o"$env:SystemRoot\Temp\NvidiaDriver" -y | Out-Null

# debloat nvidia driver
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\Display.Nview" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\FrameViewSDK" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\HDAudio" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\MSVCRT" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp.MessageBus" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvBackend" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvContainer" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvCpl" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvDLISR" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NVPCF" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvTelemetry" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvVAD" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\PhysX" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\PPC" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\ShadowPlay" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\CEF" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\osc" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\Plugins" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\UpgradeConsent" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\www" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\7z.dll" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\7z.exe" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\DarkModeCheck.exe" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\InstallerExtension.dll" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\NvApp.nvi" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\NvAppApi.dll" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\NvAppExt.dll" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemRoot\Temp\NvidiaDriver\NvApp\NvConfigGenerator.dll" -Force -ErrorAction SilentlyContinue | Out-Null

        Write-Host "INSTALLING DRIVER`n"

# install nvidia driver
Start-Process "$env:SystemRoot\Temp\NvidiaDriver\setup.exe" -ArgumentList "-s -noreboot -noeula -clean" -Wait -NoNewWindow

# install nvidia control panel
try {
Start-Process "winget" -ArgumentList "install `"9NF8H0H7WMLT`" --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --no-upgrade" -Wait -WindowStyle Hidden
} catch { }

# uninstall winget
Get-AppxPackage -allusers *Microsoft.Winget.Source* | Remove-AppxPackage

# delete old driver files
Remove-Item "$env:SystemDrive\NVIDIA" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

        Write-Host "IMPORTING SETTINGS`n"

# turn on disable dynamic pstate
$subkeys = Get-ChildItem -Path "Registry::HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -Force -ErrorAction SilentlyContinue
foreach($key in $subkeys){
if ($key -notlike '*Configuration'){
reg add "$key" /v "DisableDynamicPstate" /t REG_DWORD /d "1" /f | Out-Null
}
}

# disable hdcp
$subkeys = Get-ChildItem -Path "Registry::HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -Force -ErrorAction SilentlyContinue
foreach($key in $subkeys){
if ($key -notlike '*Configuration'){
reg add "$key" /v "RMHdcpKeyglobZero" /t REG_DWORD /d "1" /f | Out-Null
}
}

# unblock drs files
$path = "C:\ProgramData\NVIDIA Corporation\Drs"
Get-ChildItem -Path $path -Recurse | Unblock-File

# set physx to gpu
cmd /c "reg add `"HKLM\System\ControlSet001\Services\nvlddmkm\Parameters\Global\NVTweak`" /v `"NvCplPhysxAuto`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# enable developer settings
cmd /c "reg add `"HKLM\System\ControlSet001\Services\nvlddmkm\Parameters\Global\NVTweak`" /v `"NvDevToolsVisible`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

# allow access to the gpu performance counters to all users
$subkeys = Get-ChildItem -Path "Registry::HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -Force -ErrorAction SilentlyContinue
foreach($key in $subkeys){
if ($key -notlike '*Configuration'){
reg add "$key" /v "RmProfilingAdminOnly" /t REG_DWORD /d "0" /f | Out-Null
}
}
cmd /c "reg add `"HKLM\System\ControlSet001\Services\nvlddmkm\Parameters\Global\NVTweak`" /v `"RmProfilingAdminOnly`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# disable show notification tray icon
cmd /c "reg add `"HKCU\Software\NVIDIA Corporation\NvTray`" /v `"StartOnLogin`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# enable nvidia legacy sharpen
cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\FTS`" /v `"EnableGR535`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SYSTEM\ControlSet001\Services\nvlddmkm\Parameters\FTS`" /v `"EnableGR535`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Parameters\FTS`" /v `"EnableGR535`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# turn on no scaling for all displays
$configKeys = Get-ChildItem -Path "HKLM:\System\ControlSet001\Control\GraphicsDrivers\Configuration" -Recurse -ErrorAction SilentlyContinue
foreach ($key in $configKeys) {
$scalingValue = Get-ItemProperty -Path $key.PSPath -Name "Scaling" -ErrorAction SilentlyContinue
if ($scalingValue) {
$regPath = $key.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '').Replace('HKEY_LOCAL_MACHINE', 'HKLM')
Run-Trusted -command "reg add `"$regPath`" /v `"Scaling`" /t REG_DWORD /d `"2`" /f"
}
}

# turn on override the scaling mode set by games and programs for all displays
# perform scaling on display
$displayDbPath = "HKLM:\System\ControlSet001\Services\nvlddmkm\State\DisplayDatabase"
if (Test-Path $displayDbPath) {
$displays = Get-ChildItem -Path $displayDbPath -ErrorAction SilentlyContinue
foreach ($display in $displays) {
$regPath = $display.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '').Replace('HKEY_LOCAL_MACHINE', 'HKLM')
Run-Trusted -command "reg add `"$regPath`" /v `"ScalingConfig`" /t REG_BINARY /d `"DB02000010000000200100000E010000`" /f"
}
}

# download inspector
Get-FileFromWeb -URL "https://github.com/Orbmu2k/nvidiaProfileInspector/releases/download/2.4.0.31/nvidiaProfileInspector.zip" -File "$env:SystemRoot\Temp\Inspector.zip"

# extract inspector with 7zip
& "C:\Program Files\7-Zip\7z.exe" x "$env:SystemRoot\Temp\Inspector.zip" -o"$env:SystemRoot\Temp\Inspector" -y | Out-Null

# set config for inspector
$nipfile = @'
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Base Profile</ProfileName>
    <Executables/>
    <Settings>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter V3</SettingNameInfo>
        <SettingID>277041154</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Application Mode</SettingNameInfo>
        <SettingID>294973784</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Application State</SettingNameInfo>
        <SettingID>279476687</SettingID>
        <SettingValue>4</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Global Feature</SettingNameInfo>
        <SettingID>278196567</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Global Mode</SettingNameInfo>
        <SettingID>278196727</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>GSYNC - Indicator Overlay</SettingNameInfo>
        <SettingID>268604728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Maximum Pre-Rendered Frames</SettingNameInfo>
        <SettingID>8102046</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred Refresh Rate</SettingNameInfo>
        <SettingID>6600001</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Ultra Low Latency - CPL State</SettingNameInfo>
        <SettingID>390467</SettingID>
        <SettingValue>2</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Ultra Low Latency - Enabled</SettingNameInfo>
        <SettingID>277041152</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync</SettingNameInfo>
        <SettingID>11041231</SettingID>
        <SettingValue>138504007</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync - Smooth AFR Behavior</SettingNameInfo>
        <SettingID>270198627</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync - Tear Control</SettingNameInfo>
        <SettingID>5912412</SettingID>
        <SettingValue>2525368439</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vulkan/OpenGL Present Method</SettingNameInfo>
        <SettingID>550932728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Gamma Correction</SettingNameInfo>
        <SettingID>276652957</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Mode</SettingNameInfo>
        <SettingID>276757595</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Setting</SettingNameInfo>
        <SettingID>282555346</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filter - Optimization</SettingNameInfo>
        <SettingID>8703344</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filter - Sample Optimization</SettingNameInfo>
        <SettingID>15151633</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filtering - Mode</SettingNameInfo>
        <SettingID>282245910</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic Filtering - Setting</SettingNameInfo>
        <SettingID>270426537</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture Filtering - Negative LOD Bias</SettingNameInfo>
        <SettingID>1686376</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture Filtering - Quality</SettingNameInfo>
        <SettingID>13510289</SettingID>
        <SettingValue>20</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture Filtering - Trilinear Optimization</SettingNameInfo>
        <SettingID>3066610</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>CUDA - Force P2 State</SettingNameInfo>
        <SettingID>1343646814</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
	  <ProfileSetting>
        <SettingNameInfo>CUDA - Sysmem Fallback Policy</SettingNameInfo>
        <SettingID>283962569</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Power Management - Mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shader Cache - Cache Size</SettingNameInfo>
        <SettingID>11306135</SettingID>
        <SettingValue>4294967295</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Threaded Optimization</SettingNameInfo>
        <SettingID>549528094</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>OpenGL GDI Compatibility</SettingNameInfo>
        <SettingID>544392611</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred OpenGL GPU</SettingNameInfo>
        <SettingID>550564838</SettingID>
        <SettingValue>id,2.0:268410DE,00000100,GF - (400,2,161,24564) @ (0)</SettingValue>
        <ValueType>String</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
</ArrayOfProfile>
'@
Set-Content -Path "$env:SystemRoot\Temp\Inspector.nip" -Value $nipfile -Force

# import nip
Start-Process -wait "$env:SystemRoot\Temp\Inspector\nvidiaProfileInspector.exe" -ArgumentList "-silentImport -silent $env:SystemRoot\Temp\Inspector.nip"

        break MainLoop

          }
    	2 {

        Clear-Host

        Write-Host "DOWNLOAD AMD GPU DRIVER`n" -ForegroundColor Yellow
		## explorer "https://www.amd.com/en/support/download/drivers.html"
		## C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe

# download driver
Start-Sleep -Seconds 5
Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://www.amd.com/en/support/download/drivers.html"
Wait-Process -Name chrome

        Write-Host "SELECT DOWNLOADED DRIVER`n" -ForegroundColor Yellow

# select driver
Start-Sleep -Seconds 5
$InstallFile = Show-ModernFilePicker -Mode File

        Write-Host "DEBLOATING DRIVER`n"

# extract driver with 7zip
& "C:\Program Files\7-Zip\7z.exe" x "$InstallFile" -o"$env:SystemRoot\Temp\AmdDriver" -y | Out-Null

# debloat amd driver
$path = "$env:SystemRoot\Temp\AmdDriver\Packages\Drivers\Display\WT6A_INF"
Get-ChildItem $path -Directory | Where-Object {
    $_.Name -notlike "B*" -and
    $_.Name -ne "amdvlk" -and
    $_.Name -ne "amdogl" -and
	$_.Name -ne "amdocl"
} | Remove-Item -Recurse -Force

# edit xml files, set enabled & hidden to false
$xmlFiles = @(
"$env:SystemRoot\Temp\AmdDriver\Config\AMDAUEPInstaller.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\AMDCOMPUTE.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\AMDLinkDriverUpdate.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\AMDRELAUNCHER.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\AMDScoSupportTypeUpdate.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\AMDUpdater.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\AMDUWPLauncher.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\EnableWindowsDriverSearch.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\InstallUEP.xml"
"$env:SystemRoot\Temp\AmdDriver\Config\ModifyLinkUpdate.xml"
)
foreach ($file in $xmlFiles) {
if (Test-Path $file) {
$content = Get-Content $file -Raw
$content = $content -replace '<Enabled>true</Enabled>', '<Enabled>false</Enabled>'
$content = $content -replace '<Hidden>true</Hidden>', '<Hidden>false</Hidden>'
Set-Content $file -Value $content -NoNewline
}
}

# edit json files, set installbydefault to no
$jsonFiles = @(
"$env:SystemRoot\Temp\AmdDriver\Config\InstallManifest.json"
"$env:SystemRoot\Temp\AmdDriver\Bin64\cccmanifest_64.json"
)
foreach ($file in $jsonFiles) {
if (Test-Path $file) {
$content = Get-Content $file -Raw
$content = $content -replace '"InstallByDefault"\s*:\s*"Yes"', '"InstallByDefault" : "No"'
Set-Content $file -Value $content -NoNewline
}
}

        Write-Host "INSTALLING DRIVER`n"

# install amd driver
Start-Process -Wait "$env:SystemRoot\Temp\AmdDriver\Bin64\ATISetup.exe" -ArgumentList "-INSTALL -VIEW:2" -WindowStyle Hidden

# delete amdnoisesuppression startup
cmd /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Run`" /v `"AMDNoiseSuppression`" /f >nul 2>&1"

# delete startrsx startup
cmd /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce`" /v `"StartRSX`" /f >nul 2>&1"

# delete startcn task
Unregister-ScheduledTask -TaskName "StartCN" -Confirm:$false -ErrorAction SilentlyContinue

# delete amd audio coprocessr dsp driver
cmd /c "sc stop `"amdacpbus`" >nul 2>&1"
cmd /c "sc delete `"amdacpbus`" >nul 2>&1"

# delete amd streaming audio function driver
cmd /c "sc stop `"AMDSAFD`" >nul 2>&1"
cmd /c "sc delete `"AMDSAFD`" >nul 2>&1"

# delete amd function driver for hd audio service driver
cmd /c "sc stop `"AtiHDAudioService`" >nul 2>&1"
cmd /c "sc delete `"AtiHDAudioService`" >nul 2>&1"

# delete amd bug report tool
Remove-Item "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\AMD Bug Report Tool" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemDrive\Windows\SysWOW64\AMDBugReportTool.exe" -Force -ErrorAction SilentlyContinue | Out-Null

# uninstall amd install manager
$findamdinstallmanager = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
$amdinstallmanager = Get-ItemProperty $findamdinstallmanager -ErrorAction SilentlyContinue |
Where-Object { $_.DisplayName -like "*AMD Install Manager*" }
if ($amdinstallmanager) {
$guid = $amdinstallmanager.PSChildName
Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow
}

# delete download
Remove-Item "$InstallFile" -Force -ErrorAction SilentlyContinue | Out-Null

# cleaner start menu shortcut path
$folderName = "AMD Software$([char]0xA789) Adrenalin Edition"
Move-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$folderName\$folderName.lnk" -Destination "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$folderName" -Recurse -Force -ErrorAction SilentlyContinue

# delete old driver files
Remove-Item "$env:SystemDrive\AMD" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

# wait incase driver timeout or installer bugs

        80..0 | % { Write-Host "`rIMPORTING SETTINGS $_   " -NoNewline; Start-Sleep 1 }; Write-Host "`n"

# open & close amd software adrenalin edition settings page so settings stick
Start-Process "C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe"
Start-Sleep -Seconds 30
Stop-Process -Name "RadeonSoftware" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# disable ulps
$subkeys = Get-ChildItem -Path "Registry::HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -Force -ErrorAction SilentlyContinue
foreach($key in $subkeys){
if ($key -notlike '*Configuration'){
reg add "$key" /v "EnableUlps" /t REG_DWORD /d "0" /f | Out-Null
}
}

# import amd software adrenalin edition settings
# system
# manual check for updates
cmd /c "reg add `"HKCU\Software\AMD\CN`" /v `"AutoUpdate`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

# graphics
# graphics profile - custom
cmd /c "reg add `"HKCU\Software\AMD\CN`" /v `"WizardProfile`" /t REG_SZ /d `"PROFILE_CUSTOM`" /f >nul 2>&1"

# wait for vertical refresh - always off
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$optionKeys = $allKeys | Where-Object { $_.PSChildName -eq "UMD" }
foreach ($key in $optionKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"VSyncControl`" /t REG_BINARY /d `"3000`" /f >nul 2>&1"
}

# texture filtering quality - performance
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$optionKeys = $allKeys | Where-Object { $_.PSChildName -eq "UMD" }
foreach ($key in $optionKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"TFQ`" /t REG_BINARY /d `"3200`" /f >nul 2>&1"
}

# tessellation mode - override application settings
# maximum tessellation level - off
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$optionKeys = $allKeys | Where-Object { $_.PSChildName -eq "UMD" }
foreach ($key in $optionKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"Tessellation`" /t REG_BINARY /d `"3100`" /f >nul 2>&1"
cmd /c "reg add `"$regPath`" /v `"Tessellation_OPTION`" /t REG_BINARY /d `"3200`" /f >nul 2>&1"
}

# display
# accept custom resolution eula
cmd /c "reg add `"HKCU\Software\AMD\CN\CustomResolutions`" /v `"EulaAccepted`" /t REG_SZ /d `"true`" /f >nul 2>&1"

# accept overrides eula
cmd /c "reg add `"HKCU\Software\AMD\CN\DisplayOverride`" /v `"EulaAccepted`" /t REG_SZ /d `"true`" /f >nul 2>&1"

# disable hdcp support
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$edidKeysWithSuffix = $allKeys | Where-Object { $_.PSChildName -match '^EDID_[A-F0-9]+_[A-F0-9]+_[A-F0-9]+$' }
foreach ($edidKey in $edidKeysWithSuffix) {
if ($edidKey.PSChildName -match '^(EDID_[A-F0-9]+_[A-F0-9]+)_[A-F0-9]+$') {
$baseEdidName = $matches[1]
$parentPath = Split-Path $edidKey.PSPath
$baseEdidPath = Join-Path $parentPath $baseEdidName
if (!(Test-Path $baseEdidPath)) {
New-Item -Path $baseEdidPath -Force -ErrorAction SilentlyContinue | Out-Null
}   
$optionPathNew = Join-Path $baseEdidPath "Option"
if (!(Test-Path $optionPathNew)) {
New-Item -Path $optionPathNew -Force -ErrorAction SilentlyContinue | Out-Null
}
$regPath = $optionPathNew.Replace('Microsoft.PowerShell.Core\Registry::', '').Replace('HKEY_LOCAL_MACHINE', 'HKLM')
cmd /c "reg add `"$regPath`" /v `"All_nodes`" /t REG_BINARY /d `"50726F74656374696F6E436F6E74726F6C00`" /f >nul 2>&1"
cmd /c "reg add `"$regPath`" /v `"default`" /t REG_BINARY /d `"64`" /f >nul 2>&1"
cmd /c "reg add `"$regPath`" /v `"ProtectionControl`" /t REG_BINARY /d `"0100000001000000`" /f >nul 2>&1"
}
}

# vari-bright - maximize brightness
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$optionKeys = $allKeys | Where-Object { $_.PSChildName -eq "power_v1" }
foreach ($key in $optionKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"abmlevel`" /t REG_BINARY /d `"00000000`" /f >nul 2>&1"
}

# preferences
# disable system tray menu
cmd /c "reg add `"HKCU\Software\AMD\CN`" /v `"SystemTray`" /t REG_SZ /d `"false`" /f >nul 2>&1"

# disable toast notifications
cmd /c "reg add `"HKCU\Software\AMD\CN`" /v `"CN_Hide_Toast_Notification`" /t REG_SZ /d `"true`" /f >nul 2>&1"

# disable animation & effects
cmd /c "reg add `"HKCU\Software\AMD\CN`" /v `"AnimationEffect`" /t REG_SZ /d `"false`" /f >nul 2>&1"

# notifications - remove
cmd /c "reg delete `"HKCU\Software\AMD\CN\Notification`" /f >nul 2>&1"
cmd /c "reg add `"HKCU\Software\AMD\CN\Notification`" /f >nul 2>&1"
cmd /c "reg add `"HKCU\Software\AMD\CN\FreeSync`" /v `"AlreadyNotified`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
cmd /c "reg add `"HKCU\Software\AMD\CN\OverlayNotification`" /v `"AlreadyNotified`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
cmd /c "reg add `"HKCU\Software\AMD\CN\VirtualSuperResolution`" /v `"AlreadyNotified`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

        break MainLoop

          }
    	3 {

        Clear-Host
        
        Write-Host "DOWNLOAD INTEL GPU DRIVER`n" -ForegroundColor Yellow
		## explorer "https://www.intel.com/content/www/us/en/search.html#sortCriteria=%40lastmodifieddt%20descending&f-operatingsystem_en=Windows%2011%20Family*&f-downloadtype=Drivers&cf-tabfilter=Downloads&cf-downloadsppth=Graphics"
		## shell:appsFolder\AppUp.IntelGraphicsExperience_8j3eq9eme6ctt!App
		## C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe

# download driver
Start-Sleep -Seconds 5
Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://www.intel.com/content/www/us/en/search.html#sortCriteria=%40lastmodifieddt%20descending&f-operatingsystem_en=Windows%2011%20Family*&f-downloadtype=Drivers&cf-tabfilter=Downloads&cf-downloadsppth=Graphics"
Wait-Process -Name chrome

        Write-Host "SELECT DOWNLOADED DRIVER`n" -ForegroundColor Yellow

# select driver
Start-Sleep -Seconds 5
$InstallFile = Show-ModernFilePicker -Mode File

        Write-Host "DEBLOATING DRIVER`n"

# extract driver with 7zip
& "C:\Program Files\7-Zip\7z.exe" x "$InstallFile" -o"$env:SystemDrive\IntelDriver" -y | Out-Null

        Write-Host "INSTALLING DRIVER`n"

# install intel driver
Start-Process "cmd.exe" -ArgumentList "/c `"$env:SystemDrive\IntelDriver\Installer.exe`" -f --noExtras --terminateProcesses -s" -WindowStyle Hidden -Wait

# install intel control panel
$IntelGraphicsSoftware = Get-ChildItem "$env:SystemDrive\IntelDriver\Resources\Extras\IntelGraphicsSoftware_*.exe" | Select-Object -First 1 -ExpandProperty Name
if ($IntelGraphicsSoftware) {
Start-Process "$env:SystemDrive\IntelDriver\Resources\Extras\$IntelGraphicsSoftware" -ArgumentList "/s" -Wait -NoNewWindow
}

# delete intel® graphics software startup
$FileName = "Intel$([char]0xAE) Graphics Software"
cmd /c "reg delete `"HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run`" /v `"$FileName`" /f >nul 2>&1"

# delete intelgfxfwupdatetool service
cmd /c "sc stop `"IntelGFXFWupdateTool`" >nul 2>&1"
cmd /c "sc delete `"IntelGFXFWupdateTool`" >nul 2>&1"

# delete intel® content protection hdcp service
cmd /c "sc stop `"cplspcon`" >nul 2>&1"
cmd /c "sc delete `"cplspcon`" >nul 2>&1"

# delete intel(r) cta child driver driver
cmd /c "sc stop `"CtaChildDriver`" >nul 2>&1"
cmd /c "sc delete `"CtaChildDriver`" >nul 2>&1"

# delete intel(r) graphics system controller auxiliary firmware interface driver
cmd /c "sc stop `"GSCAuxDriver`" >nul 2>&1"
cmd /c "sc delete `"GSCAuxDriver`" >nul 2>&1"

# delete intel(r) graphics system controller firmware interface driver
cmd /c "sc stop `"GSCx64`" >nul 2>&1"
cmd /c "sc delete `"GSCx64`" >nul 2>&1"

# stop intelgraphicssoftware presentmonservice running
$stop = "IntelGraphicsSoftware", "PresentMonService"
$stop | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# delete presentmonservice.exe
Remove-Item "$env:SystemDrive\Program Files\Intel\Intel Graphics Software\PresentMonService.exe" -Force -ErrorAction SilentlyContinue | Out-Null 

# delete download
Remove-Item "$InstallFile" -Force -ErrorAction SilentlyContinue | Out-Null

# cleaner start menu shortcut path
$FileName = "Intel$([char]0xAE) Graphics Software"
Move-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Intel\Intel Graphics Software\$FileName.lnk" -Destination "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Intel" -Recurse -Force -ErrorAction SilentlyContinue

# delete old driver files
Remove-Item "$env:SystemDrive\Intel" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item "$env:SystemDrive\IntelDriver" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

        Write-Host "IMPORTING SETTINGS`n"

# create 3dkeys key
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$adapterKeys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue
foreach ($key in $adapterKeys) {
if ($key.PSChildName -match '^\d{4}$') {
$regPath = $key.Name
cmd /c "reg add `"$regPath\3DKeys`" /f >nul 2>&1"
}
}

# display
# variable refresh rate mode - disabled
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$optionKeys = $allKeys | Where-Object { $_.PSChildName -eq "3DKeys" }
foreach ($key in $optionKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"Global_VRRWindowedBLT`" /t REG_DWORD /d `"2`" /f >nul 2>&1"
}

# variable refresh rate - disabled
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$adapterKeys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue
foreach ($key in $adapterKeys) {
if ($key.PSChildName -match '^\d{4}$') {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"AdaptiveVsyncEnableUserSetting`" /t REG_BINARY /d `"00000000`" /f >nul 2>&1"
}
}

# graphics
# frame synchronization - vsync off
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$optionKeys = $allKeys | Where-Object { $_.PSChildName -eq "3DKeys" }
foreach ($key in $optionKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"Global_AsyncFlipMode`" /t REG_DWORD /d `"2`" /f >nul 2>&1"
}

# low latency mode - off
$basePath = "HKLM:\System\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$allKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
$optionKeys = $allKeys | Where-Object { $_.PSChildName -eq "3DKeys" }
foreach ($key in $optionKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"Global_LowLatency`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
}

        break MainLoop

          }
        4 {

        Clear-Host

        break MainLoop

          }
          }
          } else {
          Write-Host "Invalid input. Please select a valid option (1-4).`n" -ForegroundColor Yellow
          Pause
          show-menu
          }
          }

        Clear-Host
        Write-Host "SET" -ForegroundColor Yellow
        Write-Host "- SOUND" -ForegroundColor Yellow
        Write-Host "- RESOLUTION" -ForegroundColor Yellow
        Write-Host "- REFRESH RATE" -ForegroundColor Yellow
        Write-Host "- PRIMARY DISPLAY`n" -ForegroundColor Yellow
		## shell:appsFolder\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel
    	## ms-settings:display
		## mmsys.cpl

# open display, nvidia & sound panels
try {
Start-Process "ms-settings:display"
} catch { }
try {
Start-Process shell:appsFolder\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel
} catch { }
Start-Process mmsys.cpl
Pause

        Clear-Host

# disable automatically manage color for apps
$basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\MonitorDataStore"
$monitorKeys = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue
foreach ($key in $monitorKeys) {
$regPath = $key.Name
cmd /c "reg add `"$regPath`" /v `"AutoColorManagementEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
cmd /c "reg add `"$regPath`" /v `"AutoColorManagementSupported`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
}

# reapply for nvidia cards after changing resolution
# turn on no scaling for all displays
$configKeys = Get-ChildItem -Path "HKLM:\System\ControlSet001\Control\GraphicsDrivers\Configuration" -Recurse -ErrorAction SilentlyContinue
foreach ($key in $configKeys) {
$scalingValue = Get-ItemProperty -Path $key.PSPath -Name "Scaling" -ErrorAction SilentlyContinue
if ($scalingValue) {
$regPath = $key.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '').Replace('HKEY_LOCAL_MACHINE', 'HKLM')
Run-Trusted -command "reg add `"$regPath`" /v `"Scaling`" /t REG_DWORD /d `"2`" /f"
}
}

# enable msi mode for all gpus
$gpuDevices = Get-PnpDevice -Class Display
foreach ($gpu in $gpuDevices) {
$instanceID = $gpu.InstanceId
cmd /c "reg add `"HKLM\SYSTEM\ControlSet001\Enum\$instanceID\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties`" /v `"MSISupported`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
}

# show all hidden taskbar icons
        ## ms-settings:taskbar
$notifyiconsettings = Get-ChildItem -Path 'registry::HKEY_CURRENT_USER\Control Panel\NotifyIconSettings' -Recurse -Force
foreach ($setreg in $notifyiconsettings) {
if ((Get-ItemProperty -Path "registry::$setreg").IsPromoted -eq 0) {
}
else {
Set-ItemProperty -Path "registry::$setreg" -Name 'IsPromoted' -Value 1 -Force
}
}

        Write-Host "RESTARTING`n" -ForegroundColor Red

# restart
Start-Sleep -Seconds 5
shutdown -r -t 00
