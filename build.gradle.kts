plugins {
    id("me.modmuss50.mod-publish-plugin") version "2.1.1"
}

val packVersion   = providers.gradleProperty("packVersion").getOrElse("0.0.0")
val mcVersion     = providers.gradleProperty("mcVersion").getOrElse("1.21")
val cfFile        = providers.gradleProperty("cfFile").getOrElse("dummy.zip")
val mrFile        = providers.gradleProperty("mrFile").getOrElse("dummy.mrpack")
val changelogFile = providers.gradleProperty("changelogFile").getOrElse("CHANGELOG.md")

publishMods {
    changelog = file(changelogFile).readText()
    version = packVersion
    displayName = "SkyBlock Enhanced $packVersion"
    type = when {
        packVersion.contains("-beta", ignoreCase = true)  -> BETA
        packVersion.contains("-alpha", ignoreCase = true) -> ALPHA
        else -> STABLE
    }
    modLoaders.add("fabric")


    dryRun = providers.environmentVariable("CURSEFORGE_API_KEY").orNull == null

    curseforge {
        projectId = "1365629"
        accessToken = providers.environmentVariable("CURSEFORGE_API_KEY")
        minecraftVersions.add(mcVersion)
        file(cfFile)
    }

    modrinth {
        projectId = "e0oMrxjp"
        accessToken = providers.environmentVariable("MODRINTH_TOKEN")
        minecraftVersions.add(mcVersion)
        file(mrFile)
    }

    github {
        repository = "KdGaming0/SkyBlock-Enhanced-Modpack"
        accessToken = providers.environmentVariable("GITHUB_TOKEN")
        commitish = "main"
        tagName = "v$packVersion"
        file(cfFile)
        additionalFiles.from(mrFile)
    }
}
