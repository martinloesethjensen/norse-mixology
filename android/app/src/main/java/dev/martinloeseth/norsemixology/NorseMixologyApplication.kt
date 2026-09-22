package dev.martinloeseth.norsemixology

import android.app.Application

class NorseMixologyApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
