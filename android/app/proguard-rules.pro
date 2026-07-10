# android/app/proguard-rules.pro
#
# ProGuard / R8 rules for CrispCloud release builds.

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep our Kotlin platform-channel handlers
-keep class com.CrispStrobe.cloud_dart.** { *; }

# Dart FFI (used by drift/sqlite3, cryptography_flutter, ffi package)
-keep class **NativeFunction { *; }
-keep class **Pointer { *; }

# SQLite (drift + sqlite3_flutter_libs)
-keep class org.sqlite.** { *; }
-keep class io.requery.android.database.** { *; }

# dartssh2 / BouncyCastle (pointycastle uses reflection)
-dontwarn org.bouncycastle.**
-keep class org.bouncycastle.** { *; }

# OkHttp / Conscrypt (pulled in by some plugins)
-dontwarn okhttp3.**
-dontwarn org.conscrypt.**

# Flutter Local Notifications
-keep class com.dexterous.** { *; }

# WorkManager
-keep class androidx.work.** { *; }

# video_player
-keep class io.flutter.plugins.videoplayer.** { *; }

# Keep Parcelable/Serializable for bundle extras
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
