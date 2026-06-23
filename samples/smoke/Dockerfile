# Minimal runtime image used only by the sample smoke tests (samples/smoke-test.sh).
# Release images are built by JReleaser; this Dockerfile exists so the smoke test
# can boot a Korvet image from the current source without the Paketo buildpack's
# Syft step, which downloads a binary from GitHub at build time and is rate-limit
# flaky in CI. Build context is the repository root; run
# `:korvet-cli:installDist` first so the application-plugin launcher and libs
# exist under korvet-cli/build/install/korvet/.
FROM eclipse-temurin:25-jre
WORKDIR /opt/korvet
COPY korvet-cli/build/install/korvet/ ./
EXPOSE 8080 9092
ENTRYPOINT ["/opt/korvet/bin/korvet"]
CMD ["server"]
