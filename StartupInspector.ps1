
import-module PSSqlite

function GetStartupItems {

param (
   $hostname
)

$regpaths = @(   
"HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
"HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
"HKCU:\\Software\Microsoft\Windows\CurrentVersion\RunOnce"

)

$RegStartup = @{}
$ServiceStartup = @{}

foreach ($path in $regpaths){

    $key = Get-ItemProperty -Path $path

    $values = $key.PSObject.Properties | Select-Object Name, Value

   foreach ($value in $values){
    $RegStartup[$value.name] = $value.Value
   }

}

$services = Get-CimInstance -ClassName Win32_Service | where-object {$_.StartMode -eq "Auto"} | select Name,Pathname
foreach ($service in $services){

    $ServiceStartup[$service.Name] = $service.Pathname
}

return @($RegStartup, $ServiceStartup)

}



function CreateDatabase {

$Database = "C:\Temp\tempdb.sqlite"
$droptablehosts = "DROP TABLE IF EXISTS Hosts"
$droptableregistry = "DROP TABLE IF EXISTS RegistryAutoStart"
$droptableservices = "DROP TABLE IF EXISTS ServicesAutoStart"   
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
Invoke-SqliteQuery -Database $Database -Query $droptablehosts
Invoke-SqliteQuery -Database $Database -Query $droptableregistry
Invoke-SqliteQuery -Database $Database -Query $droptableservices
Invoke-SqliteQuery -Database $Database -Query $query
Invoke-SqliteQuery -Database $Database -Query $query2
Invoke-SqliteQuery -Database $Database -Query $query3

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
   
}


}

Main