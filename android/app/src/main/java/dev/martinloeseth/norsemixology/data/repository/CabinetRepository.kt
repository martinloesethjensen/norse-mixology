package dev.martinloeseth.norsemixology.data.repository

import dev.martinloeseth.norsemixology.data.local.CabinetDao
import dev.martinloeseth.norsemixology.data.local.CabinetItem
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/** The user's cabinet. The single place the rest of the app reads or writes it. */
class CabinetRepository(private val dao: CabinetDao) {
    /** Returns false (and stores nothing) if that ingredient style is already in the cabinet. */
    suspend fun add(item: CabinetItem): Boolean = dao.insert(item) != -1L

    suspend fun remove(item: CabinetItem) = dao.delete(item)

    /** Every item, sorted by category then name. Emits again on any change. */
    fun allItems(): Flow<List<CabinetItem>> = dao.observeAll()

    suspend fun contains(styleId: UUID): Boolean = dao.countForStyle(styleId) > 0
}
