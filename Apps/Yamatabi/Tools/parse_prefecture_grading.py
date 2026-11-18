"""各県が単独で公表している「山のグレーディング」一覧表を構造化する。

`parse_grading.py` が扱う十県一山域の百名山版は、行の末尾に都道府県名が入る形でした。
各県が自前で出している一覧表はその県のぶんしか載らないため末尾に県名が無く、
代わりに市町村名や備考が入ったり、ルート名が複数行に割れたりします。

そこで、列の位置ではなく「末尾に小数が5つ並ぶ」ことを手がかりに切り出します。
この5つは コースタイム・ルート長・累積登り・累積下り・ルート定数 で、
どの県の表でも同じ順に並んでいます。

出力は `parse_grading.py` と同じ形で、`match_routes.py` にそのまま渡せます。

使い方:
    python3 Tools/parse_prefecture_grading.py <県名> <入力テキスト> <出力JSON>
"""
import json
import re
import sys
import unicodedata

# 末尾に並ぶ5つの小数。これがこの表の背骨。
# 前に終了地点の標高（「1,504」「1,091.2m」など）が付く。
TAIL = re.compile(
    r"(?P<end_elev>[\d,]+(?:\.\d+)?)\s*m?\s+"
    r"(?P<course_time>\d+\.\d+)\s+"
    r"(?P<length>\d+\.\d+)\s+"
    r"(?P<up>\d+\.\d+)\s+"
    r"(?P<down>\d+\.\d+)\s+"
    r"(?P<constant>\d+\.\d+)"
)

# 体力度（1〜10）と難易度（A〜E）。ここから右が地点の情報になる。
GRADE = re.compile(r"(?<![\d.])(?P<fitness>10|[1-9])\s+(?P<difficulty>[A-E])(?![A-Za-z])")

# 「地名 標高 地名 標高 地名」。標高には桁区切りと小数とmが混ざる。
PLACES = re.compile(
    r"^(?P<start_name>.+?)\s+(?P<start_elev>[\d,]+(?:\.\d+)?)\s*m?\s+"
    r"(?P<summit_name>.+?)\s+(?P<summit_elev>[\d,]+(?:\.\d+)?)\s*m?\s+"
    r"(?P<end_name>.+?)\s*$"
)

# ルート名の前に付く通し番号。
# 富山の表は左端に山域名が縦書きで入っており、1文字だけ行頭に紛れ込む
#（「連 17 縦 内蔵助平…」の「連」）。番号の手前の1文字は落とす。
LEADING = re.compile(r"^\s*(?:\S\s+)?(?P<number>\d+)\s*(?P<rest>.*)$")

# 山小屋・山荘。
# 名前に小屋が付いていても、聖光小屋・北又小屋のように駐車場のある登山口は多い。
# 「小屋→小屋」と矢印で結ばれているものだけが、稜線上の区間の評価。
HUT = re.compile(r"(小屋|山荘|ヒュッテ|小舎)$")

# 新潟の表はルート名の右によみがなが入る。ひらがなだけの塊を落とす。
KANA_ONLY = re.compile(r"[ぁ-ゖー]+$")

# 岐阜の表はルート名の右に山域名が入る。
# 「御嶽山」「白山」は山域名であると同時に山名そのものなので、
# 単独の語として立っていて、かつ先頭でないときだけ落とす。
# 先頭から消すと「御嶽山（飯森高原駅）」が「（飯森高原駅）」になってしまう。
AREAS = frozenset({
    "北アルプス", "中央アルプス", "南アルプス", "御嶽山", "白山",
    "奥美濃", "奥三河", "飛騨高地", "伊吹・鈴鹿",
})


def clean_number(value):
    return float(value.replace(",", ""))


def normalize_spaces(text):
    """全角空白と連続空白をならす。半角カナも全角に直す。"""
    text = unicodedata.normalize("NFKC", text)
    return re.sub(r"\s+", " ", text).strip()


def strip_decorations(route):
    """ルート名から、山域名・よみがな・記号を落とす。"""
    text = normalize_spaces(route)
    # 「縦」「周」「往復」「周回」などの種別表記。
    text = re.sub(r"[縦周]\s*□|□|【[^】]*】|往復|周回|縦走", " ", text)
    text = normalize_spaces(text)
    # 山域名は、単独の語で、かつ先頭でないときだけ落とす。
    tokens = [
        token for index, token in enumerate(text.split(" "))
        if index == 0 or token not in AREAS
    ]
    text = " ".join(tokens)
    # 末尾のよみがな（ひらがなだけの塊）。
    parts = text.split(" ")
    while parts and KANA_ONLY.fullmatch(parts[-1] or ""):
        parts.pop()
    return " ".join(parts).strip()


def mountain_name(route):
    """ルート名から山名を取り出す。「大朝日岳（朝日鉱泉口）＜…＞」→「大朝日岳」"""
    name = re.split(r"[（(＜<→・]", route)[0].strip()
    # 「縦 北岳→塩見岳」のように種別が前に残ることがある。
    name = re.sub(r"^[縦周往復回\s]+", "", name)
    return name.strip()


def parse_line(line, prefecture, pending=()):
    """1行を構造化する。

    - Parameter pending: 直前の、数値を持たない行。ルート名が複数行に割れている表
      （長野の縦走ルート、岐阜のほぼ全ルート）では、名前がここに入っています。
    """
    body = normalize_spaces(line)
    if not body:
        return None

    tail = TAIL.search(body)
    if not tail:
        return None

    grade = None
    # 体力度・難易度は、末尾の数値群より左にある最後のものを採る。
    for found in GRADE.finditer(body[:tail.start()]):
        grade = found
    if grade is None:
        return None

    middle = body[grade.end():tail.start()].strip()
    places = PLACES.match(middle)
    if not places:
        return None

    head = body[:grade.start()].strip()
    number_match = LEADING.match(head)
    number = int(number_match.group("number")) if number_match else 0
    own = strip_decorations(number_match.group("rest") if number_match else head)

    # 名前が前の行にある表では、own が「□」や「〈右俣〉」だけになる。
    # 数値は揃っているので、名前を前の行から補う。
    if pending and (not own or own.startswith(("〈", "＜", "(", "（", "<"))):
        parts = list(pending)
        # 通し番号は前の行の先頭に付いている。名前から外して番号として採る。
        first = LEADING.match(parts[0])
        if first:
            number = int(first.group("number"))
            parts[0] = first.group("rest")
        route = strip_decorations(" ".join(parts + ([own] if own else [])))
    else:
        route = own
    if not route:
        return None

    start_name = normalize_spaces(places.group("start_name"))
    end_name = normalize_spaces(places.group("end_name"))
    summit_name = normalize_spaces(places.group("summit_name"))

    return {
        "number": number,
        "mountain": mountain_name(route),
        "route": route,
        "fitnessLevel": int(grade.group("fitness")),
        "difficultyLevel": grade.group("difficulty"),
        "startName": start_name,
        "startElevation": clean_number(places.group("start_elev")),
        "summitName": summit_name,
        "summitElevation": clean_number(places.group("summit_elev")),
        "endName": end_name,
        "endElevation": clean_number(tail.group("end_elev")),
        # 出発地と終了地が同じなら往復。違えば縦走・周回で、車で戻れない点に注意が要る。
        "isRoundTrip": start_name == end_name,
        "courseTimeHours": float(tail.group("course_time")),
        "lengthKm": float(tail.group("length")),
        "ascentKm": float(tail.group("up")),
        "descentKm": float(tail.group("down")),
        "routeConstant": float(tail.group("constant")),
        "prefecture": prefecture,
    }


def looks_sane(route):
    """明らかにおかしい行を捨てる。表の罫線や注記を拾ってしまうことがある。"""
    if not (0 < route["courseTimeHours"] <= 60):
        return False
    if not (0 < route["lengthKm"] <= 200):
        return False
    if not (0 < route["summitElevation"] <= 3776):
        return False
    if route["startElevation"] <= 0 or route["endElevation"] <= 0:
        return False
    # 山頂が出発地より低いのは、表の読み違い。
    if route["summitElevation"] < route["startElevation"]:
        return False
    # 小屋から小屋への区間の評価。車で行けないうえ、登山口からの計画に使うと
    # コースタイムを短く見積もってしまい危ない。
    if (HUT.search(route["startName"]) and HUT.search(route["endName"])
            and "→" in route["route"]):
        return False
    if not route["mountain"]:
        return False
    # 山名らしさ。記号や数字だけの塊を山名として通さない。
    if not re.search(r"[ぁ-ヿ一-鿿]", route["mountain"]):
        return False
    return True


def main(prefecture, src, dst):
    routes = []
    skipped = 0
    incomplete = 0
    pending = []
    for line in open(src, encoding="utf-8"):
        raw = line.rstrip("\n")
        body = normalize_spaces(raw)

        # 長野の表は末尾に「県外」の節があり、高尾山などが比較用に載っています。
        # その県のルートではないため、正しい都道府県を付けられません。
        # 誤った県名を付けるくらいなら載せないほうがよいので、ここで打ち切ります。
        if body.replace(" ", "") == "県外":
            break

        has_numbers = bool(TAIL.search(body))

        if not has_numbers:
            # 数値を持たない行は、ルート名の断片かもしれないので覚えておく。
            # 注記や見出しを拾わないよう、短いものだけに限る。
            if body and len(body) <= 40 and not body.startswith(("※", "○", "■", "注", "(注")):
                pending.append(body)
                pending[:] = pending[-3:]
            else:
                pending.clear()
            continue

        parsed = parse_line(raw, prefecture, tuple(pending))
        pending.clear()
        if parsed is None:
            # 数値はあるのに読めない行。列が欠けている可能性が高い。
            # コースタイムを取り違えると危ないので、曖昧なものは捨てる。
            incomplete += 1
            continue
        if not looks_sane(parsed):
            skipped += 1
            continue
        routes.append(parsed)

    with open(dst, "w", encoding="utf-8") as out:
        json.dump(routes, out, ensure_ascii=False, indent=1)

    print(f"{prefecture}: {len(routes)} ルート"
          f"（列が欠けて読めない行 {incomplete} 件、値がおかしい行 {skipped} 件を捨てた）")
    if routes:
        times = [r["courseTimeHours"] for r in routes]
        print(f"  コースタイム: {min(times):.1f} 〜 {max(times):.1f} 時間")
        print(f"  往復: {sum(1 for r in routes if r['isRoundTrip'])} / 縦走・周回: "
              f"{sum(1 for r in routes if not r['isRoundTrip'])}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
