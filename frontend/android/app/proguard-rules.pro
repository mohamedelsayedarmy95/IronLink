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

# ── The rules above were necessary and not sufficient ─────────────────────────
#
# With only those, the release APK built and then died on launch, before a
# single line of Dart ran:
#
#   FATAL EXCEPTION: main
#   Unable to get provider com.google.mlkit.common.internal.MlKitInitProvider:
#   Unsatisfied dependency for component
#     Component<[com.google.mlkit.vision.text.internal.zzo]>
#     ... com.google.mlkit.common.sdkinternal.d
#
# Found by installing the release build on a real phone (Honor 8X, Android 10),
# which is the only thing that could have found it. The unit tests do not run
# R8 and do not run on Android. CI *builds* this APK on every push and has never
# once *started* it, so a green pipeline coexisted with an app that could not
# open.
#
# The mechanism: ML Kit initialises through a dependency-injection graph whose
# components declare their dependencies as Class objects, resolved at runtime.
# The rules above kept the text-recognition half of that graph and not the
# common half it depends on, so R8 removed `com.google.mlkit.common.sdkinternal`
# entirely — correctly, by its own analysis, because nothing references it in a
# way static analysis can see.
#
# WHY THESE RULES ARE BROAD, DELIBERATELY
#
# Keeping one more package would fix today's crash and leave the next dependency
# edge to be discovered the same way — by an app that will not start, on
# somebody's phone. A dependency-injection graph is precisely the structure
# where narrow keep rules fail one edge at a time.
#
# So the whole SDK is kept. It costs APK size, and the engineering priority
# hierarchy is unambiguous about that trade: Reliability outranks Performance,
# and an app that does not launch has no performance characteristics worth
# measuring.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit** { *; }

# Component discovery itself. ML Kit and Firebase both find their registrars by
# scanning for implementations of this interface, so an implementation R8 has
# renamed is an implementation neither of them can find.
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.firebase.components.** { *; }

# ── Syncfusion PDF ────────────────────────────────────────────────────────────
#
# Pure Dart, so R8 does not touch its logic. Kept as a note rather than a rule:
# if PDF extraction ever fails only in release builds, this is the first place
# to look, and the absence of a rule here is the reason it would be a surprise.
