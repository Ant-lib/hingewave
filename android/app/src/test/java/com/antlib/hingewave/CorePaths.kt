package com.antlib.hingewave

import java.io.File

/** Locates the repository's core/ directory from the Gradle module working directory. */
object CorePaths {
    val core: File by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        repeat(6) {
            val candidate = File(dir, "core/effect.json")
            if (candidate.exists()) return@lazy candidate.parentFile
            dir = dir?.parentFile
        }
        error("core/effect.json not found above ${System.getProperty("user.dir")}")
    }
}
