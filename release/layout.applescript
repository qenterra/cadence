on run argv
    set volumeName to item 1 of argv
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set pathbar visible of container window to false
            set bounds of container window to {100, 100, 760, 560}
            set theViewOptions to icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 112
            set text size of theViewOptions to 13
            set background picture of theViewOptions to file ".background:dmg-background.png"
            set position of item "Cadence.app" of container window to {190, 235}
            set position of item "Applications" of container window to {470, 235}
            update without registering applications
            delay 2
            close
            open
            delay 2
        end tell
    end tell
end run
