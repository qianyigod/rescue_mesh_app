# Satellite Relay Reserved Interface Design

**Goal:** Reserve a satellite relay transport interface for future Beidou short-message integration without changing current BLE and network behavior.

## Scope

- Add a service-layer transport abstraction for satellite relay.
- Provide a default no-op implementation that reports the transport as reserved but not implemented.
- Invoke the satellite transport from the existing SOS trigger flow.
- Keep BLE broadcast and network sync semantics unchanged.

## Design

`SosTriggerService` remains the SOS orchestration layer. A new `SatelliteRelayService` abstraction is introduced as a third transport channel alongside BLE broadcast and network sync.

The default implementation is `NoopSatelliteRelayService`. It accepts a typed request, does not perform any hardware or network work, and returns a structured result indicating that the interface is reserved and currently inactive. This keeps the future integration seam explicit without adding runtime risk.

`SosTriggerResult` will carry the satellite relay outcome so future UI or telemetry can inspect it without changing the service contract again.

## Error Handling

- No-op satellite execution must never break SOS triggering.
- Satellite failures must be isolated from BLE and network failures.
- Existing BLE and network error reporting remains unchanged.

## Testing

- Verify the default no-op implementation is called from `SosTriggerService`.
- Verify SOS succeeds when the satellite transport reports "reserved".
- Verify SOS still succeeds when the satellite transport throws.
