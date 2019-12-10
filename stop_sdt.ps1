<#
  .SYNOPSIS
    This script will end a previously Scheduled Down Time (SDT) in LogicMonitor. Any combination of resource identifiers can be provided in a single execution.
  .DESCRIPTION
    When executed, this script will gather a list of all current SDTs and store them in a variable.
    From there, each resource identifier searches through the stored data to prevent multiple API calls for the same info.
    It is able to handle single and multiple identifiers for each type, as well as multiple types in a single execution.
  .PARAMETER RFC
    Please enter the RFC number tied to this SDT request.
    Example: 12345
  .PARAMETER DeviceIDs
    List one or more DeviceIDs to end their SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER DeviceDisplayNames
    List one or more DeviceDisplayNames to end their SDT.
    Example: "CNVPSRV01"
    Example: "CNVPSRV01","CNPPSRV01"
  .PARAMETER DeviceGroupIds
    List one or more DeviceGroupIds to end their SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER ServiceIDs
    List one or more ServiceIDs to end their SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER ServiceNames
    List one or more ServiceNames to end their SDT.
    Example: "espn"
    Example: "espn","chlftp"
  .PARAMETER ServiceGroupIDs
    List one or more ServiceGroupIDs to end their SDT.
    Example: 11
    Example: 11,23,31
  .PARAMETER ServiceGroupNames
    List one or more ServiceGroupNames to end their SDT.
    Example: "External Websites"
    Example: "External Websites","H2O","Ozone"
  .PARAMETER accessId
    Please enter the accessid for the LogicMonitor API account you wish to use
  .PARAMETER accessKey
    Please enter the accesskey for the LogicMonitor API account you wish to use
  .PARAMETER company
    Please enter the company value for the LogicMonitor account and environment you wish to use
    Accepted values are: "acmenetworks" and "acmenetworkssandbox"
  .NOTES
    If ran without any resource identifiers, it will return a list of all active SDTs for the given account
  .EXAMPLE
    > Stop-SDT.ps1 -RFC 12345 -accessid '48v294y53sq5EuF' -accesskey 'H_D9i(f5^nS~e75gy382Bf6{)P+' -company "acmenetworks"
    This example will stop SDTs for any SDT with a comment containing RFC12345.
  .EXAMPLE
    > Stop-SDT.ps1 -DeviceIDS 1,11 -ServiceGroupNames "Test2" -accessid '48v2wRzfK94EuF' -accesskey 'H_D9i(f5~B^U36~e75gy382Bf6{)P+' -company "acmenetworks"
    This example will stop the active SDTs for DevicesIDS 1 and 11, plus ServiceGroupName Test2.
  .EXAMPLE
    > Stop-SDT.ps1
    This example will display all active SDTs in the sytem.
#>
[CmdletBinding(PositionalBinding=$False)]
param(
  [Parameter(Mandatory=$False)]
  [array]$RFC,

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

  [Parameter(Mandatory=$False)]
  $accessId,

  [Parameter(Mandatory=$False)]
  $accessKey,

  [Parameter(Mandatory=$False)]
  $company
)

# Assign local variables to global variables for use throughout multiple functions
$Global:Accessid = $accessId
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
    [Parameter(Mandatory=$True)]
    $data,
    [Parameter(Mandatory=$True)]
    $resourcePath,
    [Parameter(Mandatory=$True)]
    $url
  )
  # Concatenate Request Details
  $requestVars = $httpVerb + $Global:epoch + $resourcePath

  # Construct Signature
  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = [Text.Encoding]::UTF8.GetBytes($Global:accessKey)
  $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
  $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
  $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

  # Construct Headers
  $auth = 'LMv1 ' + $Global:accessId + ':' + $signature + ':' + $epoch
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization",$auth)
  $headers.Add("Content-Type",'application/json')

  # Make Request
  $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers

  #Store the returned items in a global variable for later processing
  $Global:items = $response.data.items

  # Print the status to the screen
  Write-Host "Status:$($response.status)`n"
  Return $Global:items
}
# Use TLS 1.2 as required by LogicMonitor
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Get current time in milliseconds
$Global:epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

# Construct URL to gather all SDTs
$url = 'https://' + $Global:company + '.logicmonitor.com/santaba/rest/sdt/sdts'

# Get a list of all active and store in $Global:Items
Write-Output "`nGathering a list of all active SDTS"
$SDTItems = Invoke-LogicMonitor -httpVerb 'GET' -data '' -resourcePath '/sdt/sdts' -url $url


# If active SDTs were found, begin processing user stop SDT request
If ($SDTItems){
  If($RFC){
    $i = 0
    do{
      $RFCItems = $SDTItems | Where-Object {$_.Comment -match $RFC[$i]}
      ForEach ($RFCItem in $RFCItems){
        Write-Output "Removing $($rfcitem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($RFCItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($RFCItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($RFCItem.id)"
      }
    $i++
    } While ($i -lt $RFC.Count )
  }
  If($DeviceIDs){
    $i = 0
    do{
      $DeviceIDItems = $SDTItems | Where-Object {$_.deviceId -match $DeviceIDs[$i]}
      ForEach ($DeviceIDItem in $DeviceIDItems){
        Write-Output "Removing $($DeviceIDItem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($DeviceIDItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($DeviceIDItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($DeviceIDItem.id)"
      }
    $i++
    } While ($i -lt $DeviceIDs.Count )
  }
  If($DeviceDisplayNames){
    $i = 0
    do{
      $DeviceDisplayNameItems = $SDTItems | Where-Object {$_.deviceDisplayName -match $DeviceDisplayNames[$i]}
      ForEach ($DeviceDisplayNameItem in $DeviceDisplayNameItems){
        Write-Output "Removing $($DeviceDisplayNameItem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($DeviceDisplayNameItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($DeviceDisplayNameItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($DeviceDisplayNameItem.id)"
      }
    $i++
    } While ($i -lt $DeviceDisplayNames.Count )
  }
  If($DeviceGroupIds){
    $i = 0
    do{
      $DeviceGroupIdItems = $SDTItems | Where-Object {$_.deviceGroupId -match $DeviceGroupIds[$i]}
      ForEach ($DeviceGroupIdItem in $DeviceGroupIdItems){
        Write-Output "Removing $($DeviceGroupIdItem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($DeviceGroupIdItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($DeviceGroupIdItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($DeviceGroupIdItem.id)"
      }
    $i++
    } While ($i -lt $DeviceGroupIds.Count )
  }
  If($ServiceIDs){
    $i = 0
    do{
      $ServiceIDItems = $SDTItems | Where-Object {$_.serviceId -match $ServiceIDs[$i]}
      ForEach ($ServiceIDItem in $ServiceIDItems){
        Write-Output "Removing $($ServiceIDItem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceIDItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($ServiceIDItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceIDItem.id)"
      }
    $i++
    } While ($i -lt $ServiceIDs.Count )
  }
  If($ServiceNames){
    $i = 0
    do{
      $ServiceNameItems = $SDTItems | Where-Object {$_.serviceName -match $ServiceNames[$i]}
      ForEach ($ServiceNameItem in $ServiceNameItems){
        Write-Output "Removing $($ServiceNameItem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceNameItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($ServiceNameItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceNameItem.id)"
      }
    $i++
    } While ($i -lt $ServiceNames.Count )
  }
  If($ServiceGroupIDs){
    $i = 0
    do{
      $ServiceGroupIDItems = $SDTItems | Where-Object {$_.serviceGroupId -match $ServiceGroupIDs[$i]}
      ForEach ($ServiceGroupIDItem in $ServiceGroupIDItems){
        Write-Output "Removing $($ServiceGroupIDItem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceGroupIDItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($ServiceGroupIDItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceGroupIDItem.id)"
      }
    $i++
    } While ($i -lt $ServiceGroupIDs.Count )
  }
  If($ServiceGroupNames){
    $i = 0
    do{
      $ServiceGroupNameItems = $SDTItems | Where-Object {$_.serviceGroupName -match $ServiceGroupNames[$i]}
      ForEach ($ServiceGroupNameItem in $ServiceGroupNameItems){
        Write-Output "Removing $($ServiceGroupNameItem.ID)"
        Write-Output "url = https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceGroupNameItem.id)"
        Invoke-LogicMonitor -httpVerb 'DELETE' -resourcePath "/sdt/sdts/$($ServiceGroupNameItem.id)" -data '' -url "https://$($Global:company).logicmonitor.com/santaba/rest/sdt/sdts/$($ServiceGroupNameItem.id)"
      }
    $i++
    } While ($i -lt $ServiceGroupNames.Count )
  }
  # Display the active SDTs on screen if no idetifiers were given
  If(-not $i){
    $Global:Items | select-object id,comment,deviceid,deviceDisplayName,deviceGroupId,serviceName,serviceId,serviceGroupID,serviceGroupName | Format-Table
  }
}Else{Write-Output "There are no active SDTs to display or end.`n`n"}
