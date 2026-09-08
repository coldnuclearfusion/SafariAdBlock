#!/usr/bin/env python3
"""Converts EasyList (ABP) filter lists into Safari content blocker rules (JSON).

Usage:
  convert.py --name "Ad Blocking" --out rules/Ads.json --meta rules/Ads.meta.json \
             [--validator tools/validate] filters/custom.txt filters/sources/easylist.txt …

Converted:
  network rules     ||domain^   |anchor|   * wildcard   ^ separator   @@ exceptions
                    options: third-party / ~third-party, domain=, resource types, match-case, document (exceptions only)
  element hiding    ##selector   domain##selector   ~domain##selector   domain#@#selector (exception)
Skipped (cannot be expressed in Safari's rule syntax):
  regex rules (/…/), extended options such as $redirect $csp $removeparam $important, extended syntax such as #?# #$# #%#,
  uBO-only pseudo-classes (:has-text etc.), non-ASCII patterns, rules mixing if-domain and unless-domain

Rule order: [block] [element hiding] [exceptions (ignore-previous-rules)] — Safari exceptions only cancel earlier rules.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict

MAX_RULES = 150000          # Safari's limit per content blocker
SELECTOR_CHUNK = 250        # selectors merged into one css-display-none rule

# ABP resource type → Safari resource-type
TYPE_MAP = {
    'script': 'script', 'image': 'image', 'stylesheet': 'style-sheet', 'css': 'style-sheet',
    'font': 'font', 'media': 'media', 'subdocument': 'document', 'frame': 'document',
    'xmlhttprequest': 'fetch', 'xhr': 'fetch', 'websocket': 'websocket',
    'ping': 'ping', 'beacon': 'ping', 'other': 'other', 'object': 'other', 'popup': 'popup',
}
# Types an ABP rule applies to by default when none is given (excludes document and popup). Used for ~type negation.
DEFAULT_TYPES = ['document', 'fetch', 'font', 'image', 'media', 'other', 'ping', 'script', 'style-sheet', 'websocket']

# uBO/ABP extended pseudo-classes Safari does not understand. A selector containing any of them is skipped.
UNSUPPORTED_SELECTOR = (
    ':-abp-', ':has-text(', ':contains(', ':matches-css', ':matches-attr', ':matches-path', ':matches-prop',
    ':matches-media', ':upward(', ':xpath(', ':remove(', ':remove-attr', ':remove-class', ':style(',
    ':watch-attr', ':min-text-length', ':nth-ancestor', ':if(', ':if-not(', ':others(', ':shadow(',
    ':properties(', '>>>', ':-moz-',
)
OPTION_TAIL = re.compile(r'^[A-Za-z0-9~,=|._*:/-]*$')
COSMETIC_MARK = re.compile(r'#(@?)([?$%]*)#')
RE_SPECIAL = set('.+?()[]{}\\$|')
TRUE_VARS = {'env_safari', 'ext_safari', 'adguard_ext_safari'}   # variables treated as true in !#if conditions


def log(msg):
    print(msg, file=sys.stderr)


def eval_condition(expr):
    """Evaluates a !#if condition. Supports identifiers, !, &&, || and parentheses; rebuilds the expression from allowed tokens only."""
    tokens = re.findall(r'\(|\)|&&|\|\||!|[A-Za-z0-9_]+', expr)
    py = []
    for t in tokens:
        if t == '&&':
            py.append('and')
        elif t == '||':
            py.append('or')
        elif t == '!':
            py.append('not')
        elif t in '()':
            py.append(t)
        else:
            py.append('True' if t in TRUE_VARS else 'False')
    try:
        return bool(eval(' '.join(py), {'__builtins__': {}}, {}))
    except Exception:
        return False


def to_ascii_domain(d):
    d = d.strip().lower().rstrip('.')
    if not d:
        return None
    if not d.isascii():
        try:
            d = d.encode('idna').decode('ascii')
        except UnicodeError:
            return None
    if '*' in d or not re.fullmatch(r'[a-z0-9.-]+', d):
        return None
    return d


def parse_domains(text, sep):
    """'a.com|~b.com' → (included domains, excluded domains). None if any entry cannot be parsed."""
    pos, neg = set(), set()
    for item in text.split(sep):
        item = item.strip()
        if not item:
            continue
        negative = item.startswith('~')
        d = to_ascii_domain(item[1:] if negative else item)
        if d is None:
            return None
        (neg if negative else pos).add(d)
    return pos, neg


def escape_host(host):
    return host.replace('.', '\\.')


def pattern_to_filter(p, keep_case=False):
    """ABP URL pattern → Safari url-filter regex. None if it cannot be converted."""
    if not p.isascii():
        return None
    if not keep_case:
        p = p.lower()
    domain_anchor = start_anchor = end_anchor = False
    if p.startswith('||'):
        domain_anchor, p = True, p[2:]
    elif p.startswith('|'):
        start_anchor, p = True, p[1:]
    if p.endswith('|'):
        end_anchor, p = True, p[:-1]
    if not p or not p.strip('*'):
        return None
    if '|' in p:
        return None
    # The most common form: ||example.com^ / ||example.com → match the host (and its subdomains) exactly.
    if domain_anchor:
        m = re.fullmatch(r'([A-Za-z0-9.-]+)(\^?)', p)
        if m:
            return '^[a-z]+://([a-z0-9-]+\\.)*' + escape_host(m.group(1)) + ('[/:]' if m.group(2) else '')
    out = []
    n = len(p)
    for i, c in enumerate(p):
        if c == '*':
            if out and out[-1] == '.*':
                continue
            out.append('.*')
        elif c == '^':
            # ABP separator: any character other than letters, digits, _ - . %, or the end of the URL
            out.append('([^a-zA-Z0-9_.%-].*)?$' if i == n - 1 else '[^a-zA-Z0-9_.%-]')
        elif c in RE_SPECIAL:
            out.append('\\' + c)
        else:
            out.append(c)
    body = ''.join(out)
    if domain_anchor:
        prefix = '^[a-z]+://([a-z0-9-]+\\.)*'
    elif start_anchor:
        prefix = '^'
    else:
        prefix = ''
        if body.startswith('.*'):
            body = body[2:]
    if body.endswith('.*'):
        body = body[:-2]
        end_anchor = False
    if end_anchor and not body.endswith('$'):
        body += '$'
    if not body:
        return None
    return prefix + body


def parse_options(text):
    """Parses the option string after '$'. None if an unsupported option is present."""
    o = {'load': None, 'if': set(), 'unless': set(), 'types': None, 'case': False, 'document': False}
    types, neg_types = set(), set()
    for raw in text.split(','):
        raw = raw.strip()
        if not raw:
            continue
        negative = raw.startswith('~')
        name = raw[1:] if negative else raw
        key, _, value = name.partition('=')
        key = key.lower()
        if key in ('third-party', '3p'):
            o['load'] = 'first-party' if negative else 'third-party'
        elif key in ('first-party', '1p'):
            o['load'] = 'third-party' if negative else 'first-party'
        elif key == 'domain':
            parsed = parse_domains(value, '|')
            if parsed is None:
                return None
            pos, neg = parsed
            if pos and neg:          # Safari cannot combine if-domain and unless-domain
                return None
            o['if'], o['unless'] = pos, neg
        elif key == 'match-case':
            o['case'] = True
        elif key in ('document', 'doc'):
            if negative:
                return None
            o['document'] = True
        elif key in TYPE_MAP:
            (neg_types if negative else types).add(TYPE_MAP[key])
        else:
            return None   # important, redirect, csp, removeparam, elemhide, generichide, popunder …
    if o['document'] and (types or neg_types):
        return None
    if types:
        o['types'] = sorted(types)
    elif neg_types:
        o['types'] = [t for t in DEFAULT_TYPES if t not in neg_types]
    return o


class Converter:
    def __init__(self, name):
        self.name = name
        self.block = []                 # block rules
        self.exceptions = []            # ignore-previous-rules rules
        self.generic = {}               # selector → excluded domains (element hiding applied on every site)
        self.specific = {}              # selector → domains it applies to
        self.cosmetic_exceptions = []   # (domains, selector)
        self.seen = set()
        self.stats = defaultdict(int)
        self.sources = []

    # ---- reading ----
    def load(self, path):
        info = {'file': os.path.basename(path), 'title': None, 'version': None, 'modified': None}
        with open(path, encoding='utf-8', errors='replace') as f:
            lines = f.read().splitlines()
        for line in lines[:40]:
            m = re.match(r'^!\s*(Title|Version|Last modified):\s*(.+)$', line)
            if m:
                info[{'Title': 'title', 'Version': 'version', 'Last modified': 'modified'}[m.group(1)]] = m.group(2).strip()
        if_stack = []
        count = 0
        for line in lines:
            line = line.strip()
            if not line:
                continue
            if line.startswith('!#'):
                directive, _, arg = line[2:].partition(' ')
                if directive == 'if':
                    if_stack.append(eval_condition(arg))
                elif directive == 'else' and if_stack:
                    if_stack[-1] = not if_stack[-1]
                elif directive == 'endif' and if_stack:
                    if_stack.pop()
                continue
            if line[0] in '![' or not all(if_stack):
                continue
            if ' ' in line and '##' not in line and '#@#' not in line:
                self.stats['skip_malformed'] += 1
                continue
            count += 1
            m = COSMETIC_MARK.search(line)
            if m:
                self.handle_cosmetic(line, m)
            else:
                self.handle_network(line)
        info['lines'] = count
        self.sources.append(info)
        log(f'  {info["file"]}: {count} lines read' + (f' ({info["title"]} {info["version"] or ""})' if info['title'] else ''))

    # ---- network rules ----
    def handle_network(self, line):
        exception = line.startswith('@@')
        if exception:
            line = line[2:]
        if not line:
            return
        if line.startswith('/') and (line.endswith('/') or '/$' in line):
            self.stats['skip_regex'] += 1
            return
        pattern, options = line, ''
        idx = line.rfind('$')
        if idx >= 0:
            tail = line[idx + 1:]
            if not OPTION_TAIL.match(tail):
                self.stats['skip_option'] += 1
                return
            pattern, options = line[:idx], tail
        opts = parse_options(options)
        if opts is None:
            self.stats['skip_option'] += 1
            return
        if opts['document']:
            # Whole-site exception: @@||example.com^$document → ignore all earlier rules on that site
            m = re.fullmatch(r'\|\|([A-Za-z0-9.-]+)\^?', pattern)
            d = to_ascii_domain(m.group(1)) if m else None
            if not exception or not d or opts['if'] or opts['unless']:
                self.stats['skip_document'] += 1
                return
            self.add(self.exceptions, {'trigger': {'url-filter': '.*', 'if-domain': ['*' + d]},
                                       'action': {'type': 'ignore-previous-rules'}})
            return
        filt = pattern_to_filter(pattern, keep_case=opts['case'])
        if filt is None:
            self.stats['skip_pattern'] += 1
            return
        trigger = {'url-filter': filt}
        if opts['case']:
            trigger['url-filter-is-case-sensitive'] = True
        if opts['load']:
            trigger['load-type'] = [opts['load']]
        if opts['types']:
            trigger['resource-type'] = opts['types']
        if opts['if']:
            trigger['if-domain'] = ['*' + d for d in sorted(opts['if'])]
        elif opts['unless']:
            trigger['unless-domain'] = ['*' + d for d in sorted(opts['unless'])]
        if exception:
            self.add(self.exceptions, {'trigger': trigger, 'action': {'type': 'ignore-previous-rules'}})
        else:
            self.add(self.block, {'trigger': trigger, 'action': {'type': 'block'}})

    def add(self, target, rule):
        key = json.dumps(rule, sort_keys=True)
        if key in self.seen:
            self.stats['duplicate'] += 1
            return
        self.seen.add(key)
        target.append(rule)

    # ---- element hiding rules ----
    def handle_cosmetic(self, line, m):
        domains_text = line[:m.start()]
        exc, ext = m.group(1), m.group(2)
        selector = line[m.end():].strip()
        if ext or not selector or selector.startswith('+js') or selector.startswith('^') \
                or any(t in selector for t in UNSUPPORTED_SELECTOR):
            self.stats['skip_cosmetic_ext'] += 1
            return
        parsed = parse_domains(domains_text, ',') if domains_text.strip() else (set(), set())
        if parsed is None:
            self.stats['skip_cosmetic_domain'] += 1
            return
        pos, neg = parsed
        if exc == '@':
            self.cosmetic_exceptions.append((pos, selector))
            return
        if pos and neg:
            self.stats['skip_cosmetic_domain'] += 1
            return
        if pos:
            self.specific.setdefault(selector, set()).update(pos)
        elif selector in self.generic:
            self.generic[selector] &= neg     # several rules for one selector: exclude only domains excluded by all of them
        else:
            self.generic[selector] = set(neg)

    def apply_cosmetic_exceptions(self):
        for doms, sel in self.cosmetic_exceptions:
            if not doms:      # #@# without a domain: drop the selector entirely
                self.generic.pop(sel, None)
                self.specific.pop(sel, None)
                continue
            if sel in self.generic:
                self.generic[sel] |= doms
            if sel in self.specific:
                self.specific[sel] -= doms
                if not self.specific[sel]:
                    del self.specific[sel]

    def cosmetic_rules(self):
        by_key = defaultdict(list)
        for sel, neg in self.generic.items():
            by_key[('unless', frozenset(neg))].append(sel)
        for sel, pos in self.specific.items():
            by_key[('if', frozenset(pos))].append(sel)
        rules = []
        for (kind, doms), sels in sorted(by_key.items(), key=lambda kv: (kv[0][0], sorted(kv[0][1]))):
            sels.sort()
            for i in range(0, len(sels), SELECTOR_CHUNK):
                trigger = {'url-filter': '.*'}
                if doms:
                    trigger['unless-domain' if kind == 'unless' else 'if-domain'] = ['*' + d for d in sorted(doms)]
                rules.append({'trigger': trigger,
                              'action': {'type': 'css-display-none', 'selector': ', '.join(sels[i:i + SELECTOR_CHUNK])}})
        return rules

    # ---- validation ----
    def validate_selectors(self, validator):
        selectors = sorted(set(self.generic) | set(self.specific))
        if not selectors:
            return
        log(f'  Checking {len(selectors)} CSS selectors with WebKit…')
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as f:
            json.dump(selectors, f, ensure_ascii=False)
            path = f.name
        try:
            out = run_validator(validator, ['selectors', path])
        finally:
            os.unlink(path)
        invalid = set(json.loads(out))
        for s in invalid:
            self.generic.pop(s, None)
            self.specific.pop(s, None)
        self.stats['skip_selector_invalid'] = len(invalid)
        if invalid:
            log(f'  Dropped {len(invalid)} invalid selectors, e.g. ' + ' | '.join(sorted(invalid)[:5]))


def run_validator(validator, args):
    proc = subprocess.run([validator] + args, capture_output=True, text=True, encoding='utf-8')
    if proc.returncode != 0:
        raise SystemExit(f'validator failed: {proc.stderr[-3000:]}')
    for line in proc.stderr.splitlines():
        if line.startswith('  ') and 'Error while parsing' not in line:
            log(line)
    return proc.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--name', required=True, help='list name (recorded in the meta file)')
    ap.add_argument('--out', required=True, help='output JSON path')
    ap.add_argument('--meta', required=True, help='meta information JSON path')
    ap.add_argument('--validator', help='tools/validate executable; if given, the result is validated with WebKit')
    ap.add_argument('sources', nargs='+', help='ABP-format filter files')
    args = ap.parse_args()

    log(f'[{args.name}] converting')
    conv = Converter(args.name)
    for src in args.sources:
        if os.path.exists(src):
            conv.load(src)
        else:
            log(f'  {src} not found, skipped')
    conv.apply_cosmetic_exceptions()
    if args.validator:
        conv.validate_selectors(args.validator)

    cosmetic = conv.cosmetic_rules()
    rules = conv.block + cosmetic + conv.exceptions
    if len(rules) > MAX_RULES:
        raise SystemExit(f'too many rules: {len(rules)} > {MAX_RULES}. Split or trim the list.')

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(rules, f, ensure_ascii=False, separators=(',', ':'))

    removed = 0
    if args.validator:
        log(f'  Compiling all {len(rules)} rules with WebKit…')
        result = json.loads(run_validator(args.validator, ['compile', args.out, '--fix', args.out]))
        removed = len(result['bad'])
        if removed:
            with open(args.out, encoding='utf-8') as f:
                rules = json.load(f)
            log(f'  Saved after dropping {removed} rules that failed to compile')

    selectors = len(conv.generic) + len(conv.specific)
    meta = {
        'name': args.name,
        'rules': len(rules),
        'generated': datetime.date.today().isoformat(),
        'sources': conv.sources,
        'stats': {'block': len(conv.block), 'exception': len(conv.exceptions), 'cosmetic_rules': len(cosmetic),
                  'selectors': selectors, 'removed_by_compiler': removed, **dict(conv.stats)},
    }
    with open(args.meta, 'w', encoding='utf-8') as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    skipped = sum(v for k, v in conv.stats.items() if k.startswith('skip'))
    log(f'[{args.name}] done: {len(rules)} rules (block {len(conv.block)}, element hiding {len(cosmetic)}/selectors {selectors}, '
        f'exceptions {len(conv.exceptions)}), skipped {skipped}, duplicates {conv.stats["duplicate"]} → {args.out}')


if __name__ == '__main__':
    main()
