package dev.martinloeseth.norsemixology

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.martinloeseth.norsemixology.ui.NorseMixologyApp
import dev.martinloeseth.norsemixology.ui.theme.NorseMixologyTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as NorseMixologyApplication).container
        setContent {
            NorseMixologyTheme {
                NorseMixologyApp(container)
            }
        }
    }
}
