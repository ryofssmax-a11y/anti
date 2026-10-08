// 学習データ。items: [インドネシア語, カタカナ読み, 日本語, ひとことメモ]
const UNITS = [
  {
    id: 'u1', name: 'あいさつ', sub: 'Salam', icon: '🙏', color: '#e63946',
    items: [
      ['Halo', 'ハロー', 'こんにちは（気軽なあいさつ）'],
      ['Selamat pagi', 'スラマッ パギ', 'おはよう', '朝（〜11時ごろ）に使います。'],
      ['Selamat siang', 'スラマッ シアン', 'こんにちは（昼）', '昼（11〜15時ごろ）に使います。'],
      ['Selamat sore', 'スラマッ ソレ', 'こんにちは（夕方）', '午後〜日没（15〜18時ごろ）に使います。'],
      ['Selamat malam', 'スラマッ マラム', 'こんばんは', '日没後に使います。'],
      ['Terima kasih', 'トゥリマ カシ', 'ありがとう', '直訳は「愛情・好意を受け取る」。'],
      ['Sama-sama', 'サマサマ', 'どういたしまして'],
      ['Maaf', 'マアフ', 'ごめんなさい'],
      ['Permisi', 'プルミシ', 'すみません・失礼します', '人の前を通る時や、声をかける時に使います。'],
      ['Apa kabar?', 'アパ カバール', 'お元気ですか？', '"apa" は「何」、"kabar" は「様子・ニュース」。'],
      ['Baik, terima kasih.', 'バイッ トゥリマ カシ', '元気です、ありがとう。', '"baik" は「良い・元気」。'],
      ['Sampai jumpa', 'サンパイ ジュンパ', 'またね・さようなら'],
    ],
    dialogs: [
      { q: 'Selamat pagi!', qja: 'おはよう！', a: 'Selamat pagi!', wrong: ['Selamat malam!', 'Sampai jumpa!'] },
      { q: 'Apa kabar?', qja: '元気？', a: 'Baik, terima kasih.', wrong: ['Sama-sama.', 'Maaf.'] },
      { q: 'Terima kasih!', qja: 'ありがとう！', a: 'Sama-sama.', wrong: ['Apa kabar?', 'Maaf.'] },
    ],
  },
  {
    id: 'u2', name: '自己紹介', sub: 'Perkenalan', icon: '😊', color: '#f77f00',
    items: [
      ['Saya', 'サヤ', '私', '丁寧で万能な「私」。'],
      ['Kamu', 'カム', 'あなた', '友だち同士で使います。目上の人には "Anda"。'],
      ['Nama saya Ayu.', 'ナマ サヤ アユ', '私の名前はアユです。', '語順は「名前＋私」。修飾する言葉があとに来ます。'],
      ['Siapa namamu?', 'シアパ ナマム', 'お名前は？', '"-mu" は「あなたの」。'],
      ['Saya dari Jepang.', 'サヤ ダリ ジュパン', '私は日本から来ました。'],
      ['Kamu dari mana?', 'カム ダリ マナ', 'どこから来たの？', '"mana" は「どこ・どれ」。'],
      ['Senang bertemu denganmu.', 'スナン ブルトゥム ドゥンガンム', 'お会いできて嬉しいです。'],
      ['Saya juga.', 'サヤ ジュガ', '私もです。'],
      ['Ya', 'ヤ', 'はい'],
      ['Tidak', 'ティダッ', 'いいえ', '動詞・形容詞の否定は "tidak"、名詞の否定は "bukan"。'],
      ['Saya orang Jepang.', 'サヤ オラン ジュパン', '私は日本人です。', '"orang" は「人」。'],
      ['Saya tidak mengerti.', 'サヤ ティダッ ムングルティ', 'わかりません。'],
      ['Tolong bicara pelan-pelan.', 'トロン ビチャラ プランプラン', 'ゆっくり話してください。', '"pelan-pelan" は「ゆっくり」。同じ語を重ねて強調する表現が多いのも特徴です。'],
    ],
    dialogs: [
      { q: 'Siapa namamu?', qja: 'お名前は？', a: 'Nama saya Budi.', wrong: ['Saya dari Jepang.', 'Saya tidak mengerti.'] },
      { q: 'Kamu dari mana?', qja: 'どこから来たの？', a: 'Saya dari Jepang.', wrong: ['Nama saya Ayu.', 'Saya juga.'] },
      { q: 'Senang bertemu denganmu.', qja: 'お会いできて嬉しいです。', a: 'Saya juga.', wrong: ['Tidak.', 'Maaf.'] },
    ],
  },
  {
    id: 'u3', name: '数字', sub: 'Angka', icon: '🔢', color: '#ffb703',
    items: [
      ['satu', 'サトゥ', '1'],
      ['dua', 'ドゥア', '2'],
      ['tiga', 'ティガ', '3'],
      ['empat', 'ウンパッ', '4'],
      ['lima', 'リマ', '5'],
      ['enam', 'ウナム', '6'],
      ['tujuh', 'トゥジュ', '7'],
      ['delapan', 'ドゥラパン', '8'],
      ['sembilan', 'スンビラン', '9'],
      ['sepuluh', 'スプル', '10', '"se-" は「1つの」。seratus（100）も se＋ratus。'],
      ['seratus', 'スラトゥス', '100'],
      ['ribu', 'リブ', '千', '"10 ribu" = 10,000ルピア。値段は ribu で言うのが基本です。'],
      ['Dua orang.', 'ドゥア オラン', '2人です。', 'お店で人数を聞かれた時に。'],
    ],
    dialogs: [
      { q: 'Berapa orang?', qja: '何名様ですか？', a: 'Dua orang.', wrong: ['Terima kasih.', 'Selamat pagi.'] },
    ],
  },
  {
    id: 'u4', name: '食べ物・注文', sub: 'Makanan', icon: '🍜', color: '#2bb673',
    items: [
      ['nasi', 'ナシ', 'ご飯', '"nasi goreng" は炒飯。'],
      ['air', 'アイル', '水', '"air putih" は「白い水」＝ミネラルウォーター。'],
      ['kopi', 'コピ', 'コーヒー'],
      ['teh', 'テ', 'お茶', '"teh manis" は甘いお茶、"es teh" はアイスティー。'],
      ['ayam', 'アヤム', '鶏肉'],
      ['ikan', 'イカン', '魚'],
      ['enak', 'エナッ', 'おいしい'],
      ['pedas', 'プダス', '辛い', '"sambal" という激辛ソースがよく出ます。'],
      ['Enak sekali!', 'エナッ スカリ', 'とってもおいしい！', '"sekali" は「とても」。形容詞のあとに置きます。'],
      ['Saya mau makan.', 'サヤ マウ マカン', '食べたいです。', '"mau" は「〜したい・欲しい」。'],
      ['Saya mau nasi goreng.', 'サヤ マウ ナシ ゴレン', 'ナシゴレンが欲しいです。'],
      ['Minta air putih.', 'ミンタ アイル プティ', 'お水をください。', '"minta" は「〜をください」のカジュアルな言い方。'],
      ['Tidak pedas, ya.', 'ティダッ プダス ヤ', '辛くしないでね。', '文末の "ya" は「〜ね」と念を押す言葉。'],
    ],
    dialogs: [
      { q: 'Mau makan apa?', qja: '何を食べたい？', a: 'Saya mau nasi goreng.', wrong: ['Terima kasih.', 'Di mana toilet?'] },
      { q: 'Pedas atau tidak?', qja: '辛いのと辛くないの、どっち？', a: 'Tidak pedas, ya.', wrong: ['Selamat tidur.', 'Sampai jumpa.'] },
    ],
  },
  {
    id: 'u5', name: '買い物・移動', sub: 'Belanja', icon: '🛵', color: '#118ab2',
    items: [
      ['Berapa harganya?', 'ブラパ ハルガニャ', 'いくらですか？'],
      ['mahal', 'マハル', '高い'],
      ['murah', 'ムラ', '安い'],
      ['Terlalu mahal.', 'トゥルラル マハル', '高すぎます。'],
      ['Bisa kurang?', 'ビサ クラン', '安くなりますか？', '市場や露店での値段交渉の定番フレーズ。'],
      ['Di mana toilet?', 'ディ マナ トイレット', 'トイレはどこですか？'],
      ['kiri', 'キリ', '左'],
      ['kanan', 'カナン', '右'],
      ['lurus', 'ルルス', 'まっすぐ'],
      ['Lurus, lalu kiri.', 'ルルス ラル キリ', 'まっすぐ行って、それから左です。', '"lalu" は「それから」。'],
      ['Berhenti di sini.', 'ブルフンティ ディ シニ', 'ここで止まってください。', 'タクシーやバイクタクシーで便利です。'],
      ['Saya mau ke bandara.', 'サヤ マウ ク バンダラ', '空港に行きたいです。'],
    ],
    dialogs: [
      { q: 'Permisi, di mana toilet?', qja: 'すみません、トイレはどこ？', a: 'Lurus, lalu kiri.', wrong: ['Enak sekali!', 'Selamat malam.'] },
      { q: 'Harganya mahal.', qja: '値段は高いですよ。', a: 'Bisa kurang?', wrong: ['Selamat pagi.', 'Saya capek.'] },
    ],
  },
  {
    id: 'u6', name: '日常会話', sub: 'Sehari-hari', icon: '💬', color: '#8338ec',
    items: [
      ['Mau ke mana?', 'マウ ク マナ', 'どこに行くの？', 'あいさつ代わりに聞かれることもあります。'],
      ['Saya mau pulang.', 'サヤ マウ プラン', '帰りたいです。'],
      ['Saya lapar.', 'サヤ ラパール', 'お腹がすきました。'],
      ['Saya haus.', 'サヤ ハウス', 'のどが渇きました。'],
      ['Saya capek.', 'サヤ チャペッ', '疲れました。'],
      ['Tidak apa-apa.', 'ティダッ アパアパ', '大丈夫です・気にしないで。'],
      ['Tolong!', 'トロン', '助けて！', '"tolong" は「お願い」「助けて」の両方に使えます。'],
      ['Hati-hati.', 'ハティハティ', '気をつけて。'],
      ['Selamat makan.', 'スラマッ マカン', '召し上がれ・いただきます。'],
      ['Selamat tidur.', 'スラマッ ティドゥール', 'おやすみなさい。'],
      ['Sampai besok.', 'サンパイ ベソッ', 'また明日。'],
      ['Selamat ulang tahun!', 'スラマッ ウラン タフン', 'お誕生日おめでとう！'],
      ['Saya suka Indonesia.', 'サヤ スカ インドネシア', 'インドネシアが好きです。'],
    ],
    dialogs: [
      { q: 'Selamat ulang tahun!', qja: 'お誕生日おめでとう！', a: 'Terima kasih!', wrong: ['Maaf.', 'Sampai besok.'] },
      { q: 'Mau ke mana?', qja: 'どこに行くの？', a: 'Saya mau pulang.', wrong: ['Nama saya Ayu.', 'Sama-sama.'] },
      { q: 'Selamat makan!', qja: 'どうぞ召し上がれ！', a: 'Terima kasih.', wrong: ['Selamat tidur.', 'Hati-hati.'] },
    ],
  },
];

const TITLES = ['旅行者', '観光客', 'ナシゴレン見習い', '市場の常連', 'バイクタクシー乗り', 'ワルン店主の友', 'バリの旅人', 'ジャカルタっ子', 'インドネシア通', '言葉の達人'];

const ALL = [];
UNITS.forEach((u) => {
  u.items = u.items.map((a, i) => {
    const it = { id: `${u.id}_${i}`, unit: u.id, id_: a[0], kana: a[1], ja: a[2], note: a[3] || '' };
    ALL.push(it);
    return it;
  });
});
const ITEM = Object.fromEntries(ALL.map((i) => [i.id, i]));
