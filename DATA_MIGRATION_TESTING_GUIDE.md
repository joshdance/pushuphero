# Pushup Hero - Phase 1 Data Migration Testing Guide

## Overview
This guide provides detailed instructions for testing the Phase 1 data migration from deprecated NSCoding to modern NSSecureCoding. The migration maintains **100% backward compatibility** with existing user data.

## What Changed

### Technical Changes
1. **DataObject.swift**: Updated from `NSCoding` to `NSSecureCoding` protocol
2. **ViewController.swift**: Modernized save/load methods with new Apple APIs
3. **Version Tracking**: Added data version field for future migrations
4. **Error Handling**: Removed force unwrapping, added proper error handling
5. **Automatic Migration**: Old data automatically converts to new format on next save

### User Impact
- **Zero data loss**: All existing workout data preserved
- **Seamless upgrade**: Migration happens automatically in background
- **Better reliability**: Improved error handling prevents crashes

---

## Pre-Testing Checklist

### Before Installing the New Version

#### 1. Backup Existing User Data (CRITICAL)
```bash
# For real device testing via Xcode
# Connect device and run:
xcrun simctl get_app_container booted com.yourbundleid data

# For simulator testing
# Find the app's container:
xcrun simctl get_app_container booted com.yourbundleid data

# Copy the Data file to a safe location:
cp ~/Library/Developer/CoreSimulator/Devices/[DEVICE-ID]/data/Containers/Data/Application/[APP-ID]/Documents/Data ~/Desktop/pushup-hero-backup-$(date +%Y%m%d).data
```

**Alternative: Using Xcode**
1. Open Xcode → Window → Devices and Simulators
2. Select your device/simulator
3. Select Pushup Hero app
4. Click the gear icon → Download Container
5. Save the .xcappdata file with today's date

#### 2. Document Current State
Record the following BEFORE upgrading:
- [ ] Total number of workouts displayed in the table
- [ ] Today's pushup count
- [ ] This week's pushup count
- [ ] This month's pushup count
- [ ] This year's pushup count
- [ ] Screenshot of the main screen
- [ ] Note any special characters in workout notes

---

## Testing Scenarios

### Scenario 1: Fresh Install (No Existing Data)

**Purpose**: Verify new installations work correctly

**Steps**:
1. Delete the app completely from device/simulator
2. Clean build folder (Cmd+Shift+K in Xcode)
3. Build and install the new version
4. Launch the app

**Expected Results**:
- ✅ App launches without errors
- ✅ Table view is empty
- ✅ All counters show 0
- ✅ Console shows: `"No existing data file found. Starting fresh."`

**Test Actions**:
1. Add a workout with 25 pushups and note "Test 1"
2. Verify it appears in the table
3. Close app completely
4. Relaunch app

**Expected Results**:
- ✅ Workout persists after relaunch
- ✅ Console shows: `"Successfully loaded 1 workouts using modern format"`
- ✅ Counter shows 25 for today

---

### Scenario 2: Upgrade from Old Version (MOST IMPORTANT)

**Purpose**: Verify existing user data migrates successfully

**Setup**:
1. Install the OLD version (v1.0 build 2) on simulator
2. Create test data:
   - Workout 1: 50 pushups, note "Before migration"
   - Workout 2: 30 pushups, note "Test data"
   - Workout 3: 100 pushups, note "Special chars: 😊 #test"
3. Force close the app (don't just background it)
4. Verify data persists by relaunching old version
5. Take note of all counts

**Migration Test**:
1. Build and install the NEW version (overwrites old version)
2. Launch the app
3. **IMMEDIATELY check Xcode console for logs**

**Expected Console Output**:
```
Data file exists. Loading...
Successfully loaded 3 workouts using legacy format
Data will be automatically migrated to new format on next save
```
OR
```
Data file exists. Loading...
Successfully loaded 3 workouts using modern format
```

**Expected UI Results**:
- ✅ All 3 workouts appear in table view
- ✅ Workout notes are intact (including emojis)
- ✅ All dates are correct
- ✅ All pushup counts are correct
- ✅ Today/Week/Month/Year counters match pre-migration values

**Verify Migration Completion**:
1. Add one new workout: 10 pushups, note "Post-migration"
2. Check console output:
   ```
   Data saved successfully. Total workouts: 4
   ```
3. Force close app
4. Relaunch app
5. Check console output:
   ```
   Successfully loaded 4 workouts using modern format
   ```
   _(Note: Should now say "modern format" instead of "legacy format")_

**Expected Results**:
- ✅ All 4 workouts present
- ✅ No data loss
- ✅ Migration to new format completed automatically

---

### Scenario 3: Multiple Migration Cycles

**Purpose**: Verify repeated saves don't corrupt data

**Steps**:
1. Start with migrated data from Scenario 2
2. Add 5 more workouts with varying data:
   - Mix of empty notes and filled notes
   - Different pushup counts (1, 50, 100, 200)
   - Some with special characters
3. After each workout, force close and relaunch app
4. Verify count increments correctly each time

**Expected Results**:
- ✅ Each workout persists
- ✅ No data corruption
- ✅ Console always shows "modern format" after first migration
- ✅ All counters update correctly

---

### Scenario 4: Midnight Workout Handling

**Purpose**: Verify date attribution logic still works

**Steps**:
1. Change device time to 1:30 AM
2. Add a workout with 20 pushups
3. Verify alert appears: "Which day?"
4. Select yesterday
5. Close and relaunch app
6. Verify workout is attributed to yesterday (not today)

**Expected Results**:
- ✅ Alert appears as expected
- ✅ Date attribution works correctly
- ✅ Data saves and loads without errors

---

### Scenario 5: Data Validation

**Purpose**: Verify all data fields are preserved correctly

**Test Matrix**:

| Field | Test Value | Expected Result |
|-------|------------|-----------------|
| `numberOfPushups` | 0 | Preserved exactly |
| `numberOfPushups` | 1 | Preserved exactly |
| `numberOfPushups` | 999 | Preserved exactly |
| `listOfStrings` | Empty string "" | Preserved |
| `listOfStrings` | "Simple text" | Preserved |
| `listOfStrings` | "Emoji 😊🎉" | Preserved |
| `listOfStrings` | "Unicode: 你好" | Preserved |
| `dateOfSave` | Any date | Preserved exactly |
| `dateOfWorkout` | Any date | Preserved exactly |

**Steps**:
1. Create workouts with each test value
2. Force close app
3. Relaunch app
4. Verify each value in UI matches input

---

### Scenario 6: Large Dataset Test

**Purpose**: Verify performance with realistic data volumes

**Steps**:
1. Create a test script or manually add 100+ workouts
2. Verify app remains responsive
3. Scroll through entire table
4. Force close and relaunch
5. Time how long load takes

**Expected Results**:
- ✅ Load completes in < 2 seconds for 100 workouts
- ✅ No memory warnings
- ✅ UI remains responsive
- ✅ All data intact

---

## Console Log Reference

### Success Logs

#### First Launch (Fresh Install)
```
No existing data file found. Starting fresh.
```

#### First Launch After Upgrade (Legacy Data)
```
Data file exists. Loading...
Successfully loaded [N] workouts using legacy format
Data will be automatically migrated to new format on next save
```

#### Subsequent Launches (After Migration)
```
Data file exists. Loading...
Successfully loaded [N] workouts using modern format
```

#### Successful Save
```
Data saved successfully. Total workouts: [N]
```

### Error Logs (Should NOT See These)

#### Load Errors
```
ERROR: Failed to read data file: [error details]
```
**Action**: Check file permissions, verify backup exists

```
ERROR: Could not decode data as array of DataObject
ERROR: Legacy decoding also failed
```
**Action**: Data may be corrupted, restore from backup

#### Save Errors
```
ERROR: Failed to save data: [error details]
```
**Action**: Check disk space, file permissions

---

## Error Handling Tests

### Scenario 7: Corrupted Data File

**Purpose**: Verify app handles corrupted data gracefully

**Steps**:
1. Install app with valid data
2. Close app
3. Manually corrupt the Data file:
   ```bash
   echo "corrupted" > [path-to-Documents]/Data
   ```
4. Launch app

**Expected Results**:
- ✅ App launches (doesn't crash)
- ✅ Alert shown: "Data Load Error"
- ✅ App starts with empty data
- ✅ User can add new workouts normally

### Scenario 8: Disk Space Test

**Purpose**: Verify handling of save failures

**Steps**:
1. Fill device storage (simulator: use large files)
2. Try to save a workout

**Expected Results**:
- ✅ Alert shown: "Save Error"
- ✅ App doesn't crash
- ✅ Can retry after freeing space

---

## Rollback Procedure

### If Migration Fails

**Emergency Rollback Steps**:

1. **Immediately close the new app version**
2. **Do NOT add any new workouts**
3. **Restore backup**:
   ```bash
   # Copy backed up Data file back to app container
   cp ~/Desktop/pushup-hero-backup-[date].data [app-container-path]/Documents/Data
   ```
4. **Reinstall old version (v1.0 build 2)**
5. **Launch and verify data**
6. **Report issue to developer**

### What to Include in Bug Report

If you encounter issues:
- [ ] Complete console log from launch
- [ ] Screenshots of the issue
- [ ] Number of workouts before migration
- [ ] Whether backup restore worked
- [ ] iOS version
- [ ] Device model

---

## Final Verification Checklist

Before approving for release:

### Data Integrity
- [ ] All workout counts match pre-migration values
- [ ] All dates are correct
- [ ] All notes are intact (including special characters)
- [ ] No duplicate entries
- [ ] No missing entries

### Functionality
- [ ] Can add new workouts
- [ ] Can view all workouts in table
- [ ] Today/Week/Month/Year counters work
- [ ] Midnight workflow still works
- [ ] App survives force close/relaunch
- [ ] Sounds play correctly
- [ ] UI responsive with full dataset

### Performance
- [ ] Load time acceptable (< 2 sec for 100 workouts)
- [ ] No memory warnings
- [ ] No console errors or warnings
- [ ] Smooth scrolling in table view

### Edge Cases
- [ ] Empty database scenario
- [ ] Single workout scenario
- [ ] Large dataset scenario (100+ workouts)
- [ ] Special characters in notes
- [ ] Very old dates (years ago)
- [ ] Future dates (if possible in old data)

---

## Known Issues & Limitations

### Expected Behavior
1. **First save after migration is slightly slower**: Normal - converting entire dataset
2. **Console shows "requiresSecureCoding = false"**: Intentional for backward compatibility
3. **Old version can't read new format**: Expected - one-way migration

### Not Issues
- Different console log format between versions
- Additional debug output in new version
- Slightly different save timing

---

## TestFlight Beta Testing Checklist

When distributing to beta testers:

### Before Distribution
- [ ] Update build number (current: 2 → new: 3)
- [ ] Update version string if desired (current: 1.0)
- [ ] Include migration guide in TestFlight notes
- [ ] Warn users to backup via iTunes/Finder

### Beta Tester Instructions
Send this to testers:

```
IMPORTANT: Before updating to this version:

1. Backup your device via iTunes/Finder
2. This update includes a data migration
3. All your workout data should transfer automatically
4. If you notice any missing workouts, IMMEDIATELY:
   - Take a screenshot
   - Contact support
   - Restore from backup if needed

Please report:
- Total workouts before and after update
- Any missing or incorrect data
- Any error messages
- App performance issues
```

---

## Automated Testing (Future)

For developers implementing UI tests:

### Suggested XCTest Cases
```swift
func testFreshInstallDataPersistence()
func testLegacyDataMigration()
func testMultipleSaveLoadCycles()
func testLargeDatasetPerformance()
func testCorruptedDataHandling()
func testSpecialCharactersInNotes()
```

### Performance Benchmarks
- Load time for 100 workouts: < 2 seconds
- Save time: < 0.5 seconds
- Memory usage: < 50MB for 1000 workouts

---

## Support Resources

### If Users Report Data Loss

1. **Request information**:
   - iOS version
   - Device model
   - Whether they backed up
   - Screenshots of console logs if possible

2. **Immediate actions**:
   - Advise not to add new workouts
   - Help restore from iTunes/iCloud backup
   - Collect crash logs if app crashes

3. **Investigation**:
   - Check if Data file exists
   - Check file size (empty file = data loss)
   - Review console logs for error patterns

### Developer Debug Tools

**Check file contents**:
```bash
# On simulator
plutil -p [path-to-Documents]/Data
# May not work for binary format, use:
xxd [path-to-Documents]/Data | head
```

**Monitor file changes**:
```bash
# Watch the Documents directory
fswatch -o [path-to-Documents] | xargs -n1 -I{} ls -lh [path-to-Documents]/Data
```

---

## Version Tracking

| Version | Build | Data Format | Notes |
|---------|-------|-------------|-------|
| 1.0 | 1-2 | NSCoding (legacy) | Original format |
| 1.0 | 3+ | NSSecureCoding | Phase 1 migration |
| TBD | TBD | CoreData | Phase 2 (future) |

**Data Version Field**:
- Version 0: Legacy data (no version field)
- Version 1: NSSecureCoding with version tracking

---

## Success Criteria

Migration is successful if:
1. ✅ 100% of existing workouts preserved
2. ✅ All data fields accurate (counts, dates, notes)
3. ✅ No crashes or errors during migration
4. ✅ Performance remains acceptable
5. ✅ New workouts save correctly after migration
6. ✅ Zero user reports of data loss

---

## Post-Release Monitoring

### Metrics to Track
- Crash rate on first launch after update
- User reports of data loss
- App Store review mentions of "data" or "lost"
- Support tickets related to workouts

### Red Flags
- Any reports of zero workouts after update
- Crash rate > 1% on app launch
- Multiple users reporting same error message

---

## Contact & Support

For issues with this migration:
- Developer: [Your contact info]
- GitHub Issues: [If applicable]
- Emergency contact: [If applicable]

---

**Document Version**: 1.0
**Created**: 2026-01-15
**Updated for**: Pushup Hero Phase 1 Data Migration
**Related Code**: DataObject.swift, ViewController.swift
