param([string]$BaseUrl = 'http://localhost:8080', [switch]$KeepTestData)
$ErrorActionPreference = 'Stop'
$base = $BaseUrl.TrimEnd('/')
$runId = [guid]::NewGuid().ToString('N').Substring(0,12)
$customer = "api-test-$runId"
$cartUrl = "$base/api/customers/$customer/cart"
$statsUrl = "$base/api/statistics/sales"
$offer = "test-offer-$runId"
$passed = 0; $failed = 0
function Invoke-Api([string]$Method,[string]$Url,[object]$Body=$null) {
    $p = @{ Uri=$Url; Method=$Method; UseBasicParsing=$true; ErrorAction='Stop' }
    if ($null -ne $Body) { $p.ContentType='application/json'; $p.Body=($Body | ConvertTo-Json -Depth 12 -Compress) }
    try { $r=Invoke-WebRequest @p; $data=$null; if ($r.Content) { $data=$r.Content | ConvertFrom-Json }; return [pscustomobject]@{ Status=[int]$r.StatusCode; Data=$data } }
    catch {
        $status=0; $data=$null
        if ($_.Exception.Response) { $status=[int]$_.Exception.Response.StatusCode }
        if ($_.ErrorDetails.Message) { try { $data=$_.ErrorDetails.Message | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status=$status; Data=$data; Error=$_.Exception.Message }
    }
}
function Check([string]$Name,[bool]$Condition,[object]$Response=$null) {
    if ($Condition) { $script:passed++; Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { $script:failed++; Write-Host "[FAIL] $Name" -ForegroundColor Red; if ($Response) { $Response | ConvertTo-Json -Depth 8 | Write-Host } }
}
function SalesCount([string]$OfferId,[string]$Action,[string]$From,[string]$To) {
    $url="$statsUrl`?offerId=$([uri]::EscapeDataString($OfferId))&action=$Action&from=$([uri]::EscapeDataString($From))&to=$([uri]::EscapeDataString($To))"
    return Invoke-Api GET $url
}
$from=[datetime]::UtcNow.AddMinutes(-10).ToString('yyyy-MM-ddTHH:mm:ssZ')
$to=[datetime]::UtcNow.AddHours(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
$otherOffer="other-$runId"
$oneTime=@{ offerId=$offer; action='ADD'; prices=@(@{type='ONE_TIME';value=19.99}) }
$recurring=@{ offerId=$offer; action='MODIFY'; prices=@(@{type='RECURRING';value=15;recurrences=12;recurrenceUnit='MONTH'}) }
Write-Host "Testing $base | customer: $customer" -ForegroundColor Cyan
try {
    $r=Invoke-Api GET $cartUrl
    Check 'GET empty cart => 200, zero items' ($r.Status -eq 200 -and @($r.Data.items).Count -eq 0) $r

    $r=Invoke-Api POST "$cartUrl/submit"
    Check 'POST submit empty cart => 400' ($r.Status -eq 400) $r

    $r=Invoke-Api POST "$cartUrl/items" @{offerId='';action='ADD';prices=@(@{type='ONE_TIME';value=10})}
    Check 'POST invalid offerId => 400' ($r.Status -eq 400) $r

    $r=Invoke-Api POST "$cartUrl/items" @{offerId=$offer;action='ADD';prices=@()}
    Check 'POST empty prices => 400' ($r.Status -eq 400) $r

    $r=Invoke-Api POST "$cartUrl/items" @{offerId=$offer;action='ADD';prices=@(@{type='ONE_TIME';value=-1})}
    Check 'POST negative price => 400' ($r.Status -eq 400) $r

    $r=Invoke-Api POST "$cartUrl/items" @{offerId=$offer;action='INVALID';prices=@(@{type='ONE_TIME';value=1})}
    Check 'POST invalid action => 400' ($r.Status -eq 400) $r

    $r=Invoke-Api POST "$cartUrl/items" @{offerId=$offer;action='ADD';prices=@(@{type='RECURRING';value=5;recurrences=0;recurrenceUnit='MONTH'})}
    Check 'POST invalid recurrences => 400' ($r.Status -eq 400) $r

    $r=Invoke-Api POST "$cartUrl/items" $oneTime
    Check 'POST add ONE_TIME => 201' ($r.Status -eq 201 -and @($r.Data.items).Count -eq 1) $r
    $firstId=$null; if ($r.Data -and $r.Data.items) { $firstId=$r.Data.items[0].id }
    Check 'Added item has ID' (-not [string]::IsNullOrWhiteSpace($firstId)) $r

    $r=Invoke-Api POST "$cartUrl/items" $recurring
    Check 'POST add RECURRING => 201' ($r.Status -eq 201 -and @($r.Data.items).Count -eq 2) $r

    $r=Invoke-Api GET $cartUrl
    Check 'GET cart => two items' ($r.Status -eq 200 -and @($r.Data.items).Count -eq 2) $r

    $r=Invoke-Api DELETE "$cartUrl/items/does-not-exist"
    Check 'DELETE nonexistent item => 404' ($r.Status -eq 404) $r

    if ($firstId) {
        $r=Invoke-Api DELETE "$cartUrl/items/$firstId"
        Check 'DELETE existing item => 204' ($r.Status -eq 204) $r
    }
    $r=Invoke-Api GET $cartUrl
    Check 'GET cart after delete => one item' ($r.Status -eq 200 -and @($r.Data.items).Count -eq 1) $r

    $r=Invoke-Api DELETE $cartUrl
    Check 'DELETE cart => 204' ($r.Status -eq 204) $r
    $r=Invoke-Api GET $cartUrl
    Check 'GET after evict => empty' ($r.Status -eq 200 -and @($r.Data.items).Count -eq 0) $r

    $r=SalesCount $offer 'ADD' $from $to
    Check 'Sales before submit => 0' ($r.Status -eq 200 -and $r.Data.count -eq 0) $r

    $r=Invoke-Api POST "$cartUrl/items" $oneTime
    Check 'POST add item for submit => 201' ($r.Status -eq 201) $r
    $r=Invoke-Api POST "$cartUrl/items" $recurring
    Check 'POST add second item for submit => 201' ($r.Status -eq 201) $r

    $r=Invoke-Api POST "$cartUrl/submit"
    Check 'POST submit => 201 and SUBMITTED' ($r.Status -eq 201 -and $r.Data.status -eq 'SUBMITTED' -and -not [string]::IsNullOrWhiteSpace($r.Data.orderId)) $r

    $r=Invoke-Api GET $cartUrl
    Check 'GET after submit => empty' ($r.Status -eq 200 -and @($r.Data.items).Count -eq 0) $r

    $r=SalesCount $offer 'ADD' $from $to
    Check 'Sales ADD after submit => 1' ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
    $r=SalesCount $offer 'MODIFY' $from $to
    Check 'Sales MODIFY after submit => 1' ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
    $r=SalesCount $offer 'DELETE' $from $to
    Check 'Sales DELETE after submit => 0' ($r.Status -eq 200 -and $r.Data.count -eq 0) $r
    $r=SalesCount $otherOffer 'ADD' $from $to
    Check 'Sales unrelated offer => 0' ($r.Status -eq 200 -and $r.Data.count -eq 0) $r

    $r=Invoke-Api POST "$cartUrl/submit"
    Check 'Repeated submit empty cart => 400' ($r.Status -eq 400) $r
    $r=SalesCount $offer 'ADD' $from $to
    Check 'Repeated submit did not double count' ($r.Status -eq 200 -and $r.Data.count -eq 1) $r

    $url="$statsUrl`?offerId=$offer&action=ADD&from=$([uri]::EscapeDataString($to))&to=$([uri]::EscapeDataString($from))"
    $r=Invoke-Api GET $url
    Check 'Sales invalid time range => 400' ($r.Status -eq 400) $r
} finally {
    # Only remove the dedicated test customer's cart; submitted sales are intentionally kept for verification.
    if (-not $KeepTestData) { $null=Invoke-Api DELETE $cartUrl }
}
Write-Host "`nRESULT: $passed passed, $failed failed. Test customer: $customer" -ForegroundColor $(if($failed -eq 0){'Green'}else{'Red'})
Write-Host 'NOTE: Confirmed sales created by this test remain in MongoDB (unique test offer IDs).'
if ($failed -gt 0) { exit 1 }
