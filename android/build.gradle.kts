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
subprojects {
    project.evaluationDependsOn(":app")
}

// 强制所有 Android 模块（含插件工程）使用 compileSdk 36：
// file_picker 8.0.7 写死 compileSdk 34，但其传递依赖
// flutter_plugin_android_lifecycle 2.0.35 要求 compileSdk >= 36，否则 AAR 元数据检查失败。
// 用反射避免依赖 AGP 类型（兼容 AGP 8/9 的 API 命名差异）。
subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android") ?: return@afterEvaluate
        var done = false
        for (name in listOf("compileSdkVersion", "setCompileSdk")) {
            try {
                val m = androidExt.javaClass.getMethod(name, Int::class.javaPrimitiveType)
                m.invoke(androidExt, 36)
                done = true
                break
            } catch (_: NoSuchMethodException) {
            } catch (_: Exception) {
            }
        }
        if (!done) {
            try {
                val m = androidExt.javaClass.getMethod("setCompileSdk", Integer::class.java)
                m.invoke(androidExt, 36)
            } catch (_: Exception) {
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
