allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = layout.buildDirectory.dir("../../build").get()
layout.buildDirectory.value(newBuildDir)

subprojects {
    project.layout.buildDirectory.value(newBuildDir.dir(project.name))
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}