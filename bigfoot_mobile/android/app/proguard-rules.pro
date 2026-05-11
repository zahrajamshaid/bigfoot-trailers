# Keep Flutter runtime and plugin registration stable under R8.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-dontwarn io.flutter.embedding.**

# Preserve Firebase Messaging service classes.
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.messaging.**
