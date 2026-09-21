#!/usr/bin/env bash
# Shared environment preamble. Flutter is not on PATH on this machine, and a
# Gradle build additionally needs ANDROID_HOME and a JDK 17.
#
# Source it, do not execute it:  . tool/env.sh
export FLUTTER_ROOT="${FLUTTER_ROOT:-/home/user/sdks/flutter}"
export PATH="$FLUTTER_ROOT/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$PATH"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
