# SafariAdBlock

[English](README.md) · **한국어** · [日本語](README.ja.md) · [中文（简体）](README.zh-Hans.md)

Safari용 광고 차단 확장 모음입니다. Safari의 네이티브 **콘텐츠 차단기(Content Blocker)** 방식이라 빠르고, 페이지 내용을 읽는 권한이 필요 없습니다. EasyList·EasyPrivacy와 한국 목록(List-KR, YousList)을 Safari 규칙으로 변환해 씁니다.

| 확장 | 출처 | 하는 일 |
|---|---|---|
| **광고 차단** | EasyList + `filters/custom.txt`(내 규칙) | 배너·팝업·광고 스크립트 차단, 광고 자리 숨김 |
| **추적 차단** | EasyPrivacy | 분석·추적 스크립트와 비콘 차단 |
| **한국 사이트 광고 차단** | List-KR(filterslist-KO) + YousList | 네이버·다음 등 국내 사이트 전용 규칙 |
| **동영상 광고 건너뛰기** | `WebExtension/` (Safari 웹 확장) | 영상 재생 전·중간 광고가 시작되지 않게 막고, 그래도 나오는 광고는 즉시 건너뛰며, 광고 차단 경고 창을 닫음 |

네 확장은 Safari 설정에서 각각 켜고 끌 수 있습니다. 앞의 셋은 콘텐츠 차단기(URL·CSS 규칙만, 페이지 안에서 코드 실행 없음)이고, 마지막은 동영상 사이트 페이지 안에서 스크립트를 실행하는 웹 확장입니다. 컨테이너 앱(SafariAdBlock.app)은 각 확장의 상태 표시, Safari 설정 열기, 규칙 새로고침을 담당합니다. 앱과 확장 이름은 한국어·영어·일본어·중국어(간체)로 제공됩니다.

## 빌드 / 설치

Xcode 없이 Command Line Tools만으로 빌드됩니다 (macOS 13 이상, Apple Silicon·Intel 공용 바이너리).

```bash
./install.sh     # 빌드 → /Applications/SafariAdBlock.app 설치 → 확장 등록 → 실행
```

빌드만 하려면 `./build.sh` (결과물: `build/SafariAdBlock.app`). 처음 빌드할 때는 필터 목록을 내려받아 변환하므로 네트워크가 필요합니다 (`rules/`는 리포에 포함하지 않습니다).

설치 후 **Safari › 설정 › 확장 프로그램**에서 `광고 차단`, `추적 차단`, `한국 사이트 광고 차단`, `동영상 광고 건너뛰기`를 켭니다. 앱의 **Safari에서 설정** 버튼을 누르면 해당 화면이 바로 열립니다. `동영상 광고 건너뛰기`는 켠 뒤 처음 동영상 사이트를 열 때 Safari가 사이트 접근 허용을 묻는데 **항상 허용**을 고르세요.

### 서명

`build.sh`는 키체인에서 **Apple Development** → Developer ID → (없으면) ad hoc 순으로 서명 인증서를 고릅니다. `CODESIGN_IDENTITY="..."` 환경변수로 직접 지정할 수도 있습니다.

- Apple 인증서로 서명하면 Safari가 확장을 바로 인식합니다. 무료 Apple ID로도 됩니다. Xcode › Settings › Accounts에 Apple ID를 추가하고 **Manage Certificates › + › Apple Development**로 인증서를 한 번 만들어 두면 됩니다.
- ad hoc 서명일 때는 Safari에서 매번 허용해야 합니다. Safari › 설정 › 고급 › **웹 개발자용 기능 보기**를 켠 뒤, **개발자용 › 개발자 설정… › 서명되지 않은 확장 프로그램 허용**. Safari를 종료하면 초기화됩니다.

#### codesign이 키체인 비밀번호를 여러 번 묻는 이유

Apple Development 인증서의 개인 키는 로그인 키체인에 있고, `codesign`이 그 키를 쓸 때마다 macOS가 허용 여부를 묻습니다. 빌드 한 번에 앱 1개와 확장 4개를 서명하므로 최대 다섯 번 뜹니다. 한 번만 **항상 허용**을 누르면 그 뒤로는 묻지 않습니다. 대화 상자 대신 터미널에서 처리하려면 (로그인 키체인 비밀번호를 물어봅니다):

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

### 여러 Mac에 설치하기

```bash
git clone https://github.com/coldnuclearfusion/SafariAdBlock.git
cd SafariAdBlock && ./install.sh
```

첫 빌드에서 필터 목록을 내려받습니다. 그 Mac에 Apple Development 인증서가 없으면 ad hoc 서명이 되므로 위의 서명 항목을 참고하세요.

## 언어

앱 UI는 한국어·영어·일본어·중국어(간체)를 지원합니다. 기본값은 시스템 언어를 따르며, 앱 오른쪽 위의 **언어** 메뉴에서 바꾸면 즉시 적용되고 선택이 기억됩니다. 그 밖의 언어는 영어로 표시됩니다.

Safari 설정 화면에 표시되는 확장 이름(그리고 Finder의 앱 이름)은 번들의 `InfoPlist.strings`와 웹 확장의 `_locales`에서 오므로, 앱의 언어 메뉴와 무관하게 항상 **시스템** 언어를 따릅니다.

문자열을 추가하거나 고치려면 `Resources/App/Localizations/<code>.json`을 편집합니다 (네 파일의 키가 같아야 하며 `build.sh`가 검사합니다). 웹 확장의 이름과 설명은 `WebExtension/_locales/<code>/messages.json`에 있습니다.

## 사용

- **특정 사이트에서만 끄기**: 그 사이트를 연 상태에서 Safari 메뉴 › **(사이트)에 대한 설정…** › **콘텐츠 차단기 활성화** 체크 해제. Safari가 사이트별로 기억합니다.
- **언어 바꾸기**: 앱 오른쪽 위의 언어 메뉴 (시스템 설정 따르기 / 한국어 / English / 日本語 / 中文).
- **차단 목록 갱신** (EasyList 등은 며칠마다 갱신됩니다):
  ```bash
  ./update-rules.sh && ./install.sh
  ```
- **내 규칙 추가**: `filters/custom.txt`에 EasyList 문법으로 적고 `SKIP_DOWNLOAD=1 ./update-rules.sh && ./install.sh`. 파일 머리에 문법 예가 있습니다.
- **규칙이 반영되지 않을 때**: 앱에서 **규칙 다시 불러오기**. 그래도 안 되면 Safari에서 확장을 껐다 켜세요.

## 문제 해결

- **켰는데 광고가 그대로 보일 때**: 콘텐츠 차단기는 새로 불러오는 페이지부터 적용됩니다. 이미 열려 있던 탭은 새로 고침(⌘R)하세요. 한 페이지 안에서 화면만 바꾸는 동영상 사이트는 탭을 닫고 다시 여는 것이 확실합니다.
- **실제로 적용되는지 확인**: 앱의 **동작 확인** 버튼이 공개 테스트 사이트(https://adblock-tester.com)를 Safari로 엽니다. 점수가 높게 나오면 규칙이 살아 있는 것입니다. (로컬 파일로 만든 검사 페이지는 Safari가 사이트별 콘텐츠 차단기 설정을 적용하지 않아 쓸 수 없습니다.)
- **영상 광고(재생 전·중간)는 콘텐츠 차단기로는 못 막습니다.** 그래서 `동영상 광고 건너뛰기` 웹 확장이 따로 있고, 두 겹으로 동작합니다.
  - `WebExtension/main.js` (메인 월드, Safari 16.4 이상): 플레이어 응답에서 광고 항목을 지워 광고가 아예 시작되지 않게 합니다. 페이지에 박힌 `ytInitialPlayerResponse`와, 페이지 안 이동 때 `JSON.parse`·`Response.json`으로 파싱되는 모든 응답이 대상입니다. 지연이 없습니다. 같은 응답에 실려 오는 YouTube의 광고 차단기 경고도 함께 지웁니다. 그 경고가 영상을 일시정지시켜 시작 화면에서 멈춘 채 두기 때문입니다.
  - `WebExtension/content.js` (격리 월드): 그래도 광고가 나오면(서버 삽입형 등) 건너뛰기 버튼을 누르거나 광고 영상을 끝으로 돌립니다. 이 경로는 광고를 한 번 로드했다 끝내는 방식이라 1~3초 지연이 남습니다. 경고 대화상자가 그래도 뜨면 나타나는 즉시 지우고 재생을 이어 줍니다. 진단 기록은 콘솔과 페이지 `<html>` 요소의 `data-sab-log`에 남습니다.
  - 사이트가 응답 구조나 화면 구조를 바꾸면 한동안 안 될 수 있으니 그때는 키 이름·선택자를 손봐야 합니다.
- **콘텐츠 차단기가 영상 광고를 못 막는 이유.** 광고가 영상과 같은 서버에서 같은 방식으로 오고, 광고 여부가 플레이어 응답 안에서만 정해지기 때문에 URL 기준으로 거르는 콘텐츠 차단기로는 구분할 수 없습니다. Safari용 유료 차단기들도 마찬가지입니다. 홈·검색·재생 페이지의 광고 카드와 배너는 숨깁니다 (`filters/custom.txt`의 동영상 사이트 항목).
- **Safari 프로필 (흔한 원인)**: 탭 막대 왼쪽에 프로필 아이콘이 보이면 프로필을 쓰는 것입니다. 확장과 콘텐츠 차단기는 프로필마다 따로 켜야 하고, 설정 › 확장 프로그램 화면의 스위치는 기본(개인) 프로필에만 적용됩니다. Safari › 설정 › **프로필** › 해당 프로필 › **확장 프로그램** 탭에서 켜세요. 앱이 보여 주는 ‘켜짐’ 상태도 기본 프로필 기준입니다.
- **사이트별 기본값**: Safari › 설정 › 웹 사이트 › 콘텐츠 차단기 › **다른 웹 사이트를 방문할 때**가 ‘끔’이면 확장을 켜도 아무 데서도 동작하지 않습니다. ‘켬’으로 두세요.
- **사생활 보호 브라우징 창**: Safari 17 이상은 확장을 사생활 보호 창에서 따로 허용해야 합니다. Safari › 설정 › 확장 프로그램 › 각 항목 › **사생활 보호 브라우징에서 허용**.
- **Safari가 규칙 재로드에 응답하지 않을 때**: `규칙 다시 불러오기`는 20초 뒤에 시간 초과로 끝납니다. macOS 26에서 Safari가 완료 콜백을 주지 않는 경우가 있는데, 규칙 자체는 이미 다시 가져간 상태입니다 (확장 프로세스가 실행된 것이 시스템 로그에 남습니다).
- **로그 보기**: `/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jhunos.SafariAdBlock"'` — 확장 인식 여부와 재로드 결과가 남습니다. (zsh에서는 `log`가 내장 명령이라 전체 경로가 필요합니다.)
- **확장이 켜져 있는데 아무것도 안 될 때 (개발 시)**: 확장 바이너리에 **AppKit이 링크되어 있어야** 합니다. Foundation만 링크하면 확장 프로세스는 뜨지만 요청이 핸들러까지 오지 않고, Safari는 2분 뒤 `SFErrorDomain Code=3`(loading interrupted)로 포기합니다. 시스템 로그에 `misconfigured plugin; external subsystem [NSSharingService_Subsystem] not present` 폴트가 남습니다. `build.sh`는 이미 `-framework AppKit`을 넣습니다.

## 동작 원리

```
filters/sources/*.txt ─▶ tools/convert.py ─▶ rules/<확장>.json ─▶ <확장>.appex/blockerList.json ─▶ Safari
   (EasyList 문법)          (Safari 규칙으로 변환)     (tools/validate로 WebKit 검증)
```

- `tools/convert.py` — EasyList(ABP) 문법을 Safari 규칙(JSON)으로 바꿉니다. `||도메인^`, 앵커, 와일드카드, `$third-party`, `$domain=`, 리소스 타입, `@@` 예외, `##` 요소 숨김(도메인별·전역·예외)을 지원하고, Safari로 표현할 수 없는 것(정규식 규칙, `$redirect`/`$csp` 같은 확장 옵션, uBO 전용 의사 클래스 등)은 건너뜁니다. 규칙 순서는 차단 → 요소 숨김 → 예외입니다.
- `tools/validate` — Safari와 같은 WebKit 컴파일러로 결과를 검증합니다. 컴파일 실패 규칙은 이분 탐색으로 찾아 뺍니다. WebKit은 잘못된 CSS 선택자를 오류 없이 조용히 버리기 때문에(합쳐진 선택자 묶음이 통째로 사라짐), 선택자는 `querySelector`로 하나씩 미리 걸러냅니다.
- `tools/smoke-test` — 변환된 광고 규칙을 WKWebView에 적용해 광고 스크립트·이미지가 실제로 막히고 광고 요소가 숨겨지는지 확인합니다 (`update-rules.sh` 끝에서 자동 실행).
- Safari 콘텐츠 차단기 하나당 규칙 15만 개 제한이 있어서 목록을 확장 3개로 나눴습니다.
- 콘텐츠 차단기 3개는 같은 소스(`Sources/ContentBlocker`)를 공유하고 규칙 파일만 다릅니다.

## 구조

```
Sources/App/               컨테이너 앱 (SwiftUI): 상태 표시, Safari 설정 열기, 규칙 새로고침, 언어 메뉴
Sources/ContentBlocker/    콘텐츠 차단 확장 진입점 (세 확장 공용)
Sources/WebExtension/      동영상 광고 건너뛰기 웹 확장의 네이티브 쪽 (최소 구현)
WebExtension/              manifest.json, main.js(응답에서 광고 제거), content.js(건너뛰기), content.css, _locales/(언어별 이름·설명)
Resources/                 Info.plist, entitlements, 앱 아이콘, Localizations/<code>.json 문자열 표
filters/custom.txt         내 규칙 (광고 차단 목록에 포함)
filters/sources/           내려받은 원본 목록 (update-rules.sh가 채움)
rules/                     변환된 Safari 규칙 JSON + 메타 정보 (빌드 때 생성, 리포에 미포함)
tools/convert.py           변환기
tools/validate.swift       WebKit 검증 도구
tools/smoke-test.swift     변환 결과를 WKWebView에 적용해 실제 차단 여부 확인
tools/make-icon.swift      앱 아이콘 생성
build.sh / install.sh / update-rules.sh
```

## 프라이버시

이 앱과 확장은 네트워크 요청을 하지 않고 어떤 데이터도 수집·전송하지 않습니다. 필터 목록은 `update-rules.sh`를 직접 실행할 때만 내려받습니다. 콘텐츠 차단기는 규칙 목록을 Safari에 넘길 뿐 페이지 내용을 볼 수 없고, `동영상 광고 건너뛰기`는 manifest에 적힌 동영상 사이트에서만 실행되며 그 안에서만 동작합니다. 코드는 전부 이 리포에 있습니다.

## 라이선스와 면책

- 이 리포의 코드는 [MIT](LICENSE)입니다.
- 필터 목록은 리포에 포함하지 않고 빌드할 때 내려받습니다. 각 목록의 라이선스는 다음과 같습니다.
  - [EasyList](https://easylist.to), [EasyPrivacy](https://easylist.to) — GPLv3 / CC BY-SA 3.0 ([라이선스](https://easylist.to/pages/licence.html))
  - [List-KR](https://github.com/List-KR/List-KR) (AdGuard 배포본 filterslist-KO) — GPLv3
  - [YousList](https://github.com/yous/YousList) — CC BY-SA 4.0
- 광고를 건너뛰는 것은 해당 동영상 사이트의 이용약관에 어긋날 수 있습니다. 사용에 따른 책임은 사용자에게 있으며, 이 소프트웨어는 어떤 보증도 없이 제공됩니다.
