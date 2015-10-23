#!/usr/bin/env bash
set -e
[ -d build ] && rm -rf build
mkdir -p build/bin
pub upgrade
dart2js bin/run.dart -o build/bin/run.dart --output-type=dart --categories=Server
cp dslink.json build/dslink.json
cp -R res build/res
cd build/
zip -r ../../../files/rest.zip .