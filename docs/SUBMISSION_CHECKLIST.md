# itch.io / THE LOST PS2 JAM 提出チェックリスト

提出と公開は本人の操作で行う。AI はここまでを準備した。

## 用意済み

- [x] Windows 版：`build/DOOOOOR_THE_CALL_win64.zip`（単体 exe、インストール不要）
- [x] ブラウザ版：`build/DOOOOOR_THE_CALL_web.zip`（`index.html` が zip の直下）
- [x] 英語の作品紹介・操作説明・タグ案：`docs/ITCH_PAGE.md`
- [x] クレジットと AI 利用開示：`docs/CREDITS.md`
- [x] スクリーンショット：`docs/screenshots/`
- [x] カバー画像案（630x500）：`docs/cover_a.png`, `docs/cover_b.png`
- [x] 盤面の全探索（詰み 0、最短 5 回転）と、書き出した exe での自動通しプレイ

## 提出前に本人が確認すること

- [ ] exe を自分の手で最初から最後まで遊ぶ（音量、ベルの聴き疲れ、扉操作の手触り、所要時間）
- [ ] ヘッドホンとスピーカーの両方でベルの方向感とこもり方を聴く
- [ ] ゲームパッドで一通り操作する（自動テストはキーボード相当の経路のみ）
- [ ] Jam の規約を読む：テーマ適合、生成AIの扱い、提出期限、ビルド形式の指定
- [ ] Windows の SmartScreen 警告が出ることを紹介文に書くか決める（署名なしの exe のため）

## itch.io の設定

- [ ] 新規プロジェクト作成、Kind of project を選ぶ（Windows 版のみなら Downloadable、ブラウザ版も載せるなら HTML）
- [ ] ブラウザ版を載せる場合：zip をアップロードし「This file will be played in the browser」にチェック、Viewport 1024 x 768、Fullscreen button を有効
- [ ] Windows 版 zip に Windows のプラットフォーム印を付ける
- [ ] `docs/ITCH_PAGE.md` の Description / Controls / Credits / AI disclosure を貼る
- [ ] カバー画像とスクリーンショット 3〜5 枚を登録
- [ ] 生成AI利用の申告欄があれば「コードとレベルデザインに使用、画像・音声生成AIは不使用」と記入
- [ ] 価格（無料）と公開範囲を設定、下書きプレビューで動作確認
- [ ] Jam ページから Submit

## リポジトリ

- [ ] ローカルブランチ `jam/the-call` をコミットするか決める（未コミット）
- [ ] `origin`（github.com/madowaku/dooooor-the-call）へ push するか決める（未 push）
- [ ] 公開リポジトリにする場合、Wrong Room の音素材（`assets/audio/pm_squeak.ogg`）は「音素材としての再配布不可」のため、リポジトリに含めるかどうかを決める
