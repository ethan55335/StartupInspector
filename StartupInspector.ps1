
import-module PSSqlite

function GetStartupItems {

param (
   $hostname
)

$GetRegScriptBlock = {

$regpaths = @(   
"HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
"HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
"HKCU:\\Software\Microsoft\Windows\CurrentVersion\RunOnce"

)
$RegStartup = @{}
foreach ($path in $regpaths){

    $key = Get-ItemProperty -Path $path

    $values = $key.PSObject.Properties | Select-Object Name, Value | Where-Object { $_.Name -NotMatch "PSPath|PSParentPath|PSProvider|PSChildName|PSDrive"}
   
   foreach ($value in $values){
    $RegStartup[$value.name] = $value.Value
   }

}

Return $RegStartup
}


$GetServiceScriptBlock = {
$ServiceStartup = @{}
$services = Get-CimInstance -ClassName Win32_Service | where-object {$_.StartMode -eq "Auto"} | select Name,Pathname
foreach ($service in $services){

    $ServiceStartup[$service.Name] = $service.Pathname
}

return $ServiceStartup

}

$GetScheduledTaskScriptBlock = {



$ScheduledTasks = @{}

get-scheduledtask | foreach-object {

    $Name = $_.TaskName
    $PathToBinary = $_.Actions.Execute
    if ($PathToBinary.Length -gt 1 ){$ScheduledTasks[$name] = $PathToBinary}
    
}

return $ScheduledTasks




}

$GetStartupFolderItemsScriptBlock = {

    $startupitems = @{}
    $folderpaths = new-object System.Collections.ArrayList
    $folderpaths.add("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp")

    $users = Get-ChildItem C:\Users -Directory | Where-Object {$_.name -notmatch 'Public'} | Select-Object -ExpandProperty Name
        foreach($user in $users){
            $appdatastartuppath = "C:\Users\" + "$($user)" + "\Appdata\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
            $folderpaths.add($appdatastartuppath)
        }
    foreach ($folderpath in $folderpaths){

        $startup = Get-ChildItem $folderpath | Select-Object -ExpandProperty Fullname
        foreach ($item in $startup){
            if ($item -match ".lnk"){
                $wshShell = New-Object -Comobject WScript.shell
                $itemshortcut = $wshShell.CreateShortcut($item)
                $itemshortcutpath = $itemshortcut.Targetpath
                $filehash = Get-FileHash $itemshortcutpath
                $startupitems[$item] = @{
                    "Path" = $itemshortcutpath
                    "Filehash" = $filehash.hash
                }

            }
            else {
                $filehash = get-filehash $item
                $startupitems[$item] = @{
                    "Path" = $item
                    "Filehash" = $filehash.hash
                }
            }

        }    

    }

    return $startupitems
}

$query0 = "SELECT MachineID from Hosts WHERE hostname = ('$($hostname)')"
$machineid = Invoke-SqliteQuery -Database $Database -Query $query0
$machineid = $machineid.MachineID


$ScheduledTasks = invoke-command -ComputerName $hostname -ScriptBlock $GetScheduledTaskScriptBlock
foreach ($item in $ScheduledTasks.keys){
    $query3 = "INSERT INTO ScheduledTasks (MachineID, taskname, binarypath) VALUES ( '$($machineid)',  '$($item)', '$($ScheduledTasks[$item])')"
    Invoke-SqliteQuery -Database $Database -query $query3
}

$RegistryStartupItems = invoke-command -ComputerName $hostname -ScriptBlock $GetRegScriptBlock
foreach ($item in $RegistryStartupItems.keys){
    $query1 = "INSERT INTO RegistryAutoStart (MachineID, name, value) VALUES ( '$($machineid)',  '$($item)', '$($RegistryStartupItems[$item])')"
    Invoke-SqliteQuery -Database $Database -query $query1}

$ServicesStartupItems = invoke-command -ComputerName $hostname -ScriptBlock $GetServiceScriptBlock
foreach ($item in $ServicesStartupItems.keys){
    $query2 = "INSERT INTO ServicesAutoStart (MachineID, ServiceName, ServicePath) VALUES ( '$($machineid)', '$($item)', '$($ServicesStartupItems[$item])')"
    Invoke-SqliteQuery -Database $Database -query $query2}

$StartupFolderItems = invoke-command -ComputerName $hostname -ScriptBlock $GetStartupFolderItemsScriptBlock
foreach ($item in $StartupFolderItems.keys){
    $query4 = "INSERT INTO StartupFolderItems (MachineID, StartupName, FilePath, FileHash) VALUES ('$($machineid)', '$($item)','$($StartupFolderItems.$item.Path)', '$($StartupFolderItems.$item.FileHash)')"
    Invoke-SqliteQuery -Database $Database -query $query4
}

}


function CreateDatabase {

$Database = "C:\Temp\tempdb.sqlite"
$droptablehosts = "DROP TABLE IF EXISTS Hosts"
$droptableregistry = "DROP TABLE IF EXISTS RegistryAutoStart"
$droptableservices = "DROP TABLE IF EXISTS ServicesAutoStart"
$droptabletasks = "DROP TABLE IF EXISTS ScheduledTasks"   
$droptablestartup = "DROP TABLE IF EXISTS StartupFolderItems"
$query = "
    CREATE TABLE Hosts (
    MachineID INTEGER PRIMARY KEY AUTOINCREMENT,
    Hostname TEXT,
    IPaddress TEXT,
    OSname)"
$query2 = "
    CREATE TABLE RegistryAutoStart (
    EntryID INTEGER PRIMARY KEY AUTOINCREMENT,
    MachineID INTEGER,
    Name TEXT,
    Value TEXT,
    FOREIGN KEY (MachineID) REFERENCES Hosts(MachineID))"
$query3 = "
    CREATE TABLE ServicesAutoStart (
    EntryID INTEGER PRIMARY KEY AUTOINCREMENT,
    MachineID INTEGER,
    ServiceName TEXT,
    ServicePath TEXT,
    FOREIGN KEY (MachineID) REFERENCES Hosts(MachineID))"
$query4 = "
    CREATE TABLE ScheduledTasks (
    EntryID INTEGER PRIMARY KEY AUTOINCREMENT,
    MachineID INTEGER,
    TaskName TEXT,
    BinaryPath TEXT,
    FOREIGN KEY (MachineID) REFERENCES Hosts(MachineID))"
$query5 = "
    CREATE TABLE StartupFolderItems (
    EntryID INTEGER PRIMARY KEY AUTOINCREMENT,
    MachineID INTEGER,
    StartupName TEXT,
    FilePath TEXT,
    FileHash TEXT,
    FOREIGN KEY (MachineID) REFERENCES Hosts(MachineID))"

Invoke-SqliteQuery -Database $Database -Query $droptablehosts
Invoke-SqliteQuery -Database $Database -Query $droptableregistry
Invoke-SqliteQuery -Database $Database -Query $droptableservices
Invoke-SqliteQuery -Database $Database -Query $droptabletasks
Invoke-SqliteQuery -Database $Database -Query $droptablestartup
Invoke-SqliteQuery -Database $Database -Query $query
Invoke-SqliteQuery -Database $Database -Query $query2
Invoke-SqliteQuery -Database $Database -Query $query3
Invoke-SqliteQuery -Database $Database -Query $query4
Invoke-SqliteQuery -Database $Database -Query $query5

return $Database
}

function AddHostInfo{

    param(
        $hostname
    )

    $IPaddress = invoke-command -ComputerName $hostname -ScriptBlock {Resolve-DnsName -Name DESKTOP-JVK39S0 | where-object {$_.Type -eq "A"} | Select-Object -ExpandProperty IPAddress}
    $OSname = invoke-command -ComputerName $hostname -ScriptBlock {Get-ComputerInfo | Select-Object -ExpandProperty osname}

    $query = "INSERT INTO Hosts (hostname, ipaddress, osname) VALUES ('$($hostname)', '$($IPaddress)', '$($OSname)')"
    Invoke-SqliteQuery -Database $Database -query $query
    
  

}


function main {

$Database = CreateDatabase

$filepath = read-host "please enter the path to the file containing the hostnames of the target systems"
$hosts = get-content -Path $filepath

foreach ($PC in $hosts){

   AddHostInfo($PC)
   GetStartupItems($PC)
}

write-host "Collected data on the following hosts: "
$hosts

$answer = read-host "Would you like to see the collected data for each host?"

if ($answer -eq "yes"){

    foreach($PC in $hosts){

    $q = "SELECT MachineID FROM Hosts WHERE Hostname = '$($PC)' "
    $MachineID = Invoke-SqliteQuery -Database $Database -query $q
    $MachineID = $MachineID | Select-Object -ExpandProperty MachineID
    $q2 = "SELECT * FROM RegistryAutoStart WHERE MachineID = '$($MachineID)'"
    $RegAutoStarts = Invoke-SqliteQuery -Database $Database -Query $q2
    Write-Host -ForegroundColor Yellow "The following registry run keys were found on host $($PC):"
    $RegAutoStarts
    }

}


}

Main