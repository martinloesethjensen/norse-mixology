package dev.martinloeseth.norsemixology.data.seed

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

private val Context.seedDataStore by preferencesDataStore(name = "seed")

/** Production [SeedFlagStore], backed by Preferences DataStore. */
class DataStoreSeedFlagStore(private val context: Context) : SeedFlagStore {
    private val key = intPreferencesKey("catalog_version")

    override suspend fun seededVersion(): Int = context.seedDataStore.data.first()[key] ?: 0

    override suspend fun setSeededVersion(version: Int) {
        context.seedDataStore.edit { it[key] = version }
    }
}
