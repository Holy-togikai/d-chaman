"""登山ルートグレーディング一覧表（PDFから抽出したテキスト）を構造化する。

出典: 十県一山域の日本百名山の「登山ルートグレーディング」一覧表
"""
import json
import re
import sys

# 行の末尾は数値が並ぶので、右側から確実に取れる形で捉える。
TAIL = re.compile(
    r"(?P<end_elev>[\d,]+)\s+"       # 終了地点の標高
    r"(?P<course_time>\d+\.\d+)\s+"  # 合計コースタイム（時間）
    r"(?P<length>\d+\.\d+)\s+"       # ルート長（km）
    r"(?P<up>\d+\.\d+)\s+"           # 累積登り標高差（km）
    r"(?P<down>\d+\.\d+)\s+"         # 累積下り標高差（km）
    r"(?P<constant>\d+\.\d+)\s+"     # ルート定数
    r"(?P<prefecture>\S+)\s*$"
)

HEAD = re.compile(
    r"^(?P<number>\d+)\s+"
    r"(?P<route>.+?)\s+"
    r"(?P<fitness>\d+)\s+"
    r"(?P<difficulty>[A-E])\s+"
    r"(?P<rest>.+)$"
)


def clean_number(value):
    return float(value.replace(",", ""))


def parse_line(line):
    # 行頭に山域の縦書き文字が混ざることがあるので、最初の数字から見る。
    start = re.search(r"\d", line)
    if not start:
        return None
    body = line[start.start():].strip()

    tail = TAIL.search(body)
    head = HEAD.match(body)
    if not tail or not head:
        return None

    # 体力度・難易度のあとから、末尾の数値群の手前までが地点の情報。
    middle = body[head.start("rest"):tail.start()].strip()

    # 「地名 標高 地名 標高 地名」の形。
    # 列の区切りが空白1個のことがあるため、空白数ではなく数値の位置で切り分ける。
    places = re.match(
        r"^(?P<start_name>.+?)\s+(?P<start_elev>[\d,]+)\s+"
        r"(?P<summit_name>.+?)\s+(?P<summit_elev>[\d,]+)\s+"
        r"(?P<end_name>.+)$",
        middle
    )
    if not places:
        return None
    names = [
        places.group("start_name").strip(),
        places.group("summit_name").strip(),
        places.group("end_name").strip(),
    ]
    numbers = [places.group("start_elev"), places.group("summit_elev")]

    route = head.group("route").strip()
    # ルート名称から山名を取り出す。「【周】大朝日岳（朝日鉱泉口）＜…＞」→「大朝日岳」
    mountain = re.sub(r"^【[^】]*】", "", route)
    mountain = re.split(r"[（(＜<→・]", mountain)[0].strip()

    start_name, summit_name, end_name = names[0], names[1], names[2]

    return {
        "number": int(head.group("number")),
        "mountain": mountain,
        "route": route,
        "fitnessLevel": int(head.group("fitness")),
        "difficultyLevel": head.group("difficulty"),
        "startName": start_name,
        "startElevation": clean_number(numbers[0]),
        "summitName": summit_name,
        "summitElevation": clean_number(numbers[1]),
        "endName": end_name,
        "endElevation": clean_number(tail.group("end_elev")),
        # 出発地と終了地が同じなら往復。違えば縦走・周回で、車で戻れない点に注意が要る。
        "isRoundTrip": start_name == end_name,
        "courseTimeHours": float(tail.group("course_time")),
        "lengthKm": float(tail.group("length")),
        "ascentKm": float(tail.group("up")),
        "descentKm": float(tail.group("down")),
        "routeConstant": float(tail.group("constant")),
        "prefecture": tail.group("prefecture"),
    }


def main(src, dst):
    routes = []
    failed = []
    for line in open(src, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parsed = parse_line(line)
        if parsed:
            routes.append(parsed)
        elif re.search(r"\d+\.\d+\s+\d+\.\d+\s+\d+\.\d+\s+\S+\s*$", line):
            failed.append(line.strip())

    routes.sort(key=lambda r: r["number"])
    with open(dst, "w", encoding="utf-8") as out:
        json.dump(routes, out, ensure_ascii=False, indent=1)

    print(f"取り込めたルート: {len(routes)}")
    print(f"取りこぼし: {len(failed)}")
    for line in failed[:5]:
        print("   ", line[:90])

    mountains = sorted({r["mountain"] for r in routes})
    print(f"山の数: {len(mountains)}")
    print("往復ルート:", sum(1 for r in routes if r["isRoundTrip"]))
    print()
    print("--- 例 ---")
    for route in routes[:3]:
        print(f"  {route['mountain']} / {route['route']}")
        print(f"    {route['startName']}({int(route['startElevation'])}m) → "
              f"{route['summitName']}({int(route['summitElevation'])}m) "
              f"コースタイム {route['courseTimeHours']}h "
              f"往復={route['isRoundTrip']} {route['prefecture']}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
