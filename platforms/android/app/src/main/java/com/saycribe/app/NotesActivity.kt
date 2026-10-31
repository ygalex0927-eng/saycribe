package com.saycribe.app

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout

class NotesActivity : Activity() {
    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 48, 24, 24)
            setBackgroundColor(0xFF111111.toInt())
        }
        val et = EditText(this).apply {
            hint = "Notes"
            setTextColor(0xFFFFFFFF.toInt())
            setHintTextColor(0xFF888888.toInt())
            minLines = 12
            setBackgroundColor(0xFF222222.toInt())
            isFocusable = true
            isFocusableInTouchMode = true
        }
        root.addView(et)
        setContentView(root)
        et.requestFocus()
        et.post {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(et, InputMethodManager.SHOW_FORCED)
        }
    }
}