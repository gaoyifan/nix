# macOS authorization options for Find My source

## Findings

- Apple documents Full Disk Access as a user-granted privacy setting. An app cannot obtain it through an entitlement or code. The user must add the app in System Settings. [Apple, Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- A persistent per-user process should normally be packaged as a launch agent managed by `SMAppService`. Apple describes `SMAppService` as managing login items, launch agents, and launch daemons whose helper executables live inside the app bundle. [Apple, SMAppService](https://developer.apple.com/documentation/ServiceManagement/SMAppService)
- Apple’s code-signing model gives a stable code identity through the signing requirement and bundle identifier. This makes a signed app bundle a more durable Full Disk Access subject than a changing executable under a Nix store path. [Apple, TN3127 Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- A launch agent runs once per logged-in user. A launch daemon runs system-wide as root. Apple notes that launch daemons cannot initiate connections to user processes, which makes a daemon a poor fit for Find My’s user-session caches. [Apple, XPC overview](https://developer.apple.com/documentation/XPC)
- `SMJobBless` and `AuthorizationExecuteWithPrivileges` are privileged-helper mechanisms for root operations. Apple marks both older APIs as deprecated and directs developers to `SMAppService` or launchd-launched helpers. Root privileges do not substitute for the user-granted TCC permission needed to access protected user data. [Apple, SMJobBless](https://developer.apple.com/documentation/servicemanagement/smjobbless%28_%3A_%3A_%3A_%3A%29), [Apple, AuthorizationExecuteWithPrivileges](https://developer.apple.com/documentation/security/authorizationexecutewithprivileges)
- Apple recommends XPC services or launch agents for long-lived app-related work instead of manually spawned processes. XPC can isolate a helper, but it does not automatically grant Full Disk Access. [Apple, Managing ongoing background processes](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)

## Implication for this project

A signed app bundle gives the Find My worker a dedicated identity for Full Disk Access. Home Manager can register its user LaunchAgent directly and the worker owns the 240-second Find My refresh loop. This uses the logged-in user's TCC authorization.

The original deployment borrowed Terminal's Full Disk Access. During the direct-launch test, macOS attributed the worker to the bundle only after the Python executable itself was installed inside it. Re-signing the ad-hoc bundle with a different code identity required renewing Full Disk Access.
