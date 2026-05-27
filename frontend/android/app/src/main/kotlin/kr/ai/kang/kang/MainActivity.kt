package kr.ai.kang.kang

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kr.ai.kang.kang/google_keep"
        ).setMethodCallHandler { call, result ->
            if (call.method == "open") {
                result.success(openGoogleKeep())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openGoogleKeep(): Boolean {
        val keepIntent = packageManager.getLaunchIntentForPackage("com.google.android.keep")
        if (keepIntent != null) {
            keepIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(keepIntent)
            return true
        }

        val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://keep.google.com/")).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(webIntent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
