// O app Android da Escalibur Wallet. A interface e em Kotlin (Jetpack Compose); o nucleo e o
// mesmo do iOS, em Swift, compilado para Android (Kit/, tools/android/compilar-nucleo.sh) e
// carregado pela ponte JNI (app/src/main/java/app/escalibur/wallet/nucleo).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "EscaliburWallet"
include(":app")
