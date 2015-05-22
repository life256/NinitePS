param(
		
		[Parameter(ParameterSetName='install')]
		[Switch]$install,
		[Parameter(ParameterSetName='uninstall')]
		[Switch]$uninstall,
		[Parameter(ParameterSetName='audit')]
		[Switch]$audit,
		[Parameter(ParameterSetName='update')]
		[Switch]$update,
		[Parameter(ValueFromRemainingArguments=$true,Position=0)]
		[string[]]$product,
        [Switch]$FullReports
)

#Get all machines in AD and test their connectivity

Import-Module ActiveDirectory
#$ADList = Get-ADComputer -Filter '*' 
$ADList = Get-ADComputer -Filter {(cn -eq "JS-MSI" -or cn -eq "BP-TELLER-001")}

if($install){
	$job = @(
		"/disableshortcuts",
		"/disableautoupdate"
	)
}	

if($uninstall){
	$job = @(
		"/uninstall"		
	)
}

if($update){
	$job = @(
		"/updateonly",
		"/disableshortcuts",
		"/disableautoupdate"
	)
}

if($audit){
	$job = @(
		"/audit"
	)
}


$job += @("/silent",".")

if($product){
    $job += @("/select")
    $job += $product
}



	

function create_hash ([array] $doublearray) {
	$keys = $doublearray[0].split(",")
	$values = $doublearray[1].split(",")
    $h = @{}
    if ($keys.Length -ne $values.Length) {
        Write-Error -Message "Array lengths do not match" `
                    -Category InvalidData `
                    -TargetObject $values
    } else {
        for ($i = 0; $i -lt $keys.Length; $i++) {
            $h[$keys[$i]] = $values[$i]
        }
    }
    return $h
}


function parse-results($resulthash,$current) {
	$needed = @()
    $installed = @()
	
	#Parse Results and add to needed pile or installed
	foreach($item in $resulthash.GetEnumerator()) { 
		if ($item.Value.Contains('Update')) {
			$needed += $item.Name
		}
        if ($item.Value.Contains('OK')) {
            $installed += $item.Name
        }
	}
	
	#Compare machines old need list to newly parsed and add or remove as needed
	foreach($item in $current.split(',')) {
		if(!$needed.Contains($item)){
			$needed += $item
		}
	}
	
	
	$returnarray = New-Object string[] 2
    $returnarray[0] = $needed -Join ','
    $returnarray[1] = $installed -Join ','
	return $returnarray
}

function Call-Ninite {

	param
	(
		[Parameter(Mandatory=$True,position=0,HelpMessage="audit/install/upgrade")]
		$job,
		[Parameter(Mandatory=$True,position=1,HelpMessage="What machine?")]
		$computer
	)

	
	if(Test-Path Ninite.exe) {
		$job += @("/remote",$computer)
		Write-Host $job
		$status = & .\Ninite.exe $job | Write-Output
        
		$status = $status[1..($status.Count - 1)]  
		return $status
	} else {
		Write-Error "Error Ninite.exe doesn't exist in this path"
		return $null
	}
}

function BuildReport ($MyReport,$title) {

Write-Host $MyReport.GetType().Name

#Get Computer Not Updated Count
$cnu = 0

if ($MyReport.Needed.GetType().Name -eq 'String') {
	if($MyReport.Needed -ne '' -and $MyReport.Needed -ne $null){
		$cnu++
	} 
} else {
	$MyReport.Needed.ForEach({
		if($_ -ne '' -and $_ -ne $null){
		$cnu++
		}
	})
}

$date = Get-Date

$pre = @"

<style>
.ninitereport TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
.ninitereport TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #6495ED;}
.ninitereport TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
.ninitereport tr:nth-child(odd) {background: #CCC}
</style>
<div class="ninitereport">


<h1>
$title
</h1>
<h2>
Run on $date
</h2>
"@

$Post = @"
<h2>
$cnu computers need updates
</h2>
</div>
"@


$MyReport | ConvertTo-HTML -PreContent $Pre -PostContent $Post | Out-File UpdateReport.html
}



if (!$audit -and (Test-Path ComputerList.csv)) {
	$CompList = @(Import-Csv ComputerList.csv)
} else {
	$CompList = @()
}

$CompObj = @{
	'Name'			= '';
	'Pingable'		= '';
	'UpToDate'		= 'Unknown';
	'Needed'		= '';
	'LastContact'	= '';
	'Installed'		= '';
}

# if ($audit) {
	# $CompObj.Add('Installed','')
# }

#START PROGRAM!!!!
foreach ($computer in $ADList) {
	if ($computer.Enabled){					
		$NewCompObj = New-Object -TypeName PSObject -Property $CompObj
		$NewCompObj.Name = $computer.Name
		$NewCompObj.Pingable = Test-Connection -ComputerName $NewCompObj.Name -Count 1 -Quiet
						
		if ($NewCompObj.Pingable) {			
			
            
            $results = Call-Ninite $job $NewCompObj.Name
            
            #Ninite needs to be called /w the audit command no matter what to get the results

          			
			if ($results) {						#PARSE RESULTS
                
				$reshash = create_hash($results)
				
								
                if($FullReports){
                    $date = Get-Date -UFormat "%m%d%Y-%H%M"
                    $compname = $NewCompObj.Name
                    if(!(Test-Path ".\FullReports")){New-Item -ItemType directory 'FullReports'}
                    ConvertFrom-Csv $results | Export-Csv ".\FullReports\$compname-$date.csv" -NoTypeInformation
                    
                }
                
								
				if($reshash.Status -eq 'OK') {$reshash.Status = 'Success'} #Change Status to Success so that results can be parsed properly
				$ParsedResults = parse-results $reshash $NewCompObj.Needed
				
				$NewCompObj.Needed = $ParsedResults[0]				
				if ($audit) {
					$NewCompObj.Installed = $ParsedResults[1]
				}
				
				if($NewCompObj.Needed -eq $null -or $NewCompObj.Needed -eq '') {
					$NewCompObj.UpToDate = 'Yes'
				} else {
					$NewCompObj.UpToDate = 'No'
				}
				
				$NewCompObj.LastContact = Get-Date
			} else {Write-Host 'No results?'}
					
			
		}
        else {
            $NewCompObj.UpToDate = 'UnKnown'
        }
		
		if ($CompList -and !$audit){
				if ($CompList.Name.Contains($NewCompObj.Name)) {
					$index = $CompList.Name.IndexOf($NewCompObj.Name)
					if ($NewCompObj.Pingable) {
						$CompList[$index].Pingable = $NewCompObj.Pingable
						$CompList[$index].UpToDate = $NewCompObj.UpToDate
						$CompList[$index].Needed = $NewCompObj.Needed
						$CompList[$index].LastContact = $NewCompObj.LastContact	
					} else {
						$CompList[$index].Pingable = $NewCompObj.Pingable
					}
				} else {
					$CompList += $NewCompObj
				}
			} else {
					$CompList += $NewCompObj
			}
		
	}
}
 if ($CompList) {
	if (!$audit) {
		$CompList | Sort-Object UpToDate | Select 'Name','UpToDate','Pingable','LastContact','Needed' | Export-CSV ComputerList.csv -NoTypeInformation
		BuildReport($CompList,'3rd Party Update Report')
	} else {
		$CompList = $CompList | Sort-Object UpToDate | Select 'Name','UpToDate','Pingable','LastContact','Needed','Installed'
		$CompList | Export-CSV ComputerList.csv -NoTypeInformation
		Write-Host "STUPID 2"
		Write-Host $CompList.GetType().Name
		BuildReport($CompList,'Software Audit Report')
	}
	
}


