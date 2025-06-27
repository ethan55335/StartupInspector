
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

}


function CreateDatabase {

$Database = "C:\Temp\tempdb.sqlite"
$droptablehosts = "DROP TABLE IF EXISTS Hosts"
$droptableregistry = "DROP TABLE IF EXISTS RegistryAutoStart"
$droptableservices = "DROP TABLE IF EXISTS ServicesAutoStart"
$droptabletasks = "DROP TABLE IF EXISTS ScheduledTasks"   
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

Invoke-SqliteQuery -Database $Database -Query $droptablehosts
Invoke-SqliteQuery -Database $Database -Query $droptableregistry
Invoke-SqliteQuery -Database $Database -Query $droptableservices
Invoke-SqliteQuery -Database $Database -Query $droptabletasks
Invoke-SqliteQuery -Database $Database -Query $query
Invoke-SqliteQuery -Database $Database -Query $query2
Invoke-SqliteQuery -Database $Database -Query $query3
Invoke-SqliteQuery -Database $Database -Query $query4

return $Database
}

function AddHostInfo{

    param(
        $hostname
    )

    $IPaddress = invoke-command -ComputerName $hostname -ScriptBlock {Resolve-DnsName -Name DESKTOP-JVK39S0 | where-object {$_.Type -eq "A"} | Select-Object -ExpandProperty IPAddress}
    $OSname = invoke-command -ComputerName $hostname -ScriptBlock {Get-ComputerInfo | Select-Object osname}

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


}

Main