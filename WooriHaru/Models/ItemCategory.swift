import Foundation

enum ItemGroup: String, CaseIterable, Identifiable {
    case vegetable = "vegetable"
    case fruit = "fruit"
    case meat = "meat"
    case egg = "egg"
    case seafood = "seafood"
    case dairy = "dairy"
    case grain = "grain"
    case kimchi = "kimchi"
    case sideDish = "side_dish"
    case readyMeal = "ready_meal"
    case noodle = "noodle"
    case cooked = "cooked"
    case canned = "canned"
    case seasoning = "seasoning"
    case bakery = "bakery"
    case snack = "snack"
    case beverage = "beverage"
    case alcohol = "alcohol"
    case coffee = "coffee"
    case health = "health"
    case bathroom = "bathroom"
    case cleaning = "cleaning"
    case household = "household"
    case other = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vegetable: "채소"
        case .fruit: "과일"
        case .meat: "정육"
        case .egg: "계란"
        case .seafood: "수산물"
        case .dairy: "유제품"
        case .grain: "쌀/잡곡"
        case .kimchi: "김치/절임"
        case .sideDish: "반찬/델리"
        case .readyMeal: "간편식"
        case .noodle: "면류"
        case .cooked: "조리식품"
        case .canned: "통조림/소스"
        case .seasoning: "양념"
        case .bakery: "빵/베이커리"
        case .snack: "과자/간식"
        case .beverage: "음료"
        case .alcohol: "주류"
        case .coffee: "커피/차"
        case .health: "건강"
        case .bathroom: "욕실용품"
        case .cleaning: "세탁/청소"
        case .household: "생활잡화"
        case .other: "기타"
        }
    }

    var categories: [ItemCategory] {
        ItemCategory.allCases.filter { $0.group == self }
    }
}

enum ItemCategory: String, CaseIterable, Identifiable {
    // 채소
    case vegetableLeaf = "vegetable_leaf"
    case vegetableRoot = "vegetable_root"
    case vegetableFruit = "vegetable_fruit"
    case vegetableSeasoning = "vegetable_seasoning"
    case vegetableMushroom = "vegetable_mushroom"
    case vegetableCorn = "vegetable_corn"
    case vegetablePepper = "vegetable_pepper"
    case vegetableBroccoli = "vegetable_broccoli"

    // 과일
    case fruitApple = "fruit_apple"
    case fruitCitrus = "fruit_citrus"
    case fruitBanana = "fruit_banana"
    case fruitGrape = "fruit_grape"
    case fruitBerry = "fruit_berry"
    case fruitPeach = "fruit_peach"
    case fruitMelon = "fruit_melon"
    case fruitKiwi = "fruit_kiwi"
    case fruitCherry = "fruit_cherry"
    case fruitPineapple = "fruit_pineapple"
    case fruitLemon = "fruit_lemon"
    case fruitDried = "fruit_dried"

    // 정육
    case meatBeef = "meat_beef"
    case meatPork = "meat_pork"
    case meatChicken = "meat_chicken"
    case meatBacon = "meat_bacon"

    // 계란
    case egg = "egg"

    // 수산물
    case seafoodFish = "seafood_fish"
    case seafoodShrimp = "seafood_shrimp"
    case seafoodCrab = "seafood_crab"
    case seafoodShellfish = "seafood_shellfish"
    case seafoodSquid = "seafood_squid"
    case seafoodSeaweed = "seafood_seaweed"

    // 유제품
    case dairyMilk = "dairy_milk"
    case dairyCheese = "dairy_cheese"
    case dairyButter = "dairy_butter"
    case dairyYogurt = "dairy_yogurt"

    // 쌀/잡곡
    case grainRice = "grain_rice"
    case grainNut = "grain_nut"

    // 김치/절임
    case kimchi = "kimchi"
    case pickle = "pickle"

    // 반찬/델리
    case sideDish = "side_dish"
    case salad = "salad"
    case fishCake = "fish_cake"

    // 간편식
    case mealKit = "meal_kit"
    case instantMeal = "instant_meal"
    case sandwich = "sandwich"

    // 면류
    case noodleRamen = "noodle_ramen"
    case noodlePasta = "noodle_pasta"

    // 조리식품
    case cookedPizza = "cooked_pizza"
    case cookedBurger = "cooked_burger"
    case cookedHotdog = "cooked_hotdog"
    case cookedDumpling = "cooked_dumpling"
    case cookedChicken = "cooked_chicken"
    case cookedFries = "cooked_fries"
    case cookedStirfry = "cooked_stirfry"
    case cookedRiceCake = "cooked_rice_cake"

    // 통조림/소스
    case canned = "canned"

    // 양념
    case seasoningPaste = "seasoning_paste"
    case seasoningSauce = "seasoning_sauce"
    case seasoningOil = "seasoning_oil"
    case seasoningSpice = "seasoning_spice"
    case seasoningHoney = "seasoning_honey"

    // 빵/베이커리
    case bakeryBread = "bakery_bread"
    case bakeryPastry = "bakery_pastry"
    case bakeryCake = "bakery_cake"
    case bakeryDonut = "bakery_donut"
    case bakeryWaffle = "bakery_waffle"

    // 과자/간식
    case snackCookie = "snack_cookie"
    case snackChocolate = "snack_chocolate"
    case snackCandy = "snack_candy"
    case snackJelly = "snack_jelly"
    case snackPopcorn = "snack_popcorn"
    case snackPie = "snack_pie"
    case snackIcecream = "snack_icecream"

    // 음료
    case beverageWater = "beverage_water"
    case beverageSoda = "beverage_soda"
    case beverageSports = "beverage_sports"
    case beverageIce = "beverage_ice"

    // 주류
    case alcoholBeer = "alcohol_beer"
    case alcoholWine = "alcohol_wine"
    case alcoholSoju = "alcohol_soju"
    case alcoholCocktail = "alcohol_cocktail"

    // 커피/차
    case coffee = "coffee"
    case tea = "tea"

    // 건강
    case healthSupplement = "health_supplement"

    // 욕실용품
    case bathroomToothbrush = "bathroom_toothbrush"
    case bathroomSoap = "bathroom_soap"
    case bathroomShampoo = "bathroom_shampoo"
    case bathroomSkincare = "bathroom_skincare"
    case bathroomRazor = "bathroom_razor"
    case bathroomTissue = "bathroom_tissue"

    // 세탁/청소
    case cleaningDetergent = "cleaning_detergent"
    case cleaningTrashBag = "cleaning_trash_bag"
    case cleaningGloves = "cleaning_gloves"

    // 생활잡화
    case householdBattery = "household_battery"
    case householdBulb = "household_bulb"

    // 기타
    case other = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vegetableLeaf: "잎채소"
        case .vegetableRoot: "뿌리채소"
        case .vegetableFruit: "열매채소"
        case .vegetableSeasoning: "양념채소"
        case .vegetableMushroom: "버섯"
        case .vegetableCorn: "옥수수"
        case .vegetablePepper: "고추/피망"
        case .vegetableBroccoli: "브로콜리"
        case .fruitApple: "사과/배"
        case .fruitCitrus: "감귤/오렌지"
        case .fruitBanana: "바나나"
        case .fruitGrape: "포도"
        case .fruitBerry: "딸기/베리"
        case .fruitPeach: "복숭아"
        case .fruitMelon: "수박/멜론"
        case .fruitKiwi: "키위/망고"
        case .fruitCherry: "체리"
        case .fruitPineapple: "파인애플"
        case .fruitLemon: "레몬/라임"
        case .fruitDried: "건과일"
        case .meatBeef: "소고기"
        case .meatPork: "돼지고기"
        case .meatChicken: "닭/오리"
        case .meatBacon: "베이컨/햄"
        case .egg: "계란"
        case .seafoodFish: "생선"
        case .seafoodShrimp: "새우"
        case .seafoodCrab: "게/랍스터"
        case .seafoodShellfish: "조개/굴"
        case .seafoodSquid: "오징어/문어"
        case .seafoodSeaweed: "해조류"
        case .dairyMilk: "우유"
        case .dairyCheese: "치즈"
        case .dairyButter: "버터/크림"
        case .dairyYogurt: "요거트"
        case .grainRice: "쌀/잡곡"
        case .grainNut: "견과류"
        case .kimchi: "김치"
        case .pickle: "장아찌/젓갈"
        case .sideDish: "반찬/조림"
        case .salad: "샐러드"
        case .fishCake: "어묵"
        case .mealKit: "도시락/밀키트"
        case .instantMeal: "즉석밥/카레"
        case .sandwich: "샌드위치"
        case .noodleRamen: "라면"
        case .noodlePasta: "파스타/스파게티"
        case .cookedPizza: "피자"
        case .cookedBurger: "햄버거"
        case .cookedHotdog: "핫도그/소시지"
        case .cookedDumpling: "만두/교자"
        case .cookedChicken: "치킨"
        case .cookedFries: "튀김"
        case .cookedStirfry: "볶음/구이"
        case .cookedRiceCake: "떡/경단"
        case .canned: "통조림"
        case .seasoningPaste: "장류"
        case .seasoningSauce: "소스/드레싱"
        case .seasoningOil: "기름/식초"
        case .seasoningSpice: "향신료/소금"
        case .seasoningHoney: "꿀/시럽"
        case .bakeryBread: "식빵/베이글"
        case .bakeryPastry: "크루아상/페이스트리"
        case .bakeryCake: "케이크"
        case .bakeryDonut: "도넛"
        case .bakeryWaffle: "와플/팬케이크"
        case .snackCookie: "과자/스낵"
        case .snackChocolate: "초콜릿"
        case .snackCandy: "사탕"
        case .snackJelly: "젤리/구미"
        case .snackPopcorn: "팝콘"
        case .snackPie: "파이"
        case .snackIcecream: "아이스크림"
        case .beverageWater: "생수"
        case .beverageSoda: "탄산/주스"
        case .beverageSports: "스포츠음료"
        case .beverageIce: "얼음"
        case .alcoholBeer: "맥주"
        case .alcoholWine: "와인"
        case .alcoholSoju: "소주/청주"
        case .alcoholCocktail: "칵테일/기타"
        case .coffee: "커피"
        case .tea: "차"
        case .healthSupplement: "영양제"
        case .bathroomToothbrush: "칫솔/치약"
        case .bathroomSoap: "비누/바디워시"
        case .bathroomShampoo: "샴푸/린스"
        case .bathroomSkincare: "마스크팩/스킨케어"
        case .bathroomRazor: "면도기"
        case .bathroomTissue: "휴지/티슈"
        case .cleaningDetergent: "세제/섬유유연제"
        case .cleaningTrashBag: "쓰레기봉투"
        case .cleaningGloves: "장갑/수세미"
        case .householdBattery: "배터리"
        case .householdBulb: "전구"
        case .other: "기타"
        }
    }

    var emoji: String {
        switch self {
        case .vegetableLeaf: "🥬"
        case .vegetableRoot: "🥕"
        case .vegetableFruit: "🍅"
        case .vegetableSeasoning: "🧅"
        case .vegetableMushroom: "🍄"
        case .vegetableCorn: "🌽"
        case .vegetablePepper: "🌶️"
        case .vegetableBroccoli: "🥦"
        case .fruitApple: "🍎"
        case .fruitCitrus: "🍊"
        case .fruitBanana: "🍌"
        case .fruitGrape: "🍇"
        case .fruitBerry: "🍓"
        case .fruitPeach: "🍑"
        case .fruitMelon: "🍉"
        case .fruitKiwi: "🥝"
        case .fruitCherry: "🍒"
        case .fruitPineapple: "🍍"
        case .fruitLemon: "🍋"
        case .fruitDried: "🫐"
        case .meatBeef: "🥩"
        case .meatPork: "🍖"
        case .meatChicken: "🍗"
        case .meatBacon: "🥓"
        case .egg: "🥚"
        case .seafoodFish: "🐟"
        case .seafoodShrimp: "🦐"
        case .seafoodCrab: "🦀"
        case .seafoodShellfish: "🦪"
        case .seafoodSquid: "🦑"
        case .seafoodSeaweed: "🌿"
        case .dairyMilk: "🥛"
        case .dairyCheese: "🧀"
        case .dairyButter: "🧈"
        case .dairyYogurt: "🫙"
        case .grainRice: "🌾"
        case .grainNut: "🥜"
        case .kimchi: "🥬"
        case .pickle: "🫙"
        case .sideDish: "🥘"
        case .salad: "🥗"
        case .fishCake: "🍢"
        case .mealKit: "🍱"
        case .instantMeal: "🍛"
        case .sandwich: "🥪"
        case .noodleRamen: "🍜"
        case .noodlePasta: "🍝"
        case .cookedPizza: "🍕"
        case .cookedBurger: "🍔"
        case .cookedHotdog: "🌭"
        case .cookedDumpling: "🥟"
        case .cookedChicken: "🍗"
        case .cookedFries: "🍟"
        case .cookedStirfry: "🍳"
        case .cookedRiceCake: "🍡"
        case .canned: "🥫"
        case .seasoningPaste: "🫗"
        case .seasoningSauce: "🧴"
        case .seasoningOil: "🫒"
        case .seasoningSpice: "🧂"
        case .seasoningHoney: "🍯"
        case .bakeryBread: "🍞"
        case .bakeryPastry: "🥐"
        case .bakeryCake: "🎂"
        case .bakeryDonut: "🍩"
        case .bakeryWaffle: "🧇"
        case .snackCookie: "🍪"
        case .snackChocolate: "🍫"
        case .snackCandy: "🍬"
        case .snackJelly: "🍭"
        case .snackPopcorn: "🍿"
        case .snackPie: "🥧"
        case .snackIcecream: "🍦"
        case .beverageWater: "💧"
        case .beverageSoda: "🥤"
        case .beverageSports: "🧃"
        case .beverageIce: "🧊"
        case .alcoholBeer: "🍺"
        case .alcoholWine: "🍷"
        case .alcoholSoju: "🍶"
        case .alcoholCocktail: "🍸"
        case .coffee: "☕"
        case .tea: "🍵"
        case .healthSupplement: "💊"
        case .bathroomToothbrush: "🪥"
        case .bathroomSoap: "🧼"
        case .bathroomShampoo: "🧴"
        case .bathroomSkincare: "💆"
        case .bathroomRazor: "🪒"
        case .bathroomTissue: "🧻"
        case .cleaningDetergent: "🫧"
        case .cleaningTrashBag: "🗑️"
        case .cleaningGloves: "🧤"
        case .householdBattery: "🔋"
        case .householdBulb: "💡"
        case .other: "📦"
        }
    }

    var group: ItemGroup {
        switch self {
        case .vegetableLeaf, .vegetableRoot, .vegetableFruit, .vegetableSeasoning,
             .vegetableMushroom, .vegetableCorn, .vegetablePepper, .vegetableBroccoli:
            .vegetable
        case .fruitApple, .fruitCitrus, .fruitBanana, .fruitGrape, .fruitBerry,
             .fruitPeach, .fruitMelon, .fruitKiwi, .fruitCherry, .fruitPineapple,
             .fruitLemon, .fruitDried:
            .fruit
        case .meatBeef, .meatPork, .meatChicken, .meatBacon:
            .meat
        case .egg:
            .egg
        case .seafoodFish, .seafoodShrimp, .seafoodCrab, .seafoodShellfish,
             .seafoodSquid, .seafoodSeaweed:
            .seafood
        case .dairyMilk, .dairyCheese, .dairyButter, .dairyYogurt:
            .dairy
        case .grainRice, .grainNut:
            .grain
        case .kimchi, .pickle:
            .kimchi
        case .sideDish, .salad, .fishCake:
            .sideDish
        case .mealKit, .instantMeal, .sandwich:
            .readyMeal
        case .noodleRamen, .noodlePasta:
            .noodle
        case .cookedPizza, .cookedBurger, .cookedHotdog, .cookedDumpling,
             .cookedChicken, .cookedFries, .cookedStirfry, .cookedRiceCake:
            .cooked
        case .canned:
            .canned
        case .seasoningPaste, .seasoningSauce, .seasoningOil, .seasoningSpice, .seasoningHoney:
            .seasoning
        case .bakeryBread, .bakeryPastry, .bakeryCake, .bakeryDonut, .bakeryWaffle:
            .bakery
        case .snackCookie, .snackChocolate, .snackCandy, .snackJelly, .snackPopcorn, .snackPie, .snackIcecream:
            .snack
        case .beverageWater, .beverageSoda, .beverageSports, .beverageIce:
            .beverage
        case .alcoholBeer, .alcoholWine, .alcoholSoju, .alcoholCocktail:
            .alcohol
        case .coffee, .tea:
            .coffee
        case .healthSupplement:
            .health
        case .bathroomToothbrush, .bathroomSoap, .bathroomShampoo,
             .bathroomSkincare, .bathroomRazor, .bathroomTissue:
            .bathroom
        case .cleaningDetergent, .cleaningTrashBag, .cleaningGloves:
            .cleaning
        case .householdBattery, .householdBulb:
            .household
        case .other:
            .other
        }
    }
}
