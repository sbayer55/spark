# Spark task runner. `just` lists recipes.

set shell := ["bash", "-euo", "pipefail", "-c"]

derived := "build"
app := derived / "Build/Products"

# List recipes
default:
    @just --list

# Regenerate Spark.xcodeproj from project.yml
generate:
    xcodegen generate

# Build the app (Debug or Release)
build config="Debug": generate
    xcodebuild build \
        -scheme Spark \
        -configuration {{config}} \
        -destination 'platform=macOS' \
        -derivedDataPath {{derived}} \
        | tee build.log

# Build like CI: fail if the build emits any warnings
check config="Debug": (build config)
    #!/usr/bin/env bash
    set -euo pipefail
    if grep -E '^(/[^:]+:[0-9]+:[0-9]+: )?warning: ' build.log | sort -u | tee /dev/stderr | grep -q .; then
        echo "error: build produced warnings" >&2
        exit 1
    fi
    echo "No warnings."

# Build Debug, then relaunch the app; extra args go to the app (e.g. `just run -SparkEphemeralSecrets YES`)
run *args: build
    -pkill -x Spark
    open {{app}}/Debug/Spark.app {{ if args == "" { "" } else { "--args " + args } }}

# Generate the project and open it in Xcode
xcode: generate
    open Spark.xcodeproj

# Archive and zip a release build into build/ (same steps as the Release workflow)
archive: generate
    xcodebuild archive \
        -scheme Spark \
        -destination 'generic/platform=macOS' \
        -derivedDataPath {{derived}} \
        -archivePath {{derived}}/Spark.xcarchive
    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" {{derived}}/Spark.xcarchive/Products/Applications/Spark.app/Contents/Info.plist); \
    ditto -c -k --sequesterRsrc --keepParent {{derived}}/Spark.xcarchive/Products/Applications/Spark.app "{{derived}}/Spark-$version.zip"; \
    echo "{{derived}}/Spark-$version.zip"

# Remove build output and the generated project
clean:
    rm -rf {{derived}} DerivedData Spark.xcodeproj build.log
