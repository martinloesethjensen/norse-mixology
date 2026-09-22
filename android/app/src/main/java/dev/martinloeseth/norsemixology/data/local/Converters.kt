package dev.martinloeseth.norsemixology.data.local

import androidx.room3.ColumnTypeConverter
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.util.Date

/**
 * Column converters for the types Room 3 doesn't handle itself. `UUID` and the enums use Room's
 * built-in converters (enabled on the database); only `Date` and `List<String>` are custom.
 */
class Converters {
    @ColumnTypeConverter
    fun dateToLong(value: Date): Long = value.time

    @ColumnTypeConverter
    fun longToDate(value: Long): Date = Date(value)

    @ColumnTypeConverter
    fun stringListToJson(value: List<String>): String = Json.encodeToString(stringList, value)

    @ColumnTypeConverter
    fun jsonToStringList(value: String): List<String> = Json.decodeFromString(stringList, value)

    private companion object {
        val stringList = ListSerializer(String.serializer())
    }
}
