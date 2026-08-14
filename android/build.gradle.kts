allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Some plugins (e.g. flutter_piwikpro 0.0.3) predate AGP 8: they declare their
// package only in AndroidManifest.xml and pin an old compileSdk. AGP 8 requires
// an explicit namespace, and the Flutter embedding needs a current compileSdk,
// so backfill both for any subproject that is still missing a namespace.
// Registered before the evaluationDependsOn block below, which would otherwise
// evaluate projects before this hook is attached.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        androidExtension.withGroovyBuilder {
            if (getProperty("namespace") == null) {
                val manifest = file("src/main/AndroidManifest.xml")
                val legacyPackage = if (manifest.exists()) {
                    Regex("""package\s*=\s*"([^"]+)"""")
                        .find(manifest.readText())
                        ?.groupValues
                        ?.get(1)
                } else {
                    null
                }

                if (legacyPackage != null) {
                    logger.lifecycle("Backfilling namespace '$legacyPackage' for :${project.name}")
                    setProperty("namespace", legacyPackage)
                    setProperty("compileSdk", 35)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}