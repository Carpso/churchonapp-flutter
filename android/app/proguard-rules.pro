-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Supabase / GoTrue / Postgrest
-keep class com.supabase.** { *; }
-keep class io.github.jan.supabase.** { *; }

# OkHttp (used by many plugins)
-keepattributes Signature
-keepattributes *Annotation*
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**

# Gson / JSON Serialization
-keep class com.google.gson.** { *; }
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Audio Service
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }

# Flutter Foreground Task (Carpso Ride background location)
-keep class com.pravera.flutter_foreground_task.** { *; }

# Video Player / Chewie
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class com.yourcompany.videoplayer.** { *; }

# Mobile Scanner (QR/barcode)
-keep class com.yourcompany.mobilescanner.** { *; }

# Prevent stripping of Dart model classes used in fromJson factories
# Supabase/PostgREST responses are deserialized via .fromMap / fromJson
-keep class church_on_app.features.** { *; }
-keep class church_on_app.core.** { *; }

# Lipila Payment callback models
-keep class com.lipila.** { *; }

# Bitmap downsampling — strip metadata to reduce APK size
-keepclassmembers class * extends android.graphics.drawable.Drawable {
    public int getIntrinsicWidth();
    public int getIntrinsicHeight();
}

# Prevent R8 from stripping R8 resource shrinking
-keep class ** extends android.app.Application { *; }

# Firebase / Google Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
