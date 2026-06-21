# Kang Frontend

Flutter frontend for Kang.

Open this folder in Android Studio:

```text
D:\kcastle\kang\frontend
```

Then select an Android emulator, Chrome, or a connected device and run `lib/main.dart`.

For command-line runs, use the repository-level script so `.env` values are passed as Flutter `--dart-define` values:

```powershell
cd D:\kcastle\kang
.\scripts\flutter_run_with_env.ps1 -Device chrome
```

Default API host:

- All platforms: `https://www.kang.ai.kr`

Override with `--dart-define=API_BASE_URL=<url>` when using a physical device or deployed backend.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
