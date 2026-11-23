# DOOOOOR: THE CALL — Cloudflare公開手順

公開先は [dooooor-the-call.cacao-ixora-coccinea.workers.dev](https://dooooor-the-call.cacao-ixora-coccinea.workers.dev/)。

Godotの既存Web書き出しをWorkers Static Assetsで配信する。`index.wasm` は約37.7 MiBで1ファイル25 MiBの上限を超えるため、gzipで約9.7 MiBにして配置する。Workerは `/index.wasm` に対し `application/wasm` で返す。ブラウザがgzipを受信できる場合はあらかじめ圧縮した内容を使う。その他のゲームファイルは静的アセットとして配信する。R2の設定は不要。

## 更新

Godotの `Web` プリセットでリポジトリ直下の `build/web/index.html` に書き出す。`cloudflare/` に移動し、以下を実行する。Node.jsは使用する `cf` のサポート範囲（24系は24.22以降）に合わせる。

```powershell
npm ci
npm run prepare:web
cf build
npm run typecheck
cf deploy --prebuilt --no-provision
```

`npm ci` は依存関係の初回セットアップと更新時に実行する。`public/` は `prepare:web` が生成する。公開後はゲームのタイトル画面、開始・移動操作、ベルの出力を確認する。
