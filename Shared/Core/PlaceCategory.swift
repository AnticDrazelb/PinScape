import Foundation

/// A kind of place. Categories drive the glyph and colour a pin wears, the
/// search Pinscape runs to find matching places nearby, and the hints used to
/// guess a place from what you said ("wood stain" → hardware store).
enum PlaceCategory: String, CaseIterable, Codable, Sendable {
    case supermarket
    case convenience
    case pharmacy
    case hardware
    case garden
    case homeware
    case electronics
    case cafe
    case restaurant
    case pub
    case bakery
    case books
    case clothing
    case fuel
    case gym
    case park
    case library
    case postOffice
    case bank
    case transit
    case airport
    case health
    case school
    case office
    case home
    case beauty
    case pets
    case florist
    case area
    case spot
    case sticker
    case other

    var displayName: String {
        switch self {
        case .supermarket: "Supermarket"
        case .convenience: "Corner shop"
        case .pharmacy: "Pharmacy"
        case .hardware: "Hardware store"
        case .garden: "Garden centre"
        case .homeware: "Home store"
        case .electronics: "Electronics store"
        case .cafe: "Café"
        case .restaurant: "Restaurant"
        case .pub: "Pub"
        case .bakery: "Bakery"
        case .books: "Bookshop"
        case .clothing: "Clothes shop"
        case .fuel: "Petrol station"
        case .gym: "Gym"
        case .park: "Park"
        case .library: "Library"
        case .postOffice: "Post office"
        case .bank: "Bank"
        case .transit: "Station"
        case .airport: "Airport"
        case .health: "Doctor"
        case .school: "School"
        case .office: "Office"
        case .home: "Home"
        case .beauty: "Salon"
        case .pets: "Pet shop"
        case .florist: "Florist"
        case .area: "Area"
        case .spot: "Spot"
        case .sticker: "Sticker"
        case .other: "Place"
        }
    }

    /// Plural used for "any …" phrasing: "Any pharmacy".
    var anyPhrase: String {
        "Any \(displayName.lowercased())"
    }

    /// SF Symbol shown inside the place glyph.
    var symbol: String {
        switch self {
        case .supermarket: "cart.fill"
        case .convenience: "basket.fill"
        case .pharmacy: "cross.case.fill"
        case .hardware: "hammer.fill"
        case .garden: "leaf.fill"
        case .homeware: "sofa.fill"
        case .electronics: "desktopcomputer"
        case .cafe: "cup.and.saucer.fill"
        case .restaurant: "fork.knife"
        case .pub: "wineglass.fill"
        case .bakery: "birthday.cake.fill"
        case .books: "book.fill"
        case .clothing: "tshirt.fill"
        case .fuel: "fuelpump.fill"
        case .gym: "figure.strengthtraining.traditional"
        case .park: "tree.fill"
        case .library: "books.vertical.fill"
        case .postOffice: "envelope.fill"
        case .bank: "sterlingsign.circle.fill"
        case .transit: "tram.fill"
        case .airport: "airplane"
        case .health: "stethoscope"
        case .school: "graduationcap.fill"
        case .office: "building.2.fill"
        case .home: "house.fill"
        case .beauty: "scissors"
        case .pets: "pawprint.fill"
        case .florist: "camera.macro"
        case .area: "map.fill"
        case .spot: "mappin"
        case .sticker: "tag.fill"
        case .other: "mappin.and.ellipse"
        }
    }

    /// Hex colour for the category glyph.
    var colorHex: String {
        switch self {
        case .supermarket: "#34C759"
        case .convenience: "#30B0C7"
        case .pharmacy: "#FF453A"
        case .hardware: "#FF9500"
        case .garden: "#32B45A"
        case .homeware: "#5E5CE6"
        case .electronics: "#0A84FF"
        case .cafe: "#A2845E"
        case .restaurant: "#FF7A2F"
        case .pub: "#BF5AF2"
        case .bakery: "#E0A050"
        case .books: "#AF52DE"
        case .clothing: "#FF2D72"
        case .fuel: "#64748B"
        case .gym: "#FF375F"
        case .park: "#2FBF71"
        case .library: "#6366F1"
        case .postOffice: "#F2B705"
        case .bank: "#0EA5E9"
        case .transit: "#3478F6"
        case .airport: "#38BDF8"
        case .health: "#EF4444"
        case .school: "#EAB308"
        case .office: "#71717A"
        case .home: "#FF9F0A"
        case .beauty: "#EC4899"
        case .pets: "#B07D4F"
        case .florist: "#F472B6"
        case .area: "#14B8A6"
        case .spot: "#FF5A4E"
        case .sticker: "#8B5CF6"
        case .other: "#FF5A4E"
        }
    }

    /// Natural language query used with Apple Maps search to find places of this kind.
    var searchQuery: String {
        switch self {
        case .supermarket: "supermarket"
        case .convenience: "convenience store"
        case .pharmacy: "pharmacy"
        case .hardware: "hardware store"
        case .garden: "garden centre"
        case .homeware: "home furnishings store"
        case .electronics: "electronics store"
        case .cafe: "coffee shop"
        case .restaurant: "restaurant"
        case .pub: "pub"
        case .bakery: "bakery"
        case .books: "bookshop"
        case .clothing: "clothing store"
        case .fuel: "petrol station"
        case .gym: "gym"
        case .park: "park"
        case .library: "library"
        case .postOffice: "post office"
        case .bank: "bank"
        case .transit: "train station"
        case .airport: "airport"
        case .health: "doctor"
        case .school: "school"
        case .office: "office"
        case .home: "home"
        case .beauty: "hair salon"
        case .pets: "pet shop"
        case .florist: "florist"
        case .area, .spot, .sticker, .other: ""
        }
    }

    /// Whether this category can be searched for as "any <category>".
    var isSearchable: Bool {
        switch self {
        case .area, .spot, .sticker, .other, .home, .office, .school: false
        default: true
        }
    }

    /// Words that name this kind of place when spoken: "the chemist", "a petrol station".
    var placeWords: [String] {
        switch self {
        case .supermarket: ["supermarket", "supermarkets", "grocery store", "grocery shop", "grocer", "grocers", "food shop"]
        case .convenience: ["corner shop", "convenience store", "newsagent", "newsagents", "off licence", "bodega", "offy"]
        case .pharmacy: ["pharmacy", "pharmacies", "chemist", "chemists", "drugstore", "drug store"]
        case .hardware: ["hardware store", "hardware shop", "diy store", "diy shop", "builders merchant"]
        case .garden: ["garden centre", "garden center", "nursery"]
        case .homeware: ["home store", "furniture store", "furniture shop"]
        case .electronics: ["electronics store", "electronics shop", "phone shop", "tech store"]
        case .cafe: ["cafe", "café", "coffee shop", "coffee place"]
        case .restaurant: ["restaurant"]
        case .pub: ["pub", "the local", "bar"]
        case .bakery: ["bakery", "bakers", "baker"]
        case .books: ["bookshop", "book shop", "bookstore", "book store"]
        case .clothing: ["clothes shop", "clothing store"]
        case .fuel: ["petrol station", "gas station", "garage", "filling station", "services"]
        case .gym: ["gym", "leisure centre", "fitness centre"]
        case .park: ["park"]
        case .library: ["library"]
        case .postOffice: ["post office", "postbox", "post box", "mailbox"]
        case .bank: ["bank", "cash machine", "cashpoint", "atm"]
        case .transit: ["station", "train station", "tube station", "tube", "bus station"]
        case .airport: ["airport"]
        case .health: ["doctor", "doctors", "gp", "surgery", "dentist", "hospital", "clinic"]
        case .school: ["school"]
        case .office: ["office", "work"]
        case .home: ["home", "house"]
        case .beauty: ["hairdresser", "hairdressers", "barber", "barbers", "salon"]
        case .pets: ["pet shop", "pet store", "vet", "vets"]
        case .florist: ["florist", "flower shop"]
        case .area, .spot, .sticker, .other: []
        }
    }

    /// Words in a note that suggest which kind of place would solve it.
    var itemHints: [String] {
        switch self {
        case .supermarket: ["milk", "bread", "eggs", "butter", "cheese", "batteries", "bin bags", "washing up liquid", "toilet roll", "loo roll", "coffee beans", "pasta", "rice", "fruit", "veg", "vegetables", "wine", "beer", "groceries", "shopping", "snacks", "cereal", "detergent", "nappies", "foil", "cling film", "kitchen roll", "lightbulb", "light bulb"]
        case .convenience: ["newspaper", "lottery", "stamps book", "chewing gum"]
        case .pharmacy: ["prescription", "paracetamol", "ibuprofen", "plasters", "hay fever", "antihistamine", "sunscreen", "sun cream", "vitamins", "contact lens", "toothpaste", "medicine", "cough", "lemsip", "calpol", "razor", "shampoo", "deodorant"]
        case .hardware: ["wood stain", "stain", "paint", "screws", "nails", "drill", "sandpaper", "sealant", "silicone", "fuse", "hinge", "rawlplugs", "wall plugs", "filler", "varnish", "brush", "roller", "tape measure", "spirit level", "timber", "decking", "grout", "tiles", "allen key", "spanner", "pliers", "extension lead", "padlock", "key cut", "keys cut"]
        case .garden: ["compost", "seeds", "bulbs", "plant pot", "plants", "potting", "hose", "lawn", "bird seed"]
        case .homeware: ["standing desk", "desk", "shelf", "shelves", "bookcase", "lamp", "rug", "cushion", "duvet", "pillow", "curtains", "frame", "meatballs", "wardrobe", "drawer", "mattress", "alcove"]
        case .electronics: ["charger", "cable", "hdmi", "usb", "headphones", "earbuds", "laptop", "phone case", "screen protector", "printer ink", "ink cartridge", "tv", "router", "adapter"]
        case .cafe: ["latte", "flat white", "croissant", "coffee with", "catch up"]
        case .restaurant: ["book a table", "reservation", "dinner"]
        case .pub: ["pint", "quiz", "creative ideas", "ideas"]
        case .bakery: ["birthday cake", "cake", "sourdough", "pastries", "baguette"]
        case .books: ["book for", "novel", "paperback", "notebook", "birthday card", "card for"]
        case .clothing: ["socks", "shirt", "jeans", "jacket", "shoes", "trainers", "dress", "return the", "refund"]
        case .fuel: ["petrol", "diesel", "fuel", "tyre pressure", "tire pressure", "screenwash", "air for tyres", "car wash"]
        case .gym: ["locker", "towel", "membership", "personal trainer", "protein"]
        case .park: ["walk", "run", "picnic", "feed the ducks"]
        case .library: ["return book", "return the book", "library card", "renew"]
        case .postOffice: ["parcel", "post the", "stamps", "send the", "return label", "package"]
        case .bank: ["cash", "cheque", "deposit", "withdraw"]
        case .transit: ["railcard", "season ticket", "oyster", "top up"]
        case .airport: ["passport", "duty free"]
        case .health: ["appointment", "blood test", "check up", "checkup"]
        case .school: ["permission slip", "pick up the kids", "uniform"]
        case .office: ["laptop charger", "badge", "printer", "meeting"]
        case .home: ["water the plants", "bins", "take out the bins", "feed the cat", "laundry"]
        case .beauty: ["haircut", "trim", "fringe"]
        case .pets: ["dog food", "cat food", "cat litter", "flea", "worming", "treats"]
        case .florist: ["flowers", "bouquet", "roses"]
        case .area, .spot, .sticker, .other: []
        }
    }
}
