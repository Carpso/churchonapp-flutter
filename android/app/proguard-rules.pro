# ============================================================
# R8 FULL OPTIMIZATION — Church On App
# ============================================================
# Aggressive optimization for maximum performance and size reduction
-optimizationpasses 5
-allowaccessmodification
-overloadaggressively
-mergeinterfacesaggressively
-repackageclasses ''

# Keep Flutter engine classes (required for runtime)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Flutter JNI / native layer
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class io.flutter.embedding.engine.dart.DartExecutor { *; }
-keep class io.flutter.embedding.engine.renderer.FlutterRenderer { *; }

# ============================================================
# SUPABASE + GOTRUE + POSTGREST
# ============================================================
-keep class com.supabase.** { *; }
-keep class io.github.jan.supabase.** { *; }
-keep class kotlinx.serialization.** { *; }
-dontwarn kotlinx.serialization.**

# ============================================================
# NETWORK — OkHttp + Retrofit
# ============================================================
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes Exceptions, InnerClasses, EnclosingMethod, RuntimeVisibleAnnotations, RuntimeInvisibleAnnotations
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# ============================================================
# JSON — Gson + Moshi + Jackson
# ============================================================
-keep class com.google.gson.** { *; }
-keepattributes EnclosingMethod, InnerClasses
-keepattributes Signature

# ============================================================
# DART MODEL CLASSES — Keep all fromJson/toJson targets
# ============================================================
-keep class church_on_app.** { *; }
-keep class **.g.** { *; }
-keep class **.freezed.** { *; }
-keep class **.serialization.** { *; }

# Feature-specific model keeps (reflection-safe)
-keep class church_on_app.features.finance.** { *; }
-keep class church_on_app.features.admin.** { *; }
-keep class church_on_app.features.home.** { *; }
-keep class church_on_app.features.profile.** { *; }
-keep class church_on_app.features.modules.** { *; }
-keep class church_on_app.features.navigation.** { *; }
-keep class church_on_app.features.auth.** { *; }
-keep class church_on_app.features.support.** { *; }
-keep class church_on_app.core.** { *; }

# ============================================================
# AUDIO SERVICE (just_audio / audio_service)
# ============================================================
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# ============================================================
# FOREGROUND SERVICE (Carpso Ride & location)
# ============================================================
-keep class com.pravera.flutter_foreground_task.** { *; }

# ============================================================
# VIDEO PLAYER — Media3 / ExoPlayer
# ============================================================
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# ============================================================
# FIREBASE + GOOGLE PLAY SERVICES
# ============================================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Auth multi-factor
-keep class com.google.firebase.auth.** { *; }

# ============================================================
# FACEBOOK / SHIMMER / ANIMATION LIBRARIES
# ============================================================
-keep class com.facebook.** { *; }
-dontwarn com.facebook.**

# ============================================================
# LEAFCANVAS / FLUTTER_MAP
# ============================================================
-keep class org.maplibre.** { *; }
-keep class com.mapbox.** { *; }
-dontwarn org.maplibre.**
-dontwarn com.mapbox.**

# ============================================================
# SQUARE / PICASSO / COIL (image loading)
# ============================================================
-keep class com.squareup.picasso.** { *; }
-keep class coil.** { *; }
-dontwarn coil.**

# ============================================================
# ANDROID ARCHITECTURE COMPONENTS
# ============================================================
-keep class androidx.lifecycle.** { *; }
-keep class androidx.room.** { *; }
-dontwarn androidx.room.**
-keep class androidx.work.** { *; }

# ============================================================
# R8 RESOURCE SHRINKING — keep app resources
# ============================================================
-keep class **.R$* { *; }
-keep class ** extends android.app.Application { *; }

# Bitmap metadata (needed for image caching)
-keepclassmembers class * extends android.graphics.drawable.Drawable {
    public int getIntrinsicWidth();
    public int getIntrinsicHeight();
}

# ============================================================
# STRIP LOGGING IN RELEASE (safe after debugging)
# ============================================================
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# ============================================================
# DART / FLUTTER RUNTIME REFLECTION CALLBACKS
# ============================================================
-keepclassmembers class * {
    native <methods>;
}
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep enum classes (Dart enums bridge to Java)
-keepclassmembers enum * { *; }

# ============================================================
# LOCAL BROADCAST / RECEIVERS
# ============================================================
-keep class android.content.** { *; }

# ============================================================
# THIRD-PARTY CRASH REPORTERS
# ============================================================
-keep class com.sentry.** { *; }
-keep class net.hockeyapp.** { *; }
-dontwarn com.sentry.**
-dontwarn net.hockeyapp.**

# ============================================================
# WEBRTC (for voice/video calls & streaming)
# ============================================================
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# ============================================================
# CRYPTOGRAPHY / ENCRYPT
# ============================================================
-keep class javax.crypto.** { *; }
-keep class android.security.** { *; }

# ============================================================
# GEOLOCATOR / MAPLIBRE / LOCATION SERVICES
# ============================================================
-keep class com.google.android.gms.location.** { *; }
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ============================================================
# IMAGE PICKER / CAMERA
# ============================================================
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class io.flutter.plugins.camera.** { *; }

# ============================================================
# SHARE PLUS / URL LAUNCHER
# ============================================================
-keep class io.flutter.plugins.share.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }

# ============================================================
# SHARED PREFERENCES / SECURE STORAGE
# ============================================================
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.fluttersecurestorage.** { *; }

# ============================================================
# CONNECTIVITY / DEVICE INFO / PACKAGE INFO
# ============================================================
-keep class io.flutter.plugins.connectivityplus.** { *; }
-keep class io.flutter.plugins.deviceinfo.** { *; }
-keep class io.flutter.plugins.packageinfo.** { *; }

# ============================================================
# GOOGLE SIGN IN / PASSKEYS
# ============================================================
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ============================================================
# LOCAL NOTIFICATIONS / WAKELOCK
# ============================================================
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class io.flutter.plugins.wakelock.** { *; }

# ============================================================
# PDF / PRINTING
# ============================================================
-keep class io.flutter.plugins.printing.** { *; }
-dontwarn io.flutter.plugins.printing.**

# ============================================================
# MOBILE SCANNER / QR
# ============================================================
-keep class io.flutter.plugins.mobilescanner.** { *; }

# ============================================================
# LINT: Strip unused code aggressively
# ============================================================
-allowaccessmodification
-repackageclasses ''
