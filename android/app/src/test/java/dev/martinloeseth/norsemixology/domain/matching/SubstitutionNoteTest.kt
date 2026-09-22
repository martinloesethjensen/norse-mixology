package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.FlavorProfile
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class SubstitutionNoteTest {
    private val taxonomy = SeedFiles.taxonomy()
    private fun style(name: String) = taxonomy.stylesById.values.first { it.name == name }

    @Test
    fun bourbonToRyeNoteMentionsSpicier() {
        val note = SubstitutionNote.generate(style("Bourbon"), style("Rye Whiskey"))
        assertTrue("Expected note to mention 'spicier', got: $note", note.contains("spicier"))
        assertTrue(note.contains("Rye Whiskey"))
        assertTrue(note.contains("Bourbon"))
    }

    @Test
    fun londonDryToContemporaryNoteMentionsFloral() {
        val note = SubstitutionNote.generate(style("London Dry Gin"), style("Contemporary Gin"))
        assertTrue("Expected note to mention 'floral', got: $note", note.contains("floral"))
    }

    @Test
    fun closeMatchFallbackWhenNoSignificantDelta() {
        val profile = FlavorProfile(0.3, 0.1, 0.0, 0.2, 0.1, 0.1, 0.2, 0.1, 0.0, 40.0)
        val required = IngredientStyle(UUID.randomUUID(), "Style A", UUID.randomUUID(), UUID.randomUUID(), profile, 40.0, 40.0, emptyList(), 0)
        val substitute = IngredientStyle(UUID.randomUUID(), "Style B", UUID.randomUUID(), UUID.randomUUID(), profile, 40.0, 40.0, emptyList(), 0)

        val note = SubstitutionNote.generate(required, substitute)
        assertTrue(note.contains("close match"))
    }

    @Test
    fun ratioHintOnlyAppliesToSweetenerSourRole() {
        val sweeter = FlavorProfile(0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        val lessSweet = FlavorProfile(0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        val required = IngredientStyle(UUID.randomUUID(), "Simple Syrup", UUID.randomUUID(), UUID.randomUUID(), lessSweet, 0.0, 0.0, emptyList(), 0)
        val substitute = IngredientStyle(UUID.randomUUID(), "Grenadine", UUID.randomUUID(), UUID.randomUUID(), sweeter, 0.0, 0.0, emptyList(), 0)

        assertNotNull(SubstitutionNote.ratioHint(IngredientRole.SweetenerSour, required, substitute))
        assertNull(SubstitutionNote.ratioHint(IngredientRole.Base, required, substitute))
    }
}
