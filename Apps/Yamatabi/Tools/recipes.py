"""山ごはんのレシピを定義し、検証して JSON に書き出す。

レシピは山で作ることを前提に自作したもので、レシピサイトからの引き写しではない。

材料は id・数量・単位で持つ。同じ材料は単位を1つに固定し、
買い出しリストで足し合わせられるようにする。「少々」のように量を決めないものは
数量を持たせない（quantity を null にする）。
"""
import json
import sys
from collections import defaultdict

# 材料の分類。買い出しリストを売り場ごとにまとめるために使う。
AISLE_PRODUCE = "野菜・果物"
AISLE_MEAT = "肉・魚"
AISLE_DAIRY = "乳製品・卵"
AISLE_DRY = "乾物・保存食"
AISLE_SEASONING = "調味料"
AISLE_BREAD = "パン・主食"

# 材料の辞書。単位はここで1つに固定する。
INGREDIENTS = {
    "tamanegi":      ("玉ねぎ", AISLE_PRODUCE, "個"),
    "ninjin":        ("にんじん", AISLE_PRODUCE, "本"),
    "jagaimo":       ("じゃがいも", AISLE_PRODUCE, "個"),
    "ninniku":       ("にんにく", AISLE_PRODUCE, "片"),
    "shouga":        ("しょうが", AISLE_PRODUCE, "片"),
    "kinoko":        ("しめじ", AISLE_PRODUCE, "パック"),
    "kyabetsu":      ("キャベツ", AISLE_PRODUCE, "枚"),
    "naganegi":     ("長ねぎ", AISLE_PRODUCE, "本"),
    "mini_tomato":   ("ミニトマト", AISLE_PRODUCE, "個"),
    "lemon":         ("レモン", AISLE_PRODUCE, "個"),
    "paseri":        ("パセリ", AISLE_PRODUCE, "枝"),

    "buta_bara":     ("豚バラ肉", AISLE_MEAT, "g"),
    "tori_momo":     ("鶏もも肉", AISLE_MEAT, "g"),
    "beikon":        ("ベーコン", AISLE_MEAT, "g"),
    "souseiji":      ("ソーセージ", AISLE_MEAT, "本"),
    "saba_kan":      ("さば水煮缶", AISLE_DRY, "缶"),
    "ebi":           ("むきえび", AISLE_MEAT, "g"),
    "asari":         ("あさり水煮缶", AISLE_DRY, "缶"),

    "tamago":        ("卵", AISLE_DAIRY, "個"),
    "chiizu":        ("とろけるチーズ", AISLE_DAIRY, "g"),
    "funmatsu_chiizu": ("粉チーズ", AISLE_DAIRY, "g"),
    "bataa":         ("バター", AISLE_DAIRY, "g"),
    "nama_kuriimu":  ("生クリーム", AISLE_DAIRY, "ml"),

    "kome":          ("無洗米", AISLE_DRY, "合"),
    "pasta":         ("スパゲッティ", AISLE_DRY, "g"),
    "kuskus":        ("クスクス", AISLE_DRY, "g"),
    "baguette":      ("バゲット", AISLE_BREAD, "cm"),
    "tortilla":      ("トルティーヤ", AISLE_BREAD, "枚"),
    "kouya_doufu":   ("高野豆腐", AISLE_DRY, "枚"),
    "doraifuruutsu": ("ドライいちじく", AISLE_DRY, "個"),
    "kurumi":        ("くるみ", AISLE_DRY, "g"),
    "torinikuno_dashi": ("固形コンソメ", AISLE_DRY, "個"),
    "kona_dashi":    ("和風だしの素", AISLE_DRY, "小さじ"),
    "toritama_soup": ("鶏がらスープの素", AISLE_DRY, "小さじ"),
    "kiri_mochi":    ("切り餅", AISLE_DRY, "個"),
    "harusame":      ("春雨", AISLE_DRY, "g"),
    "kanzume_tomato": ("カットトマト缶", AISLE_DRY, "缶"),
    "kokonattsu":    ("ココナッツミルク", AISLE_DRY, "ml"),
    "kare_rou":      ("カレールウ", AISLE_DRY, "かけ"),

    "orribu_oil":    ("オリーブオイル", AISLE_SEASONING, "大さじ"),
    "goma_abura":    ("ごま油", AISLE_SEASONING, "大さじ"),
    "shouyu":        ("しょうゆ", AISLE_SEASONING, "大さじ"),
    "miso":          ("みそ", AISLE_SEASONING, "大さじ"),
    "mirin":         ("みりん", AISLE_SEASONING, "大さじ"),
    "sake":          ("料理酒", AISLE_SEASONING, "大さじ"),
    "satou":         ("砂糖", AISLE_SEASONING, "小さじ"),
    "shio":          ("塩", AISLE_SEASONING, None),
    "koshou":        ("こしょう", AISLE_SEASONING, None),
    "kurokoshou":    ("粗挽き黒こしょう", AISLE_SEASONING, None),
    "nanmi":         ("ナンプラー", AISLE_SEASONING, "小さじ"),
    "kare_ko":       ("カレー粉", AISLE_SEASONING, "小さじ"),
    "hachimitsu":    ("はちみつ", AISLE_SEASONING, "大さじ"),
}

# 調理器具。持っている器具で絞り込めるようにする。
GEAR_STOVE = "バーナー"
GEAR_POT = "クッカー"
GEAR_MESTIN = "メスティン"
GEAR_SKILLET = "フライパン"

RECIPES = [
    {
        "id": "mestin-takikomi",
        "name": "さばと生姜の炊き込みごはん",
        "summary": "さば缶の汁ごと米に入れて炊く。山頂で炊きたてが食べられる、手間の割に贅沢な一品。",
        "gear": [GEAR_STOVE, GEAR_MESTIN],
        "cookingMinutes": 30,
        "effort": 3,
        "needsCooler": False,
        "servings": 2,
        "ingredients": [
            ("kome", 1), ("saba_kan", 1), ("shouga", 1),
            ("shouyu", 1), ("sake", 1), ("kona_dashi", 1), ("naganegi", 0.5),
        ],
        "steps": [
            "米1合をメスティンに入れ、水200mlを加えて30分ほど吸水させる（歩きながらで良い）。",
            "しょうがを千切り、長ねぎを小口切りにする。家で切って持参しても良い。",
            "さば缶を汁ごと加え、しょうゆ・酒・だしの素・しょうがを入れて軽く混ぜる。",
            "ふたをして中火。沸騰したら弱火で12分、火を止めて10分蒸らす。",
            "長ねぎを散らし、さばを軽くほぐして混ぜる。",
        ],
        "tips": "吸水をさぼると芯が残る。登山口で水を入れて歩き出すと、山頂で丁度良い。",
    },
    {
        "id": "skillet-ajillo",
        "name": "えびときのこのアヒージョ",
        "summary": "オイルで煮るだけ。残ったオイルにバゲットを浸すところまでが本番。",
        "gear": [GEAR_STOVE, GEAR_SKILLET],
        "cookingMinutes": 15,
        "effort": 2,
        "needsCooler": True,
        "servings": 2,
        "ingredients": [
            ("ebi", 120), ("kinoko", 1), ("ninniku", 2),
            ("orribu_oil", 6), ("shio", None), ("kurokoshou", None), ("baguette", 20),
        ],
        "steps": [
            "にんにくを薄切り、しめじをほぐす。えびは水気を切っておく。",
            "フライパンにオリーブオイルとにんにくを入れ、弱火でじっくり香りを出す。",
            "きのことえびを加え、塩をふって弱火のまま5分ほど煮る。",
            "黒こしょうを挽き、バゲットを添える。",
        ],
        "tips": "えびは保冷が要る。凍らせて持つと保冷剤を兼ねられる。",
    },
    {
        "id": "pot-tomato-stew",
        "name": "ベーコンと豆のトマト煮込み",
        "summary": "缶詰中心で保冷が要らない。冷えた体に一番効く。",
        "gear": [GEAR_STOVE, GEAR_POT],
        "cookingMinutes": 20,
        "effort": 2,
        "needsCooler": False,
        "servings": 2,
        "ingredients": [
            ("kanzume_tomato", 1), ("beikon", 60), ("tamanegi", 0.5),
            ("ninniku", 1), ("torinikuno_dashi", 1),
            ("orribu_oil", 1), ("shio", None), ("kurokoshou", None), ("funmatsu_chiizu", 10),
        ],
        "steps": [
            "玉ねぎとにんにくをみじん切り、ベーコンを 短冊に切る。",
            "オリーブオイルで玉ねぎ・にんにく・ベーコンを炒める。",
            "トマト缶とコンソメを入れ、10分ほど煮詰める。",
            "塩こしょうで整え、粉チーズをかける。",
        ],
        "tips": "煮詰めるほど旨い。水を足さず、トマト缶の水分だけで煮る。",
    },
    {
        "id": "mestin-pasta-carbonara",
        "name": "メスティンのカルボナーラ",
        "summary": "茹で汁を捨てない作り方。水の持ち上げを減らしつつ、濃厚に仕上がる。",
        "gear": [GEAR_STOVE, GEAR_MESTIN],
        "cookingMinutes": 20,
        "effort": 4,
        "needsCooler": True,
        "servings": 1,
        "ingredients": [
            ("pasta", 100), ("beikon", 40), ("tamago", 1),
            ("funmatsu_chiizu", 20), ("nama_kuriimu", 50),
            ("ninniku", 1), ("orribu_oil", 1), ("kurokoshou", None), ("shio", None),
        ],
        "steps": [
            "卵・粉チーズ・生クリームを先に混ぜ、ソースを作っておく。",
            "メスティンに水300mlと塩を入れ、半分に折ったパスタを茹でる（表示時間＋1分）。",
            "水分がほぼ無くなったら、ベーコンとにんにくを加えて軽く炒める。",
            "**火から下ろしてから**ソースを加え、余熱で混ぜる。",
            "黒こしょうを多めに挽く。",
        ],
        "tips": "火にかけたままソースを入れると卵が固まる。必ず下ろしてから。",
    },
    {
        "id": "pot-thai-curry",
        "name": "ココナッツとえびのグリーンカレー風",
        "summary": "ココナッツミルクとナンプラーで、山の上とは思えない香りになる。",
        "gear": [GEAR_STOVE, GEAR_POT],
        "cookingMinutes": 20,
        "effort": 3,
        "needsCooler": True,
        "servings": 2,
        "ingredients": [
            ("kokonattsu", 200), ("ebi", 100), ("kinoko", 1),
            ("kare_ko", 2), ("nanmi", 2), ("satou", 1),
            ("ninniku", 1), ("goma_abura", 1), ("kome", 1),
        ],
        "steps": [
            "別鍋かメスティンで米を炊いておく（無洗米1合・水200ml・弱火12分・蒸らし10分）。",
            "ごま油でにんにくときのこを炒める。",
            "カレー粉を加えて油となじませ、香りを立てる。",
            "ココナッツミルクとえびを入れ、5分煮る。",
            "ナンプラーと砂糖で味を決める。",
        ],
        "tips": "カレー粉を油で炒めるひと手間で、香りがまるで変わる。",
    },
    {
        "id": "skillet-ahijo-chicken",
        "name": "鶏もも肉のレモンバター焼き",
        "summary": "焼くだけだが、レモンとバターで一気に料理らしくなる。",
        "gear": [GEAR_STOVE, GEAR_SKILLET],
        "cookingMinutes": 20,
        "effort": 2,
        "needsCooler": True,
        "servings": 2,
        "ingredients": [
            ("tori_momo", 250), ("bataa", 15), ("lemon", 0.5),
            ("ninniku", 1), ("shio", None), ("kurokoshou", None), ("paseri", 1),
        ],
        "steps": [
            "鶏ももは家で一口大に切り、塩こしょうをして持参する。",
            "フライパンで皮目から焼き、焼き色が付いたら返す。",
            "にんにくとバターを加え、溶けたバターを鶏にかけながら焼く。",
            "レモンを搾り、パセリを散らす。",
        ],
        "tips": "家で下味を付けておくと、山での手順が3つに減る。",
    },
    {
        "id": "pot-kouya-nimono",
        "name": "高野豆腐ときのこの含め煮",
        "summary": "乾物中心で荷が軽い。汁まで飲める、体が温まる一品。",
        "gear": [GEAR_STOVE, GEAR_POT],
        "cookingMinutes": 20,
        "effort": 2,
        "needsCooler": False,
        "servings": 2,
        "ingredients": [
            ("kouya_doufu", 2), ("kinoko", 1), ("ninjin", 0.5),
            ("kona_dashi", 1), ("shouyu", 1), ("mirin", 1), ("satou", 1),
        ],
        "steps": [
            "水400mlにだしの素を溶かし、火にかける。",
            "高野豆腐を割り入れ、にんじんときのこを加える。",
            "しょうゆ・みりん・砂糖を入れ、10分ほど煮る。",
            "高野豆腐が汁を吸って膨らんだら出来上がり。",
        ],
        "tips": "高野豆腐は割って入れると早く戻る。汁を多めにして残りを翌朝の雑炊にしても良い。",
    },
    {
        "id": "mestin-mushi-pork",
        "name": "豚バラとキャベツの重ね蒸し",
        "summary": "重ねて蒸すだけ。水をほとんど使わず、野菜の水分で火を通す。",
        "gear": [GEAR_STOVE, GEAR_MESTIN],
        "cookingMinutes": 20,
        "effort": 2,
        "needsCooler": True,
        "servings": 2,
        "ingredients": [
            ("buta_bara", 200), ("kyabetsu", 4), ("shouga", 1),
            ("sake", 2), ("shouyu", 1), ("goma_abura", 1), ("shio", None),
        ],
        "steps": [
            "キャベツをちぎり、メスティンに敷く。",
            "豚バラとしょうがの千切りを重ね、塩をふる。これを2段くり返す。",
            "酒を回しかけ、ふたをして弱火で12分蒸す。",
            "しょうゆとごま油をかける。",
        ],
        "tips": "焦げそうなら水を大さじ2足す。キャベツを下に敷くのが焦げ防止になる。",
    },
    {
        "id": "pot-ajillo-asari",
        "name": "あさりと白いんげんのスープ",
        "summary": "缶詰だけで作れるのに出汁が出る。パンを浸して食べたい。",
        "gear": [GEAR_STOVE, GEAR_POT],
        "cookingMinutes": 15,
        "effort": 1,
        "needsCooler": False,
        "servings": 2,
        "ingredients": [
            ("asari", 1), ("beikon", 40), ("tamanegi", 0.5), ("ninniku", 1),
            ("orribu_oil", 1), ("torinikuno_dashi", 1),
            ("kurokoshou", None), ("baguette", 20),
        ],
        "steps": [
            "玉ねぎとにんにくをみじん切りにし、オリーブオイルで炒める。",
            "ベーコンを加えて炒め、水300mlとコンソメを入れる。",
            "あさりを汁ごと加え、5分煮る。",
            "黒こしょうを挽き、バゲットを添える。",
        ],
        "tips": "あさりの汁に塩気があるので、味見してから塩を足す。",
    },
    {
        "id": "skillet-tortilla",
        "name": "ソーセージとチーズのケサディーヤ",
        "summary": "挟んで焼くだけ。手が汚れず、歩きながらでも食べられる。",
        "gear": [GEAR_STOVE, GEAR_SKILLET],
        "cookingMinutes": 10,
        "effort": 1,
        "needsCooler": True,
        "servings": 2,
        "ingredients": [
            ("tortilla", 2), ("souseiji", 3), ("chiizu", 60),
            ("tamanegi", 0.25), ("kare_ko", 1), ("orribu_oil", 1),
        ],
        "steps": [
            "ソーセージを輪切り、玉ねぎを薄切りにする。",
            "フライパンで具を炒め、カレー粉をふる。",
            "トルティーヤにチーズと具をのせ、半分に折る。",
            "両面を焼き、チーズが溶けたら切り分ける。",
        ],
        "tips": "カレー粉はひとふりで味が締まる。入れすぎない。",
    },
    {
        "id": "pot-zousui",
        "name": "きのこと卵の雑炊",
        "summary": "前夜の残りや朝に。短時間で作れて、胃にやさしい。",
        "gear": [GEAR_STOVE, GEAR_POT],
        "cookingMinutes": 15,
        "effort": 1,
        "needsCooler": True,
        "servings": 1,
        "ingredients": [
            ("kome", 0.5), ("tamago", 1), ("kinoko", 0.5),
            ("kona_dashi", 1), ("shouyu", 0.5), ("naganegi", 0.5), ("shio", None),
        ],
        "steps": [
            "水400mlにだしの素を溶かし、米ときのこを入れて中火で15分煮る。",
            "しょうゆで味を整える。",
            "溶き卵を回し入れ、ふたをして1分蒸らす。",
            "長ねぎを散らす。",
        ],
        "tips": "前夜に炊いた米が残っていれば、5分で作れる。",
    },
    {
        "id": "pot-mochi-shiruko",
        "name": "くるみといちじくの甘い雑煮",
        "summary": "甘いものが欲しくなる行動後に。乾物だけで作れる。",
        "gear": [GEAR_STOVE, GEAR_POT],
        "cookingMinutes": 10,
        "effort": 1,
        "needsCooler": False,
        "servings": 2,
        "ingredients": [
            ("kiri_mochi", 2), ("doraifuruutsu", 4), ("kurumi", 20),
            ("hachimitsu", 2), ("shio", None),
        ],
        "steps": [
            "水300mlを沸かし、刻んだいちじくを入れて5分煮る。",
            "切り餅を加え、柔らかくなるまで煮る。",
            "はちみつと塩ひとつまみで味を決める。",
            "砕いたくるみを散らす。",
        ],
        "tips": "塩をひとつまみ入れると甘さが立つ。",
    },
]


def build():
    recipes = []
    problems = []

    for recipe in RECIPES:
        ingredients = []
        for item in recipe["ingredients"]:
            identifier, quantity = item
            if identifier not in INGREDIENTS:
                problems.append(f"{recipe['id']}: 未定義の材料 {identifier}")
                continue
            name, aisle, unit = INGREDIENTS[identifier]
            if unit is None and quantity is not None:
                problems.append(f"{recipe['id']}: {name} は数量を持たない材料")
            if unit is not None and quantity is None:
                problems.append(f"{recipe['id']}: {name} に数量が無い")
            ingredients.append({
                "id": identifier,
                "name": name,
                "aisle": aisle,
                "quantity": quantity,
                "unit": unit,
            })

        if not recipe["steps"]:
            problems.append(f"{recipe['id']}: 手順が空")

        recipes.append({
            "id": recipe["id"],
            "name": recipe["name"],
            "summary": recipe["summary"],
            "gear": recipe["gear"],
            "cookingMinutes": recipe["cookingMinutes"],
            "effort": recipe["effort"],
            "needsCooler": recipe["needsCooler"],
            "servings": recipe["servings"],
            "ingredients": ingredients,
            "steps": recipe["steps"],
            "tips": recipe["tips"],
        })

    # 同じ材料が複数の単位で使われていないか
    units = defaultdict(set)
    for recipe in recipes:
        for ingredient in recipe["ingredients"]:
            units[ingredient["id"]].add(ingredient["unit"])
    for identifier, found in units.items():
        if len(found) > 1:
            problems.append(f"材料 {identifier} の単位が揃っていない: {found}")

    identifiers = [r["id"] for r in recipes]
    if len(identifiers) != len(set(identifiers)):
        problems.append("レシピIDが重複している")

    return recipes, problems


def main(out_path):
    recipes, problems = build()

    if problems:
        print("検証で問題が見つかりました:")
        for problem in problems:
            print("  -", problem)
        sys.exit(1)

    with open(out_path, "w", encoding="utf-8") as out:
        json.dump(recipes, out, ensure_ascii=False, separators=(",", ":"))

    shared = defaultdict(list)
    for recipe in recipes:
        for ingredient in recipe["ingredients"]:
            shared[ingredient["id"]].append(recipe["id"])

    print(f"レシピ: {len(recipes)} 件")
    print(f"材料の種類: {len(shared)}")
    print(f"要保冷: {sum(1 for r in recipes if r['needsCooler'])} 件")
    print("調理時間:", min(r["cookingMinutes"] for r in recipes), "〜",
          max(r["cookingMinutes"] for r in recipes), "分")
    print("\n--- 複数のレシピで使う材料（合算の確認用）---")
    for identifier, used in sorted(shared.items(), key=lambda x: -len(x[1]))[:5]:
        if len(used) > 1:
            print(f"  {INGREDIENTS[identifier][0]}: {len(used)}件 {used[:3]}")


if __name__ == "__main__":
    main(sys.argv[1])
