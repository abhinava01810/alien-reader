# ML Kit text recognition: the plugin can create Chinese, Devanagari,
# Japanese and Korean recognizers, but the app bundles only the Latin model
# (google_mlkit_text_recognition without the extra script packages). Those
# classes are absent on purpose, so R8 must not fail on them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# shared_preferences_android 2.5.x calls its Kotlin code from Dart through
# JNI (SharedPreferencesApiRegistrar) but ships no keep rules. JNI finds
# methods by exact name and signature, and those signatures include
# kotlin.coroutines.Continuation (they are suspend functions). R8 renamed
# Continuation, so the lookup failed and the release app could not start
# (NoSuchMethodError: SharedPreferencesApiRegistrar.getAll). Keep both.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
# Kotlin classes the Dart jni package looks up by name (list taken from
# package:jni and the plugin's generated bindings).
-keep interface kotlin.coroutines.Continuation
-keep class kotlin.coroutines.intrinsics.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
-keep interface kotlin.enums.EnumEntries
-keep class kotlin.jvm.internal.DefaultConstructorMarker
