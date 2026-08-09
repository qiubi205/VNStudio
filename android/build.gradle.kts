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
// 用 plugins.withId 回调（插件 apply 时立即生效），不用 afterEvaluate：
// Gradle 9 中 afterEvaluate 在项目已 evaluate 时直接抛异常。
fun forceCompileSdk(p: org.gradle.api.Project) {
    val androidExt = p.extensions.findByName("android") ?: return
    val targets = listOf(
        "setCompileSdk" to Integer::class.java,
        "compileSdkVersion" to Int::class.javaPrimitiveType,
    )
    for ((name, argType) in targets) {
        try {
            val m = androidExt.javaClass.getMethod(name, argType)
            m.invoke(androidExt, 36)
            return
        } catch (_: NoSuchMethodException) {
        } catch (_: Exception) {
        }
    }
}

subprojects {
    plugins.withId("com.android.library") { forceCompileSdk(project) }
    plugins.withId("com.android.application") { forceCompileSdk(project) }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
