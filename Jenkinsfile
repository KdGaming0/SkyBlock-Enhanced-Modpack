pipeline {
    agent any

    options {
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

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
                    // release.sh writes .release-tag so a hotfix can re-release
                    // the same pack version under a new, non-conflicting tag.
                    // Fall back to v<version> for builds that predate the file.
                    env.RELEASE_TAG = fileExists('.release-tag')
                        ? readFile('.release-tag').trim()
                        : "v${env.PACK_VERSION}"
                    echo "Testing Minecraft ${env.MC_VERSION} / Fabric Loader ${env.FABRIC_VERSION} / Pack v${env.PACK_VERSION}"
                    echo "Release tag: ${env.RELEASE_TAG}"
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

        stage('Install Fabric Loader') {
            steps {
                sh '''
                    JAR="$HMC_HOME/headlessmc-launcher-${HMC_VERSION}.jar"
                    java -Dhmc.exit.on.failed.command=true \
                        -jar "$JAR" \
                        --command "fabric ${MC_VERSION} --uid ${FABRIC_VERSION}"
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

                '''
            }
        }

        stage('Launch Test') {
            steps {
                sh '''#!/bin/bash
                    set -euo pipefail
                    RUN_DIR="$WORKSPACE/run"
                    JAR="$HMC_HOME/headlessmc-launcher-${HMC_VERSION}.jar"
                    LOG="$WORKSPACE/launch.log"
                    GAME_LOG="$RUN_DIR/logs/latest.log"
                    MODLIST="$RUN_DIR/config/crash_assistant/modlist.json"
                    READY_MARKER='[CrashAssistant-ModListUpdate/INFO]: Modlist saved to config/crash_assistant/modlist.json'
                    STABILITY_SECONDS=10
                    PID=''

                    cleanup() {
                        if [ -n "$PID" ]; then
                            # --foreground below keeps timeout and the game in this session's group.
                            kill -TERM -- "-$PID" 2>/dev/null || true
                            sleep 2
                            kill -KILL -- "-$PID" 2>/dev/null || true
                            wait "$PID" 2>/dev/null || true
                        fi
                    }
                    trap cleanup EXIT
                    trap 'exit 130' INT
                    trap 'exit 143' TERM

                    diagnostics() {
                        echo '--- HeadlessMC output (last 80 lines) ---'
                        tail -80 "$LOG" 2>/dev/null || true
                        echo '--- Minecraft output (last 80 lines) ---'
                        tail -80 "$GAME_LOG" 2>/dev/null || true
                    }
                    crashed() {
                        grep -qE 'A mod crashed on startup|Reported exception thrown!|Crash report saved to|Minecraft has crashed!|Exception in thread "(main|Render thread)"' "$LOG" "$GAME_LOG" 2>/dev/null ||
                            compgen -G "$RUN_DIR/crash-reports/crash-*.txt" >/dev/null
                    }

                    if ! [[ "$TEST_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TEST_TIMEOUT" -le "$STABILITY_SECONDS" ]; then
                        echo 'ERROR: TEST_TIMEOUT must exceed the 10-second stability check.'
                        exit 1
                    fi
                    # Never accept readiness or crash evidence copied from a previous run.
                    rm -f "$GAME_LOG"
                    rm -rf "$RUN_DIR/crash-reports"
                    : > "$LOG"
                    mkdir -p "$RUN_DIR/.bobby"
                    # The CI agent has no physical audio device. Use OpenAL Soft's null backend.
                    export ALSOFT_DRIVERS=null

                    # Bound the entire launch, including Xvfb setup, and clean up on every exit.
                    setsid timeout --foreground --kill-after=10s "$TEST_TIMEOUT" xvfb-run -a \\
                    java -Dhmc.gamedir="$RUN_DIR" \\
                        -Dhmc.offline=true \\
                        -Dhmc.offline.username=Kd_Gaming1 \\
                        -Dhmc.check.xvfb=true \\
                        -Dhmc.crash.report.watcher=true \\
                        -Dhmc.exit.on.failed.command=true \\
                        -Dhmc.rethrow.launch.exceptions=true \\
                        -jar "$JAR" \\
                        --command "launch fabric-loader-${FABRIC_VERSION}-${MC_VERSION}" \\
                        > "$LOG" 2>&1 &
                    PID=$!
                    DEADLINE=$((SECONDS + TEST_TIMEOUT))
                    READY_AT=-1

                    while kill -0 "$PID" 2>/dev/null; do
                        if crashed; then
                            echo 'ERROR: Minecraft crash detected during launch.'
                            diagnostics
                            exit 1
                        fi
                        if [ "$SECONDS" -ge "$DEADLINE" ]; then
                            break
                        fi
                        # Crash Assistant's title-screen modlist refresh replaces the optional
                        # ModernFix timing message. It must be logged in this fresh game log,
                        # and the resulting file must contain exactly one JSON object or array.
                        # An unchanged checksum is normal when the mod set is unchanged.
                        if grep -qF "$READY_MARKER" "$GAME_LOG" 2>/dev/null &&
                           jq -e -s 'length == 1 and (.[0] | type == "object" or type == "array")' "$MODLIST" >/dev/null 2>&1; then
                            if [ "$READY_AT" -lt 0 ]; then
                                READY_AT=$SECONDS
                                echo 'Crash Assistant refreshed valid modlist JSON; checking stability for 10 seconds...'
                            fi
                            if [ "$((SECONDS - READY_AT))" -ge "$STABILITY_SECONDS" ]; then
                                # Check again before allowing build/tag stages to proceed.
                                if kill -0 "$PID" 2>/dev/null && ! crashed; then
                                    echo 'Launch smoke test passed: modlist refresh observed and process remained alive for 10 seconds.'
                                    exit 0
                                fi
                            fi
                        else
                            READY_AT=-1
                        fi
                        sleep 1
                    done

                    if kill -0 "$PID" 2>/dev/null; then
                        echo "ERROR: Launch test exceeded ${TEST_TIMEOUT}s before readiness and stability checks completed."
                    else
                        EXIT=0
                        wait "$PID" || EXIT=$?
                        echo "ERROR: Minecraft/HeadlessMC exited before checks completed (code $EXIT)."
                    fi
                    diagnostics
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
                    sh '''#!/bin/bash
                        MODLIST="$PACK_DIR/.pakku/client-overrides/config/crash_assistant/modlist.json"
                        REMOTE="https://${GIT_USER}:${GIT_TOKEN}@github.com/KdGaming0/SkyBlock-Enhanced-Modpack.git"
                        BRANCH="${BRANCH_NAME:-main}"
                        TAG="${RELEASE_TAG}"

                        git config user.name  "jenkins-ci"
                        git config user.email "jenkins@example.com"

                        # Step 1: Commit the refreshed modlist
                        if git diff --quiet -- "$MODLIST"; then
                            echo "modlist.json unchanged - no commit needed."
                        else
                            git add "$MODLIST"
                            git commit -m "chore(ci): refresh crash_assistant modlist.json for ${TAG}"
                            git push "$REMOTE" HEAD:"$BRANCH"
                        fi

                        # Step 2: Prevent re-releasing an existing version
                        if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/${TAG}" >/dev/null 2>&1; then
                            echo "ERROR: Tag ${TAG} already exists on GitHub!"
                            echo "Bump the version in pakku.json, or re-run release.sh"
                            echo "and pick [H] hotfix to cut a new tag for this version."
                            exit 1
                        fi

                        # Step 3: Tag the commit that contains the fresh modlist
                        git tag -d "$TAG" 2>/dev/null || true
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
            sh '''
                pkill -9 -f "hmc.gamedir=$WORKSPACE/run" || true
            '''
            archiveArtifacts artifacts: 'launch.log, run/logs/**, run/crash-reports/**',
                            allowEmptyArchive: true,
                            fingerprint: false
        }
    }
}
