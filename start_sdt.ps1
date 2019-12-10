<#
  .SYNOPSIS
    This script will create a Scheduled Down Time (SDT) in LogicMonitor. Any combination of resource identifiers can be provided in a single execution.
  .DESCRIPTION
    This script will create a Scheduled Down Time (SDT) in LogicMonitor. Any combination of resource identifiers can be provided in a single execution.
  .PARAMETER RFC
    Please enter the RFC number tied to this SDT request.
    Example: 12345
    Note: If you do not have a valid RFC, please use five '9's aka 99999
  .PARAMETER DeviceIDs
    List one or more DeviceIDs to place into SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER DeviceDisplayNames
    List one or more DeviceDisplayNames to place into SDT.
    Note: This will not create an Ops Note. Ops Notes can only be created against an ID, not a name.
    Example: "CNVPSRV01"
    Example: "CNVPSRV01","CNPPSRV01"
  .PARAMETER DeviceGroupIds
    List one or more DeviceGroupIds to place into SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER ServiceIDs
    List one or more ServiceIDs to place into SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER ServiceNames
    List one or more ServiceNames to place into SDT.
    Note: This will not create an Ops Note. Ops Notes can only be created against an ID, not a name.
    Example: "espn"
    Example: "espn","chlftp"
  .PARAMETER ServiceGroupIDs
    List one or more ServiceGroupIDs to place into SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER ServiceGroupNames
    List one or more ServiceGroupNames to place into SDT.
    Note: API is currently unable to resolve ServiceGroupNames. This script will query the available service groups, match the name to an ID and use the ID for the backend processing.
    Example: "External Websites"
    Example: "External Websites","H2O","Ozone"
  .PARAMETER MaintenanceStart
    Enter the start time for the planned SDT. Start time must be now or in the future. No past values will be accepted.
    Default: If no value is given, the current time will be used to start the SDT.
  .PARAMETER maintenancelength
    Enter a value in minutes to set the duration of the SDT. Maximum value is 5760 (4 days).
    Default: If no value is given, a four-hour window will be assigned
  .PARAMETER comment
    Enter a custom comment to be included in the SDT
    Default: If no value is given, the default is Scheduled down time in accordance with RFCxxxxx
  .PARAMETER accessId
    Please enter the accessid for the LogicMonitor API account you wish to use
  .PARAMETER accessKey
    Please enter the accesskey for the LogicMonitor API account you wish to use
  .PARAMETER company
    Please enter the company value for the LogicMonitor account and environment you wish to use
    Accepted values are: "acmenetworks" and "acmenetworkssandbox"
  .EXAMPLE
    > Start-SDT.ps1 -RFC 12345 -DeviceIDS 1,11 -ServiceGroupNames "Test2" -accessid '48v2wRzfKsq5EuF' -accesskey 'H_D9i(f=^nS~e75gy382Bf6{)P+' -company "acmenetworks"
#>
[CmdletBinding(PositionalBinding=$False)]
param(
  [Parameter(Mandatory=$True,HelpMessage="Please enter an RFC Number. If you don't have one, use 5 9's instead `(99999`)")]
  [string]$RFC,

  [Parameter(Mandatory=$False)]
  [array]$DeviceIDs,

  [Parameter(Mandatory=$False)]
  [array]$DeviceDisplayNames,

  [Parameter(Mandatory=$False)]
  [array]$DeviceGroupIds,

  [Parameter(Mandatory=$False)]
  [array]$ServiceIDs,

  [Parameter(Mandatory=$False)]
  [array]$ServiceNames,

  [Parameter(Mandatory=$False)]
  [array]$ServiceGroupIDs,

  [Parameter(Mandatory=$False)]
  [array]$ServiceGroupNames,

  [PARAMETER(Mandatory=$False)]
  [ValidateScript({$_ -ge (Get-Date)})]
  [DateTime]
  $MaintenanceStart,

  [ValidateRange(1,5760)]
  [Int]$maintenancelength = 240,

  [Parameter(Mandatory=$False)]
  $Comment = $null,

  [Parameter(Mandatory=$False)]
  $accessId,

  [Parameter(Mandatory=$False)]
  $accessKey,

  [Parameter(Mandatory=$False)]
  [ValidateSet("acmenetworkssandbox","acmenetworks")]
  $company
)

# Assign local variables to global variables to use in multiple functions
$Global:accessId = $accessId
$Global:accessKey = $accessKey
$Global:company = $company

Function Invoke-LogicMonitor{
  <#
    .SYNOPSIS
      This function communicates with the LogicMonitor API
    .DESCRIPTION
      This takes user provided inputs and first creates the data string.
      It provides handling for requests with and without a $data field. (GET and DELETE requests do not require a body field be sent and will error if sent empty.)
    .PARAMETER httpverb
      The HTTP Method to be used via the API.
      Valid options are 'GET', 'POST', and 'DELETE'
    .PARAMETER data
      Input to be passed in the body field to LogicMonitor via the Invoke-RestMethod command
    .PARAMETER resourcePath
      The rest end point being called
      Examples: /sdt/sdts, /settings/opsnotes
    .PARAMETER url
      The full URL to be used via the Invoke-RestMethod command to commnicate with LogicMonitor
  #>
  param(
    [Parameter(Mandatory=$True)]
    [ValidateSet("POST","GET","DELETE")]
    $httpVerb,
    [Parameter(Mandatory=$False)]
    $data = $null,
    [Parameter(Mandatory=$True)]
    $resourcePath,
    [Parameter(Mandatory=$True)]
    $url
  )

  # Concatenate Request Details
  # Determine if there is a data payload (not used with GET verb) and dynamically include in request vars as it will break signature if included but not used
  If ($data){
    $requestVars = $httpVerb + $Global:epoch + $data + $resourcePath
  }Else{$requestVars = $httpVerb + $Global:epoch + $resourcePath}
  # Construct Signature
  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = [Text.Encoding]::UTF8.GetBytes($Global:accessKey)
  $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
  $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
  $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

  # Construct Headers
  $auth = 'LMv1 ' + $Global:accessId + ':' + $signature + ':' + $Global:epoch
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization",$auth)
  $headers.Add("Content-Type",'application/json')

  # Make Request based on whether or not $data is used (GET verb does not use it).
  If ($data){
  $response = Invoke-RestMethod -Uri $url -body $data -Method $httpVerb -Header $headers
  }Else{$response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers}

  $Global:items = $response.data.items

  # Print the status of the Invoke-RestMethod command
  Write-Host "Status:$($response.status)`n"

  Return $Global:Items
}
Function New-SDT {
  <#
    .SYNOPSIS
      This function generates the required sdt data string to pass to the Invoke-LogicMonitor function
    .DESCRIPTION
      This function simplifies the process of creating the body field data of creating an SDT and then forwards the request to the Invoke-LogicMonitor function to write the data to the API
    .PARAMETER ResourceID
      This variable contains the resource type and identifiers needed to create an SDT
      Examples: "deviceId":1
      Examples: "deviceDisplayName":"PWVPSWPROBE01"
    .PARAMETER Type
      This variable contains the SDT Type
      Example: ServiceSDT
      Example: ServiceGroupSDT
  #>
  param(
    [Parameter(Mandatory=$True,ValueFromPipeline)]
    $ResourceID,
    [Parameter(Mandatory=$True,ValueFromPipeline)]
    $Type
  )
    # Generate the data string to send to LogicMonitor to configure the requested SDT
  $sdtdata = '{"sdtType":'+$Global:stdTYpe+',"type":"'+ $Type +'","comment":"' + $Global:Comment + '",' + $ResourceID +',"startDateTime":'+ $Global:startDateepoch +',"endDateTime":'+ $Global:endDateepoch +'}'
  Invoke-LogicMonitor -httpVerb 'POST' -data $sdtdata -resourcePath '/sdt/sdts'-url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts"
}
Function New-OpsNote {
  <#
    .SYNOPSIS
      This function generates the required ops note data string to pass to the Invoke-LogicMonitor function
    .DESCRIPTION
      This function simplifies the process of creating the body field data of creating an Ops Note and then forwards the request to the Invoke-LogicMonitor function to write the data to the API
    .PARAMETER ResourceID
      This variable contains the resource type and identifiers needed to create an SDT
      Examples: "deviceId":1
      Examples: "groupId":3
    .PARAMETER Type
      This variable contains the SDT Type
      Example: device
      Example: service
  #>
  param(
    [Parameter(Mandatory=$True,ValueFromPipeline)]
    $ResourceID,
    [Parameter(Mandatory=$True,ValueFromPipeline)]
    $Type
  )
  # Generate the data string to send to LogicMonitor to configure the Op Note
  $notedata = "{`"note`":`"$Global:Comment`",`"scopes`":[{`"type`":`"$Type`",$ResourceID}],`"happenedOnInSec`":$Global:startDateepoch}"
  Invoke-LogicMonitor -httpVerb 'POST' -data $notedata -resourcePath '/setting/opsnotes' -url "https://$($global:company).logicmonitor.com/santaba/rest/setting/opsnotes"
}
# Use TLS 1.2 as required by LogicMonitor
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# stdTYpe (integer)
# 1 - one time, 2 - Weekly SDT, 3 - Monthly SDT, 4 - Daily SDT
# we have to use "one time" style values because LM has no concept of day of month
$Global:stdTYpe = 1

# If no comment was passed via CLI, generate a generic comment
If (-not $Comment){
  $Global:Comment = "Scheduled down time in accordance with RFC$RFC"
}Else{$Global:Comment = $Comment}

# If maintenance start date was not provided, set it to current time
If (-not $MaintenanceStart){
  [datetime]$MaintenanceStart = Get-Date
}

# Convert the start time to epoch as required by LogicMonitor
$startDate = (Get-Date -Date $maintenancestart).ToUniversalTime()
$Global:startDateepoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end $startDate).TotalMilliseconds)

# Caclulate the end time and convert to epoch
$endDate = $startDate.AddMinutes($maintenancelength)
$Global:endDateepoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end $endDate).TotalMilliseconds)

# Get current time in milliseconds
$Global:epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

# Parse through each resource identifier and created SDTs and Ops Notes as required
If ($DeviceIDs){
  $i = 0
  do{
    $ResourceID = "`"deviceId`":$($DeviceIds[$i])"
    $i++
    New-SDT -ResourceID $ResourceID -Type 'DeviceSDT'
    New-OpsNote -ResourceID $ResourceID -Type 'device'
  } While ($i -lt $DeviceIDs.Count )
}
If ($DeviceDisplayNames){
  $i = 0
  do{
    $ResourceID = "`"deviceDisplayName`":`"$($DeviceDisplayNames[$i])`""
    $i++
    New-SDT -ResourceID $ResourceID -Type 'DeviceSDT'
  } While ($i -lt $DeviceDisplayNames.Count )
}
If ($DeviceGroupIds){
  $i = 0
  do{
    $SDTResourceID = "`"deviceGroupId`":$($DeviceGroupIds[$i]),`"dataSourceId`":0"
    $NoteResourceID = "`"groupId`":$($DeviceGroupIds[$i])"
    $i++
    New-SDT -ResourceID $SDTResourceID -Type 'DeviceGroupSDT'
    New-OpsNote -ResourceID $NoteResourceID -Type 'device'
  } While ($i -lt $DeviceGroupIds.Count )
}
If ($ServiceIDs){
  $i = 0
  do{
    $ResourceID = "`"serviceId`":$($ServiceIDs[$i])"
    $i++
    New-SDT -ResourceID $ResourceID -Type 'ServiceSDT'
    New-OpsNote -ResourceID $ResourceID -Type 'service'
  } While ($i -lt $ServiceIDs.Count )
}
If ($ServiceNames){
  $i = 0
  do{
    $ResourceID = "`"serviceName`":`"$($ServiceNames[$i])`""
    $i++
    New-SDT -ResourceID $ResourceID -Type 'ServiceSDT'
  } While ($i -lt $ServiceNames.Count )
}
If ($ServiceGroupIDs){
  $i = 0
  do{
    $SDTResourceID = "`"serviceGroupId`":$($ServiceGroupIDs[$i])"
    $NoteResourceID = "`"groupId`":$($ServiceGroupIDs[$i])"
    $i++
    New-SDT -ResourceID $SDTResourceID -Type 'ServiceGroupSDT'
    New-OpsNote -ResourceID $NoteResourceID -Type 'service'
  } While ($i -lt $ServiceGroupIDs.Count )
}
If ($ServiceGroupNames){
  $i = 0
  do{
    # Convert ServiceGroupName to ServiceGroupID
    $resourcepath = '/service/groups'
    $url = 'https://' + $Global:company + '.logicmonitor.com/santaba/rest' + $resourcePath
    $ServiceGroups = Invoke-LogicMonitor -httpVerb 'GET' -resourcePath $resourcepath -url $url
    $ServiceGroupId = ($ServiceGroups | Where-Object {$_.Name -eq $ServiceGroupNames[$i]}).id
    Write-Output "`n`n`nServiceGroupId = $ServiceGroupID`n`n`n"
    $SDTResourceID = "`"serviceGroupId`":$($ServiceGroupId)"
    $NoteResourceID = "`"groupId`":$($ServiceGroupId)"
    $i++
    New-SDT -ResourceID $SDTResourceID -Type 'ServiceGroupSDT'
    New-OpsNote -ResourceID $NoteResourceID -Type 'service'
  } While ($i -lt $ServiceGroupNames.Count )
}
# If at least one resource identifier was found, $i will exist. This will present the user with a message if no resources identifiers were used.
If (-not $i){Write-Output "You did not provide any resource identifiers"}
