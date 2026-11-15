"""国土地理院「日本の主な山岳標高」GeoJSON を、アプリが読む JSON に変換する。

出典: 国土地理院「日本の主な山岳標高」
https://www.gsi.go.jp/kihonjohochousa/kihonjohochousa41139.html
"""
import json
import sys

# 日本百名山（深田久弥）。国土地理院のデータには百名山の情報が無いため、山名で突き合わせる。
# 地理院側の表記ゆれ（五竜→五龍 など）は別名を並べて吸収する。
HYAKUMEIZAN_BY_NAME = [
    ["利尻山"], ["羅臼岳"], ["斜里岳"], ["雌阿寒岳"],
    ["大雪山（ヌタプカウシペ）", "大雪山"], ["トムラウシ山"],
    ["十勝岳"], ["幌尻岳"], ["羊蹄山"],
    ["岩木山"], ["八甲田山"], ["八幡平"], ["岩手山"], ["早池峰山"],
    ["鳥海山"], ["月山"], ["蔵王山"], ["飯豊山"],
    ["安達太良山"], ["磐梯山"], ["那須岳"],
    ["平ヶ岳"], ["巻機山"], ["燧ヶ岳"], ["至仏山"],
    ["谷川岳"], ["雨飾山"], ["苗場山"], ["妙高山"], ["火打山"], ["高妻山"],
    ["男体山"], ["皇海山"], ["武尊山"], ["赤城山"],
    ["四阿山"], ["浅間山"], ["筑波山"],
    ["白馬岳"], ["五龍岳"], ["鹿島槍ヶ岳"], ["剱岳"], ["立山"], ["薬師岳"],
    ["黒部五郎岳"], ["水晶岳"], ["鷲羽岳"], ["槍ヶ岳"], ["穂高岳", "奥穂高岳"],     ["常念岳"], ["笠ヶ岳"], ["焼岳"], ["乗鞍岳"], ["御嶽山"],
    ["美ヶ原"], ["霧ヶ峰"], ["蓼科山"], ["八ヶ岳"],
    ["両神山"], ["雲取山"], ["甲武信ヶ岳"], ["金峰山"], ["瑞牆山"],
    ["大菩薩嶺"], ["丹沢山"], ["富士山"], ["天城山"],
    ["空木岳"], ["恵那山"],
    ["仙丈ヶ岳"], ["北岳"], ["間ノ岳"], ["塩見岳"],
    ["荒川岳"], ["赤石岳"], ["聖岳"], ["光岳"],
    ["白山"], ["荒島岳"], ["伊吹山"], ["大台ヶ原山"], ["八経ヶ岳"],
    ["大山"], ["剣山"], ["石鎚山"],
    ["九重山", "くじゅう連山"], ["祖母山"], ["阿蘇山"], ["霧島山"],
    ["開聞岳"], ["宮之浦岳"],
]

# 地理院の山名だけでは区別できないもの。山名と標高の組で特定する。
# 「駒ヶ岳」は会津・越後・木曽・甲斐がすべて同じ名前で登録されているため。
HYAKUMEIZAN_BY_NAME_AND_ELEVATION = {
    ("駒ヶ岳", 2133): "会津駒ヶ岳",
    ("駒ヶ岳", 2003): "越後駒ヶ岳",
    ("駒ヶ岳", 2956): "木曽駒ヶ岳",
    ("駒ヶ岳", 2967): "甲斐駒ヶ岳",
    ("観音ヶ岳", 2841): "鳳凰山",     # 鳳凰三山の最高峰
    ("西吾妻山", 2035): "吾妻山",      # 吾妻連峰の最高峰
    ("白根山", 2578): "日光白根山",    # 草津白根山（2160m）と同名のため標高で区別
    ("白根山", 2160): "草津白根山",
    ("赤岳", 2899): "八ヶ岳",        # 八ヶ岳連峰の最高峰
    ("朝日岳", 1870): "大朝日岳",     # 群馬・山梨の朝日岳と同名のため標高で区別
    ("東岳", 3141): "荒川岳",         # 悪沢岳。荒川三山の最高峰だが別の索引番号で登録されている
}


def split_name(value):
    """「蔵王山＜熊野岳＞」→ ("蔵王山", "熊野岳")"""
    if "＜" in value:
        base, _, rest = value.partition("＜")
        return base, rest.rstrip("＞")
    return value, None


def strip_alias(value):
    """「利尻山（利尻富士）」→ "利尻山"。照合用に括弧の別名を落とす。"""
    return value.split("（")[0] if "（" in value else value


def searchable_kana(value):
    """よみを検索用にならす。
    「ざおうざん（ざおうさん）＜くまのだけ＞」→「ざおうざん ざおうさん くまのだけ」"""
    for char in "＜＞（）()":
        value = value.replace(char, " ")
    return " ".join(value.split())


def index_group(index_number):
    """「204-3」→「204」。同じ山の複数の山頂をまとめるための鍵。"""
    return str(index_number).split("-")[0]


def main(src, dst):
    features = json.load(open(src, encoding="utf-8"))["features"]

    alias_to_peak = {}
    for group in HYAKUMEIZAN_BY_NAME:
        for alias in group:
            alias_to_peak[alias] = group[0]

    # --- 1周目: 百名山に当たる地点を見つけ、その山（索引番号のまとまり）を控える ---
    matched_groups = {}   # 索引番号の基部 -> 百名山としての呼び名
    matched_peaks = set()

    for feature in features:
        props = feature["properties"]
        name, _ = split_name(props["山名＜山頂名＞"])
        name = strip_alias(name)
        elevation = int(props["標高値(m)"])

        peak = (
            HYAKUMEIZAN_BY_NAME_AND_ELEVATION.get((name, elevation))
            or alias_to_peak.get(name)
        )
        if peak:
            matched_groups[index_group(props["索引番号"])] = peak
            matched_peaks.add(peak)

    # --- 2周目: 変換する。副峰（蔵王山＜刈田岳＞など）も同じ山として扱う ---
    mountains = []
    for feature in features:
        props = feature["properties"]
        raw_name = props["山名＜山頂名＞"]
        name, peak_name = split_name(raw_name)

        mountains.append({
            "id": str(props["索引番号"]),
            "name": strip_alias(name),
            "peak": peak_name,
            "kana": searchable_kana(props["山名よみ＜山頂名よみ＞"]),
            "elevation": int(props["標高値(m)"]),
            "prefectures": props["都道府県"].split(),
            "latitude": float(props["緯度"]),
            "longitude": float(props["経度"]),
            "isHyakumeizan": index_group(props["索引番号"]) in matched_groups,
        })

    # 標高の高い順。アプリ側で毎回並べ替えずに済む。
    mountains.sort(key=lambda m: -m["elevation"])

    with open(dst, "w", encoding="utf-8") as out:
        json.dump(mountains, out, ensure_ascii=False, separators=(",", ":"))

    # --- 検証結果 ---
    expected = {g[0] for g in HYAKUMEIZAN_BY_NAME} | set(HYAKUMEIZAN_BY_NAME_AND_ELEVATION.values())
    expected.discard("草津白根山")  # 下で百名山として数える
    expected.add("草津白根山")
    unmatched = sorted(expected - matched_peaks)

    print(f"山の総数: {len(mountains)}")
    print(f"照合できた百名山: {len(matched_peaks)}/{len(expected)}")
    print(f"百名山フラグの地点数: {sum(1 for m in mountains if m['isHyakumeizan'])}"
          f"（副峰を含むため100より多い）")
    if unmatched:
        print(f"未照合 ({len(unmatched)}): " + "、".join(unmatched))
    else:
        print("未照合: なし")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
