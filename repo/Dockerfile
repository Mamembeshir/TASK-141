# iOS builds require macOS + Xcode and cannot run inside a Linux container.
# This Dockerfile exists so Docker-based CI pipelines have a valid image to
# pull/build; the actual test suite runs on a macOS runner (see Makefile /
# run_tests.sh).  The container simply prints a notice and exits 0 so the
# Docker step is marked green without blocking the pipeline.

FROM alpine:3.20

LABEL maintainer="GreenGate CI"
LABEL description="Stub image — iOS builds run on macOS runners, not Docker."

RUN echo "iOS CI stub image built successfully."

CMD ["sh", "-c", \
  "echo ''; \
   echo '╔══════════════════════════════════════════════════════════╗'; \
   echo '║  GreenGate — iOS project                                ║'; \
   echo '║  Xcode builds require a macOS runner.                   ║'; \
   echo '║  This container is a CI placeholder that exits 0.       ║'; \
   echo '║  Real tests: xcodebuild / make test (macOS runner only) ║'; \
   echo '╚══════════════════════════════════════════════════════════╝'; \
   echo ''"]
