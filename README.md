### This is a rough/WIP example of packages for a fork of Termux with a changed package name and a huge number of preinstalled packages
- The [bootstrap `.zip` files in termux-app-retired64](https://github.com/owokitty/termux-app-retired64/blob/retired64/app/src/main/bootstrap-part-1/bootstrap-aarch64-part-1.zip) can be reconstructed using some commands that are something like these.
- The trick is to first build the single bootstrap `.zip` file [similar to how you build an upstream one](https://github.com/termux/termux-packages/wiki/For-maintainers#build-bootstrap-archives) just messier and requiring more manual build intervention, then extract it and organize it out into four smaller `.zip` files, which do not need to contain specific files as long as the entire original bootstrap is preserved between them and the `SYMLINKS.txt` files are written correctly,
- Then place the bootstrap `.zip` files into their folders in the termux-app-retired64 project, run the gradle build four times to generate four `.apk` files, [one for each of the ndkBuild project files](https://github.com/owokitty/termux-app-retired64/blob/retired64/app/build.gradle#L109-L112), uncommenting one at a time,
- Then extract all four `.apk` files, copy all of the `.so` files into one of the extracted directory trees, then repackage and sign that folder as another `.apk` file.
- This is not 100% exactly accurate to how I built the release but they are real commands from partial bash history and I hope you get the idea, you need to extract the bootstrap, move some of its folders into other folders while making sure no single part is too large, make a new `SYMLINKS.txt` for each new bootstrap part, make sure it has the correct list of symlinks in it, compress the new `.zip` files, then build the termux-app-retired64 gradle project four times once for assembling/compiling the each `.zip` file into a `.so` file, then unzip all the `.apk` files, copy all the `.so` files into one of the unzipped folders, and rezip and resign the final `.apk` file.

```bash
mkdir bootstrap-aarch64
mkdir bootstrap-aarch64-part-{1,2,3,4}
cd bootstrap-aarch64/
unzip ../bootstrap-aarch64.zip
cat SYMLINKS.txt | grep share > bootstrap-aarch64-part-2/SYMLINKS.txt
cat SYMLINKS.txt | grep -v share > bootstrap-aarch64-part-1/SYMLINKS.txt
cd bootstrap-aarch64-part-2/
cd termux/termux-app/bootstrap-aarch64/
cd bootstrap-aarch64-part-1/
mv lib ../bootstrap-aarch64-part-2/
cat ../SYMLINKS.txt | grep ←./lib/ > ../bootstrap-aarch64-part-2/SYMLINKS.txt
cat ../SYMLINKS.txt | grep -v ←./lib/ > SYMLINKS.txt
cd ../bootstrap-aarch64-part-1/
7z a bootstrap-aarch64-part-1.zip * -mfb=258 -mpass=15
cd ../bootstrap-aarch64-part-2/
7z a bootstrap-aarch64-part-2.zip * -mfb=258 -mpass=15
cd ../bootstrap-aarch64-part-3/
7z a bootstrap-aarch64-part-3.zip * -mfb=258 -mpass=15
cd ../bootstrap-aarch64-part-4/
7z a bootstrap-aarch64-part-4.zip * -mfb=258 -mpass=15
cd ..
wget https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar
mkdir apk-tmp-part-{1,2,3,4}
cd apk-tmp-part-1/
unzip ../termux-app_apt-android-7-debug_arm64-v8a-part-1.apk
cd ../apk-tmp-part-2/
unzip ../termux-app_apt-android-7-debug_arm64-v8a-part-2.apk
cd ../apk-tmp-part-3/
unzip ../termux-app_apt-android-7-debug_arm64-v8a-part-3.apk
cd ../apk-tmp-part-4/
unzip ../termux-app_apt-android-7-debug_arm64-v8a-part-4.apk
cd ../apk-tmp-part-1/
cp ../apk-tmp-part-2/lib/arm64-v8a/libtermux-bootstrap-part-2.so lib/arm64-v8a/
cp ../apk-tmp-part-3/lib/arm64-v8a/libtermux-bootstrap-part-3.so lib/arm64-v8a/
cp ../apk-tmp-part-4/lib/arm64-v8a/libtermux-bootstrap-part-4.so lib/arm64-v8a/
zip -0 -r uncompressed.zip ./*
zipalign -f -p 4 uncompressed.zip com.retired64.termux.apk
java -jar ../uber-apk-signer-1.3.0.jar -a com.retired64.termux.apk --ks ../../app/testkey_untrusted.jks --ksAlias alias --ksKeyPass xrj45yWGLbsO7W0v --ksPass xrj45yWGLbsO7W0v -o com.retired64.termux
cd com.retired64.termux/
mv com.retired64.termux-aligned-signed.apk com.retired64.termux.apk
```

# Termux packages original README below

![GitHub repo size](https://img.shields.io/github/repo-size/termux/termux-packages)
[![Packages last build status](https://github.com/termux/termux-packages/workflows/Packages/badge.svg)](https://github.com/termux/termux-packages/actions)
[![Docker image status](https://github.com/termux/termux-packages/workflows/Docker%20image/badge.svg)](https://hub.docker.com/r/termux/package-builder)
[![Repology metadata](https://github.com/termux/repology-metadata/workflows/Repology%20metadata/badge.svg)](https://repology.org/repository/termux)
[![Join the chat at https://gitter.im/termux/termux](https://badges.gitter.im/termux/termux.svg)](https://gitter.im/termux/termux)
[![Join the Termux discord server](https://img.shields.io/discord/641256914684084234.svg?label=&logo=discord&logoColor=ffffff&color=5865F2)](https://discord.gg/HXpF69X)

[![Repository status](https://repology.org/badge/repository-big/termux.svg)](https://repology.org/repository/termux)

<img src=".github/static/hosted-by-hetzner.png" alt="Hosted by Hetzner" width="128px"></img>

This project contains scripts and patches to build packages for the [Termux](https://github.com/termux/termux-app)
Android application.

Quick how-to about Termux package management is available at [Package Management](https://github.com/termux/termux-packages/wiki/Package-Management). It also has info on how to fix **`repository is under maintenance or down`** errors when running `apt` or `pkg` commands.

## Contributing

Read [CONTRIBUTING.md](/CONTRIBUTING.md) and [Developer's Wiki](https://github.com/termux/termux-packages/wiki) for more details.

## Contacts

General mailing list: https://groups.io/g/termux

Developer mailing list: https://groups.io/g/termux-dev

General chat: https://gitter.im/termux/termux or #termux on IRC/libera.chat.

Developer chat: https://gitter.im/termux/dev.
