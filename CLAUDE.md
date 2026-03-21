# SpacePin

macOS向けのフローティングピン（ノート/画像）アプリ。Swift + AppKit。

## 開発環境

- Xcode を開くには `xed` コマンドを使う（`open -a Xcode` は非標準パスだと失敗する）
- Xcode が複数バージョンある場合は `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` で切り替え

## ビルド & リリース

- `ruby scripts/generate_xcodeproj.rb` - Xcode プロジェクトを再生成
- `bash scripts/archive_app_store.sh` - App Store 用アーカイブ作成
- `bash scripts/export_app_store.sh` - アーカイブをエクスポート (.pkg)
- エクスポート/アップロードには Xcode の Accounts でログイン済みセッションが必要
- アップロード: `xcrun altool --upload-app -f .derived/export-app-store/SpacePin.pkg -t macos -u <Apple ID> -p @keychain:AC_PASSWORD`
- アプリアイコンは `.icon` 形式 (`Support/AppIcon.icon`) + ICNS (`Support/AppIcon.icns`)。旧 `generate_app_icons.swift` は使わない
- App Store は ICNS 形式のアイコンも必須。`.icon` だけでは UPLOAD FAILED になる
