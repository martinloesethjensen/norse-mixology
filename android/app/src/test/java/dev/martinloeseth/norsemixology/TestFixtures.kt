package dev.martinloeseth.norsemixology

import androidx.room3.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase_Impl
import dev.martinloeseth.norsemixology.data.seed.CatalogParser
import dev.martinloeseth.norsemixology.data.seed.SeedFlagStore
import dev.martinloeseth.norsemixology.data.seed.TaxonomyRows
import dev.martinloeseth.norsemixology.domain.Taxonomy
import java.io.File

/** The shared catalog JSON — the same files the iOS app bundles. */
object SeedFiles {
    // Set by Gradle (see app/build.gradle.kts) so tests never depend on the working directory.
    val dir: File = File(requireNotNull(System.getProperty("seed.dir")) { "seed.dir system property not set" })
    val iosResourcesDir: File = File(dir.parentFile, "ios/NorseMixology/Resources")

    fun taxonomyText(): String = File(dir, "taxonomy.json").readText()
    fun recipesText(): String = File(dir, "recipes.json").readText()

    fun taxonomyRows(): TaxonomyRows = CatalogParser.parseTaxonomy(taxonomyText())
    fun taxonomy(): Taxonomy = Taxonomy.from(taxonomyRows())
}

/** A real Room database in memory, driven by the bundled SQLite so it runs on the plain JVM. */
fun inMemoryDatabase(): NorseMixologyDatabase =
    Room.inMemoryDatabaseBuilder<NorseMixologyDatabase> { NorseMixologyDatabase_Impl() }
        .setDriver(BundledSQLiteDriver())
        .build()

class InMemorySeedFlagStore(var version: Int = 0) : SeedFlagStore {
    override suspend fun seededVersion(): Int = version
    override suspend fun setSeededVersion(version: Int) { this.version = version }
}
