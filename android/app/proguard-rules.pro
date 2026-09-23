# R8 rules for the release build.
#
# Everything here exists because R8 only runs in release. A rule that is missing
# produces a build that compiles, installs, launches — and then fails at the one
# moment it is exercised, with a stack trace naming an obfuscated class. None of
# it is reproducible from a debug build or from any test on a Linux box.

# ── whisper.cpp FFI ───────────────────────────────────────────────────────────
#
# ⚠️ The single most important rule in this file.
#
# The speech engine is reached through dart:ffi by SYMBOL NAME. The JNI/native
# bridge classes declare `native` methods whose names must survive minification,
# because the runtime linker resolves them textually. R8 renames them by default,
# `DynamicLibrary.lookup` then throws ArgumentError "Failed to lookup symbol",
# and the app's whole reason to exist — transcription — fails in RELEASE BUILDS
# ONLY.
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class com.whispercpp.** { *; }

# ── sqlite3 / drift ───────────────────────────────────────────────────────────
#
# sqlite3_flutter_libs loads libsqlite3.so through JNI. The Java side is thin but
# it is reflected into, and a stripped constructor means the database cannot be
# opened at all — i.e. an app that shows an empty task list forever.
-keep class com.tekartik.sqflite.** { *; }
-keep class io.flutter.plugins.sqlite.** { *; }
-dontwarn org.sqlite.**

# ── flutter_local_notifications ───────────────────────────────────────────────
#
# Two separate hazards:
#
# 1. The receivers are named as strings in AndroidManifest.xml. R8 usually keeps
#    manifest-referenced classes, but the plugin's inner classes and the
#    scheduled-notification bookkeeping are reached reflectively.
# 2. ⚠️ The plugin persists every scheduled notification as JSON through Gson.
#    Gson reads FIELD NAMES via reflection, so an obfuscated model class
#    serialises to `{"a":1,"b":"..."}` and deserialises to nulls. The symptom is
#    that reminders survive until the process dies and then vanish on reboot —
#    which looks exactly like a missing RECEIVE_BOOT_COMPLETED and sends the
#    next maintainer to the wrong file for a day.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.models.** { <fields>; }

# Gson itself: generic signatures and the TypeToken machinery.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# ── in_app_purchase ───────────────────────────────────────────────────────────
#
# The Play Billing Library talks to a remote service over AIDL and its
# listener interfaces are invoked from outside our code. A stripped listener
# means the purchase stream never delivers, so the paywall spins forever after a
# successful payment — a charge with no entitlement, which is the worst possible
# bug to ship.
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }
-keep interface com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# ── Misc plugin surface ───────────────────────────────────────────────────────
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── Diagnostics ───────────────────────────────────────────────────────────────
#
# Keeps file names and line numbers in a release stack trace. There is no crash
# reporter in this app (by design — see store/privacy-policy.html), so the only
# stack trace anybody will ever read is one a user pastes out of a bug report,
# and `Unknown Source` makes it worthless.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
