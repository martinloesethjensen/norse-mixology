package dev.martinloeseth.norsemixology.data.repository

import dev.martinloeseth.norsemixology.data.local.TaxonomyDao
import dev.martinloeseth.norsemixology.domain.Taxonomy

class TaxonomyRepository(private val dao: TaxonomyDao) {
    /** Reads the seeded taxonomy from Room into its in-memory tree. */
    suspend fun load(): Taxonomy = Taxonomy.from(dao.categories(), dao.families(), dao.styles())
}
