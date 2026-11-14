# DOOOOOR: THE CALL

すべてのドアからノブが消えた建物。ひとつだけ持っている自分のドアノブを使い、どこかで鳴っている黒電話に出る。

THE LOST PS2 JAM 向けの短編（空間パズル＋静かな探索）。Godot 4.7 / GDScript / GL Compatibility。

## 操作

| | キーボード | ゲームパッド |
|---|---|---|
| 移動 | 矢印キー / WASD | 十字キー / 左スティック |
| けってい（触る・ノブを付ける・つかむ・はなす・受話器を取る） | Z / Space / Enter | A |
| ノブを抜く | X / Backspace | B |
| 音のめやす（視覚補助）の切替 | C | Y |
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

## フォルダ

| 場所 | 中身 |
|---|---|
| `level/building.txt` | 建物の平面図（ゲームと検証ツールが同じファイルを読む） |
| `scripts/level_logic.gd` | 盤面ルール |
| `scripts/solver.gd` | 状態空間の全探索 |
| `scripts/building.gd` `door.gd` | 平面図から3Dを組み立てる |
| `scripts/sound_field.gd` | ベルの伝播（出入口グラフ上の最短経路） |
| `scripts/main.gd` | 進行・カメラ・音のミックス・QAボット |
| `scripts/human.gd` `hud.gd` `shaders/post.gdshader` | 人物・HUD・画面仕上げ |
| `tools/gen_textures.py` `gen_audio.py` | テクスチャと効果音をコードから生成 |
| `docs/` | 提出用の資料 |

## 検証コマンド

Godot は `C:\Dev\Tools\Godot-4.7-stable\Godot_v4.7-stable_win64_console.exe` を使用。

```
godot --headless --path . -s tools/solve.gd      # 盤面の全探索（解の有無・詰み・近道）
godot --path . -- --autoplay                     # 最短解を実機で通し、build/shots に画面を保存
godot --path . -- --monkey --seed=1              # ランダム操作70手のあと電話まで到達できるか
godot --path . -- --tour                         # 各部屋と各扉の画面を保存
```

2026-11-14 時点の結果：到達可能 4532 状態、詰み 0、未到達マス 0、最短 5 回転。扉1・扉2は必須、扉3・扉4はどちらか一方で解ける（別解あり）。`--autoplay` はエディタ実行・Windows書き出し版の両方で完走、`--monkey` は seed 1〜3 で完走。

## 書き出し

```
godot --headless --path . --export-release "Windows Desktop" build/windows/DOOOOOR_THE_CALL.exe
godot --headless --path . --export-release "Web" build/web/index.html
```

素材の出どころと生成AIの利用は [docs/CREDITS.md](docs/CREDITS.md) に記録。
