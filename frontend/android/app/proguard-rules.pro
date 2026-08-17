# R8 / ProGuard rules for the release build.
#
# This file exists because `flutter build apk --release` failed at
# `:app:minifyReleaseWithR8` with eight missing classes. Nobody had noticed,
# because nothing in this project had ever built a release APK — `flutter run`
# builds debug, which does not minify. So the app's release build was broken,
# and would have stayed broken until the first attempt to ship it.

# ── ML Kit text recognition: the four scripts this app does not use ───────────
#
# google_mlkit_text_recognition supports five scripts, and its initialize()
# method references all five recognizer option classes in one switch. The Gradle
# dependency for each script is separate, and this app pulls only the Latin one —
# because Latin is the only script it asks for (TextRecognitionScript.latin in
# mlkit_text_extractor.dart).
#
# R8 sees the four unresolved references and refuses to continue. These rules
# tell it not to: the branches that would construct those classes are
# unreachable, because nothing in this app ever selects those scripts.
#
# This is a suppression, not a fix, and it is the correct one. The alternative is
# adding four more ML Kit model dependencies — tens of megabytes of recognizers
# for languages this product does not target — to satisfy a static reference that
# is never taken.
#
# If a script is ever genuinely needed, add its dependency in
# app/build.gradle.kts and delete the matching line here. Do not add a script to
# TextRecognitionScript without doing both.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# The Latin recognizer IS used, and is reached reflectively through ML Kit's
# own component registry rather than by a direct call R8 can trace. Keeping it
# explicitly, so a future shrink cannot decide it is unreachable and remove the
# only OCR engine in the app.
-keep class com.google.mlkit.vision.text.latin.** { *; }
-keep class com.google.mlkit.vision.text.internal.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text** { *; }

# ── Syncfusion PDF ────────────────────────────────────────────────────────────
#
# Pure Dart, so R8 does not touch its logic. Kept as a note rather than a rule:
# if PDF extraction ever fails only in release builds, this is the first place
# to look, and the absence of a rule here is the reason it would be a surprise.
