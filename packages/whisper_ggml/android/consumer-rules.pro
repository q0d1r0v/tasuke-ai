# Merged into the R8 configuration of any app that depends on this plugin.
#
# The upstream package also kept com.antonkarpenko.ffmpegkit.** here. This fork
# removed the FFmpeg dependency entirely (see NOTICE.md), so those rules would
# now keep classes that are not on the classpath.

# whisper.cpp is reached through dart:ffi, which resolves symbols in the shared
# library by name at runtime. R8 cannot see those references, so without this
# the JNI entry points are renamed and every transcription fails with an
# unsatisfied link error — in release builds only.
-keepclasseswithmembernames class * { native <methods>; }
