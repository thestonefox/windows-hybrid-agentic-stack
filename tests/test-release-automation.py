"""Release rules, real Git history and GitHub publication without network writes."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error
import zipfile

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('release', REPO / 'scripts/release.py')
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class MemoryGitHub:
    repository = 'fixture/whas'
    prefix = '/repos/fixture/whas'

    def __init__(self):
        self.items = []
        self.pulls = {}
        self.commits = {}
        self.refs = {}
        self.assets = []
        self.calls = []
        self.fail_upload = None

    def releases(self):
        return self.items

    def associated_pulls(self, sha):
        return self.pulls.get(sha, [])

    def pull_commits(self, number):
        return self.commits[number]

    def pages(self, path):
        return iter(self.assets)

    def request(self, method, path, data=None, binary=False, optional=False):
        self.calls.append((method, path, data))
        if method == 'GET' and '/git/ref/tags/' in path:
            return self.refs.get(path.rsplit('/', 1)[1])
        if method == 'GET' and '/releases/tags/' in path:
            return next((item for item in self.items if item['tag_name'] == path.rsplit('/', 1)[1]), None)
        if method == 'POST' and path.endswith('/git/refs'):
            self.refs[data['ref'].rsplit('/', 1)[1]] = {'object': {'type': 'commit', 'sha': data['sha']}}
            return self.refs[data['ref'].rsplit('/', 1)[1]]
        if method == 'POST' and path.endswith('/releases'):
            item = dict(data, id=12, html_url='https://github.com/fixture/whas/releases/tag/' + data['tag_name'],
                        upload_url='https://uploads.github.com/repos/fixture/whas/releases/12/assets{?name,label}')
            self.items.append(item)
            return item
        if method == 'POST' and binary:
            name = path.split('?name=')[1]
            if name == self.fail_upload:
                raise RELEASE.ReleaseError('Fixture upload failure')
            item = {'name': name, 'digest': 'sha256:' + hashlib.sha256(data).hexdigest(),
                    'state': 'uploaded'}
            self.assets.append(item)
            return item
        if method == 'PATCH':
            self.items[-1].update(data)
            return self.items[-1]
        raise AssertionError('Unexpected fixture API operation: ' + method + ' ' + path)


class CommitRulesTests(unittest.TestCase):
    def test_breaking_markers_with_or_without_scope(self):
        for message in ('feat!: remove old format', 'fix(config)!: remove old format',
                        'chore(config): migrate\n\nBREAKING CHANGE: format changed',
                        'refactor(config): migrate\n\nBREAKING-CHANGE: format changed'):
            with self.subTest(message=message):
                self.assertTrue(RELEASE.parse_commit('a' * 40, message)['breaking'])

    def test_ordinary_mentions_do_not_trigger_major(self):
        for message in ('docs: explain breaking changes',
                        'fix: preserve API\n\nThere are no breaking changes.',
                        'chore: update\n\nbreaking change: no standard footer'):
            self.assertFalse(RELEASE.parse_commit('a' * 40, message)['breaking'])

    def test_case_insensitive_types_and_optional_scope(self):
        commit = RELEASE.parse_commit('a' * 40, 'FEAT(speech): add engine')
        self.assertEqual((commit['type'], commit['scope']), ('feat', 'speech'))
        self.assertEqual(RELEASE.parse_commit('a' * 40, 'fix: repair')['type'], 'fix')

    def test_group_order_details_links_and_deduplication(self):
        commits = [RELEASE.parse_commit(str(i) * 40, message) for i, message in enumerate([
            'docs: explain setup', 'fix(gui): align buttons', 'feat(speech)!: new engine\n\nBREAKING CHANGE: remove old config',
            'feat(speech)!: new engine\n\nBREAKING CHANGE: remove old config', 'unknown summary'])]
        notes = RELEASE.release_notes('fixture/whas', 'v2.0.0', 'v1.2.3', commits, 'a' * 40)
        positions = [notes.index('## ' + name) for name in
                     ('Breaking Changes', 'Features', 'Fixes', 'Documentation', 'Other Changes')]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(notes.count('new engine'), 2)  # Once in breaking, once in features.
        self.assertIn('remove old config', notes)
        self.assertIn('/compare/v1.2.3...v2.0.0', notes)
        self.assertIn('<!-- whas-release:' + 'a' * 40 + ' -->', notes)


class GitPlanningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='whas release fixture ')
        self.root = Path(self.temp.name).resolve()
        self.run_git('init', '-b', 'main', '--quiet')
        self.run_git('config', 'user.name', 'Fixture')
        self.run_git('config', 'user.email', 'fixture@example.invalid')
        (self.root / '.gitignore').write_text('dist/\ngithub-output.txt\n', encoding='utf-8')
        self.run_git('add', '.gitignore')
        self.base = self.commit('chore: initial fixture')
        self.run_git('tag', 'v1.2.3')
        self.api = MemoryGitHub()
        self.api.items = [{'tag_name': 'v1.2.3', 'draft': False, 'prerelease': False}]

    def tearDown(self):
        self.temp.cleanup()

    def run_git(self, *args):
        return RELEASE.git(self.root, *args)

    def commit(self, message):
        file = self.root / 'fixture.txt'
        file.write_text(file.read_text() + '\nchange' if file.exists() else 'initial', encoding='utf-8')
        self.run_git('add', 'fixture.txt')
        self.run_git('commit', '--quiet', '-m', message)
        return self.run_git('rev-parse', 'HEAD')

    def plan(self):
        return RELEASE.plan_release(self.root, self.api, self.run_git('rev-parse', 'HEAD'))

    def test_initial_release_starts_at_one(self):
        self.api.items = []
        self.assertEqual(self.plan()['tag'], 'v1.0.0')

    def test_every_maintenance_type_bumps_patch(self):
        for kind in ('fix', 'chore', 'refactor', 'docs', 'perf', 'test', 'build', 'ci', 'style', 'revert'):
            with self.subTest(kind=kind):
                self.commit(kind + '(fixture): update')
                plan = self.plan()
                self.assertEqual((plan['tag'], plan['bump']), ('v1.2.4', 'patch'))

    def test_feature_wins_over_fixes_and_docs(self):
        self.commit('fix(gui): align buttons')
        self.commit('feat(speech): add engine')
        self.commit('docs: update guide')
        self.assertEqual(self.plan()['tag'], 'v1.3.0')

    def test_breaking_wins_and_resets_minor_and_patch(self):
        self.commit('feat: feature')
        self.commit('refactor(config)!: remove old format')
        self.assertEqual(self.plan()['tag'], 'v2.0.0')

    def test_squash_merge_retains_original_breaking_and_unknown_commits(self):
        sha = self.commit('Update configuration (#7)')
        self.api.pulls[sha] = [{'number': 7, 'merged_at': 'fixture', 'base': {'ref': 'main'},
                                'merge_commit_sha': sha}]
        self.api.commits[7] = {'a' * 40: 'fix(config)!: remove old format',
                               'b' * 40: 'An original non-conventional commit'}
        plan = self.plan()
        self.assertEqual(plan['tag'], 'v2.0.0')
        self.assertIn('remove old format', plan['notes'])
        self.assertIn('An original non-conventional commit', plan['notes'])
        self.assertNotIn('Update configuration (#7)', plan['notes'])

    def test_unmerged_or_unrelated_pr_does_not_change_bump(self):
        sha = self.commit('fix: update')
        self.api.pulls[sha] = [{'number': 7, 'merged_at': 'fixture', 'base': {'ref': 'main'},
                                'merge_commit_sha': 'a' * 40},
                               {'number': 8, 'merged_at': None, 'base': {'ref': 'main'},
                                'merge_commit_sha': sha}]
        self.assertEqual(self.plan()['tag'], 'v1.2.4')

    def test_merge_commit_keeps_feature_and_omits_wrapper(self):
        self.run_git('checkout', '-b', 'feature', '--quiet')
        self.commit('feat(speech): fixture feature')
        self.run_git('checkout', 'main', '--quiet')
        self.run_git('merge', '--no-ff', 'feature', '-m', 'Merge feature', '--quiet')
        plan = self.plan()
        self.assertEqual(plan['tag'], 'v1.3.0')
        self.assertIn('fixture feature', plan['notes'])
        self.assertNotIn('Merge feature', plan['notes'])

    def test_previous_release_features_do_not_bump_again(self):
        self.commit('feat(speech): already released feature')
        self.run_git('tag', 'v1.3.0')
        self.api.items.append({'tag_name': 'v1.3.0', 'draft': False, 'prerelease': False})
        self.commit('docs: update the guide')
        plan = self.plan()
        self.assertEqual(plan['tag'], 'v1.3.1')
        self.assertNotIn('already released feature', plan['notes'])

    def test_already_released_or_older_runs_do_not_publish(self):
        plan = self.plan()
        self.assertFalse(plan['publish'])
        sha = self.commit('feat: newer')
        self.run_git('tag', 'v1.3.0')
        self.api.items.append({'tag_name': 'v1.3.0', 'draft': False, 'prerelease': False})
        self.run_git('checkout', '--detach', self.base)
        self.assertFalse(self.plan()['publish'])
        self.assertNotEqual(sha, self.base)

    def test_draft_and_prerelease_are_not_release_baselines(self):
        self.commit('fix: update')
        self.api.items.extend([{'tag_name': 'v9.0.0', 'draft': True, 'prerelease': False},
                               {'tag_name': 'v8.0.0', 'draft': False, 'prerelease': True}])
        self.assertEqual(self.plan()['tag'], 'v1.2.4')

    def test_exact_checkout_commit_is_required(self):
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'exact checked-out'):
            RELEASE.plan_release(self.root, self.api, 'a' * 40)

    def test_reserved_tag_for_another_commit_stops_before_build(self):
        self.commit('fix: update')
        self.api.refs['v1.2.4'] = {'object': {'type': 'commit', 'sha': 'a' * 40}}
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'already reserved'):
            self.plan()

    def test_cli_writes_plan_notes_and_github_outputs_without_dirtying_checkout(self):
        sha = self.commit('feat: fixture feature')
        directory = self.root / 'dist/release-plan'
        output = self.root / 'github-output.txt'
        environment = {'GITHUB_SHA': sha, 'GITHUB_REPOSITORY': self.api.repository,
                       'GITHUB_TOKEN': 'fixture-token', 'GITHUB_OUTPUT': str(output)}
        with patch.dict(os.environ, environment), patch.object(RELEASE, 'GitHub', return_value=self.api), \
                patch.object(RELEASE.Path, 'cwd', return_value=self.root), \
                patch('sys.argv', ['release.py', 'plan', '--output', str(directory)]):
            RELEASE.main()
        self.assertEqual(json.loads((directory / 'plan.json').read_text())['tag'], 'v1.3.0')
        self.assertIn('## Features', (directory / 'release-notes.md').read_text())
        self.assertEqual(output.read_text(), 'tag=v1.3.0\npublish=true\n')
        self.assertEqual(self.run_git('status', '--porcelain'), '')


class GitHubPaginationTests(unittest.TestCase):
    def test_original_pr_history_beyond_rest_limit(self):
        api = RELEASE.GitHub('fixture/whas', 'fixture-token')
        def response(method, path, data):
            cursor = data['variables']['cursor']
            start = int(cursor) if cursor else 0
            end = min(start + 100, 301)
            return {'data': {'repository': {'pullRequest': {'commits': {
                'totalCount': 301,
                'nodes': [{'commit': {'oid': f'{i:040x}', 'message': 'fix: fixture'}}
                          for i in range(start, end)],
                'pageInfo': {'hasNextPage': end < 301, 'endCursor': str(end)}}}}}}
        api.request = Mock(side_effect=response)
        self.assertEqual(len(api.pull_commits(7)), 301)
        self.assertEqual(api.request.call_count, 4)

    def test_graphql_errors_and_incomplete_results_fail_closed(self):
        api = RELEASE.GitHub('fixture/whas', 'fixture-token')
        api.request = Mock(return_value={'errors': [{'message': 'fixture error'}]})
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'read all commits'):
            api.pull_commits(7)
        api.request = Mock(return_value={'data': {'repository': {'pullRequest': {'commits': {
            'totalCount': 3, 'nodes': [], 'pageInfo': {'hasNextPage': False}}}}}})
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'Incomplete'):
            api.pull_commits(7)

    def test_rest_pagination(self):
        api = RELEASE.GitHub('fixture/whas', 'fixture-token')
        api.request = Mock(side_effect=[[{'number': i} for i in range(100)], [{'number': 100}]])
        self.assertEqual(len(list(api.associated_pulls('a' * 40))), 101)
        self.assertIn('page=2', api.request.call_args.args[1])

    def test_unexpected_upload_host_is_rejected_before_network(self):
        api = RELEASE.GitHub('fixture/whas', 'fixture-token')
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'unexpected API host'):
            api.request('POST', 'https://example.invalid/upload', b'fixture', binary=True)

    def test_only_not_found_is_optional_and_authentication_errors_fail(self):
        api = RELEASE.GitHub('fixture/whas', 'fixture-token')
        for status in (404, 403, 500):
            api.opener.open = Mock(side_effect=urllib.error.HTTPError(
                'https://api.github.com/fixture', status, 'Fixture error', {}, None))
            if status == 404:
                self.assertIsNone(api.request('GET', '/fixture', optional=True))
            else:
                with self.assertRaisesRegex(RELEASE.ReleaseError, 'HTTP ' + str(status)):
                    api.request('GET', '/fixture', optional=True)

    def test_redirect_does_not_forward_authorization(self):
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'refusing to forward'):
            RELEASE.NoRedirect().redirect_request(None, None, 302, '', {},
                                                  'https://example.invalid')


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='whas publish fixture ')
        self.directory = Path(self.temp.name).resolve()
        self.api = MemoryGitHub()
        self.sha = 'a' * 40
        self.plan = {'schemaVersion': 1, 'repository': self.api.repository,
                     'commit': self.sha, 'tag': 'v1.0.0', 'previousTag': None,
                     'publish': True, 'notes': '<!-- whas-release:' + self.sha + ' -->'}
        (self.directory / 'whas-gui.exe').write_bytes(b'Inert fixture; never executed.')
        with zipfile.ZipFile(self.directory / 'whas-windows-x64-v1.0.0.zip', 'w') as archive:
            archive.writestr('build.json', json.dumps({'commit': self.sha, 'version': 'v1.0.0',
                                                      'platform': 'windows-x64', 'signed': False}))
            archive.writestr('whas-gui.exe', (self.directory / 'whas-gui.exe').read_bytes())
        self.write_sums()

    def tearDown(self):
        self.temp.cleanup()

    def write_sums(self):
        lines = [hashlib.sha256((self.directory / name).read_bytes()).hexdigest() + '  ' + name
                 for name in ('whas-gui.exe', 'whas-windows-x64-v1.0.0.zip')]
        (self.directory / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    def publish(self):
        return RELEASE.publish_release(self.api, self.plan, self.directory, self.sha)

    def test_tag_then_draft_then_assets_then_publication(self):
        self.assertIn('/releases/tag/v1.0.0', self.publish())
        writes = [call for call in self.api.calls if call[0] != 'GET']
        self.assertTrue(writes[0][1].endswith('/git/refs'))
        self.assertTrue(writes[1][2]['draft'])
        self.assertEqual(len(self.api.assets), 3)
        self.assertEqual(writes[-1][0], 'PATCH')
        self.assertFalse(self.api.items[-1]['draft'])
        self.assertEqual(self.api.refs['v1.0.0']['object']['sha'], self.sha)

    def test_bad_checksums_or_package_identity_prevent_all_writes(self):
        (self.directory / 'whas-gui.exe').write_bytes(b'tampered')
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'checksum mismatch'):
            self.publish()
        self.assertEqual(self.api.calls, [])
        self.write_sums()
        with zipfile.ZipFile(self.directory / 'whas-windows-x64-v1.0.0.zip', 'w') as archive:
            archive.writestr('build.json', json.dumps({'commit': 'b' * 40, 'version': 'v1.0.0'}))
        self.write_sums()
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'commit or version differs'):
            self.publish()
        self.assertEqual(self.api.calls, [])

    def test_conflicting_tag_is_preserved(self):
        self.api.refs['v1.0.0'] = {'object': {'type': 'commit', 'sha': 'b' * 40}}
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'another commit'):
            self.publish()
        self.assertFalse(any(call[0] != 'GET' for call in self.api.calls))

    def test_mismatched_plan_prevents_all_requests(self):
        for key, value in (('commit', 'b' * 40), ('repository', 'other/repo'), ('tag', '../invalid')):
            with self.subTest(key=key):
                plan = dict(self.plan, **{key: value})
                with self.assertRaisesRegex(RELEASE.ReleaseError, 'mismatched release plan'):
                    RELEASE.publish_release(self.api, plan, self.directory, self.sha)
                self.assertEqual(self.api.calls, [])

    def test_failed_upload_leaves_unpublished_draft_and_retry_resumes(self):
        self.api.fail_upload = 'SHA256SUMS.txt'
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'upload failure'):
            self.publish()
        self.assertTrue(self.api.items[-1]['draft'])
        self.assertEqual(len(self.api.assets), 2)
        self.api.fail_upload = None
        self.publish()
        self.assertEqual(len(self.api.assets), 3)
        self.assertFalse(self.api.items[-1]['draft'])

    def test_published_release_is_not_replaced_on_retry(self):
        self.publish()
        before = copy.deepcopy(self.api.items)
        self.api.calls = []
        self.publish()
        self.assertEqual(self.api.items, before)
        self.assertFalse(any(call[0] != 'GET' for call in self.api.calls))

    def test_changed_baseline_and_unowned_release_are_rejected(self):
        self.api.items.append({'tag_name': 'v2.0.0', 'draft': False, 'prerelease': False})
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'baseline changed'):
            self.publish()
        self.assertFalse(any(call[0] != 'GET' for call in self.api.calls))
        self.api.items = [{'tag_name': 'v1.0.0', 'draft': True, 'body': 'manual draft'}]
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'not owned'):
            self.publish()

    def test_changed_draft_bytes_are_not_overwritten(self):
        self.api.fail_upload = 'SHA256SUMS.txt'
        with self.assertRaises(RELEASE.ReleaseError):
            self.publish()
        self.api.assets[0]['digest'] = 'sha256:' + '0' * 64
        self.api.calls = []
        with self.assertRaisesRegex(RELEASE.ReleaseError, 'differs from tested bytes'):
            self.publish()
        self.assertFalse(any(call[0] != 'GET' for call in self.api.calls))

    def test_checksum_path_traversal_and_duplicate_entries_are_rejected(self):
        sums = self.directory / 'SHA256SUMS.txt'
        original = sums.read_text()
        for text in (original.replace('whas-gui.exe', '../whas-gui.exe'),
                     original + original.splitlines()[0] + '\n'):
            sums.write_text(text)
            with self.assertRaisesRegex(RELEASE.ReleaseError, 'Invalid release checksum'):
                self.publish()
            self.assertEqual(self.api.calls, [])


if __name__ == '__main__':
    unittest.main()
