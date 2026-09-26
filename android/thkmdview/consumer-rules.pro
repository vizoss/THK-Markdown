# WebView invokes these callbacks by name from bundled Mermaid and math JavaScript.
-keepattributes RuntimeVisibleAnnotations
-keepclassmembers class com.thk.mdview.** {
    @android.webkit.JavascriptInterface <methods>;
}
