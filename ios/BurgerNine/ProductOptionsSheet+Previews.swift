import SwiftUI

#if DEBUG
private enum ProductOptionsPreviewData {
    static let accent = Color(red: 0.99, green: 0.72, blue: 0.10)

    static let sauceNone = MenuOptionItem(id: "sauce-none", name: "SANS SAUCE", price: 0, position: 0)
    static let sauceCherry = MenuOptionItem(id: "sauce-cherry", name: "DADA CERISE", price: 0, position: 1)
    static let sauceSpicy = MenuOptionItem(id: "sauce-spicy", name: "MAYO SPICY MAISON", price: 0, position: 2)
    static let sauceLong = MenuOptionItem(id: "sauce-long", name: "SAUCE BLANCHE CURRY CIBOULETTE", price: 0, position: 3)

    static let sauceRequired = MenuOptionGroup(
        id: "sauce-required",
        name: "Sauce crousty",
        min: 1,
        max: 1,
        allowsMultiple: false,
        position: 0,
        items: [sauceNone, sauceCherry, sauceSpicy, sauceLong]
    )

    static let drinkRequired = MenuOptionGroup(
        id: "drink-required",
        name: "Boisson",
        min: 1,
        max: 1,
        allowsMultiple: false,
        position: 1,
        items: [
            MenuOptionItem(id: "drink-coke", name: "Coca-Cola", price: 0, position: 0),
            MenuOptionItem(id: "drink-oasis", name: "Oasis Tropical", price: 0, position: 1),
            MenuOptionItem(id: "drink-water", name: "Eau plate", price: 0, position: 2)
        ]
    )

    static let supplements = MenuOptionGroup(
        id: "supplements",
        name: "Sauce Supplément",
        min: 0,
        max: 4,
        allowsMultiple: true,
        position: 2,
        items: [
            MenuOptionItem(id: "supp-thai", name: "Supp Sauce Thai", price: 0.5, position: 0),
            MenuOptionItem(id: "supp-house", name: "Supp Sauce Maison", price: 0.5, position: 1),
            MenuOptionItem(id: "supp-spicy", name: "Supp Sauce Piquante", price: 0.5, position: 2),
            MenuOptionItem(id: "supp-sweet", name: "Supp Sauce Sucrée", price: 0.5, position: 3)
        ]
    )

    static let barquetteRiz = MenuItem(
        id: "preview-barquette-riz",
        name: "Barquette Riz",
        description: "Barquette Riz Blanc",
        price: 5,
        image: "",
        tag: "Preview",
        optionGroups: [supplements]
    )

    static let extrasLong = MenuOptionGroup(
        id: "extras-long",
        name: "Ajouts croustillants",
        min: 0,
        max: 3,
        allowsMultiple: true,
        position: 3,
        items: [
            MenuOptionItem(id: "extra-1", name: "Oignons crispy maison", price: 0.8, position: 0),
            MenuOptionItem(id: "extra-2", name: "Double portion frites cheddar", price: 2.5, position: 1),
            MenuOptionItem(id: "extra-3", name: "Pickles acidulés", price: 0.7, position: 2),
            MenuOptionItem(id: "extra-4", name: "Jalapeños", price: 0.7, position: 3),
            MenuOptionItem(id: "extra-5", name: "Mozza sticks", price: 2.9, position: 4)
        ]
    )

    static func item(
        name: String = "Crousty MIXTE",
        description: String = "Crousty Mixte (Blanche/Curry)",
        price: Double = 9,
        groups: [MenuOptionGroup] = [sauceRequired, supplements]
    ) -> MenuItem {
        MenuItem(
            id: "preview-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            name: name,
            description: description,
            price: price,
            image: "",
            tag: "Preview",
            optionGroups: groups
        )
    }

    static func sheet(
        _ item: MenuItem,
        selected: [MenuOptionGroup.ID: [MenuOptionItem.ID: Int]] = [:],
        expanded: Set<MenuOptionGroup.ID> = []
    ) -> some View {
        ProductOptionsSheet(
            item: item,
            accent: accent,
            initialSelectedOptionCounts: selected,
            initialExpandedOptionGroupIDs: expanded
        ) { _, _ in }
        .preferredColorScheme(.dark)
    }
}

#Preview("Picker 01 - Required Empty") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(groups: [
            ProductOptionsPreviewData.sauceRequired,
            ProductOptionsPreviewData.supplements
        ])
    )
}

#Preview("Picker 02 - Required Picked Collapsed") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(groups: [
            ProductOptionsPreviewData.sauceRequired,
            ProductOptionsPreviewData.supplements
        ]),
        selected: [ProductOptionsPreviewData.sauceRequired.id: [ProductOptionsPreviewData.sauceNone.id: 1]]
    )
}

#Preview("Picker 03 - Required Picked Expanded") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(groups: [
            ProductOptionsPreviewData.sauceRequired,
            ProductOptionsPreviewData.supplements
        ]),
        selected: [ProductOptionsPreviewData.sauceRequired.id: [ProductOptionsPreviewData.sauceNone.id: 1]],
        expanded: [ProductOptionsPreviewData.sauceRequired.id]
    )
}

#Preview("Picker 04 - Long Selected Label") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(groups: [
            ProductOptionsPreviewData.sauceRequired,
            ProductOptionsPreviewData.supplements
        ]),
        selected: [ProductOptionsPreviewData.sauceRequired.id: [ProductOptionsPreviewData.sauceLong.id: 1]]
    )
}

#Preview("Picker 05 - Multi Select Filled") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(groups: [
            ProductOptionsPreviewData.sauceRequired,
            ProductOptionsPreviewData.supplements
        ]),
        selected: [
            ProductOptionsPreviewData.sauceRequired.id: [ProductOptionsPreviewData.sauceCherry.id: 1],
            ProductOptionsPreviewData.supplements.id: ["supp-thai": 1, "supp-cheddar": 1, "supp-chicken": 1]
        ]
    )
}

#Preview("Picker 06 - No Required Group") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(
            name: "Tenders Box",
            description: "Tenders croustillants, frites maison",
            price: 11.5,
            groups: [ProductOptionsPreviewData.supplements, ProductOptionsPreviewData.extrasLong]
        )
    )
}

#Preview("Picker 07 - Two Required Groups") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(groups: [
            ProductOptionsPreviewData.sauceRequired,
            ProductOptionsPreviewData.drinkRequired,
            ProductOptionsPreviewData.supplements
        ]),
        selected: [
            ProductOptionsPreviewData.sauceRequired.id: [ProductOptionsPreviewData.sauceSpicy.id: 1],
            ProductOptionsPreviewData.drinkRequired.id: ["drink-oasis": 1]
        ]
    )
}

#Preview("Picker 08 - Dense Options") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(groups: [
            ProductOptionsPreviewData.sauceRequired,
            ProductOptionsPreviewData.drinkRequired,
            ProductOptionsPreviewData.supplements,
            ProductOptionsPreviewData.extrasLong
        ])
    )
}

#Preview("Picker 09 - Tiny Product Copy") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(
            name: "Wrap",
            description: "",
            price: 6.9,
            groups: [ProductOptionsPreviewData.sauceRequired]
        )
    )
}

#Preview("Picker 11 - Supplement Quantities") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.barquetteRiz,
        selected: [ProductOptionsPreviewData.supplements.id: ["supp-thai": 2]]
    )
}

#Preview("Picker 10 - Long Product Copy") {
    ProductOptionsPreviewData.sheet(
        ProductOptionsPreviewData.item(
            name: "Crousty Maxi Mixte XL",
            description: "Pain toasté, poulet curry, viande marinée, crudités, cheddar fondu et frites croustillantes.",
            price: 13.9,
            groups: [
                ProductOptionsPreviewData.sauceRequired,
                ProductOptionsPreviewData.drinkRequired,
                ProductOptionsPreviewData.supplements,
                ProductOptionsPreviewData.extrasLong
            ]
        ),
        selected: [ProductOptionsPreviewData.sauceRequired.id: [ProductOptionsPreviewData.sauceNone.id: 1]]
    )
}
#endif
