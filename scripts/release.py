"""Plan and publish tested WHAS releases using Git and GitHub's APIs.

Standard-library only. Planning is read-only; publishing is a separate CI job.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile


VERSION = re.compile(r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$', re.ASCII)
SHA = re.compile(r'^[0-9a-f]{40}$')
SUBJECT = re.compile(r'^([a-z][a-z0-9-]*)(?:\(([^()\r\n]+)\))?(!)?: (.+)$', re.I)
BREAKING = re.compile(r'^(?:BREAKING CHANGE|BREAKING-CHANGE):[ \t]+(.+)$', re.M)
GROUPS = [('feat', 'Features'), ('fix', 'Fixes'), ('perf', 'Performance'),
          ('refactor', 'Refactoring'), ('docs', 'Documentation'),
          ('chore', 'Maintenance'), ('build', 'Build'), ('ci', 'CI'),
          ('test', 'Tests'), ('style', 'Style'), ('revert', 'Reverts'),
          ('other', 'Other Changes')]


class ReleaseError(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        raise ReleaseError('GitHub API redirected; refusing to forward credentials')


class GitHub:
    def __init__(self, repository, token, api_url='https://api.github.com'):
        if not re.fullmatch(r'[\w.-]+/[\w.-]+', repository):
            raise ReleaseError('Invalid GitHub repository')
        self.repository = repository
        self.base = api_url.rstrip('/')
        parsed = urllib.parse.urlsplit(self.base)
        if parsed.scheme != 'https' or parsed.username or parsed.password:
            raise ReleaseError('GitHub API requires HTTPS')
        self.hosts = {parsed.netloc, 'uploads.github.com'}
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, method, path, data=None, binary=False, optional=False):
        url = path if path.startswith('https://') else self.base + path
        if urllib.parse.urlsplit(url).netloc not in self.hosts:
            raise ReleaseError('Refusing credentials for an unexpected API host')
        headers = {'Authorization': 'Bearer ' + self.token,
                   'Accept': 'application/vnd.github+json',
                   'X-GitHub-Api-Version': '2022-11-28',
                   'User-Agent': 'WHAS-release'}
        if data is not None:
            headers['Content-Type'] = 'application/octet-stream' if binary else 'application/json'
            if not binary:
                data = json.dumps(data).encode('utf-8')
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if optional and error.code == 404:
                return None
            raise ReleaseError(f'GitHub {method} {path.split("?")[0]} failed: HTTP {error.code}') from None

    def pages(self, path):
        separator = '&' if '?' in path else '?'
        page = 1
        while True:
            items = self.request('GET', f'{path}{separator}per_page=100&page={page}')
            yield from items
            if len(items) < 100:
                return
            page += 1

    @property
    def prefix(self):
        return '/repos/' + self.repository

    def releases(self):
        return list(self.pages(self.prefix + '/releases'))

    def associated_pulls(self, sha):
        return self.pages(self.prefix + '/commits/' + sha + '/pulls')

    def pull_commits(self, number):
        # GraphQL pagination avoids REST's 250-commit limit for squash merges.
        owner, name = self.repository.split('/')
        cursor = None
        seen = set()
        commits = {}
        query = '''query($owner:String!,$name:String!,$number:Int!,$cursor:String) {
          repository(owner:$owner,name:$name) {
            pullRequest(number:$number) {
              commits(first:100,after:$cursor) {
                totalCount nodes { commit { oid message } }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }'''
        while True:
            response = self.request('POST', '/graphql', {'query': query, 'variables': {
                'owner': owner, 'name': name, 'number': number, 'cursor': cursor}})
            if response.get('errors'):
                raise ReleaseError(f'Could not read all commits for PR #{number}')
            connection = response['data']['repository']['pullRequest']['commits']
            for node in connection['nodes']:
                commit = node['commit']
                commits[commit['oid']] = commit['message']
            info = connection['pageInfo']
            if not info['hasNextPage']:
                if len(commits) != connection['totalCount']:
                    raise ReleaseError(f'Incomplete commit history for PR #{number}')
                return commits
            cursor = info['endCursor']
            if not cursor or cursor in seen:
                raise ReleaseError('Repeated GitHub pagination cursor')
            seen.add(cursor)


def git(root, *arguments):
    result = subprocess.run(['git', '-c', 'safe.directory=' + str(root), '-C', str(root),
                             *arguments], capture_output=True, text=True, encoding='utf-8')
    if result.returncode:
        raise ReleaseError('Git failed: ' + ' '.join(arguments[:2]))
    return result.stdout.strip()


def ancestor(root, older, newer):
    result = subprocess.run(['git', '-c', 'safe.directory=' + str(root), '-C', str(root),
                             'merge-base', '--is-ancestor', older, newer],
                            capture_output=True)
    if result.returncode not in (0, 1):
        raise ReleaseError('Cannot verify release ancestry; fetch complete Git history and tags')
    return result.returncode == 0


def version(tag):
    match = VERSION.fullmatch(tag)
    if not match:
        raise ReleaseError('Invalid stable version tag')
    return tuple(map(int, match.groups()))


def latest_release(api):
    releases = [release for release in api.releases()
                if not release['draft'] and not release['prerelease']
                and VERSION.fullmatch(release['tag_name'])]
    return max(releases, key=lambda item: version(item['tag_name'])) if releases else None


def parse_commit(sha, message):
    message = message.replace('\r\n', '\n')
    subject = message.splitlines()[0] if message else ''
    match = SUBJECT.fullmatch(subject)
    footers = BREAKING.findall(message)
    return {'sha': sha, 'type': match[1].lower() if match else 'other',
            'scope': match[2] if match else None,
            'description': match[4] if match else subject,
            'breaking': bool(footers or (match and match[3])),
            'details': footers, 'conventional': bool(match)}


def escape(text):
    return re.sub(r'([\\`*_\[\]<>])', r'\\\1', text)


def release_notes(repository, tag, previous, commits, sha):
    sections = {'Breaking Changes': []}
    sections.update((heading, []) for _, heading in GROUPS)
    headings = dict(GROUPS)
    seen = set()
    for commit in commits:
        key = (commit['type'], commit['scope'], commit['description'],
               commit['breaking'], tuple(commit['details']))
        if key in seen:
            continue
        seen.add(key)
        scope = '**' + escape(commit['scope']) + ':** ' if commit['scope'] else ''
        bullet = '- ' + scope + escape(commit['description'])
        bullet += f' ([{commit["sha"][:7]}](https://github.com/{repository}/commit/{commit["sha"]}))'
        sections[headings.get(commit['type'], 'Other Changes')].append(bullet)
        if commit['breaking']:
            details = ' '.join(commit['details'])
            sections['Breaking Changes'].append(bullet + (' — ' + escape(details) if details else ''))
    lines = [f'# {tag}', '']
    for heading, bullets in sections.items():
        if bullets:
            lines.extend(['## ' + heading, '', *bullets, ''])
    if previous:
        lines.extend([f'[Full comparison](https://github.com/{repository}/compare/{previous}...{tag})', ''])
    lines.extend(['## Downloads', '',
                  'Windows x64: download `whas-gui.exe` or the ZIP with guides and licence notices.',
                  'Verify the download against `SHA256SUMS.txt`. The executable is unsigned.', '',
                  f'<!-- whas-release:{sha} -->', ''])
    return '\n'.join(lines)


def plan_release(root, api, sha):
    if not SHA.fullmatch(sha) or git(root, 'rev-parse', 'HEAD') != sha:
        raise ReleaseError('Release must use the exact checked-out workflow commit')
    latest = latest_release(api)
    previous = latest['tag_name'] if latest else None
    previous_sha = git(root, 'rev-parse', previous + '^{commit}') if previous else None
    if previous_sha and ancestor(root, sha, previous_sha):
        return {'schemaVersion': 1, 'repository': api.repository, 'commit': sha,
                'tag': previous if previous_sha == sha else 'development',
                'publish': False, 'reason': 'Already released or superseded'}
    if previous_sha and not ancestor(root, previous_sha, sha):
        raise ReleaseError('Latest release is not an ancestor; refusing to version rewritten history')
    revision = previous + '..' + sha if previous else sha
    shas = git(root, 'rev-list', '--reverse', revision).splitlines()
    messages = {oid: git(root, 'show', '-s', '--format=%B', oid) for oid in shas}
    wrappers = set()
    pulls = set()
    for oid in git(root, 'rev-list', '--first-parent', '--reverse', revision).splitlines():
        for pull in api.associated_pulls(oid):
            if (not pull.get('merged_at') or pull['base']['ref'] != 'main'
                    or pull.get('merge_commit_sha') != oid):
                continue
            wrappers.add(oid)
            if pull['number'] not in pulls:
                messages.update(api.pull_commits(pull['number']))
                pulls.add(pull['number'])
    merge_shas = {parts[0] for line in git(root, 'rev-list', '--parents', revision).splitlines()
                  if len(parts := line.split()) > 2}
    commits = [parse_commit(oid, message) for oid, message in messages.items()]
    commits = [item for item in commits if item['conventional'] or item['breaking']
               or (item['sha'] not in wrappers and item['sha'] not in merge_shas)]
    bump = 'major' if any(item['breaking'] for item in commits) else (
        'minor' if any(item['type'] == 'feat' for item in commits) else 'patch')
    if previous:
        major, minor, patch = version(previous)
        next_version = {'major': (major + 1, 0, 0), 'minor': (major, minor + 1, 0),
                        'patch': (major, minor, patch + 1)}[bump]
        tag = 'v' + '.'.join(map(str, next_version))
    else:
        tag = 'v1.0.0'
    pending = api.request('GET', api.prefix + '/git/ref/tags/' + tag, optional=True)
    if pending and (pending['object']['type'] != 'commit' or pending['object']['sha'] != sha):
        raise ReleaseError('Next release tag is already reserved; finish or review its interrupted release')
    return {'schemaVersion': 1, 'repository': api.repository, 'commit': sha,
            'previousTag': previous, 'tag': tag, 'bump': bump, 'publish': True,
            'notes': release_notes(api.repository, tag, previous, commits, sha)}


def checked_assets(directory, plan):
    names = {'whas-gui.exe', f'whas-windows-x64-{plan["tag"]}.zip'}
    sums = directory / 'SHA256SUMS.txt'
    if sums.is_symlink() or not sums.is_file():
        raise ReleaseError('Missing or linked checksum file')
    found = {}
    for line in sums.read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([a-f0-9]{64})  ([^/\\]+)', line)
        if not match or match[2] not in names or match[2] in found:
            raise ReleaseError('Invalid release checksum manifest')
        path = directory / match[2]
        if path.is_symlink() or not path.is_file():
            raise ReleaseError('Missing or linked release asset')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != match[1]:
            raise ReleaseError('Release asset checksum mismatch')
        found[match[2]] = digest
    if set(found) != names:
        raise ReleaseError('Incomplete release assets')
    with zipfile.ZipFile(directory / f'whas-windows-x64-{plan["tag"]}.zip') as archive:
        metadata = json.loads(archive.read('build.json'))
        if (metadata.get('commit') != plan['commit'] or metadata.get('version') != plan['tag']
                or metadata.get('platform') != 'windows-x64' or metadata.get('signed') is not False):
            raise ReleaseError('Package commit or version differs from the tested release plan')
        if hashlib.sha256(archive.read('whas-gui.exe')).hexdigest() != found['whas-gui.exe']:
            raise ReleaseError('ZIP executable differs from the scanned standalone executable')
    found['SHA256SUMS.txt'] = hashlib.sha256(sums.read_bytes()).hexdigest()
    return found


def publish_release(api, plan, directory, expected_sha):
    if (plan.get('schemaVersion') != 1 or plan.get('repository') != api.repository
            or plan.get('publish') is not True or plan.get('commit') != expected_sha
            or not SHA.fullmatch(expected_sha) or not VERSION.fullmatch(plan.get('tag', ''))
            or f'<!-- whas-release:{expected_sha} -->' not in plan.get('notes', '')):
        raise ReleaseError('Invalid or mismatched release plan')
    hashes = checked_assets(directory, plan)
    prefix = api.prefix
    tag = plan['tag']
    ref_path = prefix + '/git/ref/tags/' + tag
    existing_ref = api.request('GET', ref_path, optional=True)
    if existing_ref and (existing_ref['object']['type'] != 'commit'
                         or existing_ref['object']['sha'] != expected_sha):
        raise ReleaseError('Release tag already points at another commit or an annotated tag')
    release = api.request('GET', prefix + '/releases/tags/' + tag, optional=True)
    marker = f'<!-- whas-release:{expected_sha} -->'
    if release:
        if marker not in (release.get('body') or '') or not existing_ref:
            raise ReleaseError('Existing release is not owned by this release plan')
        if not release['draft']:
            return release['html_url']
    latest = latest_release(api)
    if (latest['tag_name'] if latest else None) != plan.get('previousTag'):
        raise ReleaseError('Release baseline changed; rerun version planning')
    if not existing_ref:
        api.request('POST', prefix + '/git/refs', {'ref': 'refs/tags/' + tag, 'sha': expected_sha})
    if not release:
        release = api.request('POST', prefix + '/releases', {
            'tag_name': tag, 'target_commitish': expected_sha, 'name': tag,
            'body': plan['notes'], 'draft': True, 'prerelease': False})
    existing_assets = {asset['name']: asset for asset in
                       api.pages(prefix + f'/releases/{release["id"]}/assets')}
    if set(existing_assets) - set(hashes):
        raise ReleaseError('Draft contains unexpected assets; review it before retrying')
    for name, digest in hashes.items():
        if name in existing_assets:
            if existing_assets[name].get('digest') != 'sha256:' + digest:
                raise ReleaseError('Draft asset differs from tested bytes; review it before retrying')
            continue
        upload = release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(name)
        asset = api.request('POST', upload, (directory / name).read_bytes(), binary=True)
        if asset.get('state') != 'uploaded' or (asset.get('digest') and asset['digest'] != 'sha256:' + digest):
            raise ReleaseError('Uploaded asset verification failed; draft was not published')
    release = api.request('PATCH', prefix + f'/releases/{release["id"]}',
                          {'draft': False, 'make_latest': 'true'})
    return release['html_url']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    planner = commands.add_parser('plan')
    planner.add_argument('--output', type=Path, required=True)
    publisher = commands.add_parser('publish')
    publisher.add_argument('--plan', type=Path, required=True)
    publisher.add_argument('--assets', type=Path, required=True)
    args = parser.parse_args()
    api = GitHub(os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_TOKEN'],
                 os.environ.get('GITHUB_API_URL', 'https://api.github.com'))
    sha = os.environ['GITHUB_SHA']
    if args.command == 'plan':
        plan = plan_release(Path.cwd().resolve(), api, sha)
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n', encoding='utf-8')
        (args.output / 'release-notes.md').write_text(plan.get('notes', plan.get('reason', '')), encoding='utf-8')
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write(f'tag={plan["tag"]}\npublish={str(plan["publish"]).lower()}\n')
        print(f'Release plan: {plan["tag"]}; publish={plan["publish"]}')
    else:
        plan = json.loads(args.plan.read_text(encoding='utf-8'))
        print('Published release: ' + publish_release(api, plan, args.assets, sha))


if __name__ == '__main__':
    try:
        main()
    except (ReleaseError, KeyError, ValueError, OSError, zipfile.BadZipFile) as error:
        print('Release error: ' + str(error), file=sys.stderr)
        sys.exit(1)
