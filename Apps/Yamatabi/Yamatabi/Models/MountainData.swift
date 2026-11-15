import Foundation

/// 山の初期データ。
///
/// いまは動作確認用に主要な山だけを手で持っています。
/// 最終的には国土地理院「日本の主な山岳標高」（約1,000山）を取り込んで置き換える予定です。
/// 座標は山頂のおおよその位置で、小数点以下の精度は厳密ではありません。
enum MountainData {
    static let all: [Mountain] = [
        // ――― 北海道・東北 ―――
        Mountain(name: "利尻山", kana: "りしりざん", elevation: 1721, prefectures: ["北海道"],
                 latitude: 45.1786, longitude: 141.2425, isHyakumeizan: true),
        Mountain(name: "旭岳", kana: "あさひだけ", elevation: 2291, prefectures: ["北海道"],
                 latitude: 43.6633, longitude: 142.8544, isHyakumeizan: true),
        Mountain(name: "羊蹄山", kana: "ようていざん", elevation: 1898, prefectures: ["北海道"],
                 latitude: 42.8275, longitude: 140.8114, isHyakumeizan: true),
        Mountain(name: "岩木山", kana: "いわきさん", elevation: 1625, prefectures: ["青森県"],
                 latitude: 40.6556, longitude: 140.3028, isHyakumeizan: true),
        Mountain(name: "岩手山", kana: "いわてさん", elevation: 2038, prefectures: ["岩手県"],
                 latitude: 39.8531, longitude: 141.0008, isHyakumeizan: true),
        Mountain(name: "鳥海山", kana: "ちょうかいさん", elevation: 2236, prefectures: ["山形県", "秋田県"],
                 latitude: 39.0994, longitude: 140.0489, isHyakumeizan: true),
        Mountain(name: "月山", kana: "がっさん", elevation: 1984, prefectures: ["山形県"],
                 latitude: 38.5486, longitude: 140.0272, isHyakumeizan: true),
        Mountain(name: "蔵王山", kana: "ざおうさん", elevation: 1841, prefectures: ["山形県", "宮城県"],
                 latitude: 38.1444, longitude: 140.4400, isHyakumeizan: true),

        // ――― 関東・上信越 ―――
        Mountain(name: "那須岳", kana: "なすだけ", elevation: 1915, prefectures: ["栃木県"],
                 latitude: 37.1253, longitude: 139.9636, isHyakumeizan: true),
        Mountain(name: "男体山", kana: "なんたいさん", elevation: 2486, prefectures: ["栃木県"],
                 latitude: 36.7656, longitude: 139.4917, isHyakumeizan: true),
        Mountain(name: "日光白根山", kana: "にっこうしらねさん", elevation: 2578, prefectures: ["栃木県", "群馬県"],
                 latitude: 36.7983, longitude: 139.3764, isHyakumeizan: true),
        Mountain(name: "燧ヶ岳", kana: "ひうちがたけ", elevation: 2356, prefectures: ["福島県"],
                 latitude: 36.9553, longitude: 139.2864, isHyakumeizan: true),
        Mountain(name: "至仏山", kana: "しぶつさん", elevation: 2228, prefectures: ["群馬県"],
                 latitude: 36.9039, longitude: 139.1733, isHyakumeizan: true),
        Mountain(name: "谷川岳", kana: "たにがわだけ", elevation: 1977, prefectures: ["群馬県", "新潟県"],
                 latitude: 36.8347, longitude: 138.9303, isHyakumeizan: true),
        Mountain(name: "筑波山", kana: "つくばさん", elevation: 877, prefectures: ["茨城県"],
                 latitude: 36.2253, longitude: 140.1067, isHyakumeizan: true),
        Mountain(name: "両神山", kana: "りょうかみさん", elevation: 1723, prefectures: ["埼玉県"],
                 latitude: 35.9694, longitude: 138.8322, isHyakumeizan: true),
        Mountain(name: "雲取山", kana: "くもとりやま", elevation: 2017, prefectures: ["東京都", "埼玉県", "山梨県"],
                 latitude: 35.8556, longitude: 138.9436, isHyakumeizan: true),
        Mountain(name: "高尾山", kana: "たかおさん", elevation: 599, prefectures: ["東京都"],
                 latitude: 35.6253, longitude: 139.2436, isHyakumeizan: false),
        Mountain(name: "丹沢山", kana: "たんざわさん", elevation: 1567, prefectures: ["神奈川県"],
                 latitude: 35.4747, longitude: 139.1703, isHyakumeizan: true),
        Mountain(name: "天城山", kana: "あまぎさん", elevation: 1406, prefectures: ["静岡県"],
                 latitude: 34.8614, longitude: 139.0000, isHyakumeizan: true),

        // ――― 富士・八ヶ岳・南アルプス ―――
        Mountain(name: "富士山", kana: "ふじさん", elevation: 3776, prefectures: ["山梨県", "静岡県"],
                 latitude: 35.3606, longitude: 138.7274, isHyakumeizan: true),
        Mountain(name: "赤岳", kana: "あかだけ", elevation: 2899, prefectures: ["長野県", "山梨県"],
                 latitude: 35.9711, longitude: 138.3703, isHyakumeizan: true),
        Mountain(name: "金峰山", kana: "きんぷさん", elevation: 2599, prefectures: ["山梨県", "長野県"],
                 latitude: 35.8711, longitude: 138.6219, isHyakumeizan: true),
        Mountain(name: "北岳", kana: "きただけ", elevation: 3193, prefectures: ["山梨県"],
                 latitude: 35.6745, longitude: 138.2389, isHyakumeizan: true),
        Mountain(name: "甲斐駒ヶ岳", kana: "かいこまがたけ", elevation: 2967, prefectures: ["山梨県", "長野県"],
                 latitude: 35.7581, longitude: 138.2367, isHyakumeizan: true),
        Mountain(name: "仙丈ヶ岳", kana: "せんじょうがたけ", elevation: 3033, prefectures: ["山梨県", "長野県"],
                 latitude: 35.7194, longitude: 138.1831, isHyakumeizan: true),
        Mountain(name: "赤石岳", kana: "あかいしだけ", elevation: 3121, prefectures: ["長野県", "静岡県"],
                 latitude: 35.4603, longitude: 138.1586, isHyakumeizan: true),

        // ――― 北アルプス・中央アルプス ―――
        Mountain(name: "槍ヶ岳", kana: "やりがたけ", elevation: 3180, prefectures: ["長野県", "岐阜県"],
                 latitude: 36.3419, longitude: 137.6475, isHyakumeizan: true),
        Mountain(name: "奥穂高岳", kana: "おくほたかだけ", elevation: 3190, prefectures: ["長野県", "岐阜県"],
                 latitude: 36.2892, longitude: 137.6480, isHyakumeizan: true),
        Mountain(name: "立山", kana: "たてやま", elevation: 3015, prefectures: ["富山県"],
                 latitude: 36.5756, longitude: 137.6192, isHyakumeizan: true),
        Mountain(name: "剱岳", kana: "つるぎだけ", elevation: 2999, prefectures: ["富山県"],
                 latitude: 36.6236, longitude: 137.6172, isHyakumeizan: true),
        Mountain(name: "白馬岳", kana: "しろうまだけ", elevation: 2932, prefectures: ["長野県", "富山県"],
                 latitude: 36.7586, longitude: 137.7586, isHyakumeizan: true),
        Mountain(name: "乗鞍岳", kana: "のりくらだけ", elevation: 3026, prefectures: ["長野県", "岐阜県"],
                 latitude: 36.1061, longitude: 137.5536, isHyakumeizan: true),
        Mountain(name: "御嶽山", kana: "おんたけさん", elevation: 3067, prefectures: ["長野県", "岐阜県"],
                 latitude: 35.8930, longitude: 137.4804, isHyakumeizan: true),
        Mountain(name: "木曽駒ヶ岳", kana: "きそこまがたけ", elevation: 2956, prefectures: ["長野県"],
                 latitude: 35.7894, longitude: 137.8044, isHyakumeizan: true),
        Mountain(name: "浅間山", kana: "あさまやま", elevation: 2568, prefectures: ["長野県", "群馬県"],
                 latitude: 36.4061, longitude: 138.5231, isHyakumeizan: true),

        // ――― 北陸・近畿・中国 ―――
        Mountain(name: "白山", kana: "はくさん", elevation: 2702, prefectures: ["石川県", "岐阜県"],
                 latitude: 36.1553, longitude: 136.7714, isHyakumeizan: true),
        Mountain(name: "伊吹山", kana: "いぶきやま", elevation: 1377, prefectures: ["滋賀県", "岐阜県"],
                 latitude: 35.4178, longitude: 136.4064, isHyakumeizan: true),
        Mountain(name: "大山", kana: "だいせん", elevation: 1729, prefectures: ["鳥取県"],
                 latitude: 35.3711, longitude: 133.5456, isHyakumeizan: true),

        // ――― 四国・九州 ―――
        Mountain(name: "石鎚山", kana: "いしづちさん", elevation: 1982, prefectures: ["愛媛県"],
                 latitude: 33.7686, longitude: 133.1147, isHyakumeizan: true),
        Mountain(name: "阿蘇山", kana: "あそさん", elevation: 1592, prefectures: ["熊本県"],
                 latitude: 32.8844, longitude: 131.1042, isHyakumeizan: true),
        Mountain(name: "韓国岳", kana: "からくにだけ", elevation: 1700, prefectures: ["鹿児島県", "宮崎県"],
                 latitude: 31.9339, longitude: 130.8614, isHyakumeizan: true),
        Mountain(name: "宮之浦岳", kana: "みやのうらだけ", elevation: 1936, prefectures: ["鹿児島県"],
                 latitude: 30.3339, longitude: 130.5058, isHyakumeizan: true)
    ]
}
