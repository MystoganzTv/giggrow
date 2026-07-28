# GigGrow architecture decisions

## Local-first data

GigGrow is local-first. SwiftData remains the on-device source of truth so
logging a shift, scanning a screenshot, and reviewing tax information never
depend on a network connection.

For the iOS V1:

- Private iCloud/CloudKit sync protects and synchronizes the SwiftData store
  through the Apple ID already signed into the device.
- A complete, portable GigGrow backup can be exported and restored by the
  driver. CSV exports remain available for spreadsheets and accountants, but
  they are not a full backup.
- There is no GigGrow password or sign-in screen.
- Screenshot OCR stays on-device with Apple Vision.

The CloudKit container is `iCloud.com.giggrow.app`. Its production schema was
first deployed on July 28, 2026 with all eight SwiftData record types. Future
SwiftData schema changes must be exercised in a Development build and then
deployed from CloudKit Console before the corresponding TestFlight/App Store
build is released.

CloudKit doesn't support SwiftData uniqueness constraints. Platform-account
names are therefore deduplicated by GigGrow after imports, with earnings moved
to the surviving account before the duplicate is deleted.

This is a privacy and product decision, not a permanent platform limitation.

## Accounts later

GigGrow is intended to reach Android and the web later. At that point, an
independent account and backend become useful because iCloud cannot synchronize
those platforms.

The likely future direction is:

- Sign in with Apple as the primary iOS account option.
- Google sign-in as an additional cross-platform option.
- A relational backend such as Postgres/Supabase for shared iOS, Android, and
  web data.

Do not add a login merely to make the app look complete. Introduce it when the
cross-platform backend exists and includes account deletion, migration from
iCloud/local data, conflict handling, and a documented privacy model.

## When a server is justified

A server is justified when GigGrow adds one or more of:

- Android or web synchronization.
- Server-side AI processing. API secrets must never ship inside the app.
- Uber/Lyft or aggregator connections such as Argyle.
- Anonymous benchmarks across drivers.
- Shared/team data.
- Subscription or entitlement behavior that cannot be handled by StoreKit.

Until then, financial, vehicle, mileage, and profile data should remain local
and in the user's private iCloud database.
