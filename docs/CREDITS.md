# Credits / 使用素材と生成AI利用の記録

## 制作

- 企画・ゲームデザインの芯：madowaku
- ディレクション、設計、実装、検証：Claude Fable 5.2（Anthropic の生成AI、Claude Code 上で作業）
- 人物モデルとアニメーション（`scripts/human.gd`）、HUD と画面シェーダ（`scripts/hud.gd`, `shaders/post.gdshader`）：Claude Opus 5.5（同上、Fable 5.2 の仕様書に基づく）

## 生成AIの利用開示

| 対象 | AIの関与 |
|---|---|
| プログラム（GDScript、シェーダ、Python ツール） | すべて生成AI（Claude）が記述 |
| レベルデザイン・パズル | 生成AIが設計し、全探索プログラムで検証 |
| テクスチャ・ロゴ・アイコン（`assets/tex/*.png`） | 画像生成AIは不使用。AIが書いた Python（`tools/gen_textures.py`, `tools/gen_human_tex.py`）による手続き生成 |
| 効果音（`assets/audio/*.wav`） | 音声生成AIは不使用。AIが書いた Python（`tools/gen_audio.py`）による波形合成 |
| 3Dモデル | モデル生成AIは不使用。建物は箱と面、人物は多角形の輪を積んだメッシュをコードで組み立てている |
| 音楽 | なし（BGMなし） |

既存の DOOOOOR のコード・素材、実在の PS2 作品のモデル・音源・デザインは使っていない。

## 外部素材

| 素材 | 使用箇所 | 作者 | ライセンス |
|---|---|---|---|
| Impact Sounds（`footstep_wood/carpet/concrete_000〜004.ogg`） | 足音 | Kenney (kenney.nl) | CC0 1.0 |
| RPG Audio（`cloth1〜3.ogg`, `creak1〜3.ogg`） | 衣擦れ、扉のきしみ | Kenney (kenney.nl) | CC0 1.0 |

扉の蝶番の鳴き（`door_squeak.wav`）は自前の合成音。以前使っていた第三者の音素材は取り除いた。
| DotGothic16（`assets/font/DotGothic16-Regular.ttf`） | 画面内の文字、看板、ロゴ | The DotGothic16 Project Authors | SIL Open Font License 1.1（`assets/font/OFL.txt` 同梱） |


## エンジン

Godot Engine 4.7（MIT License）。https://godotengine.org/license

## クレジット表記の例（itch.io ページ用）

```
Made with Godot 4.7.
Sound: Kenney (CC0). Font: DotGothic16 (OFL).
Code, level design, procedural textures and synthesized sound effects were written by generative AI (Claude) under human direction.
```
