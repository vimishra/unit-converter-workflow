import Foundation

// Custom units
extension UnitPressure {
  static let standardAtmospheres = UnitPressure(
    symbol: "atm",
    converter: UnitConverterLinear(coefficient: 101325)
  )
}

extension UnitLength {
  static let thousandthsOfAnInch = UnitLength(
    symbol: "thou",
    converter: UnitConverterLinear(coefficient: 0.000025399999999999999)
  )
}

// Helpers
extension String {
  func removingPrefixes(_ prefixes: [String]) -> String {
    for prefix in prefixes {
      if self.hasPrefix(prefix) { return String(self.dropFirst(prefix.count)) }
    }

    return self
  }
}

struct ScriptFilterItem: Codable {
  let uid: String
  let title: String
  let subtitle: String
  let autocomplete: String?
  let arg: String?
  let valid: Bool
}

// MeasureInfo
// Refer to its extensions below as well
struct MeasureInfo {
  let names: [String]
  let symbol: String
  let unit: Dimension
  let caseInsensitive: Bool

  init(names: [String], unit: Dimension, imperial: Bool = false, caseInsensitive: Bool = false) {
    self.names = names
    self.symbol = imperial ? "imperial \(unit.symbol)" : unit.symbol
    self.unit = unit
    self.caseInsensitive = caseInsensitive
  }
}

// MeasureInfo Matching
extension MeasureInfo {
  enum MatchType {
    case none, partial, exact
  }

  // Unit names are stored lowercased, but currency names come from the system
  // already cased, where capitalizing would mangle acronyms such as “US Dollar”
  var displayName: String {
    guard let name = self.names.first else { return self.symbol }
    return self.unit is UnitCurrency ? name : name.capitalized
  }

  func matches(_ searchTerm: String) -> MatchType {
    // Currency codes match regardless of case, unlike unit symbols where case is
    // meaningful (Ml for megaliters versus ml for milliliters)
    let searchTerm = self.caseInsensitive ? searchTerm.lowercased() : searchTerm
    let symbol = self.caseInsensitive ? self.symbol.lowercased() : self.symbol
    let names = self.caseInsensitive ? self.names.map { $0.lowercased() } : self.names

    // Check for symbol matches
    let matchSymbol = symbol.hasPrefix(searchTerm)

    if matchSymbol {
      if symbol == searchTerm { return .exact }
      return .partial
    }

    // Check for name matches
    let matchNames = names.filter { $0.hasPrefix(searchTerm) }

    if matchNames.count > 0 {
      if (matchNames.contains { $0 == searchTerm }) { return .exact }
      return .partial
    }

    // Nothing matches
    return .none
  }
}

// MeasureInfo Formatting
extension MeasureInfo {
  private static let decimalPlaces: Int = Int(ProcessInfo.processInfo.environment["decimal_places"] ?? "3") ?? 3
  private static let splitFeet: Bool = (ProcessInfo.processInfo.environment["split_feet"] ?? "0") == "1"
  private static let groupThousands: Bool = (ProcessInfo.processInfo.environment["thousands_group"] ?? "0") == "1"
  private static let scientificNotation: Bool = (ProcessInfo.processInfo.environment["scientific_notation"] ?? "0") == "1"

  private static func numberToString(_ number: Double, forceSimple: Bool) -> String {
    let formatter: NumberFormatter = NumberFormatter()

    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = MeasureInfo.decimalPlaces
    formatter.numberStyle = scientificNotation && !forceSimple ? .scientific : .decimal
    formatter.hasThousandSeparators = MeasureInfo.groupThousands && !forceSimple

    return formatter.string(from: number as NSNumber) ?? String(number)
  }

  // Money reads better with cents than with the rounding used for everything else
  private static func currencyToString(_ number: Double, forceSimple: Bool) -> String {
    guard !(scientificNotation && !forceSimple) else { return MeasureInfo.numberToString(number, forceSimple: forceSimple) }

    // Two decimals for everyday amounts, more for those which would round to nothing
    let magnitude = abs(number)
    let fractionDigits = MeasureInfo.decimalPlaces < 2 ? MeasureInfo.decimalPlaces : (magnitude > 0 && magnitude < 0.01 ? 6 : 2)

    let formatter: NumberFormatter = NumberFormatter()

    formatter.minimumFractionDigits = forceSimple ? 0 : fractionDigits
    formatter.maximumFractionDigits = fractionDigits
    formatter.numberStyle = .decimal
    formatter.hasThousandSeparators = MeasureInfo.groupThousands && !forceSimple

    return formatter.string(from: number as NSNumber) ?? String(number)
  }

  func formatted(value: Double, forceSimple allowedNotation: Bool = false) -> String {
    // Currencies have their own rounding rules
    if self.unit is UnitCurrency { return "\(MeasureInfo.currencyToString(value, forceSimple: allowedNotation)) \(self.symbol)" }

    // When NOT dealing with feet OR NOT splitting, output as normal
    guard self.unit == UnitLength.feet && MeasureInfo.splitFeet else { return "\(MeasureInfo.numberToString(value, forceSimple: allowedNotation)) \(self.symbol)" }

    // Dealing with feet AND splitting
    let feet = value.rounded(.towardZero)
    let feetRemainder = value.truncatingRemainder(dividingBy: 1)
    let inches = Measurement(value: feetRemainder, unit: UnitLength.feet).converted(to: UnitLength.inches).value

    // Avoid a situation like "2 feet 12 inches" by formatting inches early
    // If the result is "12", discard it and bump feet
    let inchesFormatted = MeasureInfo.numberToString(inches, forceSimple: allowedNotation)
    if inchesFormatted == "12" { return "\(MeasureInfo.numberToString(feet + 1, forceSimple: allowedNotation))′" }

    // If no inches then return feet, and vice-versa
    if inches == 0 { return "\(MeasureInfo.numberToString(feet, forceSimple: allowedNotation))′" }
    if feet == 0 { return "\(inchesFormatted)″" }

    // Return feet and inches
    return "\(MeasureInfo.numberToString(feet, forceSimple: allowedNotation))′ \(inchesFormatted)″"
  }
}

func matchMeasures(from searchString: String, in measures: [MeasureInfo]) -> [(measure: MeasureInfo, matchedChars: Int)] {
  let splitSearch = searchString.split(separator: " ")

  // Keep removing the last word on a loop until any match is found
  for wordIndex in stride(from: splitSearch.count - 1, through: 0, by: -1) {
    let currentString = splitSearch[0...wordIndex].joined(separator: " ")

    // Filter for matches and return them with the information on if they are partial or exact
    let matchingMeasures = measures.compactMap { measure -> (measure: MeasureInfo, matching: MeasureInfo.MatchType)? in
      let matchType = measure.matches(currentString)
      if matchType == .none { return nil }
      return (measure: measure, matching: matchType)
    }

    // Number of characters matched
    let matchedChars = currentString.count

    // If something matches exactly, output it on its own
    if let exactMatch = matchingMeasures.first(where: { $0.matching == .exact }) {
      return [(measure: exactMatch.measure, matchedChars: matchedChars)]
    }

    // If there are ambiguous matches, output them all
    // Sorted by smallest unit, which is more likely to be a more common one
    if matchingMeasures.count > 0 {
      return matchingMeasures
        .sorted { $0.measure.symbol.count < $1.measure.symbol.count }
        .map { (measure: $0.measure, matchedChars: matchedChars) }
    }
  }

  // Nothing found
  return []
}

func showItems(_ sfItems: [ScriptFilterItem]) {
  let jsonData = try! JSONEncoder().encode(["items": sfItems])
  print(String(data: jsonData, encoding: .utf8)!)
}

// Currencies
// Modelled as a Dimension so they go through the same matching, filtering, and
// conversion code paths as the physical units. Rates are always fetched against
// the US Dollar, which is also this dimension’s base unit.
final class UnitCurrency: Dimension, @unchecked Sendable {
  static let usDollars = UnitCurrency(symbol: "USD", converter: UnitConverterLinear(coefficient: 1))

  override class func baseUnit() -> UnitCurrency { usDollars }
}

struct ExchangeRates: Codable {
  static let baseCode = "USD"
  static let hourInSeconds: TimeInterval = 60 * 60
  static let dayInSeconds: TimeInterval = 24 * hourInSeconds

  let rates: [String: Double]  // Amount of each currency per one US Dollar
  let updated: Date  // When the provider published these rates
  let nextUpdate: Date  // When the provider expects to publish new ones
  let provider: String

  var isStale: Bool { Date() >= self.nextUpdate }
}

// Sources of exchange rates
// Both are free, need no API key, and publish once a day, which is plenty for
// everyday conversions. The second is only consulted if the first is unreachable.
struct RateProvider {
  typealias Parsed = (rates: [String: Double], updated: Date, nextUpdate: Date)

  let name: String
  let url: URL
  let parse: ([String: Any]) -> Parsed?

  func fetch(timeout: TimeInterval) -> ExchangeRates? {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    configuration.waitsForConnectivity = false

    var payload: Data?
    let semaphore = DispatchSemaphore(value: 0)

    let task = URLSession(configuration: configuration).dataTask(with: self.url) { data, response, _ in
      if (response as? HTTPURLResponse)?.statusCode == 200 { payload = data }
      semaphore.signal()
    }

    task.resume()

    guard semaphore.wait(timeout: .now() + timeout + 1) == .success else {
      task.cancel()
      return nil
    }

    guard
      let payload = payload,
      let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
      let parsed = self.parse(json),
      parsed.rates[ExchangeRates.baseCode] != nil  // Sanity check the base is present
    else { return nil }

    return ExchangeRates(
      rates: parsed.rates,
      updated: parsed.updated,
      nextUpdate: parsed.nextUpdate,
      provider: self.name
    )
  }
}

let rateProviders: [RateProvider] = [
  RateProvider(
    name: "exchangerate-api.com",
    url: URL(string: "https://open.er-api.com/v6/latest/\(ExchangeRates.baseCode)")!,
    parse: { json in
      guard
        json["result"] as? String == "success",
        json["base_code"] as? String == ExchangeRates.baseCode,
        let rawRates = json["rates"] as? [String: Any],
        let updated = json["time_last_update_unix"] as? Double
      else { return nil }

      let updatedDate = Date(timeIntervalSince1970: updated)
      let nextUpdate = (json["time_next_update_unix"] as? Double).map { Date(timeIntervalSince1970: $0) }

      return (
        rates: rawRates.compactMapValues { ($0 as? NSNumber)?.doubleValue },
        updated: updatedDate,
        nextUpdate: nextUpdate ?? updatedDate.addingTimeInterval(ExchangeRates.dayInSeconds)
      )
    }
  ),

  RateProvider(
    name: "currency-api",
    url: URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(ExchangeRates.baseCode.lowercased()).json")!,
    parse: { json in
      let dayFormatter = DateFormatter()
      dayFormatter.locale = Locale(identifier: "en_US_POSIX")
      dayFormatter.timeZone = TimeZone(identifier: "UTC")
      dayFormatter.dateFormat = "yyyy-MM-dd"

      guard
        let day = json["date"] as? String,
        let updated = dayFormatter.date(from: day),
        let rawRates = json[ExchangeRates.baseCode.lowercased()] as? [String: Any]
      else { return nil }

      let rates = rawRates.compactMap { code, value -> (String, Double)? in
        guard let number = (value as? NSNumber)?.doubleValue else { return nil }
        return (code.uppercased(), number)
      }

      return (
        rates: Dictionary(rates, uniquingKeysWith: { first, _ in first }),
        updated: updated,
        nextUpdate: updated.addingTimeInterval(ExchangeRates.dayInSeconds)
      )
    }
  )
]

// Rate caching
// Rates are kept in the Workflow’s cache directory and reused until the provider
// publishes new ones. A stale cache is still served right away, with the refresh
// happening in a detached process so typing never waits on the network.
enum ExchangeRateStore {
  static let refreshArgument = "--refresh-rates"

  private static let syncTimeout: TimeInterval = 5
  private static let backgroundTimeout: TimeInterval = 20
  private static let retryInterval: TimeInterval = 300  // Do not hammer a provider which is down

  private static let cacheDirectory: URL = {
    let environment = ProcessInfo.processInfo.environment

    if let alfredCache = environment["alfred_workflow_cache"], !alfredCache.isEmpty {
      return URL(fileURLWithPath: alfredCache, isDirectory: true)
    }

    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(environment["alfred_workflow_bundleid"] ?? "com.alfredapp.vitor.unitconverter", isDirectory: true)
  }()

  private static let ratesFile = cacheDirectory.appendingPathComponent("exchange-rates.json")
  private static let attemptFile = cacheDirectory.appendingPathComponent("exchange-rates-attempt")

  // Nil only when there are no rates at all, i.e. the first run happened offline
  static func rates() -> ExchangeRates? {
    guard let cached = read() else {
      guard !attemptedRecently() else { return nil }

      markAttempt()
      guard let fetched = fetch(timeout: syncTimeout) else { return nil }

      write(fetched)
      return fetched
    }

    if cached.isStale && !attemptedRecently() {
      markAttempt()
      refreshInBackground()
    }

    return cached
  }

  static func refresh() {
    guard let fetched = fetch(timeout: backgroundTimeout) else { return }
    write(fetched)
  }

  private static func fetch(timeout: TimeInterval) -> ExchangeRates? {
    for provider in rateProviders {
      if let fetched = provider.fetch(timeout: timeout) { return fetched }
    }

    return nil
  }

  private static func read() -> ExchangeRates? {
    guard let data = try? Data(contentsOf: ratesFile) else { return nil }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    return try? decoder.decode(ExchangeRates.self, from: data)
  }

  private static func write(_ fetched: ExchangeRates) {
    // Never trust a provider to hand us a next update time in the past
    let stored = ExchangeRates(
      rates: fetched.rates,
      updated: fetched.updated,
      nextUpdate: max(fetched.nextUpdate, Date().addingTimeInterval(ExchangeRates.hourInSeconds)),
      provider: fetched.provider
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970

    guard let data = try? encoder.encode(stored) else { return }

    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try? data.write(to: ratesFile, options: .atomic)
  }

  private static func markAttempt() {
    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    if FileManager.default.fileExists(atPath: attemptFile.path) {
      try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: attemptFile.path)
    } else {
      FileManager.default.createFile(atPath: attemptFile.path, contents: nil)
    }
  }

  private static func attemptedRecently() -> Bool {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: attemptFile.path),
      let modified = attributes[.modificationDate] as? Date
    else { return false }

    return Date().timeIntervalSince(modified) < retryInterval
  }

  private static func refreshInBackground() {
    guard let executable = Bundle.main.executableURL else { return }

    let process = Process()
    process.executableURL = executable
    process.arguments = [refreshArgument]

    // Alfred reads this process’ output, so the child must not inherit the pipe
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    try? process.run()
  }
}

// Aliases in addition to each currency’s localized name. Deliberately conservative:
// “pounds” is not an alias for GBP, as it already means the unit of mass.
let currencyAliases: [String: [String]] = [
  "USD": ["dollars", "$"],
  "EUR": ["euros", "€"],
  "GBP": ["£"],
  "INR": ["rupees", "rs", "₹"],
  "JPY": ["yen", "¥"],
  "CNY": ["yuan", "renminbi"],
  "KRW": ["won", "₩"],
  "RUB": ["rubles", "₽"]
]

// Names come from the system, so they follow the user’s language
func currencyName(for code: String) -> String? {
  guard code.count == 3 else { return nil }
  return Locale.current.localizedString(forCurrencyCode: code.uppercased())
}

// Only codes the system recognises become measures, which also discards the
// cryptocurrencies some providers mix into their rates
func currencyMeasures(from exchangeRates: ExchangeRates?) -> [MeasureInfo] {
  guard let exchangeRates = exchangeRates else { return [] }

  return exchangeRates.rates.compactMap { code, rate -> MeasureInfo? in
    guard rate > 0, let name = currencyName(for: code) else { return nil }

    let unit =
      code == ExchangeRates.baseCode
      ? UnitCurrency.usDollars
      : UnitCurrency(symbol: code, converter: UnitConverterLinear(coefficient: 1 / rate))

    return MeasureInfo(names: [name] + (currencyAliases[code] ?? []), unit: unit, caseInsensitive: true)
  }.sorted { $0.symbol < $1.symbol }
}

func looksLikeCurrency(_ searchString: String) -> Bool {
  guard let firstWord = searchString.split(separator: " ").first else { return false }
  return currencyName(for: String(firstWord)) != nil
}

let unitMeasures: [MeasureInfo] = [
  // Not Included:
  // * UnitAcceleration, as it only has two methods and the symbols of gravity and grams clash:
  //   https://developer.apple.com/documentation/foundation/unitacceleration
  // * UnitConcentrationMass.millimolesPerLiter(withGramsPerMole:) as it requires an argument:
  //   https://developer.apple.com/documentation/foundation/unitconcentrationmass/1855799-millimolesperliter
  // * UnitDispersion, as it only has one method:
  //   https://developer.apple.com/documentation/foundation/unitdispersion
  // * UnitIlluminance, as it only has one method:
  //   https://developer.apple.com/documentation/foundation/unitilluminance

  // Angle
  MeasureInfo(names: ["degrees"], unit: UnitAngle.degrees),
  MeasureInfo(names: ["arc minutes"], unit: UnitAngle.arcMinutes),
  MeasureInfo(names: ["arc seconds"], unit: UnitAngle.arcSeconds),
  MeasureInfo(names: ["radians"], unit: UnitAngle.radians),
  MeasureInfo(names: ["gradians"], unit: UnitAngle.gradians),
  MeasureInfo(names: ["revolutions"], unit: UnitAngle.revolutions),

  // Area
  MeasureInfo(names: ["square megameters"], unit: UnitArea.squareMegameters),
  MeasureInfo(names: ["square kilometers"], unit: UnitArea.squareKilometers),
  MeasureInfo(names: ["square meters"], unit: UnitArea.squareMeters),
  MeasureInfo(names: ["square centimeters"], unit: UnitArea.squareCentimeters),
  MeasureInfo(names: ["square millimiters"], unit: UnitArea.squareMillimeters),
  MeasureInfo(names: ["square micrometers"], unit: UnitArea.squareMicrometers),
  MeasureInfo(names: ["square nanometers"], unit: UnitArea.squareNanometers),
  MeasureInfo(names: ["square inches"], unit: UnitArea.squareInches),
  MeasureInfo(names: ["square feet"], unit: UnitArea.squareFeet),
  MeasureInfo(names: ["square yards"], unit: UnitArea.squareYards),
  MeasureInfo(names: ["square miles"], unit: UnitArea.squareMiles),
  MeasureInfo(names: ["acres"], unit: UnitArea.acres),
  MeasureInfo(names: ["ares"], unit: UnitArea.ares),
  MeasureInfo(names: ["hectares"], unit: UnitArea.hectares),

  // Concentration of Mass
  MeasureInfo(names: ["grams per liter"], unit: UnitConcentrationMass.gramsPerLiter),
  MeasureInfo(names: ["milligrams per deciliter"], unit: UnitConcentrationMass.milligramsPerDeciliter),

  // Duration
  MeasureInfo(names: ["picoseconds"], unit: UnitDuration.seconds),
  MeasureInfo(names: ["nanoseconds"], unit: UnitDuration.nanoseconds),
  MeasureInfo(names: ["microseconds"], unit: UnitDuration.microseconds),
  MeasureInfo(names: ["milliseconds"], unit: UnitDuration.milliseconds),
  MeasureInfo(names: ["seconds"], unit: UnitDuration.seconds),
  MeasureInfo(names: ["minutes"], unit: UnitDuration.minutes),
  MeasureInfo(names: ["hours"], unit: UnitDuration.hours),

  // Electric Charge
  MeasureInfo(names: ["coulombs"], unit: UnitElectricCharge.coulombs),
  MeasureInfo(names: ["megaampere hours"], unit: UnitElectricCharge.megaampereHours),
  MeasureInfo(names: ["kiloampere hours"], unit: UnitElectricCharge.kiloampereHours),
  MeasureInfo(names: ["ampere hours"], unit: UnitElectricCharge.ampereHours),
  MeasureInfo(names: ["milliampere hours"], unit: UnitElectricCharge.milliampereHours),
  MeasureInfo(names: ["microampere hours"], unit: UnitElectricCharge.microampereHours),

  // Electric Current
  MeasureInfo(names: ["megaamperes"], unit: UnitElectricCurrent.megaamperes),
  MeasureInfo(names: ["kiloamperes"], unit: UnitElectricCurrent.kiloamperes),
  MeasureInfo(names: ["amperes"], unit: UnitElectricCurrent.amperes),
  MeasureInfo(names: ["milliamperes"], unit: UnitElectricCurrent.milliamperes),
  MeasureInfo(names: ["microamperes"], unit: UnitElectricCurrent.microamperes),

  // Electric Potential Difference
  MeasureInfo(names: ["megavolts"], unit: UnitElectricPotentialDifference.megavolts),
  MeasureInfo(names: ["kilovolts"], unit: UnitElectricPotentialDifference.kilovolts),
  MeasureInfo(names: ["volts"], unit: UnitElectricPotentialDifference.volts),
  MeasureInfo(names: ["millivolts"], unit: UnitElectricPotentialDifference.millivolts),
  MeasureInfo(names: ["microvolts"], unit: UnitElectricPotentialDifference.microvolts),

  // Electric Resistance
  MeasureInfo(names: ["megaohms"], unit: UnitElectricResistance.megaohms),
  MeasureInfo(names: ["kiloohms"], unit: UnitElectricResistance.kiloohms),
  MeasureInfo(names: ["ohms"], unit: UnitElectricResistance.ohms),
  MeasureInfo(names: ["milliohms"], unit: UnitElectricResistance.milliohms),
  MeasureInfo(names: ["microohms"], unit: UnitElectricResistance.microohms),

  // Energy
  MeasureInfo(names: ["kilojoules"], unit: UnitEnergy.kilojoules),
  MeasureInfo(names: ["joules"], unit: UnitEnergy.joules),
  MeasureInfo(names: ["kilocalories"], unit: UnitEnergy.kilocalories),
  MeasureInfo(names: ["calories"], unit: UnitEnergy.calories),
  MeasureInfo(names: ["kilowatt hours"], unit: UnitEnergy.kilowattHours),

  // Frequency
  MeasureInfo(names: ["terahertz"], unit: UnitFrequency.terahertz),
  MeasureInfo(names: ["gigahertz"], unit: UnitFrequency.gigahertz),
  MeasureInfo(names: ["megahertz"], unit: UnitFrequency.megahertz),
  MeasureInfo(names: ["kilohertz"], unit: UnitFrequency.kilohertz),
  MeasureInfo(names: ["hertz"], unit: UnitFrequency.hertz),
  MeasureInfo(names: ["millihertz"], unit: UnitFrequency.millihertz),
  MeasureInfo(names: ["microhertz"], unit: UnitFrequency.microhertz),
  MeasureInfo(names: ["nanohertz"], unit: UnitFrequency.nanohertz),

  // Fuel Efficiency
  MeasureInfo(names: ["liters per 100 kilometers"], unit: UnitFuelEfficiency.litersPer100Kilometers),
  MeasureInfo(names: ["miles per gallon"], unit: UnitFuelEfficiency.milesPerGallon),
  MeasureInfo(names: ["miles per imperial gallon"], unit: UnitFuelEfficiency.milesPerImperialGallon, imperial: true),

  // Information Storage
  MeasureInfo(names: ["nibbles"], unit: UnitInformationStorage.nibbles),
  MeasureInfo(names: ["bits"], unit: UnitInformationStorage.bits),
  MeasureInfo(names: ["bytes"], unit: UnitInformationStorage.bytes),

  MeasureInfo(names: ["kilobits"], unit: UnitInformationStorage.kilobits),
  MeasureInfo(names: ["megabits"], unit: UnitInformationStorage.megabits),
  MeasureInfo(names: ["gigabits"], unit: UnitInformationStorage.gigabits),
  MeasureInfo(names: ["terabits"], unit: UnitInformationStorage.terabits),
  MeasureInfo(names: ["petabits"], unit: UnitInformationStorage.petabits),
  MeasureInfo(names: ["exabits"], unit: UnitInformationStorage.exabits),
  MeasureInfo(names: ["zettabits"], unit: UnitInformationStorage.zettabits),
  MeasureInfo(names: ["yottabits"], unit: UnitInformationStorage.yottabits),

  MeasureInfo(names: ["kibibits"], unit: UnitInformationStorage.kibibits),
  MeasureInfo(names: ["mebibits"], unit: UnitInformationStorage.mebibits),
  MeasureInfo(names: ["gibibits"], unit: UnitInformationStorage.gibibits),
  MeasureInfo(names: ["tebibits"], unit: UnitInformationStorage.tebibits),
  MeasureInfo(names: ["pebibits"], unit: UnitInformationStorage.pebibits),
  MeasureInfo(names: ["exbibits"], unit: UnitInformationStorage.exbibits),
  MeasureInfo(names: ["zebibits"], unit: UnitInformationStorage.zebibits),
  MeasureInfo(names: ["yobibits"], unit: UnitInformationStorage.yobibits),

  MeasureInfo(names: ["kilobytes"], unit: UnitInformationStorage.kilobytes),
  MeasureInfo(names: ["megabytes"], unit: UnitInformationStorage.megabytes),
  MeasureInfo(names: ["gigabytes"], unit: UnitInformationStorage.gigabytes),
  MeasureInfo(names: ["terabytes"], unit: UnitInformationStorage.terabytes),
  MeasureInfo(names: ["petabytes"], unit: UnitInformationStorage.petabytes),
  MeasureInfo(names: ["exabytes"], unit: UnitInformationStorage.exabytes),
  MeasureInfo(names: ["zettabytes"], unit: UnitInformationStorage.zettabytes),
  MeasureInfo(names: ["yottabytes"], unit: UnitInformationStorage.yottabytes),

  MeasureInfo(names: ["kibibytes"], unit: UnitInformationStorage.kibibytes),
  MeasureInfo(names: ["mebibytes"], unit: UnitInformationStorage.mebibytes),
  MeasureInfo(names: ["gibibytes"], unit: UnitInformationStorage.gibibytes),
  MeasureInfo(names: ["tebibytes"], unit: UnitInformationStorage.tebibytes),
  MeasureInfo(names: ["pebibytes"], unit: UnitInformationStorage.pebibytes),
  MeasureInfo(names: ["exbibytes"], unit: UnitInformationStorage.exbibytes),
  MeasureInfo(names: ["zebibytes"], unit: UnitInformationStorage.zebibytes),
  MeasureInfo(names: ["yobibytes"], unit: UnitInformationStorage.yobibytes),

  // Length
  MeasureInfo(names: ["megameters"], unit: UnitLength.megameters),
  MeasureInfo(names: ["kilometers"], unit: UnitLength.kilometers),
  MeasureInfo(names: ["hectometers"], unit: UnitLength.hectometers),
  MeasureInfo(names: ["decameters"], unit: UnitLength.decameters),
  MeasureInfo(names: ["meters"], unit: UnitLength.meters),
  MeasureInfo(names: ["decimeters"], unit: UnitLength.decimeters),
  MeasureInfo(names: ["centimeters"], unit: UnitLength.centimeters),
  MeasureInfo(names: ["millimeters"], unit: UnitLength.millimeters),
  MeasureInfo(names: ["micrometers"], unit: UnitLength.micrometers),
  MeasureInfo(names: ["nanometers"], unit: UnitLength.nanometers),
  MeasureInfo(names: ["picometers"], unit: UnitLength.picometers),
  MeasureInfo(names: ["inches", "''", "″"], unit: UnitLength.inches),
  MeasureInfo(names: ["feet", "foot", "'", "′"], unit: UnitLength.feet),
  MeasureInfo(names: ["yards"], unit: UnitLength.yards),
  MeasureInfo(names: ["miles"], unit: UnitLength.miles),
  MeasureInfo(names: ["scandinavian miles"], unit: UnitLength.scandinavianMiles),
  MeasureInfo(names: ["light years"], unit: UnitLength.lightyears),
  MeasureInfo(names: ["nautical miles"], unit: UnitLength.nauticalMiles),
  MeasureInfo(names: ["fathoms"], unit: UnitLength.fathoms),
  MeasureInfo(names: ["furlongs"], unit: UnitLength.furlongs),
  MeasureInfo(names: ["astronomical units"], unit: UnitLength.astronomicalUnits),
  MeasureInfo(names: ["parsecs"], unit: UnitLength.parsecs),
  MeasureInfo(names: ["thousandths of an inch"], unit: UnitLength.thousandthsOfAnInch),

  // Mass
  MeasureInfo(names: ["kilograms"], unit: UnitMass.kilograms),
  MeasureInfo(names: ["grams"], unit: UnitMass.grams),
  MeasureInfo(names: ["decigrams"], unit: UnitMass.decigrams),
  MeasureInfo(names: ["centigrams"], unit: UnitMass.centigrams),
  MeasureInfo(names: ["milligrams"], unit: UnitMass.milligrams),
  MeasureInfo(names: ["micrograms"], unit: UnitMass.micrograms),
  MeasureInfo(names: ["nanograms"], unit: UnitMass.nanograms),
  MeasureInfo(names: ["picograms"], unit: UnitMass.picograms),
  MeasureInfo(names: ["ounces"], unit: UnitMass.ounces),
  MeasureInfo(names: ["pounds", "lbs"], unit: UnitMass.pounds),
  MeasureInfo(names: ["stones"], unit: UnitMass.stones),
  MeasureInfo(names: ["metric tons"], unit: UnitMass.metricTons),
  MeasureInfo(names: ["short tons"], unit: UnitMass.shortTons),
  MeasureInfo(names: ["carats"], unit: UnitMass.carats),
  MeasureInfo(names: ["ounces troy"], unit: UnitMass.ouncesTroy),
  MeasureInfo(names: ["slugs"], unit: UnitMass.slugs),

  // Power
  MeasureInfo(names: ["terawatts"], unit: UnitPower.terawatts),
  MeasureInfo(names: ["gigawatts"], unit: UnitPower.gigawatts),
  MeasureInfo(names: ["megawatts"], unit: UnitPower.megawatts),
  MeasureInfo(names: ["kilowatts"], unit: UnitPower.kilowatts),
  MeasureInfo(names: ["watts"], unit: UnitPower.watts),
  MeasureInfo(names: ["milliwatts"], unit: UnitPower.milliwatts),
  MeasureInfo(names: ["microwatts"], unit: UnitPower.microwatts),
  MeasureInfo(names: ["nanowatts"], unit: UnitPower.nanowatts),
  MeasureInfo(names: ["picowatts"], unit: UnitPower.picowatts),
  MeasureInfo(names: ["femtowatts"], unit: UnitPower.femtowatts),
  MeasureInfo(names: ["horsepower"], unit: UnitPower.horsepower),

  // Pressure
  MeasureInfo(names: ["pascals"], unit: UnitPressure.newtonsPerMetersSquared),
  MeasureInfo(names: ["gigapascals"], unit: UnitPressure.gigapascals),
  MeasureInfo(names: ["megapascals"], unit: UnitPressure.megapascals),
  MeasureInfo(names: ["kilopascals"], unit: UnitPressure.kilopascals),
  MeasureInfo(names: ["hectopascals"], unit: UnitPressure.hectopascals),
  MeasureInfo(names: ["inches of mercury"], unit: UnitPressure.inchesOfMercury),
  MeasureInfo(names: ["bars"], unit: UnitPressure.bars),
  MeasureInfo(names: ["millibars"], unit: UnitPressure.millibars),
  MeasureInfo(names: ["millimiters of mercury"], unit: UnitPressure.millimetersOfMercury),
  MeasureInfo(names: ["pound per square inch"], unit: UnitPressure.poundsForcePerSquareInch),
  MeasureInfo(names: ["standard atmospheres", "atmospheres"], unit: UnitPressure.standardAtmospheres),

  // Speed
  MeasureInfo(names: ["meters per second"], unit: UnitSpeed.metersPerSecond),
  MeasureInfo(names: ["kilometers per hour"], unit: UnitSpeed.kilometersPerHour),
  MeasureInfo(names: ["miles per hour"], unit: UnitSpeed.milesPerHour),
  MeasureInfo(names: ["knots"], unit: UnitSpeed.knots),

  // Temperature
  MeasureInfo(names: ["kelvin", "k"], unit: UnitTemperature.kelvin),
  MeasureInfo(names: ["degrees celsius", "celsius", "centigrade", "c"], unit: UnitTemperature.celsius),
  MeasureInfo(names: ["degrees fahrenheit", "fahrenheit", "f"], unit: UnitTemperature.fahrenheit),

  // Volume
  MeasureInfo(names: ["megaliters", "Ml"], unit: UnitVolume.megaliters),
  MeasureInfo(names: ["kiloliters", "kl"], unit: UnitVolume.kiloliters),
  MeasureInfo(names: ["liters", "l"], unit: UnitVolume.liters),
  MeasureInfo(names: ["deciliters", "dl"], unit: UnitVolume.deciliters),
  MeasureInfo(names: ["centiliters", "cl"], unit: UnitVolume.centiliters),
  MeasureInfo(names: ["milliliters", "ml"], unit: UnitVolume.milliliters),
  MeasureInfo(names: ["cubic kilometers"], unit: UnitVolume.cubicKilometers),
  MeasureInfo(names: ["cubic meters"], unit: UnitVolume.cubicMeters),
  MeasureInfo(names: ["cubic decimeters"], unit: UnitVolume.cubicDecimeters),
  MeasureInfo(names: ["cubic centimeters"], unit: UnitVolume.cubicCentimeters),
  MeasureInfo(names: ["cubic millimeters"], unit: UnitVolume.cubicMillimeters),
  MeasureInfo(names: ["cubic inches"], unit: UnitVolume.cubicInches),
  MeasureInfo(names: ["cubic feet"], unit: UnitVolume.cubicFeet),
  MeasureInfo(names: ["cubic yards"], unit: UnitVolume.cubicYards),
  MeasureInfo(names: ["cubic miles"], unit: UnitVolume.cubicMiles),
  MeasureInfo(names: ["acre feet"], unit: UnitVolume.acreFeet),
  MeasureInfo(names: ["bushels"], unit: UnitVolume.bushels),
  MeasureInfo(names: ["teaspoons"], unit: UnitVolume.teaspoons),
  MeasureInfo(names: ["tablespoons"], unit: UnitVolume.tablespoons),
  MeasureInfo(names: ["fluid ounces"], unit: UnitVolume.fluidOunces),
  MeasureInfo(names: ["cups"], unit: UnitVolume.cups),
  MeasureInfo(names: ["pints"], unit: UnitVolume.pints),
  MeasureInfo(names: ["quarts"], unit: UnitVolume.quarts),
  MeasureInfo(names: ["gallons"], unit: UnitVolume.gallons),
  MeasureInfo(names: ["imperial teaspoons"], unit: UnitVolume.imperialTeaspoons, imperial: true),
  MeasureInfo(names: ["imperial tablespoons"], unit: UnitVolume.imperialTablespoons, imperial: true),
  MeasureInfo(names: ["imperial fluid ounces"], unit: UnitVolume.imperialFluidOunces, imperial: true),
  MeasureInfo(names: ["imperial pints"], unit: UnitVolume.imperialPints, imperial: true),
  MeasureInfo(names: ["imperial quarts"], unit: UnitVolume.imperialQuarts, imperial: true),
  MeasureInfo(names: ["imperial gallons"], unit: UnitVolume.imperialGallons, imperial: true),
  MeasureInfo(names: ["metric cups"], unit: UnitVolume.metricCups)
]

// Refresh the exchange rates when spawned in the background by a previous run
if CommandLine.arguments.dropFirst().first == ExchangeRateStore.refreshArgument {
  ExchangeRateStore.refresh()
  exit(EXIT_SUCCESS)
}

// Currencies come after the physical units, so those win any symbol clash
let exchangeRates = ExchangeRateStore.rates()
let allMeasures: [MeasureInfo] = unitMeasures + currencyMeasures(from: exchangeRates)

// Parse input
let rawInput = CommandLine.arguments[1].trimmingCharacters(in: .whitespacesAndNewlines)

// Modify input to be expressed in feet if input is given in feet AND inches, otherwise send unmodified
let interpretedInput = {
  let feetInchRegex = #/^(?<feet>-?\d*(?:\.\d+)?)\s*(?:feet|foot|ft|'|′)\s*(?<inches>\d*(?:\.\d+)?)\s*(?:inches|in|''|″)?(?<rest>.*)/#

  guard
    let feetInchValues = try? feetInchRegex.wholeMatch(in: rawInput),
    let feet = Double(feetInchValues.feet),
    let inches = Double(feetInchValues.inches)
  else { return rawInput }

  let inchesInFeet = Measurement(value: inches, unit: UnitLength.inches).converted(to: UnitLength.feet).value
  return("\(feet + inchesInFeet) feet \(feetInchValues.rest)")
}()

// Parse number value
guard
  let rawNumber = interpretedInput.firstMatch(of: #/^(-?\d*(\.\d+)?)\D*/#)?.1,
  let startNumber = Double(rawNumber)
else {
  showItems([
    ScriptFilterItem(
      uid: "Invalid Input",
      title: "Input a Value and Unit",
      subtitle: "Example: 42 km",
      autocomplete: nil,
      arg: nil,
      valid: false
    )
  ])

  exit(EXIT_FAILURE)
}

// Parse input minus number for starting measures
let rawOperation = interpretedInput.dropFirst(rawNumber.count).trimmingCharacters(in: .whitespacesAndNewlines)
let startMeasures = matchMeasures(from: rawOperation, in: allMeasures)

// When no starting measures specified, show them all
guard rawOperation.count > 0 else {
  let sfItems: [ScriptFilterItem] = allMeasures.map { measure in
    return ScriptFilterItem(
      uid: measure.symbol,
      title: measure.formatted(value: startNumber),
      subtitle: measure.displayName,
      autocomplete: "\(measure.formatted(value: startNumber, forceSimple: true)) to ",
      arg: nil,
      valid: false
    )
  }

  showItems(sfItems)
  exit(EXIT_SUCCESS)
}

// When no starting measures match, ask for corrections
guard startMeasures.count > 0 else {
  // Currencies are missing entirely when the rates could not be fetched
  let missingRates = exchangeRates == nil && looksLikeCurrency(rawOperation)

  showItems([
    ScriptFilterItem(
      uid: missingRates ? "No Exchange Rates" : "Invalid Unit",
      title: missingRates ? "Could Not Fetch Exchange Rates" : "Input a Valid Unit",
      subtitle: missingRates ? "Check your internet connection and try again" : "Examples: km, kilometers",
      autocomplete: nil,
      arg: nil,
      valid: false
    )
  ])

  exit(EXIT_FAILURE)
}

// When multiple starting measures match, narrow with autocomplete
guard startMeasures.count < 2 else {
  let sfItems: [ScriptFilterItem] = startMeasures.map {
    let measure = $0.measure

    return ScriptFilterItem(
      uid: measure.symbol,
      title: measure.formatted(value: startNumber),
      subtitle: measure.displayName,
      autocomplete: "\(measure.formatted(value: startNumber, forceSimple: true)) to ",
      arg: nil,
      valid: false
    )
  }

  showItems(sfItems)
  exit(EXIT_SUCCESS)
}

// Parse input minus number for starting measures and starting unit
let exactStartMeasure = startMeasures[0].measure
let rawEnd = rawOperation
  .dropFirst(startMeasures[0].matchedChars)
  .trimmingCharacters(in: .whitespacesAndNewlines)
  .removingPrefixes(["to ", "as ", "in "])  // Remove connection words

// When only one starting measure matches, convert
let endMeasures = {
  // Measures which make sense to convert to
  let suitableEnds = allMeasures.filter {
    type(of: exactStartMeasure.unit).baseUnit() == type(of: $0.unit).baseUnit()  // Same unit type, so we can convert
      && exactStartMeasure.unit != $0.unit  // Remove starting measure
  }

  // Filter further to targets that match, if any
  let desiredEnds = matchMeasures(from: rawEnd, in: suitableEnds).map { $0.measure }

  // Return all targets if none match, otherwise return matching targets
  return desiredEnds.count == 0 ? suitableEnds : desiredEnds
}()

// Parse and convert
let startDimension = Measurement(value: startNumber, unit: exactStartMeasure.unit)
let formattedStartDimension = MeasureInfo(names: [], unit: startDimension.unit).formatted(value: startDimension.value, forceSimple: true)

// Currency conversions are only as fresh as the last fetched rates
let rateDate: String = {
  guard exactStartMeasure.unit is UnitCurrency, let updated = exchangeRates?.updated else { return "" }

  let formatter: DateFormatter = DateFormatter()
  formatter.dateStyle = .medium
  formatter.timeStyle = .none

  return " · Rate from \(formatter.string(from: updated))"
}()

let sfItems: [ScriptFilterItem] = endMeasures.map { measure in
  let converted = startDimension.converted(to: measure.unit)
  let formatted = measure.formatted(value: converted.value)

  return ScriptFilterItem(
    uid: "\(exactStartMeasure.symbol) to \(measure.unit.symbol)",
    title: formatted,
    subtitle: "\(exactStartMeasure.displayName) → \(measure.displayName)\(rateDate)",
    autocomplete: "\(formattedStartDimension) to \(measure.symbol)",
    arg: formatted,
    valid: true
  )
}

showItems(sfItems)
