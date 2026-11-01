package dev.atrium.application

data class Page<out T>(
    val items: List<T>,
    val nextCursor: String?,
) {
    val hasNext: Boolean get() = nextCursor != null

    fun <R> map(transform: (T) -> R): Page<R> = Page(items.map(transform), nextCursor)

    companion object {
        fun <T> empty(): Page<T> = Page(emptyList(), nextCursor = null)
    }
}
