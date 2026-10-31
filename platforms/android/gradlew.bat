@echo off
setlocal
set JAVA_HOME=D:\saycribe-android\env\jdk17
set GRADLE_USER_HOME=D:\saycribe-android\env\gradle-home
set ANDROID_HOME=D:\saycribe-android\env\sdk
set ANDROID_SDK_ROOT=D:\saycribe-android\env\sdk
set ANDROID_NDK_HOME=D:\saycribe-android\env\sdk\ndk\26.3.11579264
set GRADLE_OPTS=-Djava.net.useSystemProxies=false -Dhttp.proxyHost= -Dhttps.proxyHost= -Xmx2g
"D:\saycribe-android\env\gradle-8.7\bin\gradle.bat" %*
