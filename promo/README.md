# DOOOOOR: THE CALL — X投稿用映像

THE LOST PS2 JAM向け。1080×1350・30 fps・631フレーム（21.03秒）。中央のゲーム映像は1024×768の撮影素材を、4:3のまま1032×774で表示する。

## 編集と書き出し

`promo` ディレクトリで実行する。Node.js 24で確認。`npm ci` は初回のみ。

```powershell
npm ci
npm run dev
```

Studioの `TheCallPromo` が動画、`TheCallThumbnail` がサムネイル。`src/Composition.tsx` にカットごとの開始フレーム、素材内の開始フレーム、長さ、音量がある。色・書体・ロゴ配置は `src/promo.css`。`public/media` の素材を含めれば、編集と書き出しにGodotは不要。

```powershell
npx remotion render TheCallPromo out/DOOOOOR-THE-CALL-X.mp4 --codec=h264 --crf=17 --pixel-format=yuv420p --audio-bitrate=192k
npx remotion still TheCallThumbnail out/DOOOOOR-THE-CALL-thumbnail.png
```

Windowsの書き出し検証では、両コマンドに `--browser-executable="C:/Program Files/Google/Chrome/Application/chrome.exe"` を追加した。

## カットと素材

| 時間 | 内容 | 素材 |
| --- | --- | --- |
| 0.00–3.73秒 | 鳴る黒電話、廊下を歩いて扉1へ | `phone.mp4`、`first-door.mp4`、冒頭の `bell_ring.wav` |
| 3.73–8.30秒 | ノブ穴のない面、反対側の空のノブ穴、ポケットからノブを出して取り付ける | `blank-face.mp4`、`first-door.mp4` |
| 8.30–13.00秒 | 俯瞰で扉1の回転前、90度の回転、回転後 | `first-door.mp4` |
| 13.00–16.67秒 | 西廊下と青いタイルの地下室 | `west-hall.mp4`、`basement.mp4` |
| 16.67–18.60秒 | 第1話の黒電話に戻り、受話器を取る音でベルが止まる | `phone.mp4` |
| 18.60–21.03秒 | ロゴとitch.ioのアドレス | `logo_main.png`、`logo_sub.png`、DotGothic16 |

各カットの映像と足音、衣擦れ、ノブと扉の音、最後のベルと残響はGodot Movie Makerの収録。冒頭は収録映像にゲームの元のベル音を重ねた。BGMなし。サムネイルの黒電話は同じ収録から切り出した1フレーム。フォントのライセンスは `public/media/OFL.txt`、ゲーム素材のクレジットは [docs/CREDITS.md](../docs/CREDITS.md)。

## 撮影の再現

収録元は `2494866` のGodotプロジェクト。リポジトリ直下で実行する。`first-door` は既存のQAボットで最初の扉の1回転まで実際に操作する。ほかの撮影では目的の場所へ直接移動し、電話の寄りと扉の裏面に撮影用のカメラを使う。受話器を取る場面は第1話から収録し、回線の音が流れる前に停止する。第3話は地下室の歩行だけを収録する。

```powershell
$godot = 'C:/Dev/Tools/Godot-4.7-stable/Godot_v4.7-stable_win64_console.exe'
New-Item -ItemType Directory -Force promo/.work | Out-Null
foreach ($take in 'phone', 'first-door', 'blank-face', 'west-hall', 'basement') {
    $takeArgs = @($take)
    if ($take -eq 'basement') { $takeArgs += '--chapter=3' }
    & $godot --path . --disable-vsync --resolution 1024x768 --fixed-fps 30 `
        --write-movie "$PWD/promo/.work/$take.avi" --script res://promo/capture/record.gd -- @takeArgs
    if ($LASTEXITCODE -ne 0) { throw "Godot capture failed: $take" }
}
```

編集素材のMP4には、元のAVIから次の範囲をFFmpegで切り出した。開始フレームを30で割った秒数を `-ss` に、フレーム数を `-frames:v` に指定し、`-c:v libx264 -crf 15 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart` で変換する。

| 撮影 | 開始フレーム | フレーム数 |
| --- | ---: | ---: |
| `phone` | 98 | 215 |
| `first-door` | 120 | 523 |
| `blank-face` | 138 | 34 |
| `west-hall` | 148 | 74 |
| `basement` | 88 | 81 |

## 完成ファイルの検証

- MP4を全編デコードして、H.264の631フレーム、1080×1350、30 fps、AACステレオを確認。
- 各カットの境目、扉の回転前後、受話器を取るフレーム、タイトルとURLを完成MP4から抽出して確認。指定のネタバレ場面および番号を含まないことを、採用した撮影区間とフレームから確認。
- 音量は全編で −17.7 LUFS、トゥルーピークは −2.0 dBTP。18.57秒から残響が検出閾値の −53 dB を下回り、18.60秒からタイトルカードを表示。
- サムネイルは1080×1350のPNG。動画と合わせてRemotion Studioで編集用のコンポジションを確認。
