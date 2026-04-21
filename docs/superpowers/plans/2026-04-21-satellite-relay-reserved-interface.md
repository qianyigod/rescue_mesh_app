# Satellite Relay Reserved Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reserved satellite relay service interface with a default no-op implementation and wire it into the SOS trigger flow.

**Architecture:** Keep `SosTriggerService` as the orchestration layer and add a new `SatelliteRelayService` abstraction as a third transport channel. The default implementation returns a structured "reserved/not implemented" result so future Beidou integration can swap implementations without changing the trigger flow again.

**Tech Stack:** Flutter, Dart, Drift, flutter_test

---

### Task 1: Add transport integration tests first

**Files:**
- Create: `test/sos_trigger_service_test.dart`
- Modify: `lib/services/sos_trigger_service.dart`
- Modify: `lib/services/satellite_relay_service.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('triggerSos records reserved satellite relay result without affecting success', () async {
  // Build fake dependencies, trigger SOS, expect a reserved satellite result.
});

test('triggerSos isolates satellite relay exceptions from BLE and network paths', () async {
  // Build a throwing satellite service, trigger SOS, expect result contains satellite error.
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter.bat test test\\sos_trigger_service_test.dart`
Expected: FAIL because `SatelliteRelayService`, related result fields, or injection points do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
abstract class SatelliteRelayService {
  Future<SatelliteRelayResult> relaySos(SatelliteRelayRequest request);
}

class NoopSatelliteRelayService implements SatelliteRelayService {
  @override
  Future<SatelliteRelayResult> relaySos(SatelliteRelayRequest request) async {
    return const SatelliteRelayResult.reserved();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter.bat test test\\sos_trigger_service_test.dart`
Expected: PASS

### Task 2: Wire the transport into SOS orchestration

**Files:**
- Create: `lib/services/satellite_relay_service.dart`
- Modify: `lib/services/sos_trigger_service.dart`

- [ ] **Step 1: Extend the SOS result contract**

```dart
class SosTriggerResult {
  final SatelliteRelayResult satelliteRelayResult;
}
```

- [ ] **Step 2: Inject the satellite transport**

```dart
SosTriggerService({
  SatelliteRelayService? satelliteRelayServiceOverride,
}) : _satelliteRelayService =
         satelliteRelayServiceOverride ?? satelliteRelayService;
```

- [ ] **Step 3: Call the transport with failure isolation**

```dart
try {
  satelliteRelayResult = await _satelliteRelayService.relaySos(request);
} catch (error) {
  satelliteRelayResult = SatelliteRelayResult.failed('$error');
}
```

- [ ] **Step 4: Re-run focused tests**

Run: `flutter.bat test test\\sos_trigger_service_test.dart`
Expected: PASS with both reserved and failure-isolated cases covered.

### Task 3: Run regression checks

**Files:**
- Test: `test/network_sync_service_test.dart`
- Test: `test/ble_mesh_service_test.dart`
- Test: `test/sos_trigger_service_test.dart`

- [ ] **Step 1: Run focused regression tests**

Run: `flutter.bat test test\\sos_trigger_service_test.dart test\\network_sync_service_test.dart test\\ble_mesh_service_test.dart`
Expected: PASS

- [ ] **Step 2: Review for scope discipline**

Confirm that no UI, native channel, or database schema changes were introduced.
