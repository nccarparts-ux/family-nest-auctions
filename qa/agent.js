const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ISSUES_PATH = path.join(__dirname, '..', 'issues.jsonl');
const RESOLVED_PATH = path.join(__dirname, '..', 'issues_resolved.jsonl');

class QAAgent {
  constructor() {
    this.issues = [];
    this.resolved = [];
    this.loadIssues();
  }

  loadIssues() {
    try {
      const content = fs.readFileSync(ISSUES_PATH, 'utf8');
      const lines = content.trim().split('\n').filter(line => line);
      this.issues = lines.map(line => JSON.parse(line));
    } catch (e) {
      this.issues = [];
    }
    try {
      const content = fs.readFileSync(RESOLVED_PATH, 'utf8');
      const lines = content.trim().split('\n').filter(line => line);
      this.resolved = lines.map(line => JSON.parse(line));
    } catch (e) {
      this.resolved = [];
    }
  }

  getUnresolvedIssues() {
    const resolvedIds = new Set(this.resolved.map(r => r.id));
    return this.issues.filter(issue => !resolvedIds.has(issue.id));
  }

  groupIssues(issues) {
    const groups = {};
    issues.forEach(issue => {
      // Group by type and url (path) ignoring query params
      const url = new URL(issue.url);
      const key = `${issue.type}:${url.pathname}`;
      if (!groups[key]) groups[key] = [];
      groups[key].push(issue);
    });
    return groups;
  }

  diagnoseRootCause(group) {
    const first = group[0];
    if (first.type === 'console') {
      if (first.message.includes('FNA') || first.message.includes('BY')) {
        return 'branding_js_namespace';
      } else if (first.message.includes('undefined')) {
        return 'undefined_variable';
      } else if (first.message.includes('SyntaxError')) {
        return 'syntax_error';
      } else if (first.message.includes('Failed to load')) {
        return 'missing_resource';
      }
    } else if (first.type === 'navigation') {
      return 'page_load_failure';
    } else if (first.type === 'broken_image') {
      return 'missing_asset';
    } else if (first.type === 'javascript') {
      return 'runtime_error';
    } else if (first.type === 'accessibility') {
      return 'accessibility';
    }
    return 'unknown';
  }

  async fixIssue(group, rootCause) {
    console.log(`Attempting to fix ${rootCause} for ${group.length} issues`);
    const first = group[0];

    switch (rootCause) {
      case 'branding_js_namespace':
        return this.fixBrandingNamespace(first.url);
      case 'undefined_variable':
        return this.fixUndefinedVariable(first.url, first.message);
      case 'missing_resource':
        return this.fixMissingResource(first.url, first.message);
      case 'missing_asset':
        return this.fixMissingAsset(first.url, first.message);
      default:
        console.log(`No fix available for ${rootCause}`);
        return false;
    }
  }

  fixBrandingNamespace(url) {
    console.log(`Fixing branding namespace in ${url}`);
    // Search for FNA references in HTML files
    try {
      const files = execSync('grep -r "FNA\\.\\|FNA\\s" --include="*.html" .', { cwd: path.join(__dirname, '..') }).toString();
      if (files.trim()) {
        console.log('Found FNA references, replacing with BY');
        // Use sed to replace
        execSync('find . -name "*.html" -exec sed -i "s/FNA\\./BY./g" {} \\;', { cwd: path.join(__dirname, '..') });
        execSync('find . -name "*.html" -exec sed -i "s/\\"FNA\\"/\\"BY\\"/g" {} \\;', { cwd: path.join(__dirname, '..') });
        return true;
      }
    } catch (e) {
      // grep returns non-zero if no matches
    }
    return false;
  }

  fixUndefinedVariable(url, message) {
    console.log(`Undefined variable error: ${message}`);
    // Extract variable name
    const match = message.match(/'?([a-zA-Z_$][a-zA-Z0-9_$]*)'? is not defined/);
    if (match) {
      const varName = match[1];
      console.log(`Variable ${varName} is undefined, checking source`);
      // Could be missing import or script tag
    }
    return false;
  }

  fixMissingResource(url, message) {
    console.log(`Missing resource: ${message}`);
    return false;
  }

  fixMissingAsset(url, message) {
    console.log(`Missing asset: ${message}`);
    return false;
  }

  logResolved(issueIds, commitHash) {
    const timestamp = new Date().toISOString();
    issueIds.forEach(id => {
      const issue = this.issues.find(i => i.id === id);
      if (issue) {
        const resolved = {
          id,
          status: 'resolved',
          url: issue.url,
          commit: commitHash,
          timestamp
        };
        this.resolved.push(resolved);
        fs.appendFileSync(RESOLVED_PATH, JSON.stringify(resolved) + '\n');
      }
    });
  }

  runTests() {
    try {
      console.log('Running Playwright tests...');
      execSync('npm test', { cwd: path.join(__dirname, '..'), stdio: 'inherit' });
      return true;
    } catch (e) {
      console.error('Tests failed:', e.message);
      return false;
    }
  }

  commitChanges(message) {
    try {
      execSync('git add .', { cwd: path.join(__dirname, '..') });
      execSync(`git commit -m "${message}"`, { cwd: path.join(__dirname, '..') });
      const hash = execSync('git rev-parse --short HEAD', { cwd: path.join(__dirname, '..') }).toString().trim();
      return hash;
    } catch (e) {
      console.error('Commit failed:', e.message);
      return null;
    }
  }

  async runIteration() {
    console.log('=== QA Agent Iteration Start ===');
    this.loadIssues();
    const unresolved = this.getUnresolvedIssues();
    console.log(`Unresolved issues: ${unresolved.length}`);

    const groups = this.groupIssues(unresolved);
    console.log(`Grouped into ${Object.keys(groups).length} groups`);

    for (const [key, group] of Object.entries(groups)) {
      console.log(`\nProcessing group: ${key}`);
      const rootCause = this.diagnoseRootCause(group);
      console.log(`Root cause: ${rootCause}`);

      const fixed = await this.fixIssue(group, rootCause);
      if (fixed) {
        console.log(`Fix applied, running tests...`);
        const testsPass = this.runTests();
        if (testsPass) {
          const commitHash = this.commitChanges(`Autonomous QA fix: ${rootCause} ${group[0].url}`);
          if (commitHash) {
            this.logResolved(group.map(g => g.id), commitHash);
            console.log(`Resolved ${group.length} issues, commit ${commitHash}`);
          }
        } else {
          console.log('Tests failed, reverting changes...');
          // Revert changes
          execSync('git checkout -- .', { cwd: path.join(__dirname, '..') });
        }
      }
    }

    console.log('=== QA Agent Iteration Complete ===');
  }
}

module.exports = QAAgent;