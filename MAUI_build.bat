   
:: BEGIN

@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: CONFIGURATION VARIABLES - Edit these before running
:: ============================================================

:: Solution and project paths
set projectName=MyApp

set projectdir=C:\Projects\%projectName%
set mainproject=%projectdir%\%projectName%\%projectName%.csproj
set mainsolution=%projectdir%\%projectName%.sln


:: Output path for Droid published artifacts
set "outpath=C:\%projectdir%\MobileBuildsOutput"

:: App ID
set ApplicationId=my.app.id

:: App Framework version
set ProjectFrameworkVer=net9.0


:: iOS / Apple AppStore credentials
:: Apple ID used for App Store Connect authentication
set APPLE_ID=my@email.ru
:: App-specific password (generate at appleid.apple.com)
set APPLE_APP_PASSWORD=app-specific-password
:: Your Apple Team ID (found in Apple Developer portal)
set APPLE_TEAM_ID=TEAM_ID
:: Bundle identifier of your app
set APPLE_BUNDLE_ID=%ApplicationId%

:: Mac Build Host (for iOS remote build from Windows)
:: IP address or hostname of your Mac
set MAC_HOST=10.0.0.1
:: Mac login username
set MAC_USER=user
:: Mac login password
set MAC_PASSWORD=password

:: NB! generate public SSH key and put into ~/.ssh/authorized_keys to automatically connect with ssh, otherwise you'll be prompted enter password 100500 times.


:: appstore connect api key (P8 key must reside on Mac at ASC_KEY_PATH)
set ASC_KEY_ID=KEY_ID
set ASC_ISSUER_ID=ISSUER_ID
set ASC_KEY_PATH=/Users/%MAC_USER%/private_keys/AuthKey_%ASC_KEY_ID%.p8

:: export options PList file required to exporting xcarchive into final ipa package (must reside on Mac)
set EXPORT_OPTIONS_PLIST_LOCATION_ON_MAC=~/Dump/ExportOptions_%projectName%.plist
set ASC_WHAT_TO_TEST_FILLER_SCRIPT_PATH_ON_MAC=~/Dump/appstoreconnect-what-to-test-filler.sh





:: Android Signing credentials (for release APK/AAB signing)
:: Path to your keystore file
set ANDROID_KEYSTORE=%projectdir%\stuff\google\upload.keystore
:: Keystore password
set ANDROID_KEYSTORE_PASS=password
:: Key alias inside the keystore
set ANDROID_KEY_ALIAS=alias
:: Key alias password
set ANDROID_KEY_PASS=password













:: ============================================================
:: STEP 0: Extract current build version
:: ============================================================


:: Extract ApplicationDisplayVersion (e.g. "1.2.3")
for /f "tokens=3 delims=<>" %%i in ('findstr /i "ApplicationDisplayVersion" "%mainproject%"') do (
    set APP_DISPLAY_VERSION=%%i
)

:: Extract ApplicationVersion (e.g. build number "42")
for /f "tokens=3 delims=<>" %%i in ('findstr /i "ApplicationVersion" "%mainproject%" ^| findstr /v /i "Display"') do (
    set APP_VERSION=%%i
)

echo.

powershell -Command "Write-Host 'Current build version ' -NoNewline;  Write-Host '(verify it is not already published in GooglePlay/Testflight)' -ForegroundColor Magenta -NoNewline; Write-Host ':'; Write-Host 'Display Version : ' -NoNewline;  Write-Host '%APP_DISPLAY_VERSION%' -ForegroundColor Yellow; Write-Host 'Build Number    : ' -NoNewline;  Write-Host '%APP_VERSION%' -ForegroundColor Yellow"

set "ANDROID_APK_PACKAGE_FILENAME=%ApplicationId% (%APP_VERSION%).apk"
set "ANDROID_AAB_PACKAGE_FILENAME=%ApplicationId%(%APP_VERSION%).aab"


echo.
echo Select platform:
powershell -Command "Write-Host '[a/android]' -ForegroundColor Cyan -NoNewline;  Write-Host ': Android only';" ^
					"Write-Host '[i/ios]' -ForegroundColor Cyan -NoNewline;  Write-Host ': iOS only';" ^
					"Write-Host '[q/quit/e/exit]' -ForegroundColor Cyan -NoNewline;  Write-Host ': quit';" ^
					"Write-Host 'Anything else' -ForegroundColor Cyan -NoNewline;  Write-Host ': build both Android and iOS'"
echo.
set "bchoice="
set /p bchoice="Select and press Enter: "

if /I "%bchoice%"=="q" goto :end
if /I "%bchoice%"=="quit" goto :end
if /I "%bchoice%"=="exit" goto :end
if /I "%bchoice%"=="e" goto :end

if /I "%bchoice%"=="android" set "bchoice=a"
if /I "%bchoice%"=="ios" set "bchoice=i"

if /I "%bchoice%"=="i" (
	powershell -Command "Write-Host 'Building iOS only' -ForegroundColor Magenta"
) else if /I "%bchoice%"=="a" (
	powershell -Command "Write-Host 'Building Droid only' -ForegroundColor Magenta"
) else (
	powershell -Command "Write-Host 'Building both Droid and ios' -ForegroundColor Magenta"
)

:: ============================================================
:: STEP 1: Validate directories exist
:: ============================================================
echo.
echo [STEP 1] Validating paths...

if not exist "%projectdir%" (
    powershell -Command "Write-Host 'Project directory not found: ''%projectdir%''' -ForegroundColor Red"
    goto :error
)

if not exist "%mainproject%" (
	powershell -Command "Write-Host 'ERROR: Main project file not found: %mainproject%' -ForegroundColor Red"
    goto :error
)

:: Create output directory if it doesn't exist
if not exist "%outpath%" (
    echo Creating output directory: %outpath%
    mkdir "%outpath%"
)

echo Paths validated successfully.

:: ============================================================
:: STEP 2: Clean bin and obj folders of the main MAUI project
:: ============================================================
echo.
echo [STEP 2] Deleting bin and obj folders...

set binpath=%projectdir%\%projectName%\bin
set objpath=%projectdir%\%projectName%\obj

if exist "%binpath%" (
    echo Removing: %binpath%
    rmdir /s /q "%binpath%"
) else (
    echo bin folder not found, skipping...
)

if exist "%objpath%" (
    echo Removing: %objpath%
    rmdir /s /q "%objpath%"
) else (
    echo obj folder not found, skipping...
)

echo Clean completed.

:: ============================================================
:: STEP 3: Restore NuGet packages and Rebuild solution
::         for Release configuration
:: ============================================================

echo.

echo [STEP 3] Rebuilding project in Release configuration...

echo [STEP 3.0] Cleaning harmful remnants in csproj.user...

if exist "%mainproject%.user" powershell -Command ^
	  "[xml]$x = Get-Content '%mainproject%.user'; " ^
	  "$n = $x.SelectNodes(\"//*[local-name()='TargetiOSDevice']\"); " ^
	  "if($n.Count -gt 0){ foreach($node in $n){ $node.ParentNode.RemoveChild($node) | Out-Null }; $x.Save('%mainproject%.user'); Write-Host \"Cleaned $($n.Count) node(s)\" } else { Write-Host 'Nothing to clean' }"

echo [STEP 3.1] Rebuilding

dotnet build "%mainproject%" ^
    -c Release ^
	-p:AndroidManifest="\%projectName%\Platforms\Android\AndroidManifest.xml" ^
	-p:MtouchNoSymbolStrip=true ^
	-p:MtouchDebug=true ^
	-p:MtouchFastDev=false

if %ERRORLEVEL% neq 0 (
	powershell -Command "Write-Host 'ERROR: Build failed.' -ForegroundColor Red"
    goto :error
)

echo Build completed successfully.



rem goto :skipios


:: ============================================================
:: STEP 4: Archive for iOS (Release) with Mac remote build
::         Requires Visual Studio Mac Agent / SSH connection
::         to be configured, or use dotnet workload for iOS.
::
::         Key parameters:
::           /p:ServerAddress  - Mac IP/hostname
::           /p:ServerUser     - Mac username
::           /p:ServerPassword - Mac password
::           /p:TreatWarningsAsErrors=false - optional
:: ============================================================
echo.

if /I "%bchoice%"=="a" (
	echo [STEP 4 and 5] Skipping iOS, Android only.
	goto :skipios
)

echo [STEP 4] Archiving for iOS Release (via Mac remote build)...

dotnet publish "%mainproject%" ^
    -c Release ^
    -f %ProjectFrameworkVer%-ios ^
    /p:ArchiveOnBuild=true ^
    /p:ServerAddress=%MAC_HOST% ^
    /p:ServerUser=%MAC_USER% ^
    /p:ServerPassword=%MAC_PASSWORD% ^
    /p:TreatWarningsAsErrors=false ^
	/p:MtouchNoSymbolStrip=true /p:MtouchDebug=true /p:MtouchFastDev=false

rem /p:RuntimeIdentifier=ios-arm64
	
if %ERRORLEVEL% neq 0 (
	powershell -Command "Write-Host 'ERROR: iOS Archive failed.' -ForegroundColor Red"
    goto :error
)

echo iOS Archive completed.

:: ============================================================
:: STEP 5: Publish iOS app to Apple App Store
::         Uses Apple Transporter / altool under the hood.
::         Credentials set in variables at the top.
::
::         Note: The .ipa file is typically generated on the Mac
::         during the archive step. Adjust the .ipa path below
::         to match what was produced in STEP 4.
:: ============================================================
echo.
echo [STEP 5] Publishing iOS app to Apple App Store...

:: Adjust the path to your .ipa file produced during archiving
::set IPA_PATH=%projectdir%\%projectName%\bin\Release\%ProjectFrameworkVer%-ios\ios-arm64\publish\%projectName%.ipa

::if not exist "%IPA_PATH%" (
    ::echo WARNING: .ipa file not found at expected path: %IPA_PATH%
    ::echo Please verify the archive output location and update IPA_PATH.
    ::echo Skipping App Store publish...
    ::goto :skipios
::)

:: Upload to App Store using xcrun altool (runs on Mac via SSH)
:: Alternatively install "Apple Transporter" CLI on Mac


rem echo [5.1] Get hash folder (most recently modified = current build)
rem for /f "delims=" %%i in ('ssh %MAC_USER%@%MAC_HOST% "ls -t ~/Library/Caches/maui/PairToMac/Builds/%projectName%/ | head -1"') do (set MAC_BUILD_HASH=%%i)

REM if "%MAC_BUILD_HASH%"=="" (
    REM echo ERROR: Could not find build hash folder on Mac!
    REM goto :error
REM )

REM echo Build session hash: %MAC_BUILD_HASH%

:: Construct all related paths from the same hash
rem set MAC_BUILD_ROOT=/Users/%MAC_USER%/Library/Caches/maui/PairToMac/Builds/%projectName%/%MAC_BUILD_HASH%/bin/Release/%ProjectFrameworkVer%-ios/ios-arm64


REM set IPA_MAC_PATH=%MAC_BUILD_ROOT%/publish/%projectName%.ipa
REM set DSYM_MAC_PATH=%MAC_BUILD_ROOT%/%projectName%.app.dSYM

REM echo IPA  : %IPA_MAC_PATH%
REM echo dSYM : %DSYM_MAC_PATH%



REM echo [5.2] Uploading IPA to App Store Connect...
REM ssh %MAC_USER%@%MAC_HOST% "xcrun altool --upload-app --type ios --file \"%IPA_MAC_PATH%\" --apiKey \"%ASC_KEY_ID%\" --apiIssuer \"%ASC_ISSUER_ID%\""

REM if %ERRORLEVEL% neq 0 (
    REM echo ERROR: IPA upload failed!
    REM goto :error
REM )
	
REM echo [5.3.1] Zipping dSYM for upload...
REM ssh %MAC_USER%@%MAC_HOST% "cd \"%MAC_BUILD_ROOT%\" && zip -r %projectName%.app.dSYM.zip %projectName%.app.dSYM"
	
REM echo [5.3.2] Uploading dSYM to App Store Connect...
REM ssh %MAC_USER%@%MAC_HOST% "xcrun altool --upload-symbols --bundle-id %APPLE_BUNDLE_ID% -f \"%MAC_BUILD_ROOT%/%projectName%.app.dSYM.zip\" --username \"%APPLE_ID%\" --password \"%APPLE_APP_PASSWORD%\""

REM if %ERRORLEVEL% neq 0 (
    REM echo WARNING: dSYM upload failed - symbols won't be available in crash reports
    REM echo You can upload dSYM manually via App Store Connect web interface
REM ) else (
    REM echo dSYM upload completed successfully.
REM )

REM set IPA_MAC_PATH=%MAC_BUILD_ROOT%/publish/%projectName%.ipa

for /f "delims=" %%i in ('ssh %MAC_USER%@%MAC_HOST% "ls -t ~/Library/Developer/XCode/Archives/ | head -1"') do (set MAC_ARCHIVE_OUTPUT_FOLDER=%%i)

echo MAC_ARCHIVE_OUTPUT_FOLDER: %MAC_ARCHIVE_OUTPUT_FOLDER%

for /f "delims=" %%i in ('ssh %MAC_USER%@%MAC_HOST% "ls -t ~/Library/Developer/XCode/Archives/%MAC_ARCHIVE_OUTPUT_FOLDER%/ | head -1"') do (set MAC_ARCHIVE_FILENAME=%%i)

echo MAC_ARCHIVE_FILENAME: %MAC_ARCHIVE_FILENAME%

if "%MAC_ARCHIVE_FILENAME%"=="" (
	powershell -Command "Write-Host 'ERROR: archive not detected on Mac!' -ForegroundColor Red"
    goto :error
)



rem echo [5.1] SSH into Mac and run xcodebuild archive
rem ssh %MAC_USER%@%MAC_HOST% "xcodebuild archive -project ~/Library/Caches/maui/PairToMac/Builds/%projectName%/%MAC_BUILD_HASH%/%projectName%.xcodeproj -scheme %projectName% -configuration Release -archivePath ~/Archives/%projectName%.xcarchive"


rem ssh %MAC_USER%@%MAC_HOST% "[ -e \"$HOME/Library/Developer/Xcode/Archives/%MAC_ARCHIVE_OUTPUT_FOLDER%/%MAC_ARCHIVE_FILENAME%/Products/Applications/WebsoftWorkspaceM.app/Frameworks/libSkiaSharp.framework\" ] && echo \"+File exists+\" || echo '-Nothing-'"


rem ssh %MAC_USER%@%MAC_HOST% "security unlock-keychain -p 'your_password' ~/Library/Keychains/login.keychain-db"

rem echo [5.0] Striptease
rem ssh %MAC_USER%@%MAC_HOST% "CFRAMEWORK=\"$HOME/Library/Developer/Xcode/Archives/%MAC_ARCHIVE_OUTPUT_FOLDER%/%MAC_ARCHIVE_FILENAME%/Products/Applications/WebsoftWorkspaceM.app/Frameworks/libSkiaSharp.framework\" && echo \"Re-signing: $CFRAMEWORK\" && codesign --remove-signature \"$CFRAMEWORK\" && codesign -f -s \"iPhone Distribution: WebSoft Ltd. (M8J5ADVV86)\" \"$CFRAMEWORK\""

REM echo [5.00] Striptease hardcore
REM ssh %MAC_USER%@%MAC_HOST% ^
    REM "ARCHIVE_PATH=$HOME/Library/Developer/Xcode/Archives/%MAC_ARCHIVE_OUTPUT_FOLDER%/%MAC_ARCHIVE_FILENAME% && ^
     REM find \"$ARCHIVE_PATH/Products/Applications/WebsoftWorkspaceM.app/Frameworks\" -name '*.framework' | while read fw; do ^
         REM echo \"Re-signing: $fw\" && ^
         REM codesign --remove-signature \"$fw\" && ^
         REM codesign -f -s \"iPhone Distribution: WebSoft Ltd. (M8J5ADVV86)\" \"$fw\" ^
     REM done"
REM goto :end;

echo [STEP 5.1] Cleaning previous export folder

set MAC_EXPORT_FOLDER=~/Library/Caches/maui/Export


ssh %MAC_USER%@%MAC_HOST% "rm -rf %MAC_EXPORT_FOLDER%"



echo [STEP 5.2] Export .ipa from .xcarchive
ssh %MAC_USER%@%MAC_HOST% "security unlock-keychain -p '%MAC_PASSWORD%' ~/Library/Keychains/login.keychain-db && xcodebuild -exportArchive -archivePath \"~/Library/Developer/XCode/Archives/%MAC_ARCHIVE_OUTPUT_FOLDER%/%MAC_ARCHIVE_FILENAME%\" -exportPath %MAC_EXPORT_FOLDER% -exportOptionsPlist %EXPORT_OPTIONS_PLIST_LOCATION_ON_MAC%"

echo [STEP 5.3] Upload the exported .ipa (dSYM included automatically via xcarchive flow)
rem ssh %MAC_USER%@%MAC_HOST% "xcrun altool --validate-app --type ios --file \"%MAC_EXPORT_FOLDER%/%projectName%.ipa\" --apiKey \"%ASC_KEY_ID%\" --apiIssuer \"%ASC_ISSUER_ID%\""
ssh %MAC_USER%@%MAC_HOST% "xcrun altool --upload-app --type ios --file \"%MAC_EXPORT_FOLDER%/%projectName%.ipa\" --apiKey \"%ASC_KEY_ID%\" --apiIssuer \"%ASC_ISSUER_ID%\""

if %ERRORLEVEL% neq 0 (
	powershell -Command "Write-Host 'ERROR: IPA export failed!' -ForegroundColor Red"
    goto :error
)





echo [STEP 5.4] Launching what-to-test filler script (fire-and-forget mode, see '%ASC_WHAT_TO_TEST_FILLER_SCRIPT_PATH_ON_MAC%.log' for results)

ssh %MAC_USER%@%MAC_HOST% "chmod +x %ASC_WHAT_TO_TEST_FILLER_SCRIPT_PATH_ON_MAC% &&" ^

  "nohup bash %ASC_WHAT_TO_TEST_FILLER_SCRIPT_PATH_ON_MAC%" ^
  "%ASC_KEY_ID%" ^
  "%ASC_ISSUER_ID%" ^
  "%ASC_KEY_PATH%" ^
  "%ApplicationId%" ^
  "%APP_DISPLAY_VERSION%" ^
  "%APP_VERSION%" ^
  "'New swarm of bugs arrived in %APP_VERSION%'" ^
  "> %ASC_WHAT_TO_TEST_FILLER_SCRIPT_PATH_ON_MAC%.log 2>&1 &"
  
echo What-to-test filler script launched. Proceeding next.




echo iOS App Store publish completed.


:skipios

:: ============================================================
:: STEP 6: Archive for Android - APK format (Release)
::         Signs the APK with the provided keystore credentials.
::         /p:AndroidPackageFormats=apk  - produces only APK
:: ============================================================
echo.

if /I "%bchoice%"=="i" (
	echo [STEP 4 and 5] Skipping Android, iOS only.
	goto :end
)


echo [STEP 6] Archiving for Android Release (APK format)...

dotnet publish "%mainproject%" ^
    -c Release ^
    -f %ProjectFrameworkVer%-android ^
	-p:AndroidManifest="\%projectName%\Platforms\Android\AndroidManifest.xml" ^
    -p:AndroidPackageFormats=apk ^
    -p:AndroidKeyStore=true ^
    -p:AndroidSigningKeyStore="%ANDROID_KEYSTORE%" ^
    -p:AndroidSigningStorePass=%ANDROID_KEYSTORE_PASS% ^
    -p:AndroidSigningKeyAlias=%ANDROID_KEY_ALIAS% ^
    -p:AndroidSigningKeyPass=%ANDROID_KEY_PASS%



if %ERRORLEVEL% neq 0 (
	powershell -Command "ERROR: Android APK archive/publish failed.' -ForegroundColor Red"
    goto :error
)

echo Android APK archive completed.

:: ============================================================
:: STEP 7: Copy/Publish APK "Ad Hoc" to output directory
::         The -o flag in dotnet publish above already places
::         output into outpath\apk\, but we do an explicit
::         copy here in case you need a flat structure.
:: ============================================================
echo.
echo [STEP 7] Copying APK to output directory...



:: Find the signed APK (typically named *-Signed.apk)
for %%i in ("%projectdir%\%projectName%\bin\Release\%ProjectFrameworkVer%-android\*-Signed.apk") do (
    echo Copying %%i to %outpath%
    copy /Y "%%i" "%outpath%\%ANDROID_APK_PACKAGE_FILENAME%"
)

echo APK copy completed.

:: ============================================================
:: STEP 8: Archive for Android - AAB format (Release)
::         AAB (Android App Bundle) is required for
::         Google Play Store submission.
::         /p:AndroidPackageFormats=aab - produces only AAB
:: ============================================================
echo.
echo [STEP 8] Archiving for Android Release (AAB format)...

dotnet publish "%mainproject%" ^
    -c Release ^
    -f %ProjectFrameworkVer%-android ^
	-p:AndroidManifest="\%projectName%\Platforms\Android\AndroidManifest.xml" ^
    -p:AndroidPackageFormats=aab ^
    -p:AndroidKeyStore=true ^
    -p:AndroidSigningKeyStore="%ANDROID_KEYSTORE%" ^
    -p:AndroidSigningStorePass=%ANDROID_KEYSTORE_PASS% ^
    -p:AndroidSigningKeyAlias=%ANDROID_KEY_ALIAS% ^
    -p:AndroidSigningKeyPass=%ANDROID_KEY_PASS%



if %ERRORLEVEL% neq 0 (
	powershell -Command "ERROR: Android AAB archive/publish failed.' -ForegroundColor Red"
    goto :error
)

echo Android AAB archive completed.

:: ============================================================
:: STEP 9: Copy/Publish AAB "Ad Hoc" to output directory
::         Same as STEP 7 but for AAB files.
:: ============================================================
echo.
echo [STEP 9] Copying AAB to output directory...




:: Find the signed AAB
for %%i in ("%projectdir%\%projectName%\bin\Release\%ProjectFrameworkVer%-android\*-Signed.aab") do (
    echo Copying %%i to %outpath%
    copy /Y "%%i" "%outpath%\%ANDROID_AAB_PACKAGE_FILENAME%"
)

echo AAB copy completed.

:: ============================================================
:: ALL DONE
:: ============================================================
echo.
echo ============================================================
echo  BUILD COMPLETE!
powershell -Command "Write-Host 'APK output : %outpath%\%ANDROID_APK_PACKAGE_FILENAME%' -ForegroundColor Green; Write-Host 'APK output : %outpath%\%ANDROID_APK_PACKAGE_FILENAME%' -ForegroundColor Green"
rem echo  APK output : %outpath%\%ANDROID_APK_PACKAGE_FILENAME%
rem echo  AAB output : %outpath%\%ANDROID_AAB_PACKAGE_FILENAME%
echo ============================================================
goto :end

:error
echo.
echo ============================================================
echo  BUILD FAILED! Check the errors above.
echo ============================================================
exit /b 1

:end
endlocal
exit /b 0
