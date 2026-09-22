package dev.martinloeseth.norsemixology

import android.content.Context
import android.util.Log
import androidx.room3.Room
import androidx.sqlite.driver.AndroidSQLiteDriver
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.data.repository.TaxonomyRepository
import dev.martinloeseth.norsemixology.data.seed.CatalogSeeder
import dev.martinloeseth.norsemixology.data.seed.DataStoreSeedFlagStore
import dev.martinloeseth.norsemixology.data.seed.SeedResult
import dev.martinloeseth.norsemixology.domain.Taxonomy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Hand-rolled dependency container, created once by [NorseMixologyApplication]. Seeding runs on a
 * background coroutine so it never blocks app start; the UI reads [taxonomy], which is empty until
 * the catalog is in Room and then fills in.
 */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val database: NorseMixologyDatabase =
        Room.databaseBuilder(appContext, NorseMixologyDatabase::class.java, "norse-mixology.db")
            .setDriver(AndroidSQLiteDriver())
            .build()

    val cabinetRepository = CabinetRepository(database.cabinetDao())
    private val taxonomyRepository = TaxonomyRepository(database.taxonomyDao())

    private val _taxonomy = MutableStateFlow(Taxonomy.Empty)
    val taxonomy: StateFlow<Taxonomy> = _taxonomy

    private val seeder = CatalogSeeder(
        database = database,
        flags = DataStoreSeedFlagStore(appContext),
        taxonomyJson = { readAsset("taxonomy.json") },
        recipesJson = { readAsset("recipes.json") },
    )

    init {
        scope.launch {
            try {
                when (val result = seeder.seedIfNeeded()) {
                    SeedResult.AlreadySeeded -> Log.i(TAG, "Catalog already seeded")
                    is SeedResult.Seeded -> Log.i(TAG, "Seeded ${result.styles} styles, ${result.recipes} recipes (${result.skippedRecipes} skipped)")
                }
                _taxonomy.value = taxonomyRepository.load()
            } catch (e: Exception) {
                Log.e(TAG, "Could not load the bundled catalog", e)
            }
        }
    }

    private fun readAsset(name: String): String =
        appContext.assets.open(name).bufferedReader().use { it.readText() }

    private companion object {
        const val TAG = "Catalog"
    }
}
