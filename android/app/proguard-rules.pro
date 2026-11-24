# Flutter rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.**

# Google ML Kit Text Recognition
-dontwarn com.google.mlkit.vision.text.**
-dontwarn com.google_mlkit_text_recognition.**

# Google Sign In & Google API client
-keepclassmembers class * {
    @com.google.api.client.util.Key <fields>;
}
-keep class com.google.api.services.** { *; }
-dontwarn com.google.api.client.**
-dontwarn com.google.auth.**
-dontwarn org.apache.commons.logging.**
-dontwarn javax.annotation.**
