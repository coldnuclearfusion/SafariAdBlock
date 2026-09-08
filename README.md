# SafariAdBlock

An ad-blocking extension set for Safari. It uses Safari's native **content blocker** mechanism, so it is fast and needs no permission to read page contents. EasyList, EasyPrivacy and Korean lists (List-KR, YousList) are converted into Safari rules.

| Extension | Source | What it does |
|---|---|---|
| **Ad Blocking** | EasyList + `filters/custom.txt` (your own rules) | Blocks banners, pop-ups and ad scripts; hides ad placeholders |
| **Tracker Blocking** | EasyPrivacy | Blocks analytics and tracking scripts and beacons |
| **Korean Sites Ad Blocking** | List-KR (filterslist-KO) + YousList | Rules specific to Korean sites such as Naver and Daum |
| **Video Ad Skipper** | `WebExtension/` (Safari web extension) | Keeps pre-roll and mid-roll video ads from starting, skips any that still appear, dismisses ad-blocker warnings |

Each of the four can be turned on and off separately in Safari settings. The first three are content blockers (URL and CSS rules only, no code runs in pages); the fourth is a web extension that runs a script inside the video site's pages. The container app (SafariAdBlock.app) shows the status of each extension, opens Safari settings and reloads the rules.

## Build and install

Builds with the Command Line Tools alone, no Xcode needed (macOS 13 or later; universal binary for Apple Silicon and Intel).

```bash
./install.sh     # build → install to /Applications/SafariAdBlock.app → register the extensions → launch
```

To build only, run `./build.sh` (output: `build/SafariAdBlock.app`). The first build downloads and converts the filter lists, so it needs network access (`rules/` is not part of the repository).

After installing, turn on `Ad Blocking`, `Tracker Blocking`, `Korean Sites Ad Blocking` and `Video Ad Skipper` in **Safari › Settings › Extensions**. The app's **Set Up in Safari** button opens that screen. The first time you open the video site after enabling `Video Ad Skipper`, Safari asks for site access; choose **Always Allow**.

### Signing

`build.sh` picks a signing certificate from the keychain in this order: **Apple Development** → Developer ID → ad hoc if none is found. You can also set `CODESIGN_IDENTITY="..."` explicitly.

- With an Apple certificate, Safari recognizes the extensions right away. A free Apple ID is enough: add it in Xcode › Settings › Accounts and create a certificate once with **Manage Certificates › + › Apple Development**.
- With an ad hoc signature, Safari must be told to allow the extensions every time: Safari › Settings › Advanced › **Show features for web developers**, then **Develop › Developer Settings… › Allow unsigned extensions**. Safari resets this when it quits.

#### Why codesign asks for the keychain password several times

The private key of the Apple Development certificate lives in the login keychain, and macOS asks for permission each time `codesign` uses it. One build signs the app plus four extensions, so up to five prompts appear. Click **Always Allow** once and it stops asking. To do the same from the terminal (it prompts for the login keychain password):

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

### Installing on another Mac

```bash
git clone https://github.com/coldnuclearfusion/SafariAdBlock.git
cd SafariAdBlock && ./install.sh
```

The first build downloads the filter lists. If that Mac has no Apple Development certificate, the build is signed ad hoc; see the signing section above.

## Usage

- **Turn blocking off for one site**: open the site, then Safari menu › **Settings for <site>…** › uncheck **Enable content blockers**. Safari remembers it per site.
- **Update the block lists** (EasyList and friends update every few days):
  ```bash
  ./update-rules.sh && ./install.sh
  ```
- **Add your own rules**: write them in EasyList syntax in `filters/custom.txt`, then `SKIP_DOWNLOAD=1 ./update-rules.sh && ./install.sh`. The file starts with syntax examples.
- **Rules not applied**: click **Reload Rules** in the app. If that does not help, turn the extension off and on again in Safari.

## Troubleshooting

- **Ads still show after enabling**: content blockers apply to pages loaded from then on. Reload tabs that were already open (⌘R). For video sites that swap views inside one page, closing and reopening the tab is the sure way.
- **Confirm it is active**: the app's **Check It Works** button opens a public test site (https://adblock-tester.com) in Safari. A high score means the rules are live. (A test page served from a local file cannot be used: Safari does not apply per-site content blocker settings to it.)
- **Video ads (pre-roll and mid-roll) cannot be blocked by content blockers.** That is why the `Video Ad Skipper` web extension exists, with two layers:
  - `WebExtension/main.js` (main world, Safari 16.4 or later): removes the ad entries from the player response (`/youtubei/v1/player` and the `ytInitialPlayerResponse` embedded in the page) so ads never start. No delay.
  - `WebExtension/content.js` (isolated world): if an ad still appears (server-side inserted ads, for example), clicks the skip button or seeks to the end of the ad. This path loads the ad first and then ends it, so a delay of one to three seconds remains.
  - When the site changes its response or page structure it may stop working for a while; adjust the key names and selectors then.
- **Why content blockers cannot block video ads.** The ads come from the same servers in the same way as the video itself, and whether something is an ad is only decided inside the player response, so a URL-based content blocker cannot tell them apart. This is true of paid Safari blockers as well. Ad cards and banners on the home, search and watch pages are hidden (the video-site section of `filters/custom.txt`).
- **Safari profiles (a common cause)**: a profile icon at the left of the tab bar means profiles are in use. Extensions and content blockers are enabled per profile, and the switches in Settings › Extensions apply only to the default (personal) profile. Turn the items on in Safari › Settings › **Profiles** › the profile › **Extensions** tab. The ‘On’ state shown by the app also refers to the default profile.
- **Per-site default**: if Safari › Settings › Websites › Content Blockers › **When visiting other websites** is ‘Off’, nothing is blocked anywhere even with the extensions on. Keep it ‘On’.
- **Private Browsing windows**: Safari 17 and later require extensions to be allowed separately for Private Browsing: Safari › Settings › Extensions › each item › **Allow in Private Browsing**.
- **Safari does not respond to a rule reload**: `Reload Rules` times out after 20 seconds. On macOS 26 Safari sometimes never calls the completion handler, but the rules have already been fetched again (the system log shows the extension processes being launched).
- **Logs**: `/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jhunos.SafariAdBlock"'` shows whether Safari recognizes the extensions and the result of each reload. (In zsh, `log` is a builtin, hence the full path.)
- **Extension enabled but nothing happens (when developing)**: the extension binary must **link AppKit**. With Foundation only, the extension process starts but the request never reaches the handler, and Safari gives up after two minutes with `SFErrorDomain Code=3` (loading interrupted). The system log shows a `misconfigured plugin; external subsystem [NSSharingService_Subsystem] not present` fault. `build.sh` already passes `-framework AppKit`.

## How it works

```
filters/sources/*.txt ─▶ tools/convert.py ─▶ rules/<ext>.json ─▶ <ext>.appex/blockerList.json ─▶ Safari
   (EasyList syntax)      (converts to Safari rules)   (validated with WebKit by tools/validate)
```

- `tools/convert.py` — converts EasyList (ABP) syntax into Safari rules (JSON). Supports `||domain^`, anchors, wildcards, `$third-party`, `$domain=`, resource types, `@@` exceptions and `##` element hiding (per-domain, global and exceptions); skips what Safari cannot express (regex rules, extended options such as `$redirect`/`$csp`, uBO-only pseudo-classes and so on). Rule order is block → element hiding → exceptions.
- `tools/validate` — validates the result with the same WebKit compiler Safari uses. Rules that fail to compile are found by bisection and dropped. Because WebKit silently discards invalid CSS selectors (taking the whole merged selector group with them), selectors are pre-checked one by one with `querySelector`.
- `tools/smoke-test` — applies the converted ad rules in a WKWebView and checks that ad scripts and images are actually blocked and ad elements hidden (run automatically at the end of `update-rules.sh`).
- Safari allows 150,000 rules per content blocker, so the lists are split across three extensions.
- The three content blockers share one source file (`Sources/ContentBlocker`) and differ only in their rule file.

## Layout

```
Sources/App/               container app (SwiftUI): status, open Safari settings, reload rules
Sources/ContentBlocker/    content blocker entry point (shared by the three blockers)
Sources/WebExtension/      native side of the Video Ad Skipper web extension (minimal)
WebExtension/              manifest.json, main.js (strips ads from responses), content.js (skipper), content.css
Resources/                 Info.plist files, entitlements, app icon
filters/custom.txt         your own rules (included in the Ad Blocking list)
filters/sources/           downloaded source lists (filled by update-rules.sh)
rules/                     converted Safari rules (JSON) plus meta information (generated at build time, not in the repo)
tools/convert.py           converter
tools/validate.swift       WebKit validator
tools/smoke-test.swift     applies the result in a WKWebView to verify real blocking
tools/make-icon.swift      app icon generator
build.sh / install.sh / update-rules.sh
```

## Privacy

The app and the extensions make no network requests and collect or send no data. Filter lists are downloaded only when you run `update-rules.sh` yourself. The content blockers hand a rule list to Safari and cannot see page contents; `Video Ad Skipper` runs only on the video site listed in its manifest and acts only there. All of the code is in this repository.

## License and disclaimer

- The code in this repository is [MIT](LICENSE).
- The filter lists are not part of the repository; they are downloaded at build time. Their licenses:
  - [EasyList](https://easylist.to), [EasyPrivacy](https://easylist.to) — GPLv3 / CC BY-SA 3.0 ([license](https://easylist.to/pages/licence.html))
  - [List-KR](https://github.com/List-KR/List-KR) (filterslist-KO as distributed by AdGuard) — GPLv3
  - [YousList](https://github.com/yous/YousList) — CC BY-SA 4.0
- Skipping ads may violate the terms of service of the video site. You use this software at your own risk, and it is provided without any warranty.
