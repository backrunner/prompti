import Foundation

struct TrainingLanguage: Codable, Hashable, Identifiable, Sendable {
    var code: String
    var name: String
    var localName: String

    var id: String { code }
}

struct TravelScene: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var symbol: String
    var context: String
    var isLocal: Bool = false
}

struct Destination: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var city: String
    var country: String
    var symbol: String
    var colorSeed: String
    var languages: [TrainingLanguage]
    var localScenes: [TravelScene]
    var facts: [String]
    var landmarkName: String = "City centre"
    var latitude: Double = 0
    var longitude: Double = 0
    var isCustom: Bool = false

    var shortCode: String {
        String(city.prefix(3)).uppercased()
    }
}

struct DestinationCatalog: Sendable {
    let commonScenes: [TravelScene] = [
        .init(id: "dining", title: "Dining", symbol: "fork.knife", context: "ordering, dietary needs, paying"),
        .init(id: "shopping", title: "Shopping", symbol: "bag.fill", context: "sizes, prices, payment"),
        .init(id: "transit", title: "Transit", symbol: "tram.fill", context: "tickets, platforms, transfers"),
        .init(id: "directions", title: "Directions", symbol: "map.fill", context: "asking for and following directions"),
        .init(id: "attraction", title: "Attractions", symbol: "ticket.fill", context: "entry tickets, queues, opening information"),
        .init(id: "hotel", title: "Hotel", symbol: "bed.double.fill", context: "check-in, requests, checkout"),
        .init(id: "taxi", title: "Taxi", symbol: "car.fill", context: "destinations, pickup points, payment"),
        .init(id: "emergency", title: "Help", symbol: "cross.case.fill", context: "lost items and getting urgent help")
    ]

    let destinations: [Destination]

    init() {
        let english = TrainingLanguage(code: "en", name: "English", localName: "English")
        let chinese = TrainingLanguage(code: "zh", name: "Chinese", localName: "简体中文")
        let japanese = TrainingLanguage(code: "ja", name: "Japanese", localName: "日本語")
        let korean = TrainingLanguage(code: "ko", name: "Korean", localName: "한국어")
        let russian = TrainingLanguage(code: "ru", name: "Russian", localName: "Русский")
        let german = TrainingLanguage(code: "de", name: "German", localName: "Deutsch")
        let spanish = TrainingLanguage(code: "es", name: "Spanish", localName: "Español")

        destinations = [
            Destination(
                id: "tokyo", city: "Tokyo", country: "Japan", symbol: "building.2.fill", colorSeed: "mint",
                languages: [japanese, english],
                localScenes: [
                    .init(id: "tokyo-ramen", title: "Ramen shop", symbol: "takeoutbag.and.cup.and.straw.fill", context: "ticket-machine ramen ordering", isLocal: true),
                    .init(id: "tokyo-ic", title: "IC card", symbol: "creditcard.fill", context: "topping up and using a transit IC card", isLocal: true)
                ],
                facts: ["Many casual ramen shops use a ticket machine before seating.", "Transit IC cards are widely used on trains and in shops."],
                landmarkName: "Shibuya Crossing", latitude: 35.6762, longitude: 139.6503
            ),
            Destination(
                id: "osaka", city: "Osaka", country: "Japan", symbol: "frying.pan.fill", colorSeed: "coral",
                languages: [japanese, english],
                localScenes: [.init(id: "osaka-market", title: "Food market", symbol: "basket.fill", context: "ordering street food at a busy market", isLocal: true)],
                facts: ["Osaka is known for casual street-food counters and lively markets."],
                landmarkName: "Dotonbori", latitude: 34.6937, longitude: 135.5023
            ),
            Destination(
                id: "seoul", city: "Seoul", country: "South Korea", symbol: "building.columns.fill", colorSeed: "sky",
                languages: [korean, english],
                localScenes: [.init(id: "seoul-cafe", title: "Cafe", symbol: "cup.and.saucer.fill", context: "ordering drinks and choosing hot or iced", isLocal: true)],
                facts: ["Cafe orders commonly distinguish clearly between hot and iced drinks."],
                landmarkName: "Gyeongbokgung", latitude: 37.5665, longitude: 126.9780
            ),
            Destination(
                id: "berlin", city: "Berlin", country: "Germany", symbol: "bicycle", colorSeed: "lime",
                languages: [german, english],
                localScenes: [.init(id: "berlin-bike", title: "Bike hire", symbol: "bicycle", context: "renting and returning a city bicycle", isLocal: true)],
                facts: ["Cycling and public transport are common ways to move around Berlin."],
                landmarkName: "Brandenburg Gate", latitude: 52.5200, longitude: 13.4050
            ),
            Destination(
                id: "madrid", city: "Madrid", country: "Spain", symbol: "sun.max.fill", colorSeed: "sun",
                languages: [spanish, english],
                localScenes: [.init(id: "madrid-tapas", title: "Tapas bar", symbol: "party.popper.fill", context: "ordering small shared dishes", isLocal: true)],
                facts: ["Small shared dishes are common in casual dining settings."],
                landmarkName: "Plaza Mayor", latitude: 40.4168, longitude: -3.7038
            ),
            Destination(
                id: "barcelona", city: "Barcelona", country: "Spain", symbol: "building.2.crop.circle.fill", colorSeed: "aqua",
                languages: [spanish, english],
                localScenes: [.init(id: "barcelona-market", title: "Market", symbol: "basket.fill", context: "buying produce and prepared food", isLocal: true)],
                facts: ["Covered markets combine fresh produce and prepared-food counters."],
                landmarkName: "Sagrada Família", latitude: 41.3874, longitude: 2.1686
            ),
            Destination(
                id: "london", city: "London", country: "United Kingdom", symbol: "bus.doubledecker.fill", colorSeed: "rose",
                languages: [english, german, spanish],
                localScenes: [.init(id: "london-tube", title: "The Tube", symbol: "train.side.front.car", context: "routes, lines and contactless travel", isLocal: true)],
                facts: ["The underground rail network is commonly called the Tube."],
                landmarkName: "Tower Bridge", latitude: 51.5072, longitude: -0.1276
            ),
            Destination(
                id: "moscow", city: "Moscow", country: "Russia", symbol: "tram.fill", colorSeed: "blue",
                languages: [russian, english],
                localScenes: [.init(id: "moscow-metro", title: "Metro", symbol: "tram.fill", context: "finding lines, exits and ticket options", isLocal: true)],
                facts: ["Metro stations may have multiple numbered or named exits."],
                landmarkName: "Red Square", latitude: 55.7558, longitude: 37.6173
            )
        ] + Self.popularDestinations(languages: [
            "en": english, "zh": chinese, "ja": japanese, "ko": korean,
            "ru": russian, "de": german, "es": spanish
        ])
    }

    func destination(id: String) -> Destination {
        destinations.first(where: { $0.id == id }) ?? destinations[0]
    }

    func contains(id: String) -> Bool {
        destinations.contains(where: { $0.id == id })
    }

    func makeCustomDestination(city: String, country: String) -> Destination? {
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty, !country.isEmpty else { return nil }

        let isChina = Self.isChina(country)
        let fallbackLanguage = isChina
            ? TrainingLanguage(code: "zh", name: "Chinese", localName: "简体中文")
            : TrainingLanguage(code: "en", name: "English", localName: "English")
        let identifier = [country, city]
            .map(Self.identifierComponent)
            .joined(separator: "-")

        return Destination(
            id: "custom-\(identifier)",
            city: city,
            country: country,
            symbol: isChina ? "character.book.closed.fill" : "mappin.and.ellipse",
            colorSeed: isChina ? "coral" : "global",
            languages: [fallbackLanguage],
            localScenes: [
                TravelScene(
                    id: "custom-\(identifier)-explore",
                    title: "Around \(city)",
                    symbol: "map.fill",
                    context: "general visitor situations around \(city)",
                    isLocal: true
                )
            ],
            facts: ["Current city-specific details are unavailable for this custom destination."],
            landmarkName: city,
            isCustom: true
        )
    }

    private static func isChina(_ country: String) -> Bool {
        let key = country
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
        return [
            "china", "cn", "prc", "mainlandchina",
            "peoplesrepublicofchina", "中国", "中华人民共和国", "中国大陆"
        ].contains(key)
    }

    private static func identifierComponent(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    private static func popularDestinations(languages: [String: TrainingLanguage]) -> [Destination] {
        let seeds: [DestinationSeed] = [
            .init("beijing", "Beijing", "China", 39.9042, 116.4074, ["zh", "en"], "Forbidden City", "building.columns.fill"),
            .init("shanghai", "Shanghai", "China", 31.2304, 121.4737, ["zh", "en"], "The Bund", "building.2.fill"),
            .init("guangzhou", "Guangzhou", "China", 23.1291, 113.2644, ["zh", "en"], "Canton Tower", "antenna.radiowaves.left.and.right"),
            .init("shenzhen", "Shenzhen", "China", 22.5431, 114.0579, ["zh", "en"], "Civic Center", "building.2.crop.circle.fill"),
            .init("chengdu", "Chengdu", "China", 30.5728, 104.0668, ["zh", "en"], "Tianfu Square", "leaf.fill"),
            .init("xian", "Xi'an", "China", 34.3416, 108.9398, ["zh", "en"], "City Wall", "building.columns.fill"),
            .init("hangzhou", "Hangzhou", "China", 30.2741, 120.1551, ["zh", "en"], "West Lake", "water.waves"),
            .init("chongqing", "Chongqing", "China", 29.4316, 106.9123, ["zh", "en"], "Hongya Cave", "tram.fill"),
            .init("kyoto", "Kyoto", "Japan", 35.0116, 135.7681, ["ja", "en"], "Fushimi Inari", "torii.gate"),
            .init("sapporo", "Sapporo", "Japan", 43.0618, 141.3545, ["ja", "en"], "Odori Park", "snowflake"),
            .init("fukuoka", "Fukuoka", "Japan", 33.5902, 130.4017, ["ja", "en"], "Canal City", "takeoutbag.and.cup.and.straw.fill"),
            .init("naha", "Naha", "Japan", 26.2124, 127.6809, ["ja", "en"], "Shurijo Castle", "beach.umbrella.fill"),
            .init("busan", "Busan", "South Korea", 35.1796, 129.0756, ["ko", "en"], "Haeundae Beach", "water.waves"),
            .init("jeju", "Jeju", "South Korea", 33.4996, 126.5312, ["ko", "en"], "Hallasan", "mountain.2.fill"),
            .init("munich", "Munich", "Germany", 48.1351, 11.5820, ["de", "en"], "Marienplatz", "building.columns.fill"),
            .init("hamburg", "Hamburg", "Germany", 53.5511, 9.9937, ["de", "en"], "Elbphilharmonie", "ferry.fill"),
            .init("frankfurt", "Frankfurt", "Germany", 50.1109, 8.6821, ["de", "en"], "Römerberg", "building.2.fill"),
            .init("vienna", "Vienna", "Austria", 48.2082, 16.3738, ["de", "en"], "Schönbrunn Palace", "music.note"),
            .init("salzburg", "Salzburg", "Austria", 47.8095, 13.0550, ["de", "en"], "Hohensalzburg", "music.note.house.fill"),
            .init("zurich", "Zurich", "Switzerland", 47.3769, 8.5417, ["de", "en"], "Lake Zürich", "water.waves"),
            .init("cologne", "Cologne", "Germany", 50.9375, 6.9603, ["de", "en"], "Cologne Cathedral", "building.columns.fill"),
            .init("seville", "Seville", "Spain", 37.3891, -5.9845, ["es", "en"], "Plaza de España", "fan.fill"),
            .init("valencia", "Valencia", "Spain", 39.4699, -0.3763, ["es", "en"], "City of Arts", "sun.max.fill"),
            .init("mexico-city", "Mexico City", "Mexico", 19.4326, -99.1332, ["es", "en"], "Palacio de Bellas Artes", "building.columns.fill"),
            .init("cancun", "Cancún", "Mexico", 21.1619, -86.8515, ["es", "en"], "Caribbean beaches", "beach.umbrella.fill"),
            .init("buenos-aires", "Buenos Aires", "Argentina", -34.6037, -58.3816, ["es", "en"], "Obelisco", "music.note"),
            .init("lima", "Lima", "Peru", -12.0464, -77.0428, ["es", "en"], "Plaza Mayor", "fork.knife"),
            .init("santiago", "Santiago", "Chile", -33.4489, -70.6693, ["es", "en"], "Cerro San Cristóbal", "mountain.2.fill"),
            .init("bogota", "Bogotá", "Colombia", 4.7110, -74.0721, ["es", "en"], "Monserrate", "tram.fill"),
            .init("cartagena", "Cartagena", "Colombia", 10.3910, -75.4794, ["es", "en"], "Walled City", "sun.max.fill"),
            .init("havana", "Havana", "Cuba", 23.1136, -82.3666, ["es", "en"], "Old Havana", "car.side.fill"),
            .init("san-juan", "San Juan", "Puerto Rico", 18.4655, -66.1057, ["es", "en"], "Castillo San Felipe", "beach.umbrella.fill"),
            .init("new-york", "New York", "United States", 40.7128, -74.0060, ["en", "es"], "Statue of Liberty", "building.2.fill"),
            .init("los-angeles", "Los Angeles", "United States", 34.0522, -118.2437, ["en", "es"], "Hollywood", "film.fill"),
            .init("san-francisco", "San Francisco", "United States", 37.7749, -122.4194, ["en", "es"], "Golden Gate Bridge", "cablecar.fill"),
            .init("edinburgh", "Edinburgh", "United Kingdom", 55.9533, -3.1883, ["en"], "Edinburgh Castle", "building.columns.fill"),
            .init("dublin", "Dublin", "Ireland", 53.3498, -6.2603, ["en"], "Trinity College", "books.vertical.fill"),
            .init("toronto", "Toronto", "Canada", 43.6532, -79.3832, ["en"], "CN Tower", "antenna.radiowaves.left.and.right"),
            .init("vancouver", "Vancouver", "Canada", 49.2827, -123.1207, ["en"], "Stanley Park", "leaf.fill"),
            .init("sydney", "Sydney", "Australia", -33.8688, 151.2093, ["en"], "Sydney Opera House", "sailboat.fill"),
            .init("melbourne", "Melbourne", "Australia", -37.8136, 144.9631, ["en"], "Federation Square", "tram.fill"),
            .init("singapore", "Singapore", "Singapore", 1.3521, 103.8198, ["en"], "Marina Bay", "building.2.fill"),
            .init("saint-petersburg", "Saint Petersburg", "Russia", 59.9311, 30.3609, ["ru", "en"], "Hermitage Museum", "building.columns.fill"),
            .init("kazan", "Kazan", "Russia", 55.7961, 49.1064, ["ru", "en"], "Kazan Kremlin", "building.columns.fill"),
            .init("sochi", "Sochi", "Russia", 43.6028, 39.7342, ["ru", "en"], "Black Sea coast", "beach.umbrella.fill"),
            .init("vladivostok", "Vladivostok", "Russia", 43.1155, 131.8855, ["ru", "en"], "Golden Bridge", "ferry.fill"),
            .init("paris", "Paris", "France", 48.8566, 2.3522, ["en", "es", "de"], "Eiffel Tower", "building.2.fill"),
            .init("rome", "Rome", "Italy", 41.9028, 12.4964, ["en", "es", "de"], "Colosseum", "building.columns.fill"),
            .init("amsterdam", "Amsterdam", "Netherlands", 52.3676, 4.9041, ["en", "de"], "Canal Ring", "bicycle"),
            .init("prague", "Prague", "Czechia", 50.0755, 14.4378, ["en", "de"], "Charles Bridge", "building.columns.fill"),
            .init("lisbon", "Lisbon", "Portugal", 38.7223, -9.1393, ["en", "es", "de"], "Tram 28", "tram.fill"),
            .init("athens", "Athens", "Greece", 37.9838, 23.7275, ["en", "de"], "Acropolis", "building.columns.fill"),
            .init("istanbul", "Istanbul", "Türkiye", 41.0082, 28.9784, ["en", "de"], "Hagia Sophia", "ferry.fill"),
            .init("dubai", "Dubai", "United Arab Emirates", 25.2048, 55.2708, ["en", "de", "ru"], "Burj Khalifa", "building.2.fill"),
            .init("bangkok", "Bangkok", "Thailand", 13.7563, 100.5018, ["en"], "Grand Palace", "car.side.fill"),
            .init("bali", "Bali", "Indonesia", -8.4095, 115.1889, ["en"], "Uluwatu", "beach.umbrella.fill"),
            .init("honolulu", "Honolulu", "United States", 21.3099, -157.8581, ["en"], "Waikīkī", "beach.umbrella.fill")
        ]

        return seeds.map { seed in
            Destination(
                id: seed.id,
                city: seed.city,
                country: seed.country,
                symbol: seed.symbol,
                colorSeed: "global",
                languages: seed.languageCodes.compactMap { languages[$0] },
                localScenes: [
                    TravelScene(
                        id: "\(seed.id)-highlights",
                        title: seed.landmark,
                        symbol: seed.symbol,
                        context: "visiting and navigating around \(seed.landmark)",
                        isLocal: true
                    )
                ],
                facts: ["\(seed.landmark) is a well-known visitor area in \(seed.city)."],
                landmarkName: seed.landmark,
                latitude: seed.latitude,
                longitude: seed.longitude
            )
        }
    }
}

private struct DestinationSeed {
    let id: String
    let city: String
    let country: String
    let latitude: Double
    let longitude: Double
    let languageCodes: [String]
    let landmark: String
    let symbol: String

    init(
        _ id: String,
        _ city: String,
        _ country: String,
        _ latitude: Double,
        _ longitude: Double,
        _ languageCodes: [String],
        _ landmark: String,
        _ symbol: String
    ) {
        self.id = id
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.languageCodes = languageCodes
        self.landmark = landmark
        self.symbol = symbol
    }
}
