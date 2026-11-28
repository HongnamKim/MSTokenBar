# MSTokenBar

[English](README.md) · [한국어](README.ko.md)

**[ドット絵カタログを見る](https://hongnamkim.github.io/MSTokenBar/catalog/)**

すでに使っている AI コーディングトークン（Claude Code・Codex・Gemini CLI など）を、ガンプラ（ガンダムのプラモデル）の制作進行度に変える macOS メニューバーアプリです。[chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar) をガンプラテーマにしたフォークです。

> 宇宙世紀とそれ以外を合わせて28作品の機体を格納庫の247枠に収録しています。発売済みキットのグレード・モード・装備に合わせたドット絵は604点です。トークン使用量の追跡は元プロジェクトから引き継いだ機能です（対応ツールは[元の README](https://github.com/chattymin/PokeTokenBar#readme) を参照）。

## 仕組み

- **開封**: AI コーディングトークンを使うとキットボックスが開き、機体が登場します。
- **グレードアップ**: さらに使うと、その機体で実際に発売されたキットのグレードを順に上がります（SD → MGSD → HG → RG → MG → Ver.Ka → MGEX → PG）。発売されていないグレードは飛ばし、あとからカタログにキットのグレードが加わると、完成した機体がそのグレードを作りに再登場します。
- **完成**: 最終グレードに到達すると機体が完成し、格納庫に保存され、新しいキットボックスが届きます。完成した機体は、すべての機体を完成させるまで再登場しません。
- **専用機**: シャア専用ザク II のような指揮官機・エース専用機は、ベース機のレアな変種として登場します。ショップの塗装ツール（マスキングテープ → スミ入れペン → 塗料セット → エアブラシ）で確率を永続的に上げられます。
- **格納庫**: 機体ごとに 1 マスで、作ったグレードをすべて記録します。まだ作っていない機体は、型式番号だけを手がかりにしたシルエットで表示されます。作品別に絞り込めて、作品をコンプリートするとバッジがもらえます。
- **製作記録**: 機体ごとに、ボックスを開けた日、各グレードに到達した日、ツールごとに使ったトークンを記録します。機体詳細画面で、グレードごとに 1 本のバーとして出どころ別に表示します。
- **アイテム**: スポンジヤスリは即座に成長させ、アンコモン／レアボックスはレアリティを保証します。
- **予約注文と作品ボックス**: まだ完成していない機体を 1 機予約すると、ボックスが開くたびに 25% の確率で届き、遅くとも 4 箱目で届きます。作品ボックスは選んだ作品の機体だけが出ます。

| 格納庫 | 作品一覧 |
| --- | --- |
| ![格納庫](assets/screenshot-gunpla-hangar-ja.png) | ![作品一覧](assets/screenshot-gunpla-series-ja.png) |

| 機体詳細と製作記録 | ショップ |
| --- | --- |
| ![機体詳細と製作記録](assets/screenshot-gunpla-build-record-ja.png) | ![ショップ](assets/screenshot-gunpla-shop-ja.png) |

| 作品ボックスと予約注文 | 作品ボックス一覧 |
| --- | --- |
| ![作品ボックスと予約注文](assets/screenshot-gunpla-shop-boxes-ja.png) | ![作品ボックス一覧](assets/screenshot-gunpla-series-boxes-ja.png) |

## 動作環境

macOS 14 以降。

## インストール

1. 最新の[リリース](https://github.com/HongnamKim/MSTokenBar/releases/latest)から `MSTokenBar.zip` をダウンロードします。
2. 解凍して `MSTokenBar.app` を「アプリケーション」フォルダに移動します。
3. Apple の公証を受けていないため、初回起動時はアプリを右クリックして**開く**を選びます。

新しいバージョンが出るとアプリにアップデートバナーが表示されます。**アップデート**を押すと、アプリがリリースをダウンロードして署名を確認し、自分自身を置き換えて再起動します。0.1.1 以前のバージョンはリリースページを開くだけなので、一度だけ zip を手動でダウンロードして置き換えてください。

## バージョン規則

1.0.0 で宇宙世紀の全作品を描き終えました。以降は、完成したドット絵（一度に複数作品でも 1 回）や新機能を追加するたびにマイナーバージョンを上げ（1.1.0、1.2.0、…）、修正ではパッチバージョンを上げます。2.0.0 はアプリが大きく変わるときのために取っておきます。

## ソースからビルド

```bash
git clone https://github.com/HongnamKim/MSTokenBar.git
cd MSTokenBar
scripts/build-app.sh      # build/MSTokenBar.app を作成し /Applications にインストール
```

## クレジット

chattymin 氏の [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) のフォークです。元の MIT ライセンスと著作権表示は [LICENSE](LICENSE) にそのまま残しています。

## 免責

非公式・非営利のファンプロジェクトです。バンダイナムコ・サンライズとは無関係です。原作品の権利はすべて各権利者に帰属します。
(Unofficial, non-commercial fan project. Not affiliated with Bandai Namco or Sunrise. All rights to the original works belong to their owners.)
