// android/app/src/main/kotlin/com/example/internxt_flutter/CrispCloudWidget.kt
//
// Home screen App Widget for CrispCloud.
//
// Displays:
//   • Quick-upload button (opens MainActivity in upload mode via deep-link)
//   • Sync status badge (Synced / Syncing / Offline)
//   • Up to 3 recent files stored in SharedPreferences by the Flutter app
//
// The Flutter side writes recent-file names and the sync status to
// SharedPreferences under well-known keys (see companion object).  When a
// sync completes, the Flutter app broadcasts ACTION_APPWIDGET_UPDATE so this
// provider refreshes immediately.

package com.example.internxt_flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import com.CrispStrobe.cloud_dart.R

class CrispCloudWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        /** SharedPreferences file written by Flutter via shared_preferences plugin. */
        const val PREFS_NAME = "FlutterSharedPreferences"

        // Keys written by the Flutter app
        const val KEY_SYNC_STATUS   = "flutter.widget_sync_status"
        const val KEY_RECENT_FILE_1 = "flutter.widget_recent_1"
        const val KEY_RECENT_FILE_2 = "flutter.widget_recent_2"
        const val KEY_RECENT_FILE_3 = "flutter.widget_recent_3"

        /** Deep-link URI that opens MainActivity in quick-upload mode. */
        private const val UPLOAD_URI = "internxtdrive://upload"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val syncStatus  = prefs.getString(KEY_SYNC_STATUS, "Synced") ?: "Synced"
            val recentFile1 = prefs.getString(KEY_RECENT_FILE_1, null)
            val recentFile2 = prefs.getString(KEY_RECENT_FILE_2, null)
            val recentFile3 = prefs.getString(KEY_RECENT_FILE_3, null)

            val views = RemoteViews(context.packageName, R.layout.widget_crisp_cloud)

            // Sync status badge
            views.setTextViewText(R.id.widget_sync_status, syncStatus)

            // Quick-upload button — opens the app via deep-link
            val uploadIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse(UPLOAD_URI),
                context,
                MainActivity::class.java,
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val uploadPi = PendingIntent.getActivity(
                context, 0, uploadIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_btn_upload, uploadPi)

            // Recent file rows
            setRecentRow(context, views, R.id.widget_recent_1, R.id.widget_name_1, recentFile1)
            setRecentRow(context, views, R.id.widget_recent_2, R.id.widget_name_2, recentFile2)
            setRecentRow(context, views, R.id.widget_recent_3, R.id.widget_name_3, recentFile3)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun setRecentRow(
            context: Context,
            views: RemoteViews,
            rowId: Int,
            nameId: Int,
            fileName: String?,
        ) {
            if (fileName.isNullOrBlank()) {
                views.setTextViewText(nameId, "—")
                // Make the row non-clickable when empty
                views.setOnClickPendingIntent(rowId, null)
                return
            }

            views.setTextViewText(nameId, fileName)

            // Clicking a recent file opens MainActivity (the app handles navigation)
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("widget_recent_file", fileName)
            }
            val pi = PendingIntent.getActivity(
                context, fileName.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(rowId, pi)
        }
    }
}
