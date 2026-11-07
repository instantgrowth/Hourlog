# HourLog

A simple time tracker and timesheet app (Flutter).

Features: Punch in/out, manual entries, projects, hourly rate, daily/weekly goals, monthly timesheets, earnings overview. Data is stored locally on the device.

## Build without a computer (GitHub Actions)

1. Create a free account at github.com and a new repository named `hourlog`.
2. Upload all files from this folder, keeping the folder structure (`lib/main.dart`, `pubspec.yaml`, `.github/workflows/build.yml`).
3. Open the **Actions** tab -> **Build Android** -> wait for the green check.
4. Open the finished run, download the **hourlog-debug-apk** artifact, unzip it and install the APK on your phone to test.
