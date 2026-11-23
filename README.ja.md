# MSTokenBar

[English](README.md) · [한국어](README.ko.md)

すでに使っている AI コーディングトークン（Claude Code・Codex・Gemini CLI など）を、ガンプラ（ガンダムのプラモデル）の制作進行度に変える macOS メニューバーアプリです。[chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar) をガンプラテーマにしたフォークです。

> 開発中: ドット絵スプライトは制作中で、現在絵があるのは RX-78-2 ガンダムだけです（ほかの機体はシルエットで表示）。機体リストは開発用の 12 機で、初回公開版のリスト（宇宙世紀 15 作品・127 機）を準備しています。トークン使用量の追跡は元プロジェクトから引き継いだ機能です（対応ツールは[元の README](https://github.com/chattymin/PokeTokenBar#readme) を参照）。

## 仕組み

- **開封**: AI コーディングトークンを使うとキットボックスが開き、機体が登場します。
- **グレードアップ**: さらに使うと、その機体で実際に発売されたキットのグレードを順に上がります（SD → MGSD → HG → RG → MG → PG）。発売されていないグレードは飛ばします。
- **完成**: 最終グレードに到達すると機体が完成し、格納庫に保存され、新しいキットボックスが届きます。完成した機体は、すべての機体を完成させるまで再登場しません。
- **専用機**: シャア専用ザク II のような指揮官機・エース専用機は、ベース機のレアな変種として登場します。ショップの塗装ツール（マスキングテープ → スミ入れペン → 塗料セット → エアブラシ）で確率を永続的に上げられます。
- **格納庫**: 機体ごとに 1 マスで、作ったグレードをすべて記録します。作品別に絞り込めて、作品をコンプリートするとバッジがもらえます。
- **アイテム**: スポンジヤスリは即座に成長させ、アンコモン／レアボックスはレアリティを保証します。

## 動作環境

macOS 14 以降。

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
