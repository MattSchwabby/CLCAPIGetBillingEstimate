<#

Script to pull server billing estimate data for a customer by their root parent alias

Step 1 -
In order to enable scripts on your machine, first run the following command:
Set-ExecutionPolicy RemoteSigned

Step 2 - Press F5 to run the script

Step 3 - Enter your API Key 
    This can be found on the API section in Control
    If your name is not listed among the API users, create a ticket requesting access

Step 4 - Enter your password

Step 5 - Enter your control portal credentials

Step 6 - Enter Customer account alias

Step 7 - The Output file will be in C:\Users\Public\CLC\

#>

#Create Login Header

$APIKey = Read-Host "Please enter your CenturyLink Cloud V1 API Key"
$APIPass = Read-Host "Please enter your CenturyLink Cloud V1 API Password"

$body = @{APIKey = $APIKey; Password = $APIPass } | ConvertTo-Json
$restreply = Invoke-RestMethod -uri "https://api.ctl.io/REST/Auth/Logon/" -ContentType "Application/JSON" -Body $body -Method Post -SessionVariable session 
$global:session = $session 
Write-Host $restreply.Message

New-Item -ItemType Directory -Force -Path C:\Users\Public\CLC\

$AccountAlias = Read-Host 'Please enter a customer account alias'

$datacenterList = "DE1,GB1,GB3,SG1,WA1,CA1,UC1,UT1,NE1,IL1,CA3,CA2,VA1,NY1"
$datacenterList = $datacenterList.Split(",")

$result = $null

function getAliases
{
    $Location = $args[0]

    $JSON = @{AccountAlias = $AccountAlias; Location = $Location} | ConvertTo-Json 
    $result = Invoke-RestMethod -uri "https://api.ctl.io/REST/Server/GetAllServersForAccountHierarchy/" -ContentType "Application/JSON" -Method Post -WebSession $session -Body $JSON 

    $result.AccountServers | Export-Csv C:\Users\Public\CLC\RawData.csv -Append -ErrorAction SilentlyContinue -NoTypeInformation
    $result.AccountServers.Servers.Name | Out-File C:\Users\Public\CLC\serverTmp.csv -Append
    }



function getGroups
{
    $Location = $args[0]

    $JSON = @{AccountAlias = $AccountAlias; Location = $Location} | ConvertTo-Json 
    $result = Invoke-RestMethod -uri "https://api.ctl.io/REST/Server/GetAllServersForAccountHierarchy/" -ContentType "Application/JSON" -Method Post -WebSession $session -Body $JSON 

    $result.AccountServers.Servers.HardwareGroupUUID | Out-File C:\Users\Public\CLC\RawGroupData.csv -Append
    }

Foreach ($i in $datacenterList)
{
    getAliases($i)
    getGroups($i)
}

$date = Get-Date -Format Y
$filename = "c:\CustomerServerData\$AccountAlias-AllAliases-$date.csv"

Import-Csv C:\Users\Public\CLC\RawData.csv | Select AccountAlias –Unique  | Export-Csv $filename  -NoTypeInformation
$importAliases = Import-CSV $filename
$aliases = $importAliases.AccountAlias
$importGroups = Import-CSV C:\Users\Public\CLC\RawGroupData.csv -Header "HardwareGroupUUID" | sort HardwareGroupUUID -Unique
$groups = $importGroups.HardwareGroupUUID
$importServers = Import-CSV C:\Users\Public\CLC\serverTmp.csv -Header "Name" | sort Name -Unique
$servers = $importServers.Name

<# API V2 Login: Creates $HeaderValue for Passing Auth (highlight and press F8) #>

$global:CLCV2cred = Get-Credential -message "Please enter your Control portal Logon" -ErrorAction Stop 
$body = @{username = $CLCV2cred.UserName; password = $CLCV2cred.GetNetworkCredential().password} | ConvertTo-Json 
$global:resttoken = Invoke-RestMethod -uri "https://api.ctl.io/v2/authentication/login" -ContentType "Application/JSON" -Body $body -Method Post 
$HeaderValue = @{Authorization = "Bearer " + $resttoken.bearerToken} 

$genday = Get-Date -Uformat %a
$genmonth = Get-Date -Uformat %b
$genyear = Get-Date -Uformat %Y
$genhour = Get-Date -UFormat %H
$genmins = Get-Date -Uformat %M
$gensecs = Get-Date -Uformat %S

$gendate = "Generated-$genday-$genmonth-$genyear-$genhour-$genmins-$gensecs"

$thisServer = $null

<# get group estimates #>
Foreach ($i in $aliases)
{
    Foreach ($j in $groups)
    {
        $url = "https://api.ctl.io/v2/groups/$i/$j/billing"
        try
        {
            $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get -ErrorAction SilentlyContinue
        }
        catch
        {
            "Error retrieving billing estimate for group $j"
        }

       Foreach ($k in $importServers)
       {
            $data = $k.name
            $thisServer = $result.groups.$j.servers.$data
            if ($thisServer -eq $null)
            {
                
                #do nothing                
            } else
                {
                $thisserver | Add-Member -Membertype NoteProperty -Name "Server Name" -Value $data -Force
                $thisserver | select "Server Name",templateCost,archiveCost,monthToDate,monthlyEstimate | export-csv "C:\Users\Public\CLC\$accountalias-CLCGroupBillingData-$gendate.csv" -append -notypeinformation -force -ErrorAction SilentlyContinue
                } #end else
       }<#end foreach#>
    } <#end foreach#>
} <#end foreach#>

$monthlyEstimate = import-csv "C:\Users\Public\CLC\$accountalias-CLCGroupBillingData-$gendate.csv"
$monthlyEstimateSum = $monthlyEstimate.monthlyEstimate | measure-object -sum
$monthToDateSum = $monthlyEstimate.monthToDate | measure-object -sum

$countRow = New-Object PSObject -Property @{ "Server Name" = "Total monthly estimate"; monthlyEstimate = $monthlyEstimateSum.sum; monthToDate = $monthToDateSum.sum} | Select "Server Name", monthToDate, monthlyEstimate

$countRow | export-csv "C:\Users\Public\CLC\$accountalias-CLCGroupBillingData-$gendate.csv" -append -notypeinformation -force -ErrorAction SilentlyContinue

$file = & "C:\Users\Public\CLC\$accountalias-CLCGroupBillingData-$gendate.csv"
 
$restreply = Invoke-RestMethod -uri "https://api.ctl.io/REST/Auth/Logout/" -ContentType "Application/JSON" -Method Post -SessionVariable session 
$global:session = $session
Write-Host $restreply.Message


Remove-Item $filename

Remove-Item C:\Users\Public\CLC\RawData.csv
Remove-Item C:\Users\Public\CLC\RawGroupData.csv
Remove-Item C:\Users\Public\CLC\serverTmp.csv