# SafariAdBlock

[English](README.md) · [한국어](README.ko.md) · **日本語** · [中文（简体）](README.zh-Hans.md)

Safari 用の広告ブロック機能拡張セットです。Safari ネイティブの**コンテンツブロッカー**方式なので高速で、ページ内容を読む権限も不要です。EasyList・EasyPrivacy と韓国向けリスト（List-KR、YousList）を Safari のルールに変換して使います。

| 機能拡張 | ソース | 内容 |
|---|---|---|
| **広告ブロック** | EasyList + `filters/custom.txt`（自分のルール） | バナー・ポップアップ・広告スクリプトをブロックし、広告枠を隠す |
| **トラッカーブロック** | EasyPrivacy | 解析・トラッキングのスクリプトとビーコンをブロック |
| **韓国サイト広告ブロック** | List-KR（filterslist-KO）+ YousList | Naver や Daum など韓国のサイト向けルール |
| **動画広告スキップ** | `WebExtension/`（Safari Web 機能拡張） | 再生前・再生中の動画広告が始まらないようにし、それでも出る広告は即座にスキップし、広告ブロッカー検出の警告を閉じる |

4 つはそれぞれ Safari の設定でオン/オフできます。最初の 3 つはコンテンツブロッカー（URL と CSS のルールのみ、ページ内でコードは実行しない）で、最後の 1 つは動画サイトのページ内でスクリプトを実行する Web 機能拡張です。コンテナアプリ（SafariAdBlock.app）は各機能拡張の状態表示、Safari 設定を開く、ルールの再読み込みを担当します。アプリと機能拡張名は英語・韓国語・日本語・中国語（簡体字）に対応しています。

## ビルドとインストール

Xcode は不要で、Command Line Tools だけでビルドできます（macOS 13 以降、Apple Silicon / Intel 両対応のユニバーサルバイナリ）。

```bash
./install.sh     # ビルド → /Applications/SafariAdBlock.app にインストール → 機能拡張を登録 → 起動
```

ビルドだけなら `./build.sh`（出力：`build/SafariAdBlock.app`）。初回ビルドではフィルタリストをダウンロードして変換するのでネットワークが必要です（`rules/` はリポジトリに含めません）。

インストール後、**Safari › 設定 › 機能拡張**で `広告ブロック`、`トラッカーブロック`、`韓国サイト広告ブロック`、`動画広告スキップ`をオンにします。アプリの **Safari で設定**ボタンでその画面が開きます。`動画広告スキップ`をオンにして初めて動画サイトを開くと、Safari がサイトへのアクセス許可を求めるので**常に許可**を選んでください。

### 署名

`build.sh` はキーチェーンから **Apple Development** → Developer ID →（なければ）ad hoc の順に署名証明書を選びます。環境変数 `CODESIGN_IDENTITY="..."` で明示することもできます。

- Apple の証明書で署名すると Safari はすぐに機能拡張を認識します。無料の Apple ID で十分です。Xcode › Settings › Accounts に Apple ID を追加し、**Manage Certificates › + › Apple Development** で証明書を一度作成してください。
- ad hoc 署名の場合は毎回 Safari で許可が必要です。Safari › 設定 › 詳細 › **Web デベロッパ用の機能を表示**をオンにしてから、**開発 › デベロッパ設定… › 署名されていない機能拡張を許可**。Safari を終了するとリセットされます。

#### codesign が何度もキーチェーンのパスワードを求める理由

Apple Development 証明書の秘密鍵はログインキーチェーンにあり、`codesign` がその鍵を使うたびに macOS が許可を求めます。1 回のビルドでアプリ 1 つと機能拡張 4 つに署名するため、最大 5 回表示されます。一度**常に許可**を押せば以後は聞かれません。ダイアログの代わりにターミナルで処理するには（ログインキーチェーンのパスワードを聞かれます）：

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

### 別の Mac にインストールする

```bash
git clone https://github.com/coldnuclearfusion/SafariAdBlock.git
cd SafariAdBlock && ./install.sh
```

初回ビルドでフィルタリストをダウンロードします。その Mac に Apple Development 証明書がなければ ad hoc 署名になるので、上の署名の項を参照してください。

## 言語

アプリの UI は英語・韓国語・日本語・中国語（簡体字）に対応しています。デフォルトはシステム言語に従い、アプリ右上の**言語**メニューで切り替えると即座に反映され、選択は記憶されます。それ以外の言語では英語で表示されます。

Safari の設定画面に表示される機能拡張名（と Finder でのアプリ名）は、バンドルの `InfoPlist.strings` と Web 機能拡張の `_locales` から取られるため、アプリの言語メニューとは関係なく常に**システム**言語に従います。

文字列を追加・変更するには `Resources/App/Localizations/<code>.json` を編集します（4 つのファイルは同じキーを持つ必要があり、`build.sh` が検査します）。Web 機能拡張の名前と説明は `WebExtension/_locales/<code>/messages.json` にあります。

## 使い方

- **特定のサイトだけオフにする**：そのサイトを開いた状態で Safari メニュー › **（サイト）の設定…** › **コンテンツブロッカーを有効にする**のチェックを外します。Safari がサイトごとに記憶します。
- **言語を切り替える**：アプリ右上の言語メニュー（システム設定に従う / 한국어 / English / 日本語 / 中文）。
- **ブロックリストの更新**（EasyList などは数日ごとに更新されます）：
  ```bash
  ./update-rules.sh && ./install.sh
  ```
- **自分のルールを追加する**：`filters/custom.txt` に EasyList 構文で書き、`SKIP_DOWNLOAD=1 ./update-rules.sh && ./install.sh` を実行します。ファイル冒頭に構文例があります。
- **ルールが反映されないとき**：アプリの**ルールを再読み込み**。それでも駄目なら Safari で機能拡張を一度オフにしてからオンにしてください。

## トラブルシューティング

- **オンにしたのに広告が表示される**：コンテンツブロッカーは以後に読み込まれるページから適用されます。すでに開いていたタブは再読み込み（⌘R）してください。1 ページ内で画面だけ切り替える動画サイトは、タブを閉じて開き直すのが確実です。
- **本当に効いているか確認する**：アプリの**動作確認**ボタンが公開テストサイト（https://adblock-tester.com）を Safari で開きます。スコアが高ければルールは有効です。（ローカルファイルのテストページは、Safari がサイト別のコンテンツブロッカー設定を適用しないため使えません。）
- **動画広告（再生前・再生中）はコンテンツブロッカーでは止められません。** そのために `動画広告スキップ` Web 機能拡張があり、2 層で動作します。
  - `WebExtension/main.js`（メインワールド、Safari 16.4 以降）：プレーヤー応答から広告項目を削除し、広告がそもそも始まらないようにします。対象はページに埋め込まれた `ytInitialPlayerResponse` と、ページ内移動時に `JSON.parse`・`Response.json` で解析されるすべての応答です。遅延はありません。同じ応答に含まれる YouTube の広告ブロッカー警告も削除します。この警告が動画を一時停止させ、開始画面で止まったままにするためです。
  - `WebExtension/content.js`（隔離ワールド）：それでも広告が出た場合（サーバー側挿入型など）、スキップボタンを押すか広告動画の末尾までシークします。この経路は広告を一度読み込んでから終わらせるため、1〜3 秒の遅延が残ります。警告ダイアログがそれでも表示された場合は、現れた瞬間に削除して再生を再開します。診断ログはコンソールとページの `<html>` 要素の `data-sab-log` に記録されます。
  - サイトが応答構造や画面構造を変えるとしばらく効かないことがあります。その場合はキー名やセレクタを調整してください。
- **コンテンツブロッカーが動画広告を止められない理由。** 広告は動画と同じサーバーから同じ方式で届き、広告かどうかはプレーヤーの応答内でしか決まらないため、URL で判定するコンテンツブロッカーには区別できません。Safari 用の有料ブロッカーでも同じです。ホーム・検索・再生ページの広告カードとバナーは隠します（`filters/custom.txt` の動画サイトの項目）。
- **Safari のプロファイル（よくある原因）**：タブバー左端にプロファイルアイコンが表示されていればプロファイルを使っています。機能拡張とコンテンツブロッカーはプロファイルごとにオンにする必要があり、設定 › 機能拡張のスイッチはデフォルト（個人用）プロファイルにしか適用されません。Safari › 設定 › **プロファイル** › 該当プロファイル › **機能拡張**タブでオンにしてください。アプリが表示する「オン」もデフォルトプロファイルの状態です。
- **サイト別のデフォルト**：Safari › 設定 › Web サイト › コンテンツブロッカー › **ほかの Web サイトを閲覧するとき**が「オフ」だと、機能拡張をオンにしてもどこでもブロックされません。「オン」にしてください。
- **プライベートブラウズウインドウ**：Safari 17 以降では、プライベートブラウズで機能拡張を別途許可する必要があります。Safari › 設定 › 機能拡張 › 各項目 › **プライベートブラウズで許可**。
- **Safari がルールの再読み込みに応答しない**：`ルールを再読み込み`は 20 秒でタイムアウトします。macOS 26 では Safari が完了コールバックを返さないことがありますが、ルール自体はすでに再取得されています（機能拡張プロセスの起動がシステムログに残ります）。
- **ログを見る**：`/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jhunos.SafariAdBlock"'` — 機能拡張の認識状況と再読み込み結果が記録されます。（zsh では `log` が組み込みコマンドなのでフルパスが必要です。）
- **機能拡張はオンなのに何も起きない（開発時）**：機能拡張のバイナリは **AppKit をリンク**していなければなりません。Foundation だけだと機能拡張プロセスは起動するもののリクエストがハンドラに届かず、Safari は 2 分後に `SFErrorDomain Code=3`（loading interrupted）で諦めます。システムログに `misconfigured plugin; external subsystem [NSSharingService_Subsystem] not present` というフォルトが残ります。`build.sh` はすでに `-framework AppKit` を渡しています。

## 仕組み

```
filters/sources/*.txt ─▶ tools/convert.py ─▶ rules/<ext>.json ─▶ <ext>.appex/blockerList.json ─▶ Safari
   (EasyList 構文)         (Safari ルールに変換)     (tools/validate で WebKit 検証)
```

- `tools/convert.py` — EasyList（ABP）構文を Safari ルール（JSON）に変換します。`||domain^`、アンカー、ワイルドカード、`$third-party`、`$domain=`、リソースタイプ、`@@` 例外、`##` 要素非表示（ドメイン別・全体・例外）に対応し、Safari で表現できないもの（正規表現ルール、`$redirect`/`$csp` などの拡張オプション、uBO 専用擬似クラスなど）はスキップします。ルールの順序はブロック → 要素非表示 → 例外です。
- `tools/validate` — Safari と同じ WebKit コンパイラで結果を検証します。コンパイルに失敗するルールは二分探索で特定して除外します。WebKit は無効な CSS セレクタをエラーなしに黙って捨てる（結合されたセレクタ群ごと消える）ため、セレクタは `querySelector` で 1 つずつ事前チェックします。
- `tools/smoke-test` — 変換した広告ルールを WKWebView に適用し、広告スクリプト・画像が実際にブロックされ、広告要素が隠れることを確認します（`update-rules.sh` の最後に自動実行）。
- Safari のコンテンツブロッカーは 1 つあたり 150,000 ルールまでなので、リストを 3 つの機能拡張に分けています。
- 3 つのコンテンツブロッカーは同じソース（`Sources/ContentBlocker`）を共有し、ルールファイルだけが異なります。

## 構成

```
Sources/App/               コンテナアプリ（SwiftUI）：状態表示、Safari 設定を開く、ルール再読み込み、言語メニュー
Sources/ContentBlocker/    コンテンツブロッカーのエントリポイント（3 つで共有）
Sources/WebExtension/      動画広告スキップ Web 機能拡張のネイティブ側（最小実装）
WebExtension/              manifest.json、main.js（応答から広告を除去）、content.js（スキップ）、content.css、_locales/（言語別の名前と説明）
Resources/                 Info.plist、entitlements、アプリアイコン、Localizations/<code>.json 文字列テーブル
filters/custom.txt         自分のルール（広告ブロックのリストに含まれる）
filters/sources/           ダウンロードした元リスト（update-rules.sh が生成）
rules/                     変換済み Safari ルール（JSON）とメタ情報（ビルド時に生成、リポジトリには含めない）
tools/convert.py           変換ツール
tools/validate.swift       WebKit 検証ツール
tools/smoke-test.swift     変換結果を WKWebView に適用して実際のブロックを確認
tools/make-icon.swift      アプリアイコン生成
build.sh / install.sh / update-rules.sh
```

## プライバシー

このアプリと機能拡張はネットワークリクエストを行わず、いかなるデータも収集・送信しません。フィルタリストは自分で `update-rules.sh` を実行したときだけダウンロードされます。コンテンツブロッカーはルールリストを Safari に渡すだけでページ内容を見ることはできず、`動画広告スキップ`は manifest に記載された動画サイトでのみ実行され、その中でのみ動作します。コードはすべてこのリポジトリにあります。

## ライセンスと免責

- このリポジトリのコードは [MIT](LICENSE) です。
- フィルタリストはリポジトリに含めず、ビルド時にダウンロードします。各リストのライセンス：
  - [EasyList](https://easylist.to)、[EasyPrivacy](https://easylist.to) — GPLv3 / CC BY-SA 3.0（[ライセンス](https://easylist.to/pages/licence.html)）
  - [List-KR](https://github.com/List-KR/List-KR)（AdGuard 配布の filterslist-KO）— GPLv3
  - [YousList](https://github.com/yous/YousList) — CC BY-SA 4.0
- 広告をスキップすることは動画サイトの利用規約に反する可能性があります。使用は自己責任であり、このソフトウェアはいかなる保証もなく提供されます。
