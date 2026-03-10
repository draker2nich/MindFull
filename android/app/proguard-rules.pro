# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Mindful Pause — нативные классы, вызываемые из манифеста
-keep class com.example.mindfull.AppMonitorService { *; }
-keep class com.example.mindfull.PauseActivity { *; }
-keep class com.example.mindfull.BootReceiver { *; }
-keep class com.example.mindfull.PermissionHelper { *; }
-keep class com.example.mindfull.NoteDbHelper { *; }

# Material Components
-keep class com.google.android.material.** { *; }

# AndroidX
-keep class androidx.** { *; }