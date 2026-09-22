package dev.martinloeseth.norsemixology.domain

/** A coarse, screen-reader-friendly reading of a 0…1 flavour score. Same thresholds as iOS. */
enum class FlavorLevel {
    Low, Medium, High;

    companion object {
        fun of(value: Double): FlavorLevel = when {
            value < 0.34 -> Low
            value < 0.67 -> Medium
            else -> High
        }
    }
}
