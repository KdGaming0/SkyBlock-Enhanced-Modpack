pipeline {
    agent any

    environment {
        HMC_HOME      = '/var/jenkins_home/headlessmc-cache'
        HMC_VERSION   = '2.10.0'
        TEST_TIMEOUT  = '180'

        PAKKU_HOME    = '/var/jenkins_home/pakku-cache'
        PAKKU_VERSION = '1.4.0'

        PACK_DIR      = 'SkyBlock_Enhanced'
    }

    stages {
        stage('Checkout') {
            steps {
               checkout scm
            }
        }

        stage('Read Modpack Version') {
            steps {
                script {
                    def lock = "${env.PACK_DIR}/pakku-lock.json"
                    env.MC_VERSION     = sh(script: "jq -r '.mc_versions[0]' ${lock}", returnStdout: true).trim()
                    env.FABRIC_VERSION = sh(script: "jq -r '.loaders.fabric'  ${lock}", returnStdout: true).trim()
                    // Modpack version lives in pakku.json - reused for the release tag
                    env.PACK_VERSION   = sh(script: "jq -r '.version' ${env.PACK_DIR}/pakku.json", returnStdout: true).trim()
                    echo "Testing Minecraft ${env.MC_VERSION} / Fabric Loader ${env.FABRIC_VERSION} / Pack v${env.PACK_VERSION}"
                }
            }
        }

        stage('Setup HeadlessMC') {
            steps {
                sh '''
                    mkdir -p "$HMC_HOME"
                    JAR="$HMC_HOME/headlessmc-launcher-${HMC_VERSION}.jar"
                    if [ ! -f "$JAR" ]; then
                        echo "Downloading HeadlessMC ${HMC_VERSION}..."
                        curl -fsSL -o "$JAR" \
                          "https://github.com/headlesshq/headlessmc/releases/download/${HMC_VERSION}/headlessmc-launcher-${HMC_VERSION}.jar"
                    else
                        echo "HeadlessMC ${HMC_VERSION} already cached."
                    fi
                    java -jar "$JAR" --version || true
                '''
            }
        }

        stage('Setup Pakku') {
            steps {
                sh '''
                    mkdir -p "$PAKKU_HOME"
                    JAR="$PAKKU_HOME/pakku-${PAKKU_VERSION}.jar"
                    if [ ! -f "$JAR" ]; then
                        echo "Downloading Pakku ${PAKKU_VERSION}..."
                        curl -fsSL -o "$JAR" \
                          "https://github.com/juraj-hrivnak/Pakku/releases/download/v${PAKKU_VERSION}/pakku.jar"
                    else
                        echo "Pakku ${PAKKU_VERSION} already cached."
                    fi
                '''
            }
        }

        stage('Stage Mods & Config') {
            steps {
                sh '''
                    RUN_DIR="$WORKSPACE/run"
                    rm -rf "$RUN_DIR"
                    mkdir -p "$RUN_DIR/mods" "$RUN_DIR/resourcepacks" "$RUN_DIR/shaderpacks" "$RUN_DIR/config"

                    cp -v SkyBlock_Enhanced/mods/*.jar               "$RUN_DIR/mods/"          2>/dev/null || true
                    cp -rv SkyBlock_Enhanced/resourcepacks/.         "$RUN_DIR/resourcepacks/" 2>/dev/null || true
                    cp -rv SkyBlock_Enhanced/shaderpacks/.           "$RUN_DIR/shaderpacks/"   2>/dev/null || true

                    # 1) Default configs (1080p baseline) into the run dir
                    if [ -d "Default Configs/1080p_default_configs" ]; then
                        cp -rv "Default Configs/1080p_default_configs/." "$RUN_DIR/"
                        echo "Default configs staged."
                    else
                        echo "WARNING: 'Default Configs/1080p_default_configs' not found - continuing without defaults."
                    fi

                    # 2) Crash Assistant config (incl. current modlist.json) on top of the defaults
                    CA_SRC="SkyBlock_Enhanced/.pakku/client-overrides/config/crash_assistant"
                    if [ -d "$CA_SRC" ]; then
                        cp -rv "$CA_SRC" "$RUN_DIR/config/"
                        echo "Crash Assistant config staged."
                    else
                        echo "ERROR: crash_assistant config not found at $CA_SRC"
                        exit 1
                    fi

                    echo "Mods staged: $(ls -1 "$RUN_DIR/mods" | wc -l)"

                    # --- PackCore: make the title screen CI-friendly ---
                    # 1) Pre-complete the setup wizard
                    mkdir -p "$RUN_DIR/packcore"
                    jq -n '{
                    caxton_font: 1,
                    performance: 1,
                    item_background: 1,
                    scam_screener: 1,
                    storage_design: 1,
                    support_welcome: 1,
                    tab_design: 1,
                    main_menu_design: 1,
                    config_packs: 1,
                    resource_packs: 2,
                    sword_block: 1,
                    dungeon_routes: 2
                    }' > "$RUN_DIR/packcore/wizard.json"
                    jq empty "$RUN_DIR/packcore/wizard.json" && echo "wizard.json written and valid."

                    # 2) Switch the custom menu to MINIMAL
                    PC_CFG="$RUN_DIR/config/packcore.json"
                    if [ -f "$PC_CFG" ]; then
                        jq '.menuStyle = "MINIMAL"' "$PC_CFG" > "$PC_CFG.tmp" && mv "$PC_CFG.tmp" "$PC_CFG"
                        echo "packcore.json patched: menuStyle -> MINIMAL"
                    else
                        echo '{ "menuStyle": "MINIMAL" }' > "$PC_CFG"
                        echo "packcore.json did not exist - created with menuStyle MINIMAL"
                    fi

                    # Force headless-friendly options, even if the default configs shipped an options.txt.
                    # Strip any existing values for these keys, then append ours (last value wins anyway,
                    # but this keeps the file clean).
                    if [ -f "$RUN_DIR/options.txt" ]; then
                        sed -i '/^pauseOnLostFocus:/d;/^onboardAccessibility:/d' "$RUN_DIR/options.txt"
                    fi
                    printf 'pauseOnLostFocus:false\\nonboardAccessibility:false\\n' >> "$RUN_DIR/options.txt"

                    # Remember what the modlist looked like BEFORE launch, so we can detect
                    # when Crash Assistant has rewritten it (happens on first TitleScreen tick).
                    md5sum "$RUN_DIR/config/crash_assistant/modlist.json" | awk '{print $1}' > "$WORKSPACE/.modlist_pre_launch.md5" || true
                '''
            }
        }

        stage('Launch Test') {
            steps {
                sh '''#!/bin/bash
                    RUN_DIR="$WORKSPACE/run"
                    JAR="$HMC_HOME/headlessmc-launcher-${HMC_VERSION}.jar"
                    LOG="$WORKSPACE/launch.log"
                    SUCCESS_MARKER="Game took .* seconds to start"
                    MODLIST="$RUN_DIR/config/crash_assistant/modlist.json"
                    PRE_MD5="$(cat "$WORKSPACE/.modlist_pre_launch.md5" 2>/dev/null || echo none)"

                    # Launch in the background, capturing all output to the log
                    xvfb-run -a timeout ${TEST_TIMEOUT} \\
                    java -Dhmc.gamedir="$RUN_DIR" \\
                        -Dhmc.offline=true \\
                        -Dhmc.offline.username=Kd_Gaming1 \\
                        -Dhmc.check.xvfb=true \\
                        -Dhmc.crash.report.watcher=true \\
                        -Dhmc.exit.on.failed.command=true \\
                        -Dhmc.rethrow.launch.exceptions=true \\
                        -jar "$JAR" \\
                        --command "launch fabric:${MC_VERSION}" \\
                    > "$LOG" 2>&1 &
                    PID=$!

                    # Poll the log until the game reports a successful start,
                    # the process dies, or we hit the timeout ourselves.
                    STARTED=0
                    while kill -0 "$PID" 2>/dev/null; do
                        if grep -qE "$SUCCESS_MARKER" "$LOG"; then
                            STARTED=1
                            echo "Success marker found: $(grep -oE "$SUCCESS_MARKER" "$LOG" | head -1)"
                            break
                        fi
                        if grep -q "A mod crashed on startup" "$LOG"; then
                            echo "Detected a mod crash on startup."
                            kill "$PID" 2>/dev/null
                            wait "$PID" 2>/dev/null
                            tail -50 "$LOG"
                            exit 1
                        fi
                        sleep 2
                    done

                    if [ "$STARTED" -eq 1 ]; then
                        # Crash Assistant rewrites modlist.json on the first tick of the
                        # TitleScreen (auto_update=true, launched by a modpack_creator).
                        # That happens at roughly the same moment as the success marker,
                        # so give it up to 30s to actually land on disk before killing.
                        echo "Waiting for Crash Assistant to refresh modlist.json..."
                        MODLIST_UPDATED=0
                        for i in $(seq 1 15); do
                            CUR_MD5="$(md5sum "$MODLIST" 2>/dev/null | awk '{print $1}' || echo missing)"
                            if [ "$CUR_MD5" != "$PRE_MD5" ] && [ "$CUR_MD5" != "missing" ]; then
                                MODLIST_UPDATED=1
                                echo "modlist.json was refreshed by Crash Assistant."
                                break
                            fi
                            # If the process died on us while waiting, stop looping.
                            kill -0 "$PID" 2>/dev/null || break
                            sleep 2
                        done
                        if [ "$MODLIST_UPDATED" -eq 0 ]; then
                            echo "NOTE: modlist.json unchanged after launch (identical content, wrong player name, or write did not happen)."
                        fi

                        kill "$PID" 2>/dev/null
                        wait "$PID" 2>/dev/null
                        echo "Game reached a fully started state - test passed."
                        exit 0
                    fi

                    wait "$PID" 2>/dev/null
                    EXIT=$?
                    echo "Minecraft/HeadlessMC exit code: $EXIT"

                    # Process ended on its own without the marker: figure out why.
                    if grep -q "A mod crashed on startup" "$LOG"; then
                        echo "Detected a mod crash on startup."
                        exit 1
                    fi
                    if [ "$EXIT" -eq 124 ]; then
                        echo "Timed out without the game ever reporting a successful start."
                        exit 1
                    fi
                    echo "Game exited (code $EXIT) before reporting a successful start."
                    exit 1
                '''
            }
        }

        stage('Collect Updated Modlist') {
            steps {
                sh '''
                    RUN_DIR="$WORKSPACE/run"
                    SRC="$RUN_DIR/config/crash_assistant/modlist.json"
                    DEST="SkyBlock_Enhanced/.pakku/client-overrides/config/crash_assistant/modlist.json"

                    if [ ! -f "$SRC" ]; then
                        echo "ERROR: $SRC not found after launch test."
                        exit 1
                    fi

                    # Sanity check it is valid JSON before we let it replace the source of truth.
                    jq empty "$SRC" || { echo "ERROR: refreshed modlist.json is not valid JSON."; exit 1; }

                    cp -v "$SRC" "$DEST"
                    echo "modlist.json copied back for the build/publish stage."
                '''
                archiveArtifacts artifacts: 'run/config/crash_assistant/modlist.json', fingerprint: true
            }
        }

        // Verification build: proves the pack exports cleanly WITH the freshly
        // collected modlist.json, before anything is committed or tagged.
        // These artifacts are for inspection only - GitHub Actions rebuilds the
        // same thing from the tagged commit and publishes that.
        stage('Build Modpack (verify)') {
            steps {
                sh '''
                    JAR="$PAKKU_HOME/pakku-${PAKKU_VERSION}.jar"
                    cd "$PACK_DIR"

                    # Clean old exports so a stale file can never pass verification
                    rm -rf build/curseforge build/modrinth build/serverpack

                    java -jar "$JAR" export

                    ls build/curseforge/*.zip  >/dev/null 2>&1 || { echo "ERROR: no CurseForge zip produced"; exit 1; }
                    ls build/modrinth/*.mrpack >/dev/null 2>&1 || { echo "ERROR: no Modrinth mrpack produced"; exit 1; }
                    echo "Export verified:"
                    ls -l build/curseforge build/modrinth build/serverpack 2>/dev/null || true
                '''
                archiveArtifacts artifacts: "${env.PACK_DIR}/build/curseforge/*.zip, ${env.PACK_DIR}/build/modrinth/*.mrpack, ${env.PACK_DIR}/build/serverpack/*.zip",
                                 allowEmptyArchive: true,
                                 fingerprint: true
            }
        }

        stage('Commit Modlist & Tag Release') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-push',
                                                  usernameVariable: 'GIT_USER',
                                                  passwordVariable: 'GIT_TOKEN')]) {
                    sh '''
                        MODLIST="$PACK_DIR/.pakku/client-overrides/config/crash_assistant/modlist.json"
                        REMOTE="https://${GIT_USER}:${GIT_TOKEN}@github.com/KdGaming0/SkyBlock-Enhanced-Modpack.git"
                        BRANCH="${BRANCH_NAME:-main}"
                        TAG="v${PACK_VERSION}"

                        git config user.name  "jenkins-ci"
                        git config user.email "jenkins@example.com"

                        # 1) Commit the refreshed modlist (only if it actually changed)
                        if git diff --quiet -- "$MODLIST"; then
                            echo "modlist.json unchanged - no commit needed."
                        else
                            git add "$MODLIST"
                            git commit -m "chore(ci): refresh crash_assistant modlist.json for ${TAG} [ci skip]"
                            git push "$REMOTE" HEAD:"$BRANCH"
                        fi

                        # 2) Don't re-release an existing version
                        if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/${TAG}" >/dev/null 2>&1; then
                            echo "Tag ${TAG} already exists on the remote - skipping tag push."
                            echo "Bump the version in pakku.json to cut a new release."
                            exit 0
                        fi

                        # 3) Tag the commit that contains the fresh modlist -> triggers GH Actions release
                        git tag -a "$TAG" -m "SkyBlock Enhanced ${TAG}"
                        git push "$REMOTE" "$TAG"
                        echo "Pushed ${TAG} - GitHub Actions will publish the release."
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'launch.log, run/logs/**, run/crash-reports/**',
                            allowEmptyArchive: true,
                            fingerprint: false
        }
    }
}