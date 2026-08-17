# Vendored: flutter_tesseract_ocr

Fork of [`flutter_tesseract_ocr`](https://pub.dev/packages/flutter_tesseract_ocr)
**0.4.31**, taken from the pub cache on 2026-08-17. BSD 3-Clause, © 2019 Ahmet
tok — `LICENSE` is preserved unmodified.

## Why this is vendored rather than depended on

The published package cannot be built by this project. Its
`android/build.gradle` calls `jcenter()`, and Gradle **removed** that method;
JCenter itself shut down in 2021. So the plugin's project cannot be evaluated:

```
1: A problem occurred evaluating project ':flutter_tesseract_ocr'.
   > Could not find method jcenter() for arguments [] on repository container...

2: A problem occurred configuring project ':flutter_tesseract_ocr'.
   > java.lang.NullPointerException
   > 'kotlin-android' plugin requires one of the Android Gradle plugins.
```

Failure 2 is a consequence of failure 1 — and reading only failure 2 is how an
earlier diagnosis in this repository concluded, wrongly, that the problem was
AGP 9 incompatibility. It is not: `jcenter()` was removed by Gradle, so no AGP
version and no `newDsl` setting would have helped.

Two CI runs established this, the second on a green baseline where the Android
job passes and the project's first release APK had just been produced.

## Why Arabic needs it at all

ML Kit Text Recognition v2 ships five script models — latin, chinese,
devanagari, japanese, korean — and **no Arabic**. The Smart Keyword Alert
specification's §3.6 recommends "ML Kit + Arabic model"; no such model exists.
In an Arabic-first product, ML Kit alone leaves the primary language unreadable
in photographs.

## Changes from upstream

Only `android/build.gradle` was rewritten. Dart, Java, and iOS sources are
byte-identical to the published package.

| Change | Reason |
|---|---|
| Removed the `buildscript` block | It pinned AGP 7.1.2, fighting this project's 9.0.1. A plugin does not resolve its own AGP. |
| Removed `jcenter()` | The blocker. The method no longer exists. |
| Removed `flatDir` from `rootProject.allprojects` | It added a flat-directory repository to every module in the consuming app. The AAR is unpacked instead — see below. |
| `compileSdkVersion` → `compileSdk`, `minSdkVersion` → `minSdk` | Non-deprecated spellings. |
| Dropped the `images/` asset bundle | 64 KB of upstream test JPEGs, shipped in the APK for no reason. |
| Dropped the `web` platform entry | Malformed upstream (`default_package: FlutterTesseractOcrPlugin` names a class, not a package) and this app does not target web. |

## The binaries, and what trusting them means

The upstream package ships `tesseract4android-release.aar`, a prebuilt
[Tesseract4Android](https://github.com/adaptech-cz/Tesseract4Android) build. That
AAR is **not** committed here, because AGP refuses it:

```
Direct local .aar file dependencies are not supported when building an AAR.
```

That is a real restriction rather than pedantry — a nested AAR's classes and
resources genuinely get dropped from the enclosing one — and it is exactly what
upstream's `flatDir` hack was working around. So the AAR was unpacked into the
two forms AGP supports natively:

| Path | Contents | Size |
|---|---|---|
| `android/libs/tesseract4android.jar` | the AAR's `classes.jar`, unmodified | 49,342 bytes |
| `android/src/main/jniLibs/<abi>/` | `libtesseract`, `libleptonica`, `libjpeg`, `libpngx` for arm64-v8a, armeabi-v7a, x86, x86_64 | 30.53 MB |

Provenance, so this is reproducible:

```
source AAR   flutter_tesseract_ocr 0.4.31, android/libs/tesseract4android-release.aar
AAR size     14,082,032 bytes
AAR sha256   831c363204e3e3cd2405665568bf3e09a30f904a87b3922e50ef852fe53153dd
jar sha256   c5894e042af37b88aa4758f22728262195ce6fa8f167d8974ffe2c3987d86fc1
```

To reproduce: take that AAR from the pub cache, `unzip` it, and the `classes.jar`
and `jni/` tree are what is committed here. Nothing was recompiled or re-signed.

**These are prebuilt native libraries that nobody in this project has audited**,
running in-process in a security product, over documents its users consider
sensitive. That is worth stating plainly rather than burying in a dependency
list.

The realistic alternatives were each worse:

| Alternative | Problem |
|---|---|
| JitPack (`com.github.adaptech-cz:Tesseract4Android`) | Builds arbitrary GitHub repositories on demand. Less predictable than a fixed artifact whose hash is recorded here. |
| Maven Central | Tesseract4Android is not published there — checked directly against repo1. |
| Build Tesseract from source | Weeks of NDK work, and the result would still need auditing. |
| No Arabic image OCR | What the product had, and the reason this was done at all. |

If that trade is unacceptable, the honest fallback is to delete this directory and
the `flutter_tesseract_ocr` dependency, and accept that Arabic works only where
characters are *stated* rather than recognised — PDF text layers and plain text.
Both paths are legitimate; the choice belongs to whoever owns the threat model.

## Keeping it current

Upstream is unlikely to fix the `jcenter()` call soon; the package has carried it
for years. If a release ever does, this directory should be deleted and the
published package used again. To check what changed:

```bash
diff -r packages/flutter_tesseract_ocr/lib \
        ~/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_tesseract_ocr-<new>/lib
```

Only `android/build.gradle` should ever differ.
