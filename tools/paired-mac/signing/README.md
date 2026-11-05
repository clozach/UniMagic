# Existing signing profiles

The native device builder selects the newest unexpired profile for the app, service, and (with `--keyboard`) keyboard identifiers, for an explicitly configured team, paired device and signing certificate. It reads Apple-signed cached profiles through `security cms`; it never signs in, requests provisioning, enrolls an account or changes cached profiles.

The paired device comes from `--device`, `UNIMAGIC_DEVICE_ID`, or private `native-device.json` under the keeper’s Application Support state. No device identifier is embedded in source. `--team`, `--bundle` and `--identity` let another operator select their own signing identity; current public team/certificate defaults preserve the existing PowWorm lane. App Groups are explicit via `--app-group` and validated against actual profiles. A missing private device choice fails before profile enumeration.

This replaces the two pinned profile UUIDs, which would keep selecting the expiring pair after a successful renewal. Profiles for other apps, teams, devices or certificates are ineligible. Equal expiry uses UUID ordering for deterministic selection. Missing valid profiles fail visibly.

Run `bash projects/iphone-agent-alerts/src/signing/tests/run.sh`. Device builds also validate selected identities, capabilities, device and expiry before signing. Renewing still requires the existing Apple account and an explicit provisioning build; keep original profiles and preserve the installed app’s data. The old keeper is a separate unsupported build lane and remains unloaded.

The canonical build-10 builder requires the keyboard profile. Managed renewal derives that requirement from its frozen release, so earlier app/service-only builds remain renewable without acquiring a new extension. Run `node --no-warnings --test projects/iphone-agent-alerts/src/keeper/*.test.mjs` for extension inventory, restoration, expiry and re-signing regressions. The supported renewal implementation is [keeper/provision.mjs](../keeper/provision.mjs), under its maintenance lock.
