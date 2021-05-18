<#
CPU Reader v. 1.02
copyright (c) 2015 Michal Krowicki
 
https://krowicki.pl/tag/icinga/
 
Nagios/Icinga Check values from Open Hardware Monitor [http://openhardwaremonitor.org] WMI data
 
W A R N I N G
This is my first PowerShell script!
Tested only on:
Intel Xeon E3-1245 V2
Intel Core i7-3517U
 
To run this script, You need PS v4 (not tested on older versions)
 
If you find a bug in the code, or if you have questions, please, go to the website and write a comment.
#>
 
[CmdletBinding()]
Param (
 [Parameter(Mandatory=$False)]
 [ValidateNotNullOrEmpty()]
 [int] $tw = "65",
 
 [Parameter(Mandatory=$False)]
 [ValidateNotNullOrEmpty()]
 [int] $tc = 80,
 
 [Parameter(Mandatory=$False)]
 [ValidateNotNullOrEmpty()]
 [int] $lw = 50,
 
 [Parameter(Mandatory=$False)]
 [ValidateNotNullOrEmpty()]
 [int] $lc = 80
)
 
Add-Type -TypeDefinition @"
   public enum STATE
   {
      OK = 0,
      Warning = 1,
      Critical = 2,
      Unknown = 3
   }
"@
 
$exitStatus = [STATE]::OK
 
Add-Type -TypeDefinition @"
public struct structValue
{
    public string name;
    public string unit;
    public string value;
    public string warn;
    public string crit;
    public string min;
    public string max;
}
 
public struct structCore
{
    public string name;
    public structValue temperature;
    public structValue clock;
    public structValue load;
}
 
 
public struct structCPU{
    public string name;
    public structValue temperature;
    public structValue busSpeed;
    public structValue load;
    public structValue[] power;
    public structCore[] core; 
}
"@
 
 
$cpu = New-Object structCPU
$core = New-Object structCore
$values = New-Object structValue
 
$cpuTable = Get-WmiObject -Namespace "Root\OpenHardwareMonitor" -Query "select Identifier,Name from Hardware WHERE HardwareType='CPU'" | sort-object -Property Name -Unique
 
$msg = ""
foreach ($_cpu in $cpuTable)
{
    $cpu.name+=$cpuTable.Name
    $cores = Get-WmiObject -Namespace "Root\OpenHardwareMonitor" -Query "SELECT Name FROM Sensor WHERE Parent='$($_cpu.Identifier)' and Name like 'CPU Core %'"  | sort-object -Property Name -Unique
    foreach($_core in $cores)
    {
        $core.name=$_core.name.Replace("CPU ","").Replace("#","")
        $cpu.core += $core
    }
    $tempCore = New-Object structCore
 
 
    $wmiVal = Get-WmiObject -Namespace "Root\OpenHardwareMonitor" -Query "SELECT Name,Value,SensorType,Min,Max FROM Sensor WHERE Parent='$($_cpu.Identifier)'"  | sort-object -Property SensorType,Name -Unique
    foreach($v in $wmiVal)
    {
 
        $coreNo=$($v.Name.Substring($v.Name.Length-1))
 
        $values.name=$v.Name.Replace("CPU ","")
 
        switch ($v.SensorType)
        {
            "Clock"      
            {
                $values.unit="MHz"
                $values.value=[math]::Round($v.Value,0)
                $values.min=[math]::Round($v.Min,0)
                $values.max=[math]::Round($v.Max,0)
                if( $coreNo -match "[0-9]"){$tempCore=$cpu.core[$coreNo-1]; $tempCore.clock=$values; $cpu.core[$coreNo-1]=$tempCore}
                else {$cpu.busSpeed=$values}
            }
            "Load"       
            {
                $values.unit="%"
                $values.value=$([math]::Round($v.Value,0))
                $values.min=0
                $values.max=100
                if( $coreNo -match "[0-9]"){$tempCore=$cpu.core[$coreNo-1]; $tempCore.load=$values; $cpu.core[$coreNo-1]=$tempCore}
                else {$cpu.load=$values}
                if($lc -and $lw)
                {
                    if([int]$values.value -ge $lc)
                    { $exitStatus=[STATE]::Critical }
                    elseif(([int]$values.value -ge $lw) -and ($exitStatus -ne [STATE]::Critical) )
                    { $exitStatus=[STATE]::Warning }
                }
            }
            "Power"      
            {
                $values.unit="W"
                $values.value=$([math]::Round($v.Value,2))
                $values.min=0
                $values.max=[math]::Round($v.Max,2)
                $cpu.power+=$values
            }
            "Temperature"
            {
                $values.unit="C"
                $values.value=$([math]::Round($v.Value,0))
                $values.min=0
                $values.max=105
                if( $coreNo -match "[0-9]"){$tempCore=$cpu.core[$coreNo-1]; $tempCore.temperature=$values; $cpu.core[$coreNo-1]=$tempCore}
                else {$cpu.temperature =$values}
                if(($tc -and $tw))
                {
                    if([int]$values.value -ge $tc)
                    { $exitStatus=[STATE]::Critical }
                    elseif(([int]$values.value -ge $tw) -and ($exitStatus -ne [STATE]::Critical) )
                    { $exitStatus=[STATE]::Warning }
                }
            }
            default      
            {throw "Unknown sensor or unit!"}
        }
    }
}
 
 
#dopisać pętlę dla kilku procesorów - do każdego czeka dodać CPU? gdzie ? to nr procesora
$msg = "Processor $($cpu.name), "
$msg += "$($cpu.busSpeed.name) $($cpu.busSpeed.value)$($cpu.busSpeed.unit), "
$msg += "Package temperature $($cpu.temperature.value)$($cpu.temperature.unit), "
$msg += "$($cpu.load.name) load $($cpu.load.value)$($cpu.load.unit), "
$msg += "Powers: "
foreach ($cpupw in $cpu.power)
{
    $msg += "$($cpupw.name) $($cpupw.value)$($cpupw.unit), "
}
 
$msg = "$($msg.Substring(0,$msg.Length-2)); "
$msg += "$($cpu.core.Count) core$(if($cpu.core.Count -gt 1) {"s"}):"
$coremsg = ""
foreach ($cpucr in $cpu.core)
{
    $coreshortname = ""
    $msg += "$($cpucr.name): "
    $msg += "Clock $($cpucr.clock.value)$($cpucr.clock.unit), "
    $coremsg += "'"
    $coreshortname += $cpucr.clock.name.Replace(" #","")
    $coremsg += $coreshortname
    $coremsg += "Clock='$($cpucr.clock.value)$($cpucr.clock.unit);;;$($cpucr.clock.min);$($cpucr.clock.max) '"
    $coremsg += $coreshortname
    $coremsg += "Load='$($cpucr.load.value)$($cpucr.load.unit);$(if($lw){$lw});$(if($lc){$lc});$($cpucr.load.min);$($cpucr.load.max) '"
    $coremsg += $coreshortname
    $coremsg += "Temp='$($cpucr.temperature.value)$($cpucr.temperature.unit);$(if($tw){$tw});$(if($tc){$tc});$($cpucr.temperature.min);$($cpucr.temperature.max) "
         
    $msg += "Load $($cpucr.load.value)$($cpucr.load.unit), "
    $msg += "Temperature $($cpucr.temperature.value)$($cpucr.temperature.unit), "
 
}
$msg = "$($msg.Substring(0,$msg.Length-2))|"
$msg += "'CPU$($cpu.load.name)Load='$($cpu.load.value)$($cpu.load.unit);$(if($lw){$lw});$(if($lc){$lc});$($cpu.load.min);$($cpu.load.max) "
$msg += "'CPUPower='$($cpu.power[2].value)$($cpu.power[2].unit);;;$($cpu.power[2].min);$($cpu.power[2].max) "
$msg += "'CPU$($cpu.temperature.name)Temp='$($cpu.temperature.value)$($cpu.temperature.unit);$(if($tw){$tw});$(if($tc){$tc});$($cpu.temperature.min);$($cpu.temperature.max) "
$msg += $coremsg
 
$msg = $exitStatus.ToString() + " : " + $msg
 
echo $msg
#echo $exitStatus.value__
Exit($exitStatus.value__)
