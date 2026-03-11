package com.example.mindfull

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class NoteDbHelper(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {

    companion object {
        const val DATABASE_NAME = "mindful_notes.db"
        const val DATABASE_VERSION = 2 // Bumped for index
        const val TABLE_NAME = "notes"
        const val COL_ID = "_id"
        const val COL_TEXT = "text"
        const val COL_APP_PACKAGE = "app_package"
        const val COL_APP_NAME = "app_name"
        const val COL_TIMESTAMP = "timestamp"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE $TABLE_NAME (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_TEXT TEXT NOT NULL,
                $COL_APP_PACKAGE TEXT NOT NULL,
                $COL_APP_NAME TEXT NOT NULL,
                $COL_TIMESTAMP INTEGER NOT NULL
            )
        """.trimIndent())
        db.execSQL("""
            CREATE INDEX idx_notes_timestamp ON $TABLE_NAME ($COL_TIMESTAMP DESC)
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            // Добавляем индекс для существующих пользователей
            try {
                db.execSQL("""
                    CREATE INDEX IF NOT EXISTS idx_notes_timestamp ON $TABLE_NAME ($COL_TIMESTAMP DESC)
                """.trimIndent())
            } catch (_: Exception) { }
        }
    }
}