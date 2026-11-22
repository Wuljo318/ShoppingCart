param(
    [string]$BaseUrl = "http://localhost:8080",
    [switch]$SkipConcurrency,
    [switch]$KeepTestCarts,
    [int]$StressItems = 100,
    [int]$StressCustomers = 12
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")
$run = [guid]::NewGuid().ToString("N").Substring(0, 12)
$prefix = "api-check-$run"
$customer = "$prefix-main"
$other = "$prefix-other"
$race = "$prefix-race"
$offer = "$prefix-offer"
$passed = 0
$failed = 0
$skipped = 0
$stressCustomer = "$prefix-stress"
$testCustomers = @($customer, $other, $race, $stressCustomer)
$now = [DateTimeOffset]::UtcNow
$from = $now.AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
$to = $now.AddDays(1).ToString("yyyy-MM-ddTHH:mm:ssZ")
$oldFrom = "2020-01-01T00:00:00Z"
$oldTo = "2020-02-01T00:00:00Z"

function Invoke-Api {
    param([string]$Method, [string]$Path, [string]$Body)
    $args = @{ Uri = "$BaseUrl$Path"; Method = $Method; UseBasicParsing = $true; ErrorAction = "Stop"; TimeoutSec = 20 }
    if ($PSBoundParameters.ContainsKey("Body")) {
        $args.Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $args.ContentType = "application/json; charset=utf-8"
    }
    try {
        $response = Invoke-WebRequest @args
        $data = $null
        if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
            try { $data = $response.Content | ConvertFrom-Json } catch { $data = $response.Content }
        }
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Data = $data; Error = $null }
    } catch {
        $status = 0
        $data = $null
        $errorText = $_.Exception.Message
        $response = $_.Exception.Response
        if ($null -ne $response) {
            try { $status = [int]$response.StatusCode } catch {}
            try {
                $stream = $response.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $raw = $reader.ReadToEnd()
                    $reader.Dispose()
                    if ($raw) {
                        try { $data = $raw | ConvertFrom-Json } catch { $data = $raw }
                    }
                }
            } catch {}
        }
        return [pscustomobject]@{ Status = $status; Data = $data; Error = $errorText }
    }
}

function Check {
    param([string]$Name, [bool]$Condition, $Actual)
    if ($Condition) {
        $script:passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } else {
        $script:failed++
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        if ($null -ne $Actual) {
            Write-Host ("       " + ($Actual | ConvertTo-Json -Depth 15 -Compress)) -ForegroundColor DarkYellow
        }
    }
}

function CartPath([string]$id) { return "/api/customers/$id/cart" }

function Make-Item {
    param([string]$OfferId, [string]$Action = "ADD", [string]$Kind = "ONE_TIME", [decimal]$Value = 15.50,
          [int]$Recurrences = 12, [string]$Unit = "MONTH")
    if ($Kind -eq "ONE_TIME") {
        return '{"offerId":"' + $OfferId + '","action":"' + $Action + '","prices":[{"type":"ONE_TIME","value":' +
            $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) + '}]}'
    }
    return '{"offerId":"' + $OfferId + '","action":"' + $Action + '","prices":[{"type":"RECURRING","value":' +
        $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) +
        ',"recurrences":' + $Recurrences + ',"recurrenceUnit":"' + $Unit + '"}]}'
}

function SalesPath([string]$OfferId, [string]$Action, [string]$FromDate = $from, [string]$ToDate = $to) {
    return "/api/statistics/sales?offerId=$([uri]::EscapeDataString($OfferId))&action=$Action&from=$([uri]::EscapeDataString($FromDate))&to=$([uri]::EscapeDataString($ToDate))"
}

function ItemsCount($response) {
    if ($response.Status -ne 200 -or $null -eq $response.Data -or $null -eq $response.Data.items) { return -1 }
    return @($response.Data.items).Count
}

Write-Host "Shopping Cart API verification | $BaseUrl | run $run"
Write-Host "Test customers: $customer, $other"
Write-Host "All sales use unique offer ID: $offer"
Write-Host ""

try {
    Write-Host "=== 1. Empty cart and validation ===" -ForegroundColor Cyan
    $r = Invoke-Api GET (CartPath $customer)
    Check "GET new cart -> 200, empty" ($r.Status -eq 200 -and (ItemsCount $r) -eq 0 -and $r.Data.customerId -eq $customer) $r
    $r = Invoke-Api POST "$(CartPath $customer)/submit"
    Check "Submit empty cart -> 400" ($r.Status -eq 400) $r
    $r = Invoke-Api DELETE "$(CartPath $customer)/items/missing"
    Check "Delete missing item -> 404" ($r.Status -eq 404) $r
    $r = Invoke-Api DELETE (CartPath $customer)
    Check "Delete empty cart -> 204" ($r.Status -eq 204) $r

    $invalid = @(
        @{ Name = "Malformed JSON"; Body = '{"offerId":' },
        @{ Name = "Empty offerId"; Body = '{"offerId":"","action":"ADD","prices":[{"type":"ONE_TIME","value":10}]}' },
        @{ Name = "Blank offerId"; Body = '{"offerId":" ","action":"ADD","prices":[{"type":"ONE_TIME","value":10}]}' },
        @{ Name = "Missing offerId"; Body = '{"action":"ADD","prices":[{"type":"ONE_TIME","value":10}]}' },
        @{ Name = "Missing action"; Body = '{"offerId":"x","prices":[{"type":"ONE_TIME","value":10}]}' },
        @{ Name = "Invalid action"; Body = '{"offerId":"x","action":"OTHER","prices":[{"type":"ONE_TIME","value":10}]}' },
        @{ Name = "Missing prices"; Body = '{"offerId":"x","action":"ADD"}' },
        @{ Name = "Empty prices"; Body = '{"offerId":"x","action":"ADD","prices":[]}' },
        @{ Name = "Null price"; Body = '{"offerId":"x","action":"ADD","prices":[null]}' },
        @{ Name = "Unknown price type"; Body = '{"offerId":"x","action":"ADD","prices":[{"type":"OTHER","value":10}]}' },
        @{ Name = "Negative price"; Body = '{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME","value":-1}]}' },
        @{ Name = "Too many decimals"; Body = '{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME","value":1.001}]}' },
        @{ Name = "Recurring zero count"; Body = '{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":10,"recurrences":0,"recurrenceUnit":"MONTH"}]}' },
        @{ Name = "Recurring missing unit"; Body = '{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":10,"recurrences":12}]}' },
        @{ Name = "Recurring invalid unit"; Body = '{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":10,"recurrences":12,"recurrenceUnit":"WEEK"}]}' }
    )
    foreach ($case in $invalid) {
        $r = Invoke-Api POST "$(CartPath $customer)/items" $case.Body
        Check "$($case.Name) -> 400" ($r.Status -eq 400) $r
    }
    $r = Invoke-Api GET (CartPath $customer)
    Check "Rejected requests leave cart empty" ((ItemsCount $r) -eq 0) $r

    Write-Host ""
    Write-Host "=== 2. Valid items, deletion and isolation ===" -ForegroundColor Cyan
    $one = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item $offer "ADD" "ONE_TIME" 15.50)
    Check "Add ONE_TIME -> 201" ($one.Status -eq 201 -and @($one.Data.items).Count -eq 1) $one
    $itemId = $null
    if ($one.Status -eq 201 -and @($one.Data.items).Count -gt 0) { $itemId = $one.Data.items[0].id }
    Check "Generated item ID" (-not [string]::IsNullOrWhiteSpace($itemId)) $one

    $two = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item $offer "MODIFY" "RECURRING" 9.99 12 "MONTH")
    Check "Add RECURRING MONTH -> 201" ($two.Status -eq 201 -and @($two.Data.items).Count -eq 2) $two
    $three = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item "$offer-extra" "DELETE" "RECURRING" 2.25 3 "DAY")
    Check "Add RECURRING DAY with DELETE action -> 201" ($three.Status -eq 201 -and @($three.Data.items).Count -eq 3) $three
    $four = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item "$offer-extra" "ADD" "RECURRING" 0.01 2 "YEAR")
    Check "Add RECURRING YEAR -> 201" ($four.Status -eq 201 -and @($four.Data.items).Count -eq 4) $four

    $r = Invoke-Api GET (CartPath $customer)
    Check "GET preserves four items" ((ItemsCount $r) -eq 4) $r
    if ((ItemsCount $r) -eq 4) {
        $ids = @($r.Data.items | ForEach-Object { $_.id })
        Check "All item IDs are unique" ((@($ids | Select-Object -Unique)).Count -eq 4) $ids
        Check "Price type and recurrence unit preserved" ($r.Data.items[1].prices[0].type -eq "RECURRING" -and $r.Data.items[1].prices[0].recurrenceUnit -eq "MONTH") $r
    }

    $otherAdd = Invoke-Api POST "$(CartPath $other)/items" (Make-Item "$offer-other" "ADD" "ONE_TIME" 7.25)
    Check "Other customer can add item" ($otherAdd.Status -eq 201) $otherAdd
    $r = Invoke-Api GET (CartPath $customer)
    Check "Other customer's add does not change first cart" ((ItemsCount $r) -eq 4) $r

    if ($itemId) {
        $r = Invoke-Api DELETE "$(CartPath $customer)/items/$itemId"
        Check "Delete existing item -> 204" ($r.Status -eq 204) $r
        $r = Invoke-Api DELETE "$(CartPath $customer)/items/$itemId"
        Check "Delete same item again -> 404" ($r.Status -eq 404) $r
        $r = Invoke-Api GET (CartPath $customer)
        Check "Delete removes exactly one item" ((ItemsCount $r) -eq 3) $r
    }

    $r = Invoke-Api DELETE (CartPath $customer)
    Check "Evict cart -> 204" ($r.Status -eq 204) $r
    $r = Invoke-Api GET (CartPath $customer)
    Check "Evicted cart is empty" ((ItemsCount $r) -eq 0) $r
    $r = Invoke-Api GET (CartPath $other)
    Check "Other customer remains unaffected" ((ItemsCount $r) -eq 1) $r

    Write-Host ""
    Write-Host "=== 3. Submit and statistics ===" -ForegroundColor Cyan
    $r = Invoke-Api GET (SalesPath $offer "ADD")
    Check "Sales count before submit = 0" ($r.Status -eq 200 -and $r.Data.count -eq 0) $r

    $a = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item $offer "ADD" "ONE_TIME" 20)
    $b = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item $offer "MODIFY" "RECURRING" 5 6 "MONTH")
    $c = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item "$offer-extra" "DELETE" "ONE_TIME" 1)
    Check "Seed checkout cart with three items" ($a.Status -eq 201 -and $b.Status -eq 201 -and $c.Status -eq 201) @($a,$b,$c)
    if ($a.Status -eq 201 -and $b.Status -eq 201 -and $c.Status -eq 201) {
        $submitted = Invoke-Api POST "$(CartPath $customer)/submit"
        Check "Submit -> 201, SUBMITTED and orderId" ($submitted.Status -eq 201 -and $submitted.Data.status -eq "SUBMITTED" -and -not [string]::IsNullOrWhiteSpace($submitted.Data.orderId) -and $submitted.Data.customerId -eq $customer) $submitted
        $r = Invoke-Api GET (CartPath $customer)
        Check "Cart empty after submit" ((ItemsCount $r) -eq 0) $r
        $r = Invoke-Api GET (SalesPath $offer "ADD")
        Check "Sales ADD = 1" ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
        $r = Invoke-Api GET (SalesPath $offer "MODIFY")
        Check "Sales MODIFY = 1" ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
        $r = Invoke-Api GET (SalesPath "$offer-extra" "DELETE")
        Check "Sales DELETE = 1" ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
        $r = Invoke-Api POST "$(CartPath $customer)/submit"
        Check "Repeated submit -> 400" ($r.Status -eq 400) $r
        $r = Invoke-Api GET (SalesPath $offer "ADD")
        Check "Repeated submit did not duplicate sale" ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
        $r = Invoke-Api GET (SalesPath $offer "ADD" $oldFrom $oldTo)
        Check "Old date range excludes sale" ($r.Status -eq 200 -and $r.Data.count -eq 0) $r

        $r = Invoke-Api POST "$(CartPath $customer)/items" (Make-Item $offer "ADD" "ONE_TIME" 30)
        if ($r.Status -eq 201) {
            $r = Invoke-Api POST "$(CartPath $customer)/submit"
            Check "Second purchase by same customer -> 201" ($r.Status -eq 201) $r
            $r = Invoke-Api GET (SalesPath $offer "ADD")
            Check "Sales accumulate across two purchases = 2" ($r.Status -eq 200 -and $r.Data.count -eq 2) $r
        } else { Check "Seed second purchase" $false $r }
    }

    $r = Invoke-Api GET (SalesPath $offer "ADD" $to $from)
    Check "Reversed date range -> 400" ($r.Status -eq 400) $r
    $r = Invoke-Api GET (SalesPath $offer "ADD" $from $from)
    Check "Equal date bounds -> 400" ($r.Status -eq 400) $r
    $r = Invoke-Api GET "/api/statistics/sales?offerId=$offer&action=UNKNOWN&from=$from&to=$to"
    Check "Invalid action in statistics -> 400" ($r.Status -eq 400) $r


    Write-Host ""
    Write-Host "=== 4. Hardcore validation matrix ===" -ForegroundColor Cyan
    $moreInvalid = @(
        @{Name="Null JSON"; Body='null'},
        @{Name="JSON array instead of object"; Body='[]'},
        @{Name="JSON string instead of object"; Body='"hello"'},
        @{Name="JSON number instead of object"; Body='123'},
        @{Name="Null offerId"; Body='{"offerId":null,"action":"ADD","prices":[{"type":"ONE_TIME","value":1}]}'},
        @{Name="Null action"; Body='{"offerId":"x","action":null,"prices":[{"type":"ONE_TIME","value":1}]}'},
        @{Name="Null prices"; Body='{"offerId":"x","action":"ADD","prices":null}'},
        @{Name="Prices is string"; Body='{"offerId":"x","action":"ADD","prices":"abc"}'},
        @{Name="Prices is object"; Body='{"offerId":"x","action":"ADD","prices":{"type":"ONE_TIME","value":1}}'},
        @{Name="OfferId is object"; Body='{"offerId":{"x":1},"action":"ADD","prices":[{"type":"ONE_TIME","value":1}]}'},
        @{Name="Action is number"; Body='{"offerId":"x","action":42,"prices":[{"type":"ONE_TIME","value":1}]}'},
        @{Name="Price element is string"; Body='{"offerId":"x","action":"ADD","prices":["abc"]}'},
        @{Name="Price type null"; Body='{"offerId":"x","action":"ADD","prices":[{"type":null,"value":1}]}'},
        @{Name="Price type missing"; Body='{"offerId":"x","action":"ADD","prices":[{"value":1}]}'},
        @{Name="Price value null"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME","value":null}]}'},
        @{Name="Price value missing"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME"}]}'},
        @{Name="Price value negative 0.01"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME","value":-0.01}]}'},
        @{Name="Price too many fraction digits"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME","value":0.001}]}'},
        @{Name="Price too many integer digits"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME","value":1000000000000}]}'},
        @{Name="Recurring negative count"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":1,"recurrences":-1,"recurrenceUnit":"DAY"}]}'},
        @{Name="Recurring null count"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":1,"recurrences":null,"recurrenceUnit":"DAY"}]}'},
        @{Name="Recurring missing count"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":1,"recurrenceUnit":"DAY"}]}'},
        @{Name="Recurring null unit"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":1,"recurrences":1,"recurrenceUnit":null}]}'},
        @{Name="Recurring decimal count"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":1,"recurrences":1.5,"recurrenceUnit":"DAY"}]}'},
        @{Name="Recurring invalid case unit"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"RECURRING","value":1,"recurrences":1,"recurrenceUnit":"month"}]}'},
        @{Name="Wrong action case"; Body='{"offerId":"x","action":"add","prices":[{"type":"ONE_TIME","value":1}]}'},
        @{Name="Wrong price type case"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"one_time","value":1}]}'},
        @{Name="Broken trailing comma"; Body='{"offerId":"x","action":"ADD","prices":[{"type":"ONE_TIME","value":1}],}'}
    )
    foreach ($case in $moreInvalid) {
        $r = Invoke-Api POST "$(CartPath $stressCustomer)/items" $case.Body
        Check "Invalid: $($case.Name) -> 400" ($r.Status -eq 400) $r
    }
    $r = Invoke-Api GET (CartPath $stressCustomer)
    Check "All invalid requests left stress cart empty" ((ItemsCount $r) -eq 0) $r

    Write-Host ""
    Write-Host "=== 5. Boundary values and data integrity ===" -ForegroundColor Cyan
    $validBoundary = @(
        @{Name="Zero price"; Offer="$prefix-zero"; Body='{"offerId":"__OFFER__","action":"ADD","prices":[{"type":"ONE_TIME","value":0}]}'},
        @{Name="Smallest cent"; Offer="$prefix-cent"; Body='{"offerId":"__OFFER__","action":"ADD","prices":[{"type":"ONE_TIME","value":0.01}]}'},
        @{Name="Largest allowed amount"; Offer="$prefix-max"; Body='{"offerId":"__OFFER__","action":"ADD","prices":[{"type":"ONE_TIME","value":999999999999.99}]}'},
        @{Name="Recurring one period"; Offer="$prefix-one"; Body='{"offerId":"__OFFER__","action":"MODIFY","prices":[{"type":"RECURRING","value":0.01,"recurrences":1,"recurrenceUnit":"DAY"}]}'},
        @{Name="Recurring large count"; Offer="$prefix-many"; Body='{"offerId":"__OFFER__","action":"ADD","prices":[{"type":"RECURRING","value":1,"recurrences":2147483647,"recurrenceUnit":"YEAR"}]}'},
        @{Name="Mixed prices"; Offer="$prefix-mixed"; Body='{"offerId":"__OFFER__","action":"ADD","prices":[{"type":"ONE_TIME","value":9.99},{"type":"RECURRING","value":1.01,"recurrences":2,"recurrenceUnit":"MONTH"}]}'}
    )
    foreach ($case in $validBoundary) {
        $id = $case.Offer.Replace('$prefix', $prefix)
        $body = $case.Body.Replace('__OFFER__', $id)
        $r = Invoke-Api POST "$(CartPath $stressCustomer)/items" $body
        Check "Valid boundary: $($case.Name) -> 201" ($r.Status -eq 201) $r
    }
    $r = Invoke-Api GET (CartPath $stressCustomer)
    Check "All six boundary items persisted" ((ItemsCount $r) -eq 6) $r
    if ((ItemsCount $r) -eq 6) {
        $mixed = @($r.Data.items | Where-Object { $_.offerId -eq "$prefix-mixed" })
        Check "Mixed-price item contains both price types" ($mixed.Count -eq 1 -and @($mixed[0].prices).Count -eq 2 -and $mixed[0].prices[0].type -eq "ONE_TIME" -and $mixed[0].prices[1].type -eq "RECURRING") $mixed
        $max = @($r.Data.items | Where-Object { $_.offerId -eq "$prefix-max" })
        Check "Large decimal amount round trips" ($max.Count -eq 1 -and [decimal]$max[0].prices[0].value -eq [decimal]999999999999.99) $max
    }
    $r = Invoke-Api DELETE (CartPath $stressCustomer)
    Check "Reset stress cart -> 204" ($r.Status -eq 204) $r

    Write-Host ""
    Write-Host "=== 6. Stress: $StressItems sequential additions ===" -ForegroundColor Cyan
    $stressOffer = "$prefix-bulk"
    $stressErrors = @()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 1; $i -le $StressItems; $i++) {
        $action = @("ADD", "MODIFY", "DELETE")[($i - 1) % 3]
        $r = Invoke-Api POST "$(CartPath $stressCustomer)/items" (Make-Item $stressOffer $action "ONE_TIME" 1)
        if ($r.Status -ne 201) { $stressErrors += "item $i -> $($r.Status)" }
        if ($i % 25 -eq 0) { Write-Host "  Added $i / $StressItems" -ForegroundColor DarkGray }
    }
    $watch.Stop()
    Check "All $StressItems sequential additions -> 201" ($stressErrors.Count -eq 0) $stressErrors
    Write-Host ("  Add throughput: {0:N1} req/s" -f ($StressItems / [math]::Max(0.001, $watch.Elapsed.TotalSeconds))) -ForegroundColor DarkGray
    $r = Invoke-Api GET (CartPath $stressCustomer)
    Check "Stress cart count = $StressItems" ((ItemsCount $r) -eq $StressItems) $r
    $stressIds = @()
    if ((ItemsCount $r) -eq $StressItems) {
        $stressIds = @($r.Data.items | ForEach-Object { $_.id })
        Check "All $StressItems stress item IDs unique" ((@($stressIds | Select-Object -Unique)).Count -eq $StressItems) $stressIds
        $expectedCounts = @(0,0,0)
        for ($i = 0; $i -lt $StressItems; $i++) { $expectedCounts[$i % 3]++ }
        foreach ($i in 0..2) {
            $action = @("ADD", "MODIFY", "DELETE")[$i]
            $count = @($r.Data.items | Where-Object { $_.action -eq $action }).Count
            Check "Stress cart $action count = $($expectedCounts[$i])" ($count -eq $expectedCounts[$i]) $count
        }
    }
    $removeCount = [int][math]::Floor($stressIds.Count / 2)
    $removeErrors = @()
    for ($i = 0; $i -lt $removeCount; $i++) {
        $r = Invoke-Api DELETE "$(CartPath $stressCustomer)/items/$($stressIds[$i])"
        if ($r.Status -ne 204) { $removeErrors += "remove $i -> $($r.Status)" }
    }
    Check "Remove $removeCount stress items -> 204" ($removeErrors.Count -eq 0) $removeErrors
    $r = Invoke-Api GET (CartPath $stressCustomer)
    Check "Remaining stress cart count = $($StressItems - $removeCount)" ((ItemsCount $r) -eq ($StressItems - $removeCount)) $r
    if ((ItemsCount $r) -gt 0) {
        $expected = @{}
        foreach ($item in $r.Data.items) {
            $key = [string]$item.action
            if (-not $expected.ContainsKey($key)) { $expected[$key] = 0 }
            $expected[$key]++
        }
        $submit = Invoke-Api POST "$(CartPath $stressCustomer)/submit"
        Check "Submit stress cart -> 201" ($submit.Status -eq 201) $submit
        foreach ($action in @("ADD","MODIFY","DELETE")) {
            $want = 0
            if ($expected.ContainsKey($action)) { $want = $expected[$action] }
            $stat = Invoke-Api GET (SalesPath $stressOffer $action)
            Check "Stress sales $action = $want" ($stat.Status -eq 200 -and $stat.Data.count -eq $want) $stat
        }
        $r = Invoke-Api GET (CartPath $stressCustomer)
        Check "Stress cart cleared after submit" ((ItemsCount $r) -eq 0) $r
    }

    Write-Host ""
    Write-Host "=== 7. Customer isolation across $StressCustomers customers ===" -ForegroundColor Cyan
    $isolationErrors = @()
    for ($i = 1; $i -le $StressCustomers; $i++) {
        $id = "$prefix-isolation-$i"
        $testCustomers += $id
        $r = Invoke-Api POST "$(CartPath $id)/items" (Make-Item "$prefix-isolation-offer-$i" "ADD" "ONE_TIME" 1)
        if ($r.Status -ne 201) { $isolationErrors += "$id add: $($r.Status)" }
    }
    Check "All $StressCustomers customers add independently" ($isolationErrors.Count -eq 0) $isolationErrors
    $isolationErrors = @()
    for ($i = 1; $i -le $StressCustomers; $i++) {
        $id = "$prefix-isolation-$i"
        $r = Invoke-Api GET (CartPath $id)
        if ((ItemsCount $r) -ne 1 -or $r.Data.items[0].offerId -ne "$prefix-isolation-offer-$i") {
            $isolationErrors += "$id has wrong items"
        }
    }
    Check "All $StressCustomers carts have only own items" ($isolationErrors.Count -eq 0) $isolationErrors
    for ($i = 1; $i -le $StressCustomers; $i += 2) {
        $id = "$prefix-isolation-$i"
        $null = Invoke-Api DELETE (CartPath $id)
    }
    $isolationErrors = @()
    for ($i = 1; $i -le $StressCustomers; $i++) {
        $id = "$prefix-isolation-$i"
        $r = Invoke-Api GET (CartPath $id)
        $want = if ($i % 2 -eq 1) { 0 } else { 1 }
        if ((ItemsCount $r) -ne $want) { $isolationErrors += "$id expected $want" }
    }
    Check "Evicting odd-numbered carts leaves even-numbered carts unchanged" ($isolationErrors.Count -eq 0) $isolationErrors

    if (-not $SkipConcurrency) {
        Write-Host ""
        Write-Host "=== 8. Concurrent submit diagnostic ===" -ForegroundColor Cyan
        $r = Invoke-Api POST "$(CartPath $race)/items" (Make-Item "$offer-race" "ADD" "ONE_TIME" 1)
        if ($r.Status -ne 201) {
            $script:skipped++
            Write-Host "[SKIP] Concurrency test: could not seed cart" -ForegroundColor Yellow
        } else {
            $racePath = "$(CartPath $race)/submit"
            $jobs = @()
            try {
                1..2 | ForEach-Object {
                    $jobs += Start-Job -ScriptBlock {
                        param($url)
                        try {
                            $response = Invoke-WebRequest -Uri $url -Method POST -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                            return [int]$response.StatusCode
                        } catch {
                            if ($null -ne $_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
                            return 0
                        }
                    } -ArgumentList "$BaseUrl$racePath"
                }
                $codes = @($jobs | Wait-Job -Timeout 45 | Receive-Job)
                $successes = @($codes | Where-Object { $_ -eq 201 }).Count
                Check "Concurrent submits: exactly one 201" ($successes -eq 1 -and $codes.Count -eq 2) $codes
                $r = Invoke-Api GET (SalesPath "$offer-race" "ADD")
                Check "Concurrent submits: exactly one confirmed sale" ($r.Status -eq 200 -and $r.Data.count -eq 1) $r
            } finally {
                $jobs | Stop-Job -ErrorAction SilentlyContinue
                $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        $skipped++
        Write-Host "[SKIP] Concurrent submit diagnostic" -ForegroundColor Yellow
    }
} finally {
    if (-not $KeepTestCarts) {
        foreach ($id in $testCustomers) {
            $null = Invoke-Api DELETE (CartPath $id)
        }
    }
    Write-Host ""
    Write-Host "RESULT: $passed passed, $failed failed, $skipped skipped | run $run"
    Write-Host "Confirmed sales remain in MongoDB (test offer IDs start with $prefix)."
}
if ($failed -gt 0) { exit 1 }
exit 0
