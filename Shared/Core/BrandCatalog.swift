import Foundation

/// A chain of shops. Saying a brand means "any branch of it", so "Tesco, batteries"
/// surfaces at whichever Tesco you walk into.
struct Brand: Hashable, Sendable {
    let name: String
    let category: PlaceCategory
    let aliases: [String]
    let domains: [String]
    /// Brands whose name is also an everyday word ("Boots", "Target", "Shell")
    /// only match when written with a capital letter or after "at"/"in".
    let isCommonWord: Bool
    let market: Market

    enum Market: Sendable {
        case uk, us
    }

    init(_ name: String, _ category: PlaceCategory, market: Market = .uk, aliases: [String] = [], domains: [String] = [], isCommonWord: Bool = false) {
        self.name = name
        self.category = category
        self.market = market
        self.aliases = aliases
        self.domains = domains
        self.isCommonWord = isCommonWord
    }

    /// Search query for Apple Maps.
    var searchQuery: String { name }
}

enum BrandCatalog {
    static let all: [Brand] = [
        // UK supermarkets
        Brand("Tesco", .supermarket, aliases: ["tesco extra", "tesco express", "tesco metro", "tescos"], domains: ["tesco.com"]),
        Brand("Sainsbury's", .supermarket, aliases: ["sainsburys local", "sainsbury"], domains: ["sainsburys.co.uk"]),
        Brand("Asda", .supermarket, domains: ["asda.com"]),
        Brand("Morrisons", .supermarket, aliases: ["morrison"], domains: ["morrisons.com"]),
        Brand("Aldi", .supermarket, domains: ["aldi.co.uk", "aldi.us", "aldi.com"]),
        Brand("Lidl", .supermarket, domains: ["lidl.co.uk", "lidl.com"]),
        Brand("Waitrose", .supermarket, domains: ["waitrose.com"]),
        Brand("Co-op", .supermarket, aliases: ["coop", "co op", "the co-op"], domains: ["coop.co.uk"]),
        Brand("M&S", .supermarket, aliases: ["marks and spencer", "marks & spencer", "marks and sparks", "m and s food", "m&s food"], domains: ["marksandspencer.com"]),
        Brand("Iceland", .supermarket, domains: ["iceland.co.uk"], isCommonWord: true),
        Brand("Ocado", .supermarket, domains: ["ocado.com"]),
        // UK health & beauty
        Brand("Boots", .pharmacy, domains: ["boots.com"], isCommonWord: true),
        Brand("Superdrug", .pharmacy, domains: ["superdrug.com"]),
        Brand("Lloyds Pharmacy", .pharmacy, aliases: ["lloydspharmacy"], domains: ["lloydspharmacy.com"]),
        Brand("Holland & Barrett", .pharmacy, aliases: ["holland and barrett"], domains: ["hollandandbarrett.com"]),
        Brand("Specsavers", .health, domains: ["specsavers.co.uk"]),
        // UK DIY & home
        Brand("B&Q", .hardware, aliases: ["bnq", "b and q", "b & q", "b n q"], domains: ["diy.com"]),
        Brand("Wickes", .hardware, domains: ["wickes.co.uk"]),
        Brand("Screwfix", .hardware, domains: ["screwfix.com"]),
        Brand("Toolstation", .hardware, domains: ["toolstation.com"]),
        Brand("Homebase", .hardware, domains: ["homebase.co.uk"]),
        Brand("Dunelm", .homeware, domains: ["dunelm.com"]),
        Brand("IKEA", .homeware, domains: ["ikea.com"]),
        Brand("The Range", .homeware, domains: ["therange.co.uk"]),
        Brand("Wilko", .homeware, domains: ["wilko.com"]),
        Brand("Hobbycraft", .homeware, domains: ["hobbycraft.co.uk"]),
        Brand("Dobbies", .garden, domains: ["dobbies.com"]),
        // UK electronics & general
        Brand("Currys", .electronics, aliases: ["currys pc world", "curry's", "pc world"], domains: ["currys.co.uk"]),
        Brand("Argos", .electronics, domains: ["argos.co.uk"]),
        Brand("John Lewis", .homeware, aliases: ["john lewis and partners"], domains: ["johnlewis.com"]),
        Brand("Apple Store", .electronics, aliases: ["apple shop"], domains: ["apple.com"]),
        Brand("Halfords", .fuel, domains: ["halfords.com"]),
        Brand("Pets at Home", .pets, domains: ["petsathome.com"]),
        Brand("Waterstones", .books, domains: ["waterstones.com"]),
        Brand("WHSmith", .books, aliases: ["wh smith", "w h smith"], domains: ["whsmith.co.uk"]),
        Brand("Primark", .clothing, domains: ["primark.com"]),
        Brand("Uniqlo", .clothing, domains: ["uniqlo.com"]),
        Brand("Zara", .clothing, domains: ["zara.com"]),
        Brand("H&M", .clothing, aliases: ["h and m"], domains: ["hm.com"]),
        Brand("TK Maxx", .clothing, aliases: ["tkmaxx", "tk max", "tj maxx"], domains: ["tkmaxx.com", "tjmaxx.tjx.com"]),
        // UK food & drink
        Brand("Costa", .cafe, aliases: ["costa coffee"], domains: ["costa.co.uk"]),
        Brand("Starbucks", .cafe, domains: ["starbucks.com", "starbucks.co.uk"]),
        Brand("Pret", .cafe, aliases: ["pret a manger"], domains: ["pret.co.uk", "pret.com"]),
        Brand("Caffè Nero", .cafe, aliases: ["caffe nero", "cafe nero", "nero"], domains: ["caffenero.com"]),
        Brand("Greggs", .bakery, domains: ["greggs.co.uk"]),
        Brand("Wetherspoons", .pub, aliases: ["wetherspoon", "jd wetherspoon"], domains: ["jdwetherspoon.com"]),
        Brand("Nando's", .restaurant, aliases: ["nandos"], domains: ["nandos.co.uk", "nandos.com"]),
        // Fuel
        Brand("Shell", .fuel, domains: ["shell.co.uk", "shell.com"], isCommonWord: true),
        Brand("BP", .fuel, domains: ["bp.com"]),
        Brand("Esso", .fuel, domains: ["esso.co.uk"]),
        // US
        Brand("Target", .supermarket, market: .us, domains: ["target.com"], isCommonWord: true),
        Brand("Walmart", .supermarket, market: .us, domains: ["walmart.com"]),
        Brand("Costco", .supermarket, market: .us, domains: ["costco.com", "costco.co.uk"]),
        Brand("Whole Foods", .supermarket, market: .us, aliases: ["whole foods market"], domains: ["wholefoodsmarket.com"]),
        Brand("Trader Joe's", .supermarket, market: .us, aliases: ["trader joes"], domains: ["traderjoes.com"]),
        Brand("Kroger", .supermarket, market: .us, domains: ["kroger.com"]),
        Brand("Safeway", .supermarket, market: .us, domains: ["safeway.com"]),
        Brand("Publix", .supermarket, market: .us, domains: ["publix.com"]),
        Brand("CVS", .pharmacy, market: .us, domains: ["cvs.com"]),
        Brand("Walgreens", .pharmacy, market: .us, domains: ["walgreens.com"]),
        Brand("Home Depot", .hardware, market: .us, aliases: ["the home depot"], domains: ["homedepot.com"]),
        Brand("Lowe's", .hardware, market: .us, aliases: ["lowes"], domains: ["lowes.com"]),
        Brand("Ace Hardware", .hardware, market: .us, domains: ["acehardware.com"]),
        Brand("Best Buy", .electronics, market: .us, domains: ["bestbuy.com"]),
        Brand("Barnes & Noble", .books, market: .us, aliases: ["barnes and noble"], domains: ["barnesandnoble.com"]),
        Brand("Petco", .pets, market: .us, domains: ["petco.com"]),
        Brand("PetSmart", .pets, market: .us, domains: ["petsmart.com"]),
        Brand("Dunkin'", .cafe, market: .us, aliases: ["dunkin", "dunkin donuts"], domains: ["dunkindonuts.com"]),
    ]

    /// Key → brand, where a key is a normalised token sequence joined by single spaces.
    static let index: [String: Brand] = {
        var map: [String: Brand] = [:]
        for brand in all {
            for phrase in [brand.name] + brand.aliases {
                for key in TextNormalizer.keyVariants(of: phrase) where map[key] == nil {
                    map[key] = brand
                }
            }
        }
        return map
    }()

    /// Longest brand key, in tokens.
    static let maxKeyLength: Int = index.keys.map { $0.split(separator: " ").count }.max() ?? 1

    static func brand(named name: String) -> Brand? {
        let key = TextNormalizer.key(name)
        return index[key] ?? all.first { TextNormalizer.key($0.name) == key }
    }

    /// Finds the brand that owns a web address ("https://www.diy.com/…" → B&Q).
    static func brand(forHost host: String) -> Brand? {
        let host = host.lowercased()
        return all.first { brand in
            brand.domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}
