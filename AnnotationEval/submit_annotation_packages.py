#!/usr/bin/env python3

"""
Submit Bioconductor annotation packages to:

    https://github.com/lshep/annotation_pkg_evalutation

The package list is obtained from the Bioconductor devel VIEWS file.

The script:
  * Parses Package, Version, and source.ver from VIEWS.
  * Constructs the Bioconductor package URL.
  * Creates one GitHub issue per package.
  * Uses the package tarball filename as the issue title.
  * Monitors the "Validate Annotation Package" GitHub Actions workflow.
  * Limits the number of active/queued validation workflows.
  * Persists progress in a JSON state file.
  * Can safely be interrupted and resumed.
  * Detects existing issues to avoid duplicates.
  * Supports dry-run and limited test runs.

Authentication:
  Set GITHUB_TOKEN in the environment.

Example:

    export GITHUB_TOKEN="github_pat_..."

Dry run:

    ./submit_annotation_packages.py --dry-run

Submit only 5 packages:

    ./submit_annotation_packages.py --limit 5

Normal run:

    ./submit_annotation_packages.py

Resume after interruption:

    ./submit_annotation_packages.py
"""

import argparse
import json
import os
import random
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


# ============================================================================
# CONFIGURATION
# ============================================================================

# Bioconductor VIEWS file to read.
VIEWS_URL = (
    "https://www.bioconductor.org/packages/devel/data/annotation/VIEWS"
)

# Base URL used with the source.ver value from VIEWS.
#
# source.ver contains values such as:
#
#     src/contrib/hgu95a.db_3.13.0.tar.gz
#
# This therefore produces:
#
#     https://bioconductor.org/packages/devel/data/annotation/
#         src/contrib/hgu95a.db_3.13.0.tar.gz
#
PACKAGE_BASE_URL = (
    "https://bioconductor.org/packages/devel/data/annotation/"
)

# GitHub repository receiving the issues.
GITHUB_OWNER = "lshep"
GITHUB_REPO = "annotation_pkg_evaluation"

# Workflow used to validate each submitted package.
#
# The workflow file can be used instead of the numeric workflow ID.
WORKFLOW_FILE = ".github/workflows/bioc-validation.yml"

# Human-readable workflow name, used in status messages.
WORKFLOW_NAME = "Validate Annotation Package"

# Persistent state file.
STATE_FILE = Path("annotation_submission_state.json")

# How often to check GitHub Actions while waiting for capacity.
POLL_INTERVAL = 300

# Maximum number of validation workflow runs we intentionally allow to be
# queued or running.
#
# GitHub Free has a concurrency limit for standard hosted jobs, but we
# deliberately leave headroom rather than trying to consume the entire limit.
MAX_ACTIVE_VALIDATIONS = 15

# Maximum number of validation runs that are allowed to be queued.
#
# Normally this should remain 0 because we want the script itself to act as
# the queue. A small value can be useful if GitHub is slow to start runners.
MAX_QUEUED_VALIDATIONS = 2

# Minimum time between issue creation requests.
#
# This is NOT the primary throttling mechanism. Actions capacity is.
# This simply prevents the script from rapidly creating many issues when
# multiple Actions slots become available simultaneously.
MIN_SUBMISSION_INTERVAL = 30

# Add a little random variation to the minimum interval.
SUBMISSION_JITTER = 10

# Warn and wait if the authenticated API rate limit falls below this value.
#  5,000 requests/hour for authenticated REST API requests
MIN_REMAINING_API_REQUESTS = 200

# Number of retries for transient API failures.
MAX_API_RETRIES = 8


# ============================================================================
# GITHUB API
# ============================================================================

API_BASE = "https://api.github.com"
API_VERSION = "2026-03-10"


class GitHubAPIError(Exception):
    """Raised when a GitHub API request fails."""


class GitHubClient:
    def __init__(self, token):
        self.token = token
        self.last_rate_limit = None

    def request(self, method, path, params=None, data=None):
        """
        Make a GitHub API request with retry/backoff handling.
        """

        if params:
            path = path + "?" + urlencode(params)

        url = API_BASE + path

        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.token}",
            "X-GitHub-Api-Version": API_VERSION,
            "User-Agent": "bioconductor-annotation-submission-script",
        }

        body = None

        if data is not None:
            body = json.dumps(data).encode("utf-8")
            headers["Content-Type"] = "application/json"

        for attempt in range(1, MAX_API_RETRIES + 1):

            request = Request(
                url,
                data=body,
                headers=headers,
                method=method,
            )

            try:
                with urlopen(request, timeout=60) as response:

                    response_headers = response.headers

                    self.last_rate_limit = {
                        "limit": response_headers.get("X-RateLimit-Limit"),
                        "remaining": response_headers.get(
                            "X-RateLimit-Remaining"
                        ),
                        "reset": response_headers.get("X-RateLimit-Reset"),
                    }

                    response_body = response.read()

                    if not response_body:
                        return None

                    return json.loads(response_body.decode("utf-8"))

            except HTTPError as exc:

                response_body = exc.read().decode(
                    "utf-8",
                    errors="replace",
                )

                remaining = exc.headers.get("X-RateLimit-Remaining")
                reset = exc.headers.get("X-RateLimit-Reset")
                retry_after = exc.headers.get("Retry-After")

                self.last_rate_limit = {
                    "limit": exc.headers.get("X-RateLimit-Limit"),
                    "remaining": remaining,
                    "reset": reset,
                }

                # Primary rate limit exhausted.
                if remaining == "0" and reset:
                    wait_seconds = max(
                        1,
                        int(reset) - int(time.time()) + 5,
                    )

                    print(
                        f"\nGitHub API rate limit exhausted. "
                        f"Waiting {wait_seconds} seconds."
                    )

                    time.sleep(wait_seconds)
                    continue

                # Secondary rate limit.
                if exc.code in (403, 429):

                    if retry_after:
                        wait_seconds = int(retry_after)
                    else:
                        wait_seconds = min(
                            900,
                            60 * (2 ** (attempt - 1)),
                        )

                    print(
                        f"\nGitHub returned HTTP {exc.code}. "
                        f"Backing off for {wait_seconds} seconds."
                    )

                    if response_body:
                        print(response_body[:500])

                    time.sleep(wait_seconds)
                    continue

                # Temporary GitHub/server failure.
                if exc.code in (500, 502, 503, 504):

                    wait_seconds = min(
                        300,
                        10 * (2 ** (attempt - 1)),
                    )

                    print(
                        f"\nGitHub returned HTTP {exc.code}. "
                        f"Retrying in {wait_seconds} seconds."
                    )

                    time.sleep(wait_seconds)
                    continue

                raise GitHubAPIError(
                    f"GitHub API HTTP {exc.code}: {response_body}"
                )

            except URLError as exc:

                wait_seconds = min(
                    300,
                    10 * (2 ** (attempt - 1)),
                )

                print(
                    f"\nNetwork error: {exc}. "
                    f"Retrying in {wait_seconds} seconds."
                )

                time.sleep(wait_seconds)

        raise GitHubAPIError(
            f"GitHub API request failed after {MAX_API_RETRIES} attempts: "
            f"{method} {path}"
        )


def verify_github_auth(client):
    user = client.request("GET", "/user")
    login = user.get("login")

    if not login:
        raise RuntimeError(
            "GitHub authentication succeeded, but no username was returned."
        )

    print(f"Authenticated to GitHub as: {login}")

    if login.lower() != GITHUB_OWNER.lower():
        raise RuntimeError(
            f"Authenticated GitHub account is '{login}', "
            f"but expected '{GITHUB_OWNER}'."
        )


# ============================================================================
# VIEWS PARSING
# ============================================================================


def download_views():
    """Download the Bioconductor VIEWS file."""

    request = Request(
        VIEWS_URL,
        headers={
            "User-Agent": "bioconductor-annotation-submission-script",
        },
    )

    try:
        with urlopen(request, timeout=60) as response:
            return response.read().decode("utf-8")

    except (HTTPError, URLError) as exc:
        raise RuntimeError(
            f"Unable to download VIEWS from {VIEWS_URL}: {exc}"
        )


def parse_views(text):
    """
    Parse Package, Version, and source.ver entries from VIEWS.

    VIEWS consists of records separated by blank lines.
    """

    packages = []

    records = re.split(r"\n\s*\n", text)

    for record in records:

        package_match = re.search(
            r"^Package:\s*(.+)$",
            record,
            re.MULTILINE,
        )

        version_match = re.search(
            r"^Version:\s*(.+)$",
            record,
            re.MULTILINE,
        )

        source_match = re.search(
            r"^source\.ver:\s*(.+)$",
            record,
            re.MULTILINE,
        )

        if not package_match:
            continue

        if not version_match:
            print(
                f"WARNING: No Version found for "
                f"{package_match.group(1).strip()}"
            )
            continue

        if not source_match:
            print(
                f"WARNING: No source.ver found for "
                f"{package_match.group(1).strip()}"
            )
            continue

        package = package_match.group(1).strip()
        version = version_match.group(1).strip()
        source_ver = source_match.group(1).strip()

        filename = os.path.basename(source_ver)

        if not filename.endswith(".tar.gz"):
            print(
                f"WARNING: Unexpected source.ver for {package}: "
                f"{source_ver}"
            )
            continue

        package_url = PACKAGE_BASE_URL.rstrip("/") + "/" + source_ver

        packages.append(
            {
                "package": package,
                "version": version,
                "source_ver": source_ver,
                "filename": filename,
                "url": package_url,
            }
        )

    return packages


# ============================================================================
# STATE
# ============================================================================


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def atomic_write_json(path, data):
    """
    Write JSON atomically so an interruption does not leave a half-written
    state file.
    """

    temporary = path.with_suffix(path.suffix + ".tmp")

    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(
            data,
            handle,
            indent=2,
            sort_keys=True,
        )
        handle.write("\n")

    temporary.replace(path)


def create_initial_state(packages):
    return {
        "created_at": utc_now(),
        "views_url": VIEWS_URL,
        "package_base_url": PACKAGE_BASE_URL,
        "packages": packages,
        "submissions": {},
    }


def load_or_create_state():

    if STATE_FILE.exists():

        print(f"Loading existing state: {STATE_FILE}")

        with STATE_FILE.open("r", encoding="utf-8") as handle:
            state = json.load(handle)

        # Protect against accidentally resuming with a different URL source.
        if state.get("views_url") != VIEWS_URL:
            raise RuntimeError(
                "The existing state file was created with a different "
                f"VIEWS_URL:\n"
                f"  state: {state.get('views_url')}\n"
                f"  current: {VIEWS_URL}\n\n"
                "Delete or rename the state file if you intentionally "
                "want to start a new submission run."
            )

        if state.get("package_base_url") != PACKAGE_BASE_URL:
            raise RuntimeError(
                "The existing state file was created with a different "
                f"PACKAGE_BASE_URL:\n"
                f"  state: {state.get('package_base_url')}\n"
                f"  current: {PACKAGE_BASE_URL}\n\n"
                "Delete or rename the state file if you intentionally "
                "want to start a new submission run."
            )

        return state

    print(f"No existing state file found: {STATE_FILE}")
    print("Downloading and parsing VIEWS...")

    views = download_views()
    packages = parse_views(views)

    if not packages:
        raise RuntimeError(
            "No packages were parsed from VIEWS."
        )

    state = create_initial_state(packages)

    atomic_write_json(STATE_FILE, state)

    print(
        f"Created state file containing {len(packages)} packages."
    )

    return state


def save_state(state):
    atomic_write_json(STATE_FILE, state)


# ============================================================================
# EXISTING ISSUES
# ============================================================================


def get_existing_issues(client):
    """
    Retrieve all existing issues.

    Returns a mapping from issue title to issue information.

    We retrieve open and closed issues because a previous validation may have
    closed an issue. We don't want to submit it again.
    """

    issues = {}

    for issue_state in ("open", "closed"):

        page = 1

        while True:

            data = client.request(
                "GET",
                f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/issues",
                params={
                    "state": issue_state,
                    "per_page": 100,
                    "page": page,
                },
            )

            if not data:
                break

            for issue in data:

                # The Issues endpoint also returns pull requests.
                if "pull_request" in issue:
                    continue

                issues[issue["title"]] = {
                    "number": issue["number"],
                    "html_url": issue["html_url"],
                    "state": issue["state"],
                }

            if len(data) < 100:
                break

            page += 1

    return issues


# ============================================================================
# WORKFLOW MONITORING
# ============================================================================


def find_workflow(client):
    """
    Find the workflow ID from the configured workflow filename.
    """

    page = 1

    while True:

        data = client.request(
            "GET",
            f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/actions/workflows",
            params={
                "per_page": 100,
                "page": page,
            },
        )

        workflows = data.get("workflows", [])

        for workflow in workflows:

            if workflow["path"] == WORKFLOW_FILE:
                return workflow["id"]

            if workflow["name"] == WORKFLOW_NAME:
                return workflow["id"]

        if len(workflows) < 100:
            break

        page += 1

    raise RuntimeError(
        f"Could not find workflow '{WORKFLOW_FILE}' "
        f"('{WORKFLOW_NAME}') in "
        f"{GITHUB_OWNER}/{GITHUB_REPO}."
    )


def get_active_workflow_runs(client, workflow_id):
    """
    Return counts of queued and running workflow runs.

    We only look at the validation workflow configured above.
    """

    counts = {
        "queued": 0,
        "in_progress": 0,
        "waiting": 0,
        "requested": 0,
        "pending": 0,
    }

    # We fetch each relevant status explicitly. This avoids downloading
    # unrelated completed workflow history.
    for status in counts:

        data = client.request(
            "GET",
            (
                f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}"
                f"/actions/workflows/{workflow_id}/runs"
            ),
            params={
                "status": status,
                "per_page": 100,
            },
        )

        counts[status] = data.get("total_count", 0)

    return counts


def get_total_active(counts):
    return sum(counts.values())


def wait_for_capacity(client, workflow_id):

    while True:

        counts = get_active_workflow_runs(
            client,
            workflow_id,
        )

        running = counts["in_progress"]
        queued = (
            counts["queued"]
            + counts["waiting"]
            + counts["requested"]
            + counts["pending"]
        )

        total = running + queued

        print(
            f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] "
            f"Validation workflow: "
            f"running={running}, queued={queued}, total={total}"
        )

        if (
            running < MAX_ACTIVE_VALIDATIONS
            and queued <= MAX_QUEUED_VALIDATIONS
        ):
            return counts

        print(
            f"  Capacity limit reached "
            f"(max running={MAX_ACTIVE_VALIDATIONS}, "
            f"max queued={MAX_QUEUED_VALIDATIONS})."
        )

        print(
            f"  Waiting {POLL_INTERVAL} seconds before checking again..."
        )

        time.sleep(POLL_INTERVAL)


# ============================================================================
# RATE LIMIT MONITORING
# ============================================================================


def wait_for_rate_limit_if_needed(client):

    rate = client.last_rate_limit

    if not rate:
        return

    remaining = rate.get("remaining")

    if remaining is None:
        return

    try:
        remaining = int(remaining)
    except ValueError:
        return

    if remaining >= MIN_REMAINING_API_REQUESTS:
        return

    reset = rate.get("reset")

    if not reset:
        return

    wait_seconds = max(
        1,
        int(reset) - int(time.time()) + 5,
    )

    print(
        f"\nOnly {remaining} GitHub API requests remain "
        f"in the current rate-limit window."
    )

    print(
        f"Waiting {wait_seconds} seconds for the rate-limit window "
        f"to reset."
    )

    time.sleep(wait_seconds)


# ============================================================================
# ISSUE CREATION
# ============================================================================


def create_issue(client, package):

    title = package["filename"]

    body = (
        "Update the following URL to point to the GitHub repository of\n"
        "the package you wish to submit to _Bioconductor_ or the prebuilt "
        "source bundle.\n\n"
        f"- Package_URL: {package['url']}\n"
    )

    data = {
        "title": title,
        "body": body,
    }

    return client.request(
        "POST",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/issues",
        data=data,
    )


# ============================================================================
# MAIN
# ============================================================================


def parse_arguments():

    parser = argparse.ArgumentParser(
        description=(
            "Submit Bioconductor annotation packages as GitHub issues "
            "while monitoring GitHub Actions capacity."
        )
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Parse VIEWS and display what would be submitted, "
            "but do not create issues."
        ),
    )

    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help=(
            "Submit at most this many packages during this invocation. "
            "Useful for testing."
        ),
    )

    parser.add_argument(
        "--poll-interval",
        type=int,
        default=POLL_INTERVAL,
        help=(
            f"Seconds between GitHub Actions capacity checks "
            f"(default: {POLL_INTERVAL})."
        ),
    )

    parser.add_argument(
        "--max-active",
        type=int,
        default=MAX_ACTIVE_VALIDATIONS,
        help=(
            f"Maximum number of running validation workflows "
            f"(default: {MAX_ACTIVE_VALIDATIONS})."
        ),
    )

    parser.add_argument(
        "--max-queued",
        type=int,
        default=MAX_QUEUED_VALIDATIONS,
        help=(
            f"Maximum number of queued validation workflows "
            f"(default: {MAX_QUEUED_VALIDATIONS})."
        ),
    )

    parser.add_argument(
        "--submission-interval",
        type=int,
        default=MIN_SUBMISSION_INTERVAL,
        help=(
            f"Minimum seconds between issue creations "
            f"(default: {MIN_SUBMISSION_INTERVAL})."
        ),
    )

    return parser.parse_args()


def print_dry_run(state):

    packages = state["packages"]

    print()
    print("=" * 80)
    print("DRY RUN")
    print("=" * 80)
    print()
    print(f"VIEWS:       {VIEWS_URL}")
    print(f"Package URL: {PACKAGE_BASE_URL}")
    print()
    print(f"Packages found: {len(packages)}")
    print()

    for index, package in enumerate(packages, start=1):

        print(
            f"{index:4d}. "
            f"{package['filename']}"
        )

        print(
            f"      Package: {package['package']}"
        )

        print(
            f"      Version: {package['version']}"
        )

        print(
            f"      URL:     {package['url']}"
        )

    print()
    print("No issues were created.")


def main():

    args = parse_arguments()

    global POLL_INTERVAL
    global MAX_ACTIVE_VALIDATIONS
    global MAX_QUEUED_VALIDATIONS

    POLL_INTERVAL = args.poll_interval
    MAX_ACTIVE_VALIDATIONS = args.max_active
    MAX_QUEUED_VALIDATIONS = args.max_queued

    token = os.environ.get("GITHUB_TOKEN")

    if not token and not args.dry_run:
        print(
            "ERROR: GITHUB_TOKEN is not set.",
            file=sys.stderr,
        )
        print(
            "Set it with:",
            file=sys.stderr,
        )
        print(
            '  export GITHUB_TOKEN="your_token"',
            file=sys.stderr,
        )
        sys.exit(1)

    # Load the package list and persistent state.
    state = load_or_create_state()

    if args.dry_run:
        print_dry_run(state)
        return

    client = GitHubClient(token)
    verify_github_auth(client)

    print()
    print("=" * 80)
    print("Bioconductor annotation package submission")
    print("=" * 80)
    print()
    print(
        f"Repository: {GITHUB_OWNER}/{GITHUB_REPO}"
    )
    print(
        f"VIEWS:      {VIEWS_URL}"
    )
    print(
        f"URL base:   {PACKAGE_BASE_URL}"
    )
    print(
        f"State:      {STATE_FILE}"
    )
    print(
        f"Max active validation runs: {MAX_ACTIVE_VALIDATIONS}"
    )
    print(
        f"Max queued validation runs: {MAX_QUEUED_VALIDATIONS}"
    )
    print(
        f"Polling interval: {POLL_INTERVAL} seconds"
    )
    print()

    # Find the validation workflow.
    workflow_id = find_workflow(client)

    print(
        f"Found workflow '{WORKFLOW_NAME}' "
        f"(ID {workflow_id})."
    )

    # Retrieve existing issues before beginning.
    print()
    print("Checking existing issues...")
    existing_issues = get_existing_issues(client)

    print(
        f"Found {len(existing_issues)} existing issues."
    )

    # Add existing issues to the persistent state where they correspond to
    # packages in our VIEWS snapshot.
    state_changed = False

    for package in state["packages"]:

        title = package["filename"]

        if title in existing_issues:

            issue = existing_issues[title]

            if title not in state["submissions"]:

                state["submissions"][title] = {
                    "status": "existing",
                    "issue_number": issue["number"],
                    "issue_url": issue["html_url"],
                    "detected_at": utc_now(),
                }

                state_changed = True

    if state_changed:
        save_state(state)

    # Determine packages still requiring submission.
    pending = []

    for package in state["packages"]:

        title = package["filename"]

        if title not in state["submissions"]:
            pending.append(package)

    print()
    print(
        f"Packages in VIEWS: {len(state['packages'])}"
    )
    print(
        f"Already submitted/existing: "
        f"{len(state['submissions'])}"
    )
    print(
        f"Remaining: {len(pending)}"
    )
    print()

    if not pending:
        print("Nothing left to submit.")
        return

    if args.limit is not None:
        pending = pending[:args.limit]

        print(
            f"Applying --limit {args.limit}: "
            f"will process {len(pending)} package(s) this invocation."
        )
        print()

    last_submission_time = 0

    submitted_this_run = 0

    try:

        for package in pending:

            title = package["filename"]

            print()
            print("-" * 80)
            print(
                f"Next package: {title}"
            )
            print(
                f"Package:      {package['package']}"
            )
            print(
                f"Version:      {package['version']}"
            )
            print(
                f"URL:          {package['url']}"
            )
            print("-" * 80)

            # Respect the small API pacing interval.
            elapsed = time.time() - last_submission_time

            if elapsed < args.submission_interval:

                wait_seconds = (
                    args.submission_interval
                    - elapsed
                    + random.uniform(0, SUBMISSION_JITTER)
                )

                print(
                    f"Waiting {wait_seconds:.1f} seconds before "
                    f"the next issue creation."
                )

                time.sleep(wait_seconds)

            # Check Actions capacity.
            wait_for_capacity(
                client,
                workflow_id,
            )

            # Check primary API rate-limit state.
            wait_for_rate_limit_if_needed(client)

            print(
                f"Creating issue: {title}"
            )

            issue = create_issue(
                client,
                package,
            )

            issue_number = issue["number"]
            issue_url = issue["html_url"]

            state["submissions"][title] = {
                "status": "created",
                "issue_number": issue_number,
                "issue_url": issue_url,
                "package": package["package"],
                "version": package["version"],
                "source_ver": package["source_ver"],
                "package_url": package["url"],
                "submitted_at": utc_now(),
            }

            save_state(state)

            last_submission_time = time.time()
            submitted_this_run += 1

            print()
            print(
                f"Created issue #{issue_number}: {issue_url}"
            )

            print(
                f"Progress: "
                f"{len(state['submissions'])}/"
                f"{len(state['packages'])}"
            )

            print(
                "State saved."
            )

    except KeyboardInterrupt:

        print()
        print()
        print("=" * 80)
        print("INTERRUPTED")
        print("=" * 80)
        print()
        print(
            "The persistent state has already been saved after every "
            "successful issue creation."
        )
        print()
        print(
            "Run the same command again to resume."
        )
        print()

        return

    print()
    print("=" * 80)
    print("RUN COMPLETE")
    print("=" * 80)
    print()
    print(
        f"Submitted during this invocation: {submitted_this_run}"
    )
    print(
        f"Total recorded submissions: "
        f"{len(state['submissions'])}"
    )
    print(
        f"Total packages in VIEWS snapshot: "
        f"{len(state['packages'])}"
    )
    print()

    if len(state["submissions"]) < len(state["packages"]):

        remaining = (
            len(state["packages"])
            - len(state["submissions"])
        )

        print(
            f"{remaining} package(s) remain."
        )

        print(
            "Run the script again to continue."
        )

    else:

        print(
            "All packages have been submitted or were already present "
            "as existing issues."
        )


if __name__ == "__main__":
    main()
