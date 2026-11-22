# Nexus Calc 4D

Node-canvas + time-travel calculator (Flutter, Android project included).

Build the APK on GitHub:
1. Create a new GitHub repository.
2. Upload ALL files/folders of this project (lib, android, pubspec.yaml, .github ...).
   If `.github/workflows/build-apk.yml` did not upload (hidden folder), create it on GitHub
   (Add file > Create new file, name: .github/workflows/build-apk.yml) and paste the content
   of `WORKFLOW_COPY_build-apk.yml`.
3. Open the Actions tab > "Build Android APK" (runs on every push, or press "Run workflow").
4. When green: open the run > Artifacts > download `nexus-calc-apk` > unzip > install app-release.apk.

Local run: flutter pub get && flutter run
