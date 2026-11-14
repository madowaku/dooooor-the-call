# DOOOOOR: THE CALL

すべてのドアからノブが消えた建物。ひとつだけ持っている自分のドアノブを使い、どこかで鳴っている黒電話に出る。

THE LOST PS2 JAM 向けの短編（空間パズル＋静かな探索）。Godot 4.7 / GDScript / GL Compatibility。

## 構成（4話＋終幕）

| 話 | 図面 | 場所 | 扉 | 最短 | 探す音 |
|---|---|---|---|---|---|
| 1 | `level/building.txt` | 本館1階 | 4枚 | 5回転 | 黒電話のベル |
| 2 | `level/ch2.txt` | 宿直棟と渡り廊下 | 3枚 | 6回転 | ピンク電話のベル |
| 3 | `level/ch3.txt` | 地下の浴場とボイラー室 | 3枚 | 6回転 | 壁掛けベル（配管が音を行き止まりへ運ぶ） |
| 4 | `level/ch4.txt` | 旧館の最上階 | 2枚＋最後の扉 | 3回転 | 電話ではなく、扉を内側から叩く音 |

- 電話に出ると、受話器の奥でダイヤルが回り、次の話の音が聞こえて暗転する。そのまま次の話が始まる。
- 4話の最後の扉は、穴が閉じた部屋の内側にしかない。格子越しにノブを渡す（ノブを抜くボタン）と、向こうの誰かが扉を回し、扉の決まりどおり自分の通路が塞がる。残った電話のダイヤルを方向入力で3回まわすと、遠くで1話のベルが鳴り、タイトルへ戻る。
- 進んだ話は保存され、タイトル画面の X（パッドは B）で続きから始められる。
- 2〜4話の部屋の見た目・照明・音・小物は、図面ファイルの `room` `bell` `line` `amb` `duct` `prop` などの行で指定する（`scripts/level_meta.gd` の冒頭に書式）。規則を読む `scripts/level_logic.gd` はこれらの行を無視するので、見た目を変えても全探索の結果は変わらない。
- 2〜4話のカメラは部屋ごとに自動で置く。常に部屋の南東の角から北か西を向くので、どの部屋に入っても画面の上が南になることはない。

## 操作

| | キーボード | ゲームパッド |
|---|---|---|
| 移動 | 矢印キー / WASD | 十字キー / 左スティック |
| けってい（触る・ノブを付ける・つかむ・はなす・受話器を取る） | Z / Space / Enter | A |
| ノブを抜く | X / Backspace | B |
| 音のめやす（視覚補助）：なし → ふつう → つよい | C | Y |
| ポーズ | Esc | START |
| 全画面 | F11 / Alt+Enter | |

扉をつかんでいる間は、床の矢印の方向へ入力すると扉が回る。

## ルール（ゲーム内では文章で説明しない）

- 扉は柱を軸に90度ずつ回り、必ずどこか1か所の出入口を塞ぐ。
- ノブ穴は扉の片面にしかない。穴のない面からは動かせない。
- ノブを回した人はノブの側に残る。押せば扉と一緒に進み、引けば自分を締め出す。
- ノブは抜いて持ち歩ける。抜いても扉の角度は変わらない。
- 黒電話のベルは開いた出入口・格子・通気口を通って伝わり、閉じた扉でこもる。音が近いことと、そこへ行けることは一致しない。

すべての操作は可逆なので、詰みは存在しない（下の探索で確認）。

## 場所の手がかり（地図は出さない）

- 扉は4枚とも塗装の色と番号札が違う（1 緑、2 赤茶、3 黄土、4 青灰）。床の円弧の擦り跡は、その扉が回れる範囲。
- 開始地点の廊下には緑の非常口灯、西廊下には雨漏りとバケツと下駄箱、北廊下には火災報知の赤ランプ、東廊下は青灰の壁と額3枚。
- 音のめやすを入れると、ベルが画面の縁の波紋として見える。届いてくる側の縁に出て、数が音量、つながった速い輪が澄んだ音、途切れた遅い輪がこもった音。暗い赤の太い輪は壁越しの響きで、常に電話の方向。ノブのアイコンもベルに合わせて震える。
- ベルは2つの層で鳴る。開いた出入口を伝う金属音（扉の向きで方向も明るさも変わる）と、壁を抜けてくる低い響き（常に電話の方向を指す）。

## フォルダ

| 場所 | 中身 |
|---|---|
| `level/building.txt` | 建物の平面図（ゲームと検証ツールが同じファイルを読む） |
| `scripts/level_logic.gd` | 盤面ルール |
| `scripts/solver.gd` | 状態空間の全探索 |
| `scripts/building.gd` `door.gd` | 平面図から3Dを組み立てる |
| `scripts/sound_field.gd` | ベルの伝播（出入口グラフ上の最短経路） |
| `scripts/main.gd` | 進行・カメラ・音のミックス・QAボット |
| `scripts/story.gd` `level_meta.gd` | 話の切り替え、2〜4話の自動カメラ、終幕／図面ファイルの見た目と音の指定 |
| `scripts/human.gd` `hud.gd` `shaders/post.gdshader` | 人物・HUD・画面仕上げ |
| `tools/gen_textures.py` `gen_textures2.py` `gen_human_tex.py` `gen_audio.py` | テクスチャと効果音をコードから生成 |
| `tools/shot_human.gd` `test_human.gd` | 人物だけを撮影・点検する |
| `docs/` | 提出用の資料 |

## DOOOOOR LAB（開発用のテスト盤面）

パズルの案を、建物を作る前に手で試すための簡素なモード。タイトル画面で L キー、または起動引数 `--lab`。

- 盤面は `level/lab/*.txt`。壁と扉と電球だけの部屋を、南側の上から建物全体が見える固定カメラで映す。
- 遊んでいる間は R でやり直し、L で一覧へ。電話に出ると回転数と時間を記録し、最短解の回転数はクリア後にだけ表示する。
- 記録は `build/lab_log.txt`（書き出し版は exe と同じフォルダ）に、回した扉の順番つきで追記される。

```
godot --headless --path . -s tools/lab.gd                       # 盤面の計測（必須の扉、押す/引く/抜き直しを禁じたときの可否）
godot --headless --path . -s tools/lab.gd -- --gen=40000 --size=4x3 --doors=2   # 小さな盤面を自動生成して候補を出す
godot --headless --path . -s tools/lab_sound.gd -- --level=res://level/building.txt --door=3   # 扉1枚が音をどれだけ変えるか
godot --path . -- --lab=c_come_back --labbot                    # 最短解を実機で通す
```

## 検証コマンド

Godot は `C:\Dev\Tools\Godot-4.7-stable\Godot_v4.7-stable_win64_console.exe` を使用。

```
godot --headless --path . -s tools/solve.gd      # 盤面の全探索（解の有無・詰み・近道）
godot --path . -- --autoplay                     # 最短解を実機で通し、build/shots に画面を保存
godot --path . -- --monkey --seed=1              # ランダム操作70手のあと電話まで到達できるか
godot --path . -- --tour                         # 各部屋と各扉の画面を保存
godot --path . -- --chapter=3 --autoplay         # 2〜4話は --chapter=N を付ける（--monkey も同じ）
godot --path . -- --marathon                     # 1話から終幕まで、本物の場面転換を通して一気に遊ぶ
godot --headless --path . -s tools/lab.gd -- --file=res://level/ch2.txt   # 2〜4話の盤面の計測
```

2026-11-14 時点の結果：到達可能 4532 状態、詰み 0、未到達マス 0、最短 5 回転。扉1・扉2は必須、扉3・扉4はどちらか一方で解ける（別解あり）。`--autoplay` はエディタ実行・Windows書き出し版の両方で完走、`--monkey` は seed 1〜3 で完走。

## 書き出し

```
godot --headless --path . --export-release "Windows Desktop" build/windows/DOOOOOR_THE_CALL.exe
godot --headless --path . --export-release "Web" build/web/index.html
```

素材の出どころと生成AIの利用は [docs/CREDITS.md](docs/CREDITS.md) に記録。
