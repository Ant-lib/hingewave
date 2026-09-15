package com.antlib.hingewave.render

/** Which physical panel the wallpaper surface is on, decided from its size. */
enum class Panel {
    /** The large inner display of a book-style foldable. Hinge runs down the middle. */
    INNER,

    /** The narrow cover display. Hinge along its inner edge. */
    COVER;

    companion object {
        /**
         * Book-style inner panels are close to square (Fold 8 about 0.9, Pixel Fold about 1.2).
         * Cover panels and ordinary phones are tall (0.45 to 0.55).
         */
        fun fromSize(width: Int, height: Int): Panel {
            val aspect = width.toDouble() / height.toDouble()
            return if (aspect > 0.7) INNER else COVER
        }
    }
}

/** Side of the inner panel that physically moves, and the edge of the cover panel nearest the hinge. */
enum class MovingSide { LEFT, RIGHT }

/** Geometry the shader needs for one panel: hinge edge code and folding band. */
data class FoldGeometry(val hingeEdge: Int, val regionStart: Float, val regionEnd: Float) {
    companion object {
        const val BOTTOM = 0
        const val LEFT = 1
        const val RIGHT = 2
        const val TOP = 3

        fun forPanel(panel: Panel, side: MovingSide): FoldGeometry = when (panel) {
            // Inner: the moving half folds about the centre line; the other half stays sharp.
            // u runs from the hinge edge, so the band is the far half of the panel.
            Panel.INNER -> when (side) {
                MovingSide.RIGHT -> FoldGeometry(LEFT, 0.5f, 1.0f)
                MovingSide.LEFT -> FoldGeometry(RIGHT, 0.5f, 1.0f)
            }
            // Cover: the whole panel folds about its inner edge.
            Panel.COVER -> when (side) {
                MovingSide.RIGHT -> FoldGeometry(LEFT, 0.0f, 1.0f)
                MovingSide.LEFT -> FoldGeometry(RIGHT, 0.0f, 1.0f)
            }
        }
    }
}
