package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.FlavorProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FlavorSimilarityTest {
    private val taxonomy = SeedFiles.taxonomy()
    private fun style(name: String) = taxonomy.stylesById.values.first { it.name == name }

    @Test
    fun identicalProfilesAreFullySimilar() {
        val profile = FlavorProfile(0.4, 0.1, 0.2, 0.3, 0.1, 0.2, 0.1, 0.3, 0.2, 40.0)
        assertEquals(1.0, FlavorSimilarity.cosine(profile, profile), 0.0001)
    }

    @Test
    fun orthogonalProfilesAreNotSimilar() {
        val a = FlavorProfile(1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        val b = FlavorProfile(0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        assertEquals(0.0, FlavorSimilarity.cosine(a, b), 0.0001)
    }

    @Test
    fun zeroVectorReturnsZero() {
        val zero = FlavorProfile(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        val other = FlavorProfile(0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 40.0)
        assertEquals(0.0, FlavorSimilarity.cosine(zero, other), 0.0)
    }

    @Test
    fun abvIsExcludedFromSimilarity() {
        val a = FlavorProfile(0.5, 0.2, 0.0, 0.1, 0.0, 0.0, 0.0, 0.2, 0.0, 10.0)
        val b = FlavorProfile(0.5, 0.2, 0.0, 0.1, 0.0, 0.0, 0.0, 0.2, 0.0, 90.0)
        assertEquals(1.0, FlavorSimilarity.cosine(a, b), 0.0001)
    }

    @Test
    fun bourbonIsMoreSimilarToRyeThanToIslayScotch() {
        val bourbon = style("Bourbon")
        val rye = style("Rye Whiskey")
        val islay = style("Scotch Single Malt (Islay)")

        val bourbonRye = FlavorSimilarity.cosine(bourbon.flavorProfile, rye.flavorProfile)
        val bourbonIslay = FlavorSimilarity.cosine(bourbon.flavorProfile, islay.flavorProfile)

        assertTrue("Bourbon should read closer to Rye than to a heavily-peated Islay Scotch", bourbonRye > bourbonIslay)
        assertTrue(bourbonRye > 0.6)
        assertTrue(bourbonIslay < 0.7)
    }
}
