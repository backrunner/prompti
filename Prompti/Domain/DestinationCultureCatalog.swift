import Foundation

/// Generation-only, evergreen context. Each request includes just its city,
/// region and learning language; none of these examples is a selectable scene.
enum DestinationCultureCatalog {
    struct RegionalContext: Sendable {
        let code: String
        let culture: String
        let etiquette: String
        var speech: [String: String] = [:]
    }

    static func facts(for destination: Destination, languageCode: String) -> [String] {
        let region = region(forCountry: destination.country)
        var facts: [String] = []
        if !destination.isCustom, let city = cityLife[destination.id] { facts.append(city) }
        if let region { facts += [region.culture, region.etiquette] }
        if let speech = region?.speech[languageCode] ?? standardSpeech[languageCode] {
            facts.append(speech)
        }
        return facts
    }

    static func region(forCountry country: String) -> RegionalContext? {
        if let region = regions[country] { return region }
        return countryAliases[normalized(country)].flatMap { regions[$0] }
    }

    private static let countryAliases: [String: String] = {
        var aliases: [String: String] = [:]
        for (country, region) in regions {
            for name in [country, region.code,
                         Locale(identifier: "en").localizedString(forRegionCode: region.code),
                         Locale(identifier: "zh-Hans").localizedString(forRegionCode: region.code)].compactMap({ $0 }) {
                aliases[normalized(name)] = country
            }
        }
        for (alias, country) in ["UK": "United Kingdom", "USA": "United States", "Turkey": "Türkiye",
                                 "PRC": "China", "中国大陆": "China", "中华人民共和国": "China",
                                 "Korea": "South Korea", "Czech Republic": "Czechia"] {
            aliases[normalized(alias)] = country
        }
        return aliases
    }()

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // Used when the learning language is not the region's usual language. This
    // keeps, for example, Japanese honorific endings out of an English answer.
    private static let standardSpeech = [
        "en": "In English travel exchanges, 'excuse me', 'could I' and 'please' support clear requests and polite clarification; plain international English works without imitating a local accent.",
        "zh": "In Mandarin travel exchanges, 请问 can open a question, 麻烦你 can soften a request and 谢谢 expresses thanks; clear standard Mandarin avoids unnecessary regional slang.",
        "ja": "In Japanese travel exchanges, すみません opens a request and です・ます forms suit unfamiliar people; お願いします is useful when asking for a service.",
        "ko": "In Korean travel exchanges, polite 요 endings suit unfamiliar people; 주세요 makes a request and 감사합니다 expresses thanks.",
        "de": "In German travel exchanges with unfamiliar adults, Sie, bitte and danke provide a polite register; a clear question is preferable to an overly elaborate formula.",
        "es": "In Spanish travel exchanges, a greeting, por favor and gracias support polite requests; forms of address vary by relationship and region.",
        "ru": "In Russian travel exchanges with unfamiliar adults, вы, пожалуйста and спасибо support a polite register; извините can open a request."
    ]

    static let regions: [String: RegionalContext] = [
        "Japan": .init(code: "JP",
            culture: "Japanese everyday settings include sushi counters, ramen, soba and udon shops, wagashi sweets, tea shops, convenience stores and rail stations.",
            etiquette: "At Japanese entrances with shoe-removal areas, visitors can ask where to leave shoes; on trains, quiet conversation and waiting for passengers to leave are considerate practices.",
            speech: ["ja": "For Japanese service encounters, すみません, お願いします and です・ます forms are useful; brief acknowledgements such as はい help follow instructions. Standard polite Japanese works across regions without imitating dialect."]),
        "China": .init(code: "CN",
            culture: "Chinese food traditions vary by region; noodle shops, dumpling restaurants, tea houses, shared dishes and produce markets offer everyday exchanges.",
            etiquette: "When sharing a Chinese meal, asking about serving utensils and portion sizes is considerate; asking before photographing people applies in markets and neighbourhoods.",
            speech: ["zh": "请问 introduces a Mandarin question, 麻烦您 softens a request and 谢谢 expresses thanks. Mandarin works for practice across regions; local dialect words need context rather than being assumed universal."]),
        "South Korea": .init(code: "KR",
            culture: "Korean everyday settings include barbecue restaurants, shared side dishes, street-food stalls, bathhouses, cafes and traditional markets.",
            etiquette: "Using both hands when offering or receiving an item can show respect in Korean interactions; visitors can ask about removing shoes before entering a floor-seating area.",
            speech: ["ko": "Polite Korean 요 endings suit unfamiliar people; 저기요 can attract a server's attention, 주세요 requests an item and 감사합니다 expresses thanks. Casual speech depends on the relationship."]),
        "Germany": .init(code: "DE",
            culture: "German everyday settings include bread bakeries, coffee and cake, weekly markets, public transport and returnable drink containers marked Pfand.",
            etiquette: "At German shops and counters, a short greeting and waiting one's turn are courteous; visitors can ask where to return a deposit bottle rather than assuming every container is accepted.",
            speech: ["de": "Guten Tag, bitte and danke suit German service encounters; Sie is a useful default with unfamiliar adults, while staff may use du in informal settings."]),
        "Austria": .init(code: "AT",
            culture: "Austrian coffeehouses, pastries, strudel, schnitzel, music venues and outdoor outings provide varied visitor conversations.",
            etiquette: "In Austrian cafes, visitors can ask whether to wait for seating or choose a table; concert and museum staff can clarify cloakroom arrangements.",
            speech: ["de": "Grüß Gott is a familiar Austrian greeting and Guten Tag also works; Sie, bitte and danke suit unfamiliar adults. Austrian menu terms such as Melange can be clarified in standard German."]),
        "Switzerland": .init(code: "CH",
            culture: "Switzerland has several language regions; cheese dishes, chocolate, local bakeries, lake boats and rail travel offer everyday settings.",
            etiquette: "A greeting before a request and keeping shared transport spaces clear are considerate; visitors can ask about seating or quiet areas instead of assuming a rule.",
            speech: ["de": "In German-speaking Switzerland, Grüezi is a common greeting; standard German is suitable for visitors even when they hear Swiss German dialect. Sie and polite request forms remain useful."]),
        "Spain": .init(code: "ES",
            culture: "Spanish everyday settings include tapas bars, covered markets, bakeries, cafes and plazas; regional food and languages vary.",
            etiquette: "At a busy Spanish market, asking who is last in line can clarify turn-taking; asking whether a dish is for sharing helps with ordering.",
            speech: ["es": "Hola or buenos días, por favor and gracias suit service exchanges in Spain. Tú is common in many casual settings and usted adds formality; either can be appropriate in context."]),
        "Mexico": .init(code: "MX",
            culture: "Mexican everyday settings include taco stands, panaderías, markets, fruit drinks and regional craft shops; sauces vary in heat.",
            etiquette: "Greeting a vendor before ordering and asking about salsa or handling produce are courteous ways to begin a Mexican market exchange.",
            speech: ["es": "Buenos días, disculpe, por favor and gracias are useful in Mexican service exchanges; usted is a respectful option with unfamiliar adults, not a requirement for every encounter."]),
        "Argentina": .init(code: "AR",
            culture: "Argentine food and social settings include empanadas, grilled meats, cafe pastries, mate and tango venues.",
            etiquette: "When offered shared mate, visitors can ask how to take part or politely decline; at a performance venue they can ask before taking photographs.",
            speech: ["es": "Rioplatense Spanish commonly uses vos and forms such as tenés; usted remains available for formality. Visitors can use clear standard Spanish without imitating an accent."]),
        "Peru": .init(code: "PE",
            culture: "Peruvian everyday settings include ceviche restaurants, cooked rice dishes, fruit-juice counters, textile shops and local markets.",
            etiquette: "Greeting a stallholder and asking permission before photographing people or craftwork are considerate practices; ingredients and preparation can be clarified directly.",
            speech: ["es": "Buenos días, disculpe, por favor and gracias suit Peruvian service exchanges; usted can show respect with unfamiliar adults. Clear requests need not copy regional slang."]),
        "Chile": .init(code: "CL",
            culture: "Chilean food settings include empanadas, sandwiches, seafood and produce markets; cafes and local craft stalls offer further exchanges.",
            etiquette: "A brief greeting and waiting one's turn support courteous counter service; visitors can ask how a queue or collection point works.",
            speech: ["es": "Chilean Spanish can be fast and colloquial; ¿Puede repetir más despacio, por favor? is a useful clarification. Standard polite Spanish works without slang or imitating pronunciation."]),
        "Colombia": .init(code: "CO",
            culture: "Colombian everyday settings include coffee shops, arepas, fruit juices, flower markets and regional crafts.",
            etiquette: "Greeting a vendor before making a request and asking before touching displayed crafts or photographing people are considerate.",
            speech: ["es": "Buenos días and por favor suit Colombian service exchanges; usted occurs in both courteous and familiar speech, with regional variation. It should not automatically be read as distant or unfriendly."]),
        "Cuba": .init(code: "CU",
            culture: "Cuban food and cultural settings include rice and beans, sandwiches, coffee, music venues and neighbourhood produce stands.",
            etiquette: "At a Cuban counter or queue, visitors can ask who is last; asking a performer or vendor before photographing them is courteous.",
            speech: ["es": "Buenos días, disculpe and gracias are useful in Cuban Spanish exchanges; asking for repetition is appropriate when connected speech is unfamiliar. Clear standard Spanish is sufficient."]),
        "Puerto Rico": .init(code: "PR",
            culture: "Puerto Rican everyday settings include plantain dishes, rice and beans, coffee, artisan stalls and coastal outings.",
            etiquette: "Greeting staff and asking about portions or shared dishes is courteous; a visitor can ask which language a speaker prefers without assuming fluency.",
            speech: ["es": "Buenos días, por favor and gracias work in Puerto Rican Spanish; Spanish and English may both be heard, but a practice exchange can stay in the selected language without forced code-switching."]),
        "United States": .init(code: "US",
            culture: "US everyday settings include diners, delis, coffee shops, food trucks, neighbourhood markets and diverse regional cuisines.",
            etiquette: "In US restaurants, asking whether to wait for a host or order at the counter helps clarify service; waiting one's turn and requesting permission before sharing a table are courteous.",
            speech: ["en": "In US English, 'to go', 'check' for a restaurant bill and 'restroom' are common service terms. 'Could I have…?' is a polite request; 'How are you?' may be a brief greeting."]),
        "United Kingdom": .init(code: "GB",
            culture: "British everyday settings include tea rooms, bakeries, pubs, takeaway counters, parks and public transport.",
            etiquette: "Orderly queues are common in Britain; asking whether someone is waiting avoids cutting in. In a pub, visitors can ask whether to order at the bar or table.",
            speech: ["en": "In British English, 'takeaway', 'queue' and 'bill' are common service terms; 'excuse me' and 'could I…?' soften requests, and 'cheers' can mean thanks informally."]),
        "Ireland": .init(code: "IE",
            culture: "Irish everyday settings include soda bread, stews, cafes, pubs, traditional music and coastal or countryside outings.",
            etiquette: "In a pub music session, asking before joining or recording respects the performers; visitors can clarify whether to order at the bar.",
            speech: ["en": "In Irish English, 'grand' often means fine or okay, and 'thanks a million' is a familiar expression of thanks. Plain polite English works without adopting an accent."]),
        "Canada": .init(code: "CA",
            culture: "Canadian everyday settings include bakeries, coffee shops, local produce markets, maple products and varied immigrant cuisines.",
            etiquette: "Waiting one's turn, checking whether a seat is free and keeping shared paths clear are considerate; language preference can be asked without assuming everyone is bilingual.",
            speech: ["en": "Canadian English uses familiar polite requests such as 'could I…?' and 'excuse me'; 'washroom' is a common term. Regional pronunciation or slang is not required."]),
        "Australia": .init(code: "AU",
            culture: "Australian everyday settings include espresso cafes, flat whites, bakeries, produce markets, seafood counters and coastal outings.",
            etiquette: "At Australian cafes, visitors can ask whether to order at the counter or wait at a table; leaving space on shared walking and cycling paths is considerate.",
            speech: ["en": "In Australian English, 'takeaway' is common and 'no worries' can acknowledge thanks or a request. Friendly plain English is suitable; slang and accent imitation are unnecessary."]),
        "Russia": .init(code: "RU",
            culture: "Russian everyday settings include blini, pelmeni, tea with pastries, markets, museums and long-distance or urban rail travel.",
            etiquette: "Visitors can ask about a cloakroom when entering a Russian theatre or museum; a polite greeting and waiting one's turn suit service encounters.",
            speech: ["ru": "Здравствуйте, извините, пожалуйста and спасибо suit Russian service exchanges; вы is a useful default with unfamiliar adults. Short, clear requests can still be polite."]),
        "France": .init(code: "FR",
            culture: "French everyday settings include boulangeries, pâtisseries, cheese shops, neighbourhood markets, cafes and museums.",
            etiquette: "In a French shop, greeting staff before making a request is customary; asking before handling produce or taking a seat avoids assumptions about service.",
            speech: ["en": "In an English exchange in France, a greeting before the request and 'could I…?' convey courtesy; the learner can ask whether English is spoken. French wording is not required for an English answer."]),
        "Italy": .init(code: "IT",
            culture: "Italian everyday settings include espresso bars, bakeries, gelaterias, produce markets, pasta restaurants and neighbourhood piazzas.",
            etiquette: "At an Italian cafe, visitors can ask whether to pay first and whether to sit or stand at the counter; these arrangements differ by venue.",
            speech: ["en": "In an English exchange in Italy, greet staff and clearly specify the item or service; ask for clarification of an unfamiliar menu word without switching the whole exercise into Italian."]),
        "Netherlands": .init(code: "NL",
            culture: "Dutch everyday settings include bicycle travel, cheese stalls, street markets, canal boats, cafes and museums.",
            etiquette: "Keeping cycle paths clear and checking where to park a rented bicycle are considerate in the Netherlands; visitors can ask before joining a queue or boarding a boat.",
            speech: ["en": "Clear, concise English requests with 'please' and 'thank you' suit visitor exchanges in the Netherlands; direct wording need not be judged rude, and English fluency should not be assumed."]),
        "Czechia": .init(code: "CZ",
            culture: "Czech everyday settings include bakeries, dumpling dishes, cafes, tram travel, craft shops and historic town squares.",
            etiquette: "Greeting staff on entering a small shop and asking whether a table is available are courteous; visitors can ask transport staff how to validate a ticket.",
            speech: ["en": "In an English exchange in Czechia, a greeting, a clear request and thanks are useful; asking for slower repetition is preferable to inventing local English slang."]),
        "Portugal": .init(code: "PT",
            culture: "Portuguese everyday settings include pastelarias, custard tarts, espresso, seafood, tiled streets and local markets.",
            etiquette: "Greeting staff and checking whether a counter uses numbered tickets are courteous; in a fado venue visitors can ask when it is appropriate to speak or take photos.",
            speech: ["en": "In English exchanges in Portugal, greet staff and use clear polite requests; ask about language preference rather than assuming Spanish is understood or treating it as Portuguese."]),
        "Greece": .init(code: "GR",
            culture: "Greek everyday settings include bakeries, tavernas, shared meze, coffee, produce markets and island or coastal boat travel.",
            etiquette: "Asking about shared portions and whether a table is available supports courteous taverna exchanges; visitors can ask before photographing people or entering a worship space.",
            speech: ["en": "In English exchanges in Greece, a greeting, a clear request and thanks convey courtesy; clarify unfamiliar menu or place names without imitating Greek-accented English."]),
        "Türkiye": .init(code: "TR",
            culture: "Turkish everyday settings include tea, coffee, bakeries, simit, shared breakfast dishes, bazaars and ferry travel.",
            etiquette: "Tea can be offered as hospitality and may be politely accepted or declined; at a mosque entrance, visitors can ask about shoes, clothing and visitor areas rather than assume arrangements.",
            speech: ["en": "In English exchanges in Türkiye, greet the speaker and make a clear polite request; a visitor can clarify a tea offer or unfamiliar item without performing a local accent."]),
        "United Arab Emirates": .init(code: "AE",
            culture: "Emirati food traditions include dates, Arabic coffee and spiced rice dishes; souks and multicultural neighbourhood restaurants offer varied settings.",
            etiquette: "When offered Arabic coffee, a small cup is customary; visitors can accept or decline politely and ask before photographing people. Religious-site arrangements should be checked with staff.",
            speech: ["en": "English is used in many UAE visitor settings among speakers with varied first languages; clear greetings, concise requests and checking understanding are useful without imitating an accent."]),
        "Thailand": .init(code: "TH",
            culture: "Thai everyday settings include noodle stalls, curry shops, fruit stalls, iced drinks, markets and temple visits.",
            etiquette: "At Thai temple entrances with shoe-removal areas, visitors can ask where shoes belong; asking before photographing people is considerate. A wai is a greeting gesture whose use varies by context.",
            speech: ["en": "In English exchanges in Thailand, short clear polite requests help with clarification; Thai politeness particles are not English grammar and should not be required in an English answer."]),
        "Indonesia": .init(code: "ID",
            culture: "Indonesian everyday settings include warung eateries, rice dishes, satay, coffee, craft markets and regionally distinct traditions.",
            etiquette: "Using the right hand when offering an item is a common courtesy in Indonesia; visitors can ask about shoes and clothing at a place of worship without assuming one rule for all sites.",
            speech: ["en": "In English exchanges in Indonesia, greet the speaker and use clear requests with please and thanks; titles or local words need context and should not be forced into every reply."]),
        "Singapore": .init(code: "SG",
            culture: "Singapore's hawker centres combine food and drink stalls: Bak kut teh, Durian, kopi, kaya toast, ice kachang and chendol provide varied food topics.",
            etiquette: "In Singapore hawker centres, asking whether a table is occupied and where to return a tray are useful courteous exchanges; shared spaces bring together different food traditions.",
            speech: ["en": "In Singapore English, 'takeaway' and 'queue' are familiar terms. Kopi ordering terms can be clarified in context; standard polite English works without adding Singlish particles such as lah."])
    ]

    // Every built-in city has its own everyday-life anchor, beyond its landmark.
    // Coverage tests fail when a destination is added without one of these.
    static let cityLife: [String: String] = [
        "tokyo": "Tokyo neighbourhoods offer ramen ticket machines, department-store food halls, small shops and interconnected rail stations.",
        "osaka": "Osaka is associated with takoyaki, okonomiyaki, covered shopping arcades and lively street-food markets.",
        "seoul": "Seoul combines neighbourhood cafes, traditional markets, palace visits and extensive metro travel; shared barbecue meals offer group-ordering situations.",
        "berlin": "Berlin offers neighbourhood markets, currywurst and varied international food, bicycle travel and U-Bahn and S-Bahn connections.",
        "madrid": "Madrid offers tapas bars, churros with chocolate, neighbourhood markets, art museums and metro travel.",
        "barcelona": "Barcelona combines covered food markets, Catalan dishes and architecture visits; Catalan and Spanish are both used in the city.",
        "london": "London offers diverse neighbourhood food, theatre outings, markets and Tube travel; a station can have several exits.",
        "moscow": "Moscow combines metro interchanges, theatres, food markets and tea with pastries; asking about an exit or cloakroom offers everyday practice.",
        "beijing": "Beijing is associated with roast duck, hutong neighbourhoods, traditional snack shops and park visits.",
        "shanghai": "Shanghai is associated with xiaolongbao, shengjian buns, lane neighbourhoods and riverside outings.",
        "guangzhou": "Guangzhou is known for Cantonese dim sum, tea-house dining, Cantonese speech and wholesale or neighbourhood markets.",
        "shenzhen": "Shenzhen combines electronics shopping, regional Chinese food, coastal parks and extensive metro travel.",
        "chengdu": "Chengdu is associated with Sichuan dishes, hotpot, tea houses and relaxed park outings; spice preferences offer useful clarification.",
        "xian": "Xi'an is associated with roujiamo, varied noodles, old-city lanes and wall visits; food stalls offer portion and ingredient questions.",
        "hangzhou": "Hangzhou is associated with Longjing tea, Jiangnan cooking, lakeside walks and silk products.",
        "chongqing": "Chongqing is known for hotpot and xiaomian noodles; hills, stairways and river crossings provide varied direction questions.",
        "kyoto": "Kyoto is associated with matcha, wagashi sweets, tofu dishes, traditional crafts and temple gardens.",
        "sapporo": "Sapporo is associated with miso ramen, soup curry, Hokkaido dairy products and winter outings.",
        "fukuoka": "Fukuoka is known for Hakata-style ramen and yatai food stalls; small counters provide seating and ordering exchanges.",
        "naha": "Naha reflects Okinawan culture through Okinawa soba, goya champuru, beni-imo sweets, pottery shops and market streets.",
        "busan": "Busan is known for seafood markets, fish-cake snacks, beaches and hillside neighbourhoods.",
        "jeju": "Jeju is associated with citrus fruit, seafood, black-pork dishes and volcanic walking landscapes.",
        "munich": "Munich offers Bavarian pretzels, food markets, beer gardens and museum outings; shared tables provide polite seating questions.",
        "hamburg": "Hamburg is associated with harbour outings, fish sandwiches, canal-side districts and ferry connections.",
        "frankfurt": "Frankfurt offers green sauce dishes, apple-wine taverns, Main riverside outings and busy rail connections.",
        "vienna": "Vienna is associated with coffeehouse culture, pastries, music performances and tram travel.",
        "salzburg": "Salzburg combines music venues, old-town shops, Austrian pastries and nearby mountain outings.",
        "zurich": "Zürich offers lakeside walks, tram travel, chocolate shops and Swiss German everyday speech.",
        "cologne": "Cologne is associated with Kölsch brewery taverns, the Rhine waterfront, museums and neighbourhood shopping streets.",
        "seville": "Seville offers tapas, flamenco venues, courtyard architecture and local ceramic crafts.",
        "valencia": "Valencia is associated with paella, horchata, covered markets and cycling through former riverbed parkland.",
        "mexico-city": "Mexico City offers tacos, tamales, neighbourhood markets, museum visits and extensive metro travel.",
        "cancun": "Cancún offers Yucatán food, coastal outings, craft shopping and boat-excursion counters beyond hotel dining.",
        "buenos-aires": "Buenos Aires is associated with tango, neighbourhood cafes, empanadas, bookshops and Rioplatense Spanish.",
        "lima": "Lima is associated with ceviche, criollo cooking, neighbourhood markets and Pacific coastal walks.",
        "santiago": "Santiago offers produce markets, Chilean sandwiches, hillside viewpoints and metro connections.",
        "bogota": "Bogotá offers coffee shops, ajiaco, produce markets, museums and mountain viewpoints.",
        "cartagena": "Cartagena combines Caribbean seafood, coconut rice, old-city walks and local craft stalls.",
        "havana": "Havana offers coffee counters, music venues, neighbourhood markets and seafront walks.",
        "san-juan": "San Juan combines Puerto Rican dishes such as mofongo, coffee shops, old-town streets and coastal outings.",
        "new-york": "New York neighbourhoods offer bagel shops, delis, diverse cuisines, theatre venues and subway travel.",
        "los-angeles": "Los Angeles offers taco stands, diverse neighbourhood cuisines, film-related outings, beaches and spread-out travel destinations.",
        "san-francisco": "San Francisco is associated with sourdough, neighbourhood food markets, steep streets, cable cars and waterfront outings.",
        "edinburgh": "Edinburgh offers Scottish shortbread, local cafes, literary venues, old-town lanes and hillside walks.",
        "dublin": "Dublin combines literary history, cafes, traditional music sessions, markets and coastal rail outings.",
        "toronto": "Toronto offers diverse neighbourhood cuisines, public markets, streetcar travel and lakefront outings.",
        "vancouver": "Vancouver combines Pacific seafood, varied Asian cuisines, neighbourhood markets, waterfront paths and nearby outdoor outings.",
        "sydney": "Sydney offers harbour ferries, seafood markets, beach outings and neighbourhood cafes.",
        "melbourne": "Melbourne is associated with laneway cafes, diverse food markets, arts venues and tram travel.",
        "singapore": "Singapore combines hawker dining, wet markets, neighbourhood heritage walks, multicultural festivals and MRT travel beyond Marina Bay.",
        "saint-petersburg": "Saint Petersburg offers museums, theatre outings, canal trips, courtyards and pastry cafes.",
        "kazan": "Kazan brings together Tatar and Russian cultural settings, including echpochmak pastries, tea and craft shops.",
        "sochi": "Sochi combines Black Sea coastal outings, produce markets, seafood and nearby mountain trips.",
        "vladivostok": "Vladivostok offers Pacific seafood, harbour viewpoints, hills and ferry-related visitor settings.",
        "paris": "Paris offers neighbourhood boulangeries, cheese shops, street markets, museums and metro connections beyond its landmark visits.",
        "rome": "Rome offers espresso counters, pizza al taglio, neighbourhood markets, ancient sites and piazzas.",
        "amsterdam": "Amsterdam combines bicycle travel, canal boats, neighbourhood markets, cheese shops and museums.",
        "prague": "Prague offers Czech bakery and dumpling dishes, tram travel, craft shops and historic neighbourhood walks.",
        "lisbon": "Lisbon is associated with pastéis de nata, hilly streets, trams, tiled buildings and fado venues.",
        "athens": "Athens offers bakeries, souvlaki, shared meze, neighbourhood markets and archaeological visits.",
        "istanbul": "Istanbul combines simit stalls, tea and coffee, bazaars, neighbourhood mosques and Bosphorus ferries.",
        "dubai": "Dubai offers souks, creek boat crossings, Emirati food and multicultural neighbourhood restaurants as well as modern attractions.",
        "bangkok": "Bangkok offers street-food markets, fruit and iced-drink stalls, canal or river boats and temple visits.",
        "bali": "Bali has distinct Hindu temple and offering traditions, local craft workshops, warung eateries and rice-growing landscapes; customs vary by village and site.",
        "honolulu": "Honolulu combines Native Hawaiian and other Pacific and Asian cultural influences, lei crafts, plate lunches and coastal outings; sacred places deserve respectful questions about access."
    ]
}
