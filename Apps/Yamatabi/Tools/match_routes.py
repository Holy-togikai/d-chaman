"""登山ルートグレーディングのルートを、国土地理院の山データに結びつける。

ルート表の山名は深田久弥の呼称に近く、地理院の登録名とは食い違うことがあるため、
山名・山頂名の両方と、既知の別名表で突き合わせる。
"""
import json
import sys
import unicodedata
from collections import defaultdict

# ルート表の呼称 → 地理院側の山名／山頂名。
# convert_mountains.py と同じ考え方で、表記の違いを吸収する。
ALIASES = {
    "日光白根山": "白根山",
    "沖武尊": "武尊山",
    "前掛山": "浅間山",      # 浅間山は前掛山までが一般的な登山対象
    "雄山": "立山",          # 地理院には東京都の雄山（775m）もあるため明示する
    "荒川東岳": "東岳",       # 悪沢岳
    "観音岳": "観音ヶ岳",     # 鳳凰三山の最高峰
    "弥山": "石鎚山",
    "熊野岳": "蔵王山",
    "地蔵岳": "蔵王山",
    "黒檜山": "赤城山",
    "駒ヶ岳": None,          # 同名が多すぎるため、山頂名での一致に任せる
    "五竜岳": "五龍岳",
    "剣岳": "剱岳",
    "剱岳": "剱岳",
    "八経ヶ岳": "八経ヶ岳",
    "大峰山": "八経ヶ岳",
    "奥穂高岳": "奥穂高岳",
    "空木岳": "空木岳",
    "木曽駒ヶ岳": "駒ヶ岳",
    "甲斐駒ヶ岳": "駒ヶ岳",
    "会津駒ヶ岳": "駒ヶ岳",
    "越後駒ヶ岳": "駒ヶ岳",
}


def normalize(name):
    """表記ゆれをならす。ルート表には半角カナの「ｹ」が混ざっている。"""
    if not name:
        return name
    text = unicodedata.normalize("NFKC", name)
    for char in "ケヶヵカ":
        text = text.replace(char, "ヶ") if char in "ケヶ" else text
    return text


def main(mountains_path, routes_path, out_path):
    mountains = json.load(open(mountains_path, encoding="utf-8"))
    routes = json.load(open(routes_path, encoding="utf-8"))

    by_name = defaultdict(list)
    for mountain in mountains:
        by_name[normalize(mountain["name"])].append(mountain)
        if mountain.get("peak"):
            by_name[normalize(mountain["peak"])].append(mountain)

    def best_match(route):
        """標高がいちばん近いものを選ぶ。同名の山が多いので、標高が決め手になる。"""
        target = route["summitElevation"]
        candidates = []
        keys = [route["summitName"], route["mountain"]]
        # 「石鎚山・弥山」のように複数の呼び名が並ぶことがあるので分解する。
        keys += [part for key in keys if key for part in key.split("・")]
        for key in keys:
            if not key:
                continue
            normalized = normalize(key)
            candidates += by_name.get(normalized, [])
            alias = ALIASES.get(key) or ALIASES.get(normalized)
            if alias:
                candidates += by_name.get(normalize(alias), [])
        if not candidates:
            return None
        # ルート表と地理院で標高の基準が少し違うことがあるので、最も近いものを採る。
        return min(candidates, key=lambda m: abs(m["elevation"] - target))

    matched = []
    unmatched = []
    for route in routes:
        mountain = best_match(route)
        if mountain is None:
            unmatched.append(route)
            continue
        gap = abs(mountain["elevation"] - route["summitElevation"])
        if gap > 60:
            # 標高が大きく違うなら、別の山に当ててしまっている可能性が高い。
            unmatched.append({**route, "_rejected": f"{mountain['name']} {mountain['elevation']}m"})
            continue

        matched.append({
            "mountainID": mountain["id"],
            "mountainName": mountain["name"],
            "route": route["route"],
            "startName": route["startName"],
            "startElevation": route["startElevation"],
            "summitName": route["summitName"],
            "endName": route["endName"],
            "isRoundTrip": route["isRoundTrip"],
            "courseTimeHours": route["courseTimeHours"],
            "lengthKm": route["lengthKm"],
            "fitnessLevel": route["fitnessLevel"],
            "difficultyLevel": route["difficultyLevel"],
            "prefecture": route["prefecture"],
        })

    matched.sort(key=lambda r: (r["mountainName"], r["courseTimeHours"]))
    with open(out_path, "w", encoding="utf-8") as out:
        json.dump(matched, out, ensure_ascii=False, separators=(",", ":"))

    print(f"結びついたルート: {len(matched)} / {len(routes)}")
    print(f"対象の山（地理院のID単位）: {len({r['mountainID'] for r in matched})}")
    print(f"往復ルート: {sum(1 for r in matched if r['isRoundTrip'])}")
    print()
    if unmatched:
        print(f"--- 結びつかなかった {len(unmatched)} 件 ---")
        for route in unmatched:
            note = route.get("_rejected", "候補なし")
            print(f"  {route['mountain']} / {route['summitName']} "
                  f"{int(route['summitElevation'])}m → {note}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
