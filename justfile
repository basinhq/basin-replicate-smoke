# Keep recipe logic here when it is about 10 lines or fewer. Use bin/ for
# longer scripts or logic shared by multiple recipes. Recipes may use Bash.
set shell := ["bash", "-euo", "pipefail", "-c"]

# The CLI under test comes from a local binary when `cli` is set, and otherwise
# from the published pack image at `image`, or at `tag` of the default pack
# repository. Set one on the command line, for example:
#   just cli=/path/to/basin-replicate smoke
#   just tag=v0.4.0 e2e
cli := env_var_or_default("BASIN_TEST_CLI", "")
image := env_var_or_default("BASIN_CLI_IMAGE", "")
tag := env_var_or_default("BASIN_CLI_TAG", "latest")
scale := env_var_or_default("BASIN_ACCEPTANCE_TEST_SCALE", "l")

export BASIN_TEST_CLI := cli
export BASIN_CLI_IMAGE := image
export BASIN_CLI_TAG := tag
export BASIN_ACCEPTANCE_TEST_SCALE := scale

_default:
    @just --list

# The two quickest end-to-end checks.
smoke:
    bin/docker-acceptance smoke

# The normal end-to-end suite.
e2e:
    bin/docker-acceptance e2e

# Every end-to-end scenario, including scale and long-running coverage.
e2e-full:
    bin/docker-acceptance e2e-full

# One scenario by name.
scenario name:
    bin/docker-acceptance scenario {{ name }}

# One shard of an end-to-end suite: smoke, e2e, or e2e-full.
shard suite index total:
    BASIN_ACCEPTANCE_PROJECT=basin-acceptance-{{ index }} \
      bin/docker-acceptance {{ suite }} --shard {{ index }}/{{ total }}

# One shard of a named scenario group, such as scale.
shard-scenario name index total:
    BASIN_ACCEPTANCE_PROJECT=basin-acceptance-{{ index }} \
      bin/docker-acceptance scenario {{ name }} --shard {{ index }}/{{ total }}

# Unit tests for the Ruby code in lib/. These do not run Basin or databases.
unit:
    bin/docker-test

# Remove this repository's containers, volumes, images, downloaded CLI, and reports.
clean:
    if docker image inspect basin-acceptance-runner:latest >/dev/null 2>&1; then \
      docker compose --file compose.yml run --rm --no-deps --user root runner \
        sh -c 'find /acceptance/fixture-cache /acceptance/artifacts -mindepth 1 -delete 2>/dev/null || true'; \
    fi
    docker compose --file compose.yml down --volumes --remove-orphans
    docker compose --file compose.yml config --images | sort -u | xargs -r docker image rm 2>/dev/null || true
    find .tmp artifacts -depth -delete 2>/dev/null || true
