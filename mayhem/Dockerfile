# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) for TkTech/pysimdjson — builds ON TOP of the org base image
# (ghcr.io/mayhemheroes/base), which provides debian + clang/llvm + Python 3.13 + the build
# identities + the build-contract ENV.
#
# This is a Python (Atheris) target with a Cython/C++ native extension (csimdjson wrapping the
# vendored simdjson amalgamation). The base has no PyPI deps, so we bake a WHEELHOUSE here (online,
# once) and mayhem/build.sh installs from it with --no-index — so the air-gapped PATCH re-run
# (docker run --network none ... bash mayhem/build.sh) never reaches the network (SPEC §6.5).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t pysimdjson-commit:test .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an empty value
# breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Sanitizer override: declared WITHOUT a default so an unset arg lets the base ENV flow through.
ARG SANITIZER_FLAGS

# ── Bake the Python wheelhouse (ONLINE, root) so build.sh installs OFFLINE (air-gapped re-run) ──────
# atheris = the fuzzing engine; setuptools+Cython = pysimdjson's PEP-517 build backend
# (pyproject.toml build-system); pytest/pytest-benchmark (+numpy for test_numpy.py) run the
# project's own test suite in mayhem/test.sh.
# PYTHONUSERBASE pins `pip install --user` (atheris + the built csimdjson extension) to a
# $HOME-independent, world-readable path (SPEC §6.2 item 8): rlenv runs the target as another
# identity with another HOME, and /home/mayhem is 0700.
ENV WHEELHOUSE=/opt/toolchains/python/wheelhouse \
    PYTHONUSERBASE=/opt/toolchains/python/userbase
USER root
# The csimdjson native extension needs the CPython dev headers (Python.h), which the base image
# does not ship. Pinned to the base's apt snapshot for reproducibility.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends python3-dev && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir -p "$WHEELHOUSE" && \
    python3 -m pip download --dest "$WHEELHOUSE" \
        'atheris==3.1.0' 'setuptools>=74.1' 'Cython' 'wheel' \
        'pytest' 'pytest-benchmark' 'numpy' 'orjson' && \
    mkdir -p "$PYTHONUSERBASE" && chown 2000:2000 "$PYTHONUSERBASE" && \
    chmod -R a+rX /opt/toolchains
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git history) is
# copied to /mayhem; build.sh builds in place.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh && chmod -R a+rX "$PYTHONUSERBASE"

# Run the behavioral oracle at build time (a failing suite fails the image build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
