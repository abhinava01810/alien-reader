# ML Kit text recognition: the plugin can create Chinese, Devanagari,
# Japanese and Korean recognizers, but the app bundles only the Latin model
# (google_mlkit_text_recognition without the extra script packages). Those
# classes are absent on purpose, so R8 must not fail on them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
