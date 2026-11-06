# Custom balance sources

Settings → **Balance sources** can monitor an HTTPS JSON query independently of the installed AI clients. It does not change model prices or infer which local calls belong to the remote account.

1. In the service's browser developer tools, find its **read-only balance or quota query**, then choose **Copy as cURL**.
2. Choose **Add source**, enter a name and currency/unit, paste the request, and select **Request and inspect fields**.
3. Select a numeric balance field and, optionally, its total. For services exposing used amounts, select **Used amount (total − used)** and map both fields. The preview shows the result before saving. A divisor converts the endpoint's raw units (use `1` without conversion).

The picker lists JSON Pointer paths and numeric values, including numeric strings and nested array elements. `/data/remaining` and `/data/total` are common examples. Field names containing `/` and `~` are escaped as `~1` and `~0`. Boolean values never become money. Missing fields and invalid conversions fail the reading instead of becoming a zero balance.

Saved sources appear as API balance cards in the hover panel: **Remaining**, **Total**, and a consumption bar when the total is positive. The balance's own observations can provide an exhaustion estimate after at least three hours of declining readings. Totals come directly from the selected response; they are not estimates based on local token prices. Choose the endpoint's actual currency/unit, such as `USD`, `CNY`, or `CREDITS`; credit amounts are not converted to money.

The collector queries enabled sources approximately every five minutes (plus its normal request spread). **Refresh now** uses the same account request spacing as other sources. Pausing or removing a source stops further scheduled requests. A failed read retains the last successful amount and its observation time, marked as a failed reading; it does not present an old value as newly confirmed. Changing the field mapping or units starts a separate balance trend. Login expiry requires importing a fresh request through **Edit**.

The HTTP request—including its URL, headers, cookies and body—is saved in this Mac's Keychain. Settings only contain source names, units, field paths and Keychain references. Reports and the ledger contain readings, never the saved request. Browser cookies are not scraped automatically or shared implicitly with the app.

The importer parses cURL **as data**; it never invokes a shell. It accepts one HTTPS URL, GET/POST, literal `-H` / `--header`, `-b` / `--cookie`, and one inline `--data` / `--data-raw` / `--data-binary` body. Browser formatting such as line continuations and `--compressed` is supported. Other options, file reads, shell expressions, insecure transport, and redirects are rejected. Requests use an ephemeral session, no shared cookie or credential store, a 20-second resource timeout and a 2 MB response limit. Only configure read-only queries, even when they use POST.
