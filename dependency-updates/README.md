# Central dependency updates

The organization `.github` repository owns dependency-update orchestration.
Target repositories contain dependency declarations and consistency tests, but no updater script.

The scheduled workflow reads `targets.json`, checks out each repository, and invokes the update
engine published by `AtlassianPS.Standards`.
It creates or refreshes `automation/update-powershell-dependencies` when files change.
The controller and workflow contract are validated by the repository's `CI` workflow.

## GitHub App

The workflow reuses the organization-wide AtlassianPS Release Bot instead of maintaining a second
automation identity.
Give the App access only to this controller and the repositories in `targets.json`.
It needs these repository permissions:

- Contents: read and write
- Issues: read and write
- Pull requests: read and write
- Workflows: read and write

Expose its Client ID as an organization variable and its private key as an organization secret,
including access from this repository:

- `ATLASSIANPS_RELEASE_APP_CLIENT_ID`
- `ATLASSIANPS_RELEASE_APP_PRIVATE_KEY`

The workflow requests a short-lived token for one target repository at a time.

## Manual runs

Run **PowerShell dependency updates** from the Actions page.
Use `all` to process every configured repository or provide one repository name from `targets.json`.
Scheduled runs preserve dependency major versions; manual runs can explicitly allow major upgrades.
