param(
    [string]$BaseUrl = 'http://localhost:8080',
    [switch]$SkipConcurrency,
    [switch]$KeepTestData
)

$ErrorActionPreference = 'Stop'
$base = $BaseUrl.TrimEnd('/')
$runId = [guid]::NewGuid().ToString('N').Substring(0,12)
$prefix = "deep-test-$runId"
$statsUrl = "$base/api/statistics/sales"
$passed=0; $failed=0; $warnings=0
$customers = New-Object System.Collections.Generic.List[string]
$results = New-Object System.Collections.Generic.List[object]

function CartUrl([string]$Customer) { return "$base/api/customers/$Customer/cart" }
function New-Customer([string]$Suffix) {
    $id="$prefix-$Suffix"
    $script:customers.Add($id)
    return $id
}
function Invoke-Api([string]$Method,[string]$Url,[object]$Body=$null,[string]$RawBody=$null,[string]$ContentType='application/json') {
    $p=@{Uri=$Url;Method=$Method;UseBasicParsing=$true;ErrorAction='Stop';TimeoutSec=20}
    if ($Method -in @('POST','PUT','PATCH')) {
        if ($null -ne $RawBody) { $p.Body=$RawBody; $p.ContentType=$ContentType }
        elseif ($null -ne $Body) { $p.Body=($Body | ConvertTo-Json -Depth 20 -Compress); $p.ContentType=$ContentType }
    }
    try {
        $r=Invoke-WebRequest @p
        $data=$null
        if ($r.Content) { try { $data=$r.Content | ConvertFrom-Json } catch { $data=$r.Content } }
        return [pscustomobject]@{Status=[int]$r.StatusCode;Data=$data;Error=$null}
    } catch {
        $status=0; $data=$null; $raw=$null
        if ($_.Exception.Response) {
            $status=[int]$_.Exception.Response.StatusCode
            try { $stream=$_.Exception.Response.GetResponseStream(); if ($stream) { $reader=New-Object System.IO.StreamReader($stream); $raw=$reader.ReadToEnd(); $reader.Dispose() } } catch {}
        }
        if ($_.ErrorDetails.Message) { $raw=$_.ErrorDetails.Message }
        if ($raw) { try { $data=$raw | ConvertFrom-Json } catch { $data=$raw } }
        return [pscustomobject]@{Status=$status;Data=$data;Error=$_.Exception.Message}
    }
}
function Check([string]$Name,[bool]$Ok,[object]$Response=$null) {
    $script:results.Add([pscustomobject]@{Name=$Name;Result=$(if($Ok){'PASS'}else{'FAIL'})})
    if ($Ok) { $script:passed++; Write-Host "[PASS] $Name" -ForegroundColor Green }
    else {
        $script:failed++; Write-Host "[FAIL] $Name" -ForegroundColor Red
        if ($null -ne $Response) { Write-Host ("       " + ($Response | ConvertTo-Json -Depth 8 -Compress)) }
    }
}
function Warn([string]$Name,[string]$Message) {
    $script:warnings++
    $script:results.Add([pscustomobject]@{Name=$Name;Result='WARN'})
    Write-Host "[WARN] $Name - $Message" -ForegroundColor Yellow
}
function Items([object]$Response) {
    if ($null -eq $Response -or $null -eq $Response.Data -or $null -eq $Response.Data.items) { return ,@() }
    return ,@($Response.Data.items)
}
function Sales([string]$Offer,[string]$Action,[string]$From,[string]$To) {
    $url="$statsUrl`?offerId=$([uri]::EscapeDataString($Offer))&action=$([uri]::EscapeDataString($Action))&from=$([uri]::EscapeDataString($From))&to=$([uri]::EscapeDataString($To))"
    return Invoke-Api GET $url
}
function One([string]$Offer,[string]$Action='ADD',[object]$Value=19.99) {
    return @{offerId=$Offer;action=$Action;prices=@(@{type='ONE_TIME';value=$Value})}
}
function Rec([string]$Offer,[string]$Action='ADD',[object]$Value=15,[int]$Count=12,[string]$Unit='MONTH') {
    return @{offerId=$Offer;action=$Action;prices=@(@{type='RECURRING';value=$Value;recurrences=$Count;recurrenceUnit=$Unit})}
}
function ValidateBadItem([string]$Label,[object]$Body,[string]$Url,[int]$ExpectedItems=0) {
    $r=Invoke-Api POST "$Url/items" $Body
    Check "$Label => HTTP 400" ($r.Status -eq 400) $r
    $after=Invoke-Api GET $Url
    Check "$Label => cart unchanged" ($after.Status -eq 200 -and (Items $after).Count -eq $ExpectedItems) $after
}

$start=[datetime]::UtcNow.AddMinutes(-30)
$end=[datetime]::UtcNow.AddHours(2)
$from=$start.ToString('yyyy-MM-ddTHH:mm:ssZ')
$to=$end.ToString('yyyy-MM-ddTHH:mm:ssZ')
$offer="$prefix-offer"
$other="$prefix-other"

Write-Host "Shopping Cart comprehensive API tests" -ForegroundColor Cyan
Write-Host "Base: $base | Run ID: $runId | Prefix: $prefix"
Write-Host "Tests create isolated customers and confirmed sales. Existing data is not modified intentionally."

try {
    $customer=New-Customer 'main'; $cart=CartUrl $customer
    Write-Host "`n=== 1. Empty carts, HTTP behavior ===" -ForegroundColor Cyan
    $r=Invoke-Api GET $cart
    Check 'GET missing cart => 200, correct customer, empty' ($r.Status -eq 200 -and $r.Data.customerId -eq $customer -and (Items $r).Count -eq 0) $r
    $r=Invoke-Api POST "$cart/submit"
    Check 'Submit missing cart => 400' ($r.Status -eq 400) $r
    $r=Invoke-Api DELETE $cart
    Check 'DELETE missing cart => 204 (idempotent)' ($r.Status -eq 204) $r
    $r=Invoke-Api DELETE "$cart/items/unknown"
    Check 'DELETE item in missing cart => 404' ($r.Status -eq 404) $r
    $r=Invoke-Api POST "$cart/items" -RawBody='{bad-json'
    Check 'Malformed JSON => 400' ($r.Status -eq 400) $r
    $r=Invoke-Api POST "$cart/items" -RawBody=''
    Check 'Missing request body => 400' ($r.Status -eq 400) $r
    $r=Invoke-Api POST "$cart/items" -RawBody='[]'
    Check 'JSON array instead of object => 400' ($r.Status -eq 400) $r

    Write-Host "`n=== 2. Validation and invalid prices ===" -ForegroundColor Cyan
    $valid=One $offer
    ValidateBadItem 'Empty offerId' @{offerId='';action='ADD';prices=$valid.prices} $cart
    ValidateBadItem 'Whitespace offerId' @{offerId='   ';action='ADD';prices=$valid.prices} $cart
    ValidateBadItem 'Missing offerId' @{action='ADD';prices=$valid.prices} $cart
    ValidateBadItem 'Missing action' @{offerId=$offer;prices=$valid.prices} $cart
    ValidateBadItem 'Null action' @{offerId=$offer;action=$null;prices=$valid.prices} $cart
    ValidateBadItem 'Invalid action enum' @{offerId=$offer;action='PURCHASE';prices=$valid.prices} $cart
    ValidateBadItem 'Missing prices' @{offerId=$offer;action='ADD'} $cart
    ValidateBadItem 'Null prices' @{offerId=$offer;action='ADD';prices=$null} $cart
    ValidateBadItem 'Empty prices' @{offerId=$offer;action='ADD';prices=@()} $cart
    ValidateBadItem 'Null price element' @{offerId=$offer;action='ADD';prices=@($null)} $cart
    ValidateBadItem 'Unknown price type' @{offerId=$offer;action='ADD';prices=@(@{type='INVALID';value=1})} $cart
    ValidateBadItem 'Missing price type' @{offerId=$offer;action='ADD';prices=@(@{value=1})} $cart
    ValidateBadItem 'Missing price value' @{offerId=$offer;action='ADD';prices=@(@{type='ONE_TIME'})} $cart
    ValidateBadItem 'Null price value' @{offerId=$offer;action='ADD';prices=@(@{type='ONE_TIME';value=$null})} $cart
    ValidateBadItem 'Negative one-time value' (One $offer 'ADD' -0.01) $cart
    ValidateBadItem 'More than two decimals' (One $offer 'ADD' 1.234) $cart
    ValidateBadItem 'Oversized decimal' (One $offer 'ADD' 1234567890123) $cart
    ValidateBadItem 'Non-numeric price' (One $offer 'ADD' 'abc') $cart
    ValidateBadItem 'Recurring negative value' (Rec $offer 'ADD' -1) $cart
    ValidateBadItem 'Recurring zero count' (Rec $offer 'ADD' 5 0) $cart
    ValidateBadItem 'Recurring negative count' (Rec $offer 'ADD' 5 -1) $cart
    ValidateBadItem 'Recurring missing count' @{offerId=$offer;action='ADD';prices=@(@{type='RECURRING';value=5;recurrenceUnit='MONTH'})} $cart
    ValidateBadItem 'Recurring missing unit' @{offerId=$offer;action='ADD';prices=@(@{type='RECURRING';value=5;recurrences=12})} $cart
    ValidateBadItem 'Recurring invalid unit' (Rec $offer 'ADD' 5 12 'WEEK') $cart
    ValidateBadItem 'Mixed valid/invalid prices' @{offerId=$offer;action='ADD';prices=@(@{type='ONE_TIME';value=5},@{type='ONE_TIME';value=-2})} $cart

    Write-Host "`n=== 3. Add, retrieve, delete, preservation ===" -ForegroundColor Cyan
    $zeroBody=One $offer 'ADD' 0
    Write-Host ('DEBUG zero price JSON: ' + ($zeroBody | ConvertTo-Json -Depth 20 -Compress)) -ForegroundColor DarkCyan
    $r=Invoke-Api POST "$cart/items" $zeroBody
    Check 'Zero price accepted' ($r.Status -eq 201 -and (Items $r).Count -eq 1) $r
    $zeroId=$null; if ((Items $r).Count -eq 1) { $zeroId=(Items $r)[0].id }
    Check 'Generated item ID is nonblank' (-not [string]::IsNullOrWhiteSpace($zeroId)) $r
    $r=Invoke-Api POST "$cart/items" (Rec $offer 'MODIFY' 15.25 12 'MONTH')
    Check 'Recurring MONTH accepted' ($r.Status -eq 201 -and (Items $r).Count -eq 2) $r
    $r=Invoke-Api POST "$cart/items" (Rec $other 'DELETE' 2 7 'DAY')
    Check 'Recurring DAY + DELETE accepted' ($r.Status -eq 201 -and (Items $r).Count -eq 3) $r
    $r=Invoke-Api POST "$cart/items" (Rec $other 'ADD' 100 2 'YEAR')
    Check 'Recurring YEAR accepted' ($r.Status -eq 201 -and (Items $r).Count -eq 4) $r
    $multi=@{offerId=$offer;action='ADD';prices=@(@{type='ONE_TIME';value=9.99},@{type='RECURRING';value=3.50;recurrences=6;recurrenceUnit='MONTH'})}
    $r=Invoke-Api POST "$cart/items" $multi
    Check 'Multiple prices on one item accepted' ($r.Status -eq 201 -and (Items $r).Count -eq 5) $r
    $ids=@((Items $r) | ForEach-Object { $_.id })
    Check 'All five IDs unique' (($ids | Select-Object -Unique).Count -eq 5) $r
    $r=Invoke-Api GET $cart
    Check 'GET preserves five items' ($r.Status -eq 200 -and (Items $r).Count -eq 5) $r
    $offers=@((Items $r) | ForEach-Object { $_.offerId })
    Check 'GET preserves offer IDs' (($offers | Where-Object {$_ -eq $offer}).Count -eq 3 -and ($offers | Where-Object {$_ -eq $other}).Count -eq 2) $r
    $withMulti=@((Items $r) | Where-Object { $_.action -eq 'ADD' -and @($_.prices).Count -eq 2 })
    Check 'GET preserves mixed price array' ($withMulti.Count -eq 1) $r
    $r=Invoke-Api DELETE "$cart/items/not-a-real-id"
    Check 'Delete unknown item => 404' ($r.Status -eq 404) $r
    $r=Invoke-Api GET $cart
    Check 'Failed delete leaves cart intact' ((Items $r).Count -eq 5) $r
    if ($zeroId) {
        $r=Invoke-Api DELETE "$cart/items/$zeroId"
        Check 'Delete existing item => 204' ($r.Status -eq 204) $r
        $r=Invoke-Api DELETE "$cart/items/$zeroId"
        Check 'Delete same item twice => 404' ($r.Status -eq 404) $r
        $r=Invoke-Api GET $cart
        Check 'Deleted item absent; four remain' ((Items $r).Count -eq 4 -and @((Items $r) | Where-Object {$_.id -eq $zeroId}).Count -eq 0) $r
    }

    Write-Host "`n=== 4. Customer isolation and evict ===" -ForegroundColor Cyan
    $second=New-Customer 'second'; $secondUrl=CartUrl $second
    $r=Invoke-Api GET $secondUrl
    Check 'Second customer initially empty' ($r.Status -eq 200 -and (Items $r).Count -eq 0) $r
    $r=Invoke-Api POST "$secondUrl/items" (One "$prefix-second" 'ADD' 77)
    Check 'Second customer can add item' ($r.Status -eq 201 -and (Items $r).Count -eq 1) $r
    $r=Invoke-Api GET $cart
    Check 'First customer unaffected by second' ($r.Status -eq 200 -and (Items $r).Count -eq 4) $r
    $r=Invoke-Api DELETE $cart
    Check 'Evict first customer => 204' ($r.Status -eq 204) $r
    $r=Invoke-Api GET $cart
    Check 'Evicted cart empty' ($r.Status -eq 200 -and (Items $r).Count -eq 0) $r
    $r=Invoke-Api GET $secondUrl
    Check 'Evict did not affect second customer' ($r.Status -eq 200 -and (Items $r).Count -eq 1) $r
    $r=Invoke-Api DELETE $cart
    Check 'Repeated evict => 204' ($r.Status -eq 204) $r

    Write-Host "`n=== 5. Submit, stats, time boundaries ===" -ForegroundColor Cyan
    $buyer=New-Customer 'buyer'; $buyerUrl=CartUrl $buyer
    $saleOffer="$prefix-sale"
    $before=Sales $saleOffer 'ADD' $from $to
    Check 'No sales before checkout' ($before.Status -eq 200 -and $before.Data.count -eq 0) $before
    $null=Invoke-Api POST "$buyerUrl/items" (One $saleOffer 'ADD' 10)
    $null=Invoke-Api POST "$buyerUrl/items" (Rec $saleOffer 'ADD' 5 12 'MONTH')
    $null=Invoke-Api POST "$buyerUrl/items" (One $saleOffer 'MODIFY' 20)
    $null=Invoke-Api POST "$buyerUrl/items" (One $saleOffer 'DELETE' 30)
    $null=Invoke-Api POST "$buyerUrl/items" (One "$prefix-unrelated" 'ADD' 99)
    $r=Invoke-Api GET $buyerUrl
    Check 'Buyer has five items before submit' ($r.Status -eq 200 -and (Items $r).Count -eq 5) $r
    $r=Invoke-Api POST "$buyerUrl/submit"
    $saleTime=$null
    if ($r.Data -and $r.Data.submittedAt) { try {$saleTime=[datetime]::Parse($r.Data.submittedAt).ToUniversalTime()} catch {} }
    Check 'Submit => 201, SUBMITTED, order ID, customer, timestamp' ($r.Status -eq 201 -and $r.Data.status -eq 'SUBMITTED' -and -not [string]::IsNullOrWhiteSpace($r.Data.orderId) -and $r.Data.customerId -eq $buyer -and $null -ne $saleTime) $r
    $r=Invoke-Api GET $buyerUrl
    Check 'Buyer cart cleared after submit' ($r.Status -eq 200 -and (Items $r).Count -eq 0) $r
    $r=Invoke-Api GET $secondUrl
    Check 'Other customer cart survives submit' ($r.Status -eq 200 -and (Items $r).Count -eq 1) $r
    foreach($pair in @(@('ADD',2),@('MODIFY',1),@('DELETE',1))) {
        $r=Sales $saleOffer $pair[0] $from $to
        Check "Sales $($pair[0]) => $($pair[1])" ($r.Status -eq 200 -and $r.Data.count -eq $pair[1]) $r
    }
    $r=Sales "$prefix-unrelated" 'ADD' $from $to
    Check 'Unrelated offer in same order => 1' ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
    $r=Sales "$prefix-not-sold" 'ADD' $from $to
    Check 'Unrelated offer not sold => 0' ($r.Status -eq 200 -and $r.Data.count -eq 0) $r
    $r=Invoke-Api POST "$buyerUrl/submit"
    Check 'Repeated submit => 400' ($r.Status -eq 400) $r
    $r=Sales $saleOffer 'ADD' $from $to
    Check 'Repeated submit did not double count' ($r.Status -eq 200 -and $r.Data.count -eq 2) $r
    $r=Sales $saleOffer 'ADD' '2020-01-01T00:00:00Z' '2020-01-02T00:00:00Z'
    Check 'Old time range excludes new sales' ($r.Status -eq 200 -and $r.Data.count -eq 0) $r
    $r=Sales $saleOffer 'ADD' $to $from
    Check 'Reversed time range => 400' ($r.Status -eq 400) $r
    $r=Sales $saleOffer 'ADD' $from $from
    Check 'Equal time bounds => 400' ($r.Status -eq 400) $r
    if ($saleTime) {
        $beforeSale=$saleTime.AddSeconds(-1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $afterSale=$saleTime.AddSeconds(1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $atSale=$saleTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $r=Sales $saleOffer 'ADD' $beforeSale $atSale
        Check 'Exclusive upper bound excludes sale' ($r.Status -eq 200 -and $r.Data.count -eq 0) $r
        $r=Sales $saleOffer 'ADD' $atSale $afterSale
        Check 'Inclusive lower bound includes sale' ($r.Status -eq 200 -and $r.Data.count -eq 2) $r
    }

    Write-Host "`n=== 6. Statistics input validation ===" -ForegroundColor Cyan
    foreach($case in @(
        @{Label='Missing offerId';Query="action=ADD&from=$from&to=$to"},
        @{Label='Blank offerId';Query="offerId=%20%20&action=ADD&from=$from&to=$to"},
        @{Label='Missing action';Query="offerId=$saleOffer&from=$from&to=$to"},
        @{Label='Invalid action';Query="offerId=$saleOffer&action=UPSERT&from=$from&to=$to"},
        @{Label='Missing from';Query="offerId=$saleOffer&action=ADD&to=$to"},
        @{Label='Missing to';Query="offerId=$saleOffer&action=ADD&from=$from"},
        @{Label='Invalid from';Query="offerId=$saleOffer&action=ADD&from=not-a-date&to=$to"},
        @{Label='Invalid to';Query="offerId=$saleOffer&action=ADD&from=$from&to=not-a-date"}
    )) {
        $r=Invoke-Api GET "$statsUrl`?$($case.Query)"
        Check "Stats $($case.Label) => 400" ($r.Status -eq 400) $r
    }

    Write-Host "`n=== 7. Second purchase, persistent totals ===" -ForegroundColor Cyan
    $null=Invoke-Api POST "$buyerUrl/items" (One $saleOffer 'ADD' 11)
    $r=Invoke-Api POST "$buyerUrl/submit"
    Check 'Same customer can make second purchase' ($r.Status -eq 201 -and $r.Data.status -eq 'SUBMITTED') $r
    $r=Sales $saleOffer 'ADD' $from $to
    Check 'Sales accumulate across purchases => 3' ($r.Status -eq 200 -and $r.Data.count -eq 3) $r
    $r=Sales $saleOffer 'MODIFY' $from $to
    Check 'MODIFY count unchanged by second purchase => 1' ($r.Status -eq 200 -and $r.Data.count -eq 1) $r

    Write-Host "`n=== 8. Concurrent submits (optional diagnostic) ===" -ForegroundColor Cyan
    if ($SkipConcurrency) { Warn 'Concurrent submit' 'Skipped by -SkipConcurrency' }
    else {
        $race=New-Customer 'race'; $raceUrl=CartUrl $race; $raceOffer="$prefix-race"
        $seed=Invoke-Api POST "$raceUrl/items" (One $raceOffer 'ADD' 1)
        if ($seed.Status -ne 201) { Warn 'Concurrent submit' 'Could not seed race cart' }
        else {
            $jobs=@()
            for($i=0;$i -lt 2;$i++) {
                $jobs+=Start-Job -ArgumentList "$raceUrl/submit" -ScriptBlock {
                    param($url)
                    try { $r=Invoke-WebRequest -Uri $url -Method Post -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop; [int]$r.StatusCode }
                    catch { if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 } }
                }
            }
            $null=$jobs | Wait-Job -Timeout 35
            $statuses=@($jobs | Receive-Job)
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue | Out-Null
            $r=Sales $raceOffer 'ADD' $from $to
            Check 'Two concurrent submits produce exactly one sale' ($r.Status -eq 200 -and $r.Data.count -eq 1) ([pscustomobject]@{Statuses=$statuses;Sales=$r})
            if (@($statuses | Where-Object {$_ -eq 201}).Count -ne 1) { Warn 'Concurrent response codes' "Expected one HTTP 201; observed $($statuses -join ', ') (inspect logs)" }
        }
    }
} catch {
    $script:failed++
    Write-Host "[FAIL] Unexpected script error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
} finally {
    if (-not $KeepTestData) {
        foreach($c in $customers) { $null=Invoke-Api DELETE (CartUrl $c) }
    }
}

Write-Host "`nRESULT: $passed passed, $failed failed, $warnings warnings" -ForegroundColor $(if($failed -eq 0){'Green'}else{'Red'})
Write-Host "Run ID: $runId"
Write-Host 'Confirmed sales remain in MongoDB (unique test offer IDs); test carts are cleaned unless -KeepTestData.'
if ($failed -gt 0) { exit 1 }
exit 0
