# <img src='Workflow/icon.png' width='45' align='center' alt='icon'> Unit Converter Alfred Workflow

Convert between different units of measurement and currencies

[⤓ Install on the Alfred Gallery](https://alfred.app/workflows/alfredapp/unit-converter)

## Usage

Convert dimensions via the `conv` keyword. Type a number to see all available units with their full name and symbol.

![Typing a number](Workflow/images/about/number.png)

Type a unit to filter.

![Filtering for starting unit](Workflow/images/about/kilo.png)

Pressing <kbd>↩&#xFE0E;</kbd> on a partial match triggers the autocomplete. See all possible conversion targets when matching a unit exactly.

![Showing all possible conversions](Workflow/images/about/kbto.png)

Type further to filter for target units. Connector words (“to”, “as”, “in”) are optional to help with readability.

![Filtering for ending unit](Workflow/images/about/kbtom.png)

### Currencies

Currencies work the same way, matched by ISO code (in any case) or by name.

```
100 usd to inr
100 GBP to INR
100 INR to USD
```

Common symbols and nicknames are recognised too, such as `$`, `€`, `£`, `₹`, `rupees`, `euros`, and `yen`. Note that `pounds` remains the unit of mass — use `gbp` or `£` for the currency, and `cup` remains the unit of volume — use the uppercase `CUP` for the Cuban Peso.

Exchange rates come from [ExchangeRate-API](https://www.exchangerate-api.com/docs/free), falling back to [Currency API](https://github.com/fawazahmed0/exchange-api). Both are free and need no API key. Rates are published once a day and cached in the Workflow’s cache directory, so conversions are accurate to within a day. Fetching always happens in a detached background process and a cached rate is used immediately, so typing never waits on the network, whatever the state of the connection. A first-ever query may briefly report that rates are unavailable while that fetch completes. Conversions keep working offline with the last fetched rates, and the subtitle of every currency result says when those rates were published.

* <kbd>↩&#xFE0E;</kbd> Copy result to clipboard.
* <kbd>⌘</kbd><kbd>↩&#xFE0E;</kbd> Paste result to frontmost app.

Currency amounts are rounded to two decimal places, or to the configured precision when that is lower. Rounding precision and output notation can be set in the [Workflow’s Configuration](https://www.alfredapp.com/help/workflows/user-configuration/). Output format follows the Number Style in System Settings → General → Language & Region.

Configure the [Hotkey](https://www.alfredapp.com/help/workflows/triggers/hotkey/) or use the [Universal Action](https://www.alfredapp.com/help/features/universal-actions/) as shortcuts to convert results from Alfred’s [Calculator](https://www.alfredapp.com/help/features/calculator/), [Clipboard History](https://www.alfredapp.com/help/features/clipboard/), or selected text.

![Universal Action](Workflow/images/about/ua.png)

## Building

The Script Filter runs the universal binary at `Workflow/converter`, built from `Resources/converter.swift`:

```
./Resources/build.sh
```

The build ad-hoc signs the binary, as `lipo` leaves the merged result unsigned and Apple Silicon refuses to run unsigned code. It is not notarized, so a `.alfredworkflow` downloaded through a browser arrives quarantined and macOS may refuse to run the converter. Either build on the machine that will use it, or clear the flag after installing:

```
xattr -dr com.apple.quarantine ~/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows
```
