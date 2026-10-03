# SDK Dependency Policy

## Default for SDK runtime code

New SDKs and new runtime dependencies must use the .NET platform, official
Microsoft packages, or explicitly identified first-party tryAGI/HavenDV packages.
Prefer the platform APIs available in .NET 10 and later over additional packages.

Official Google and AWS packages are permitted for their service integrations.
Their required transitive dependencies must be inventoried and reviewed as part
of the integration; this permission does not extend to unrelated third-party
packages merely used alongside them.

The rule covers the complete dependency graph, including dependencies introduced
by our own packages, local project references, vendored source, native libraries,
and binaries embedded in a NuGet package. An owned wrapper or fork does not change
the provenance of upstream code. Package names and publisher metadata alone do
not establish ownership or trust.

`PrivateAssets="all"` controls dependency propagation. It does not establish that
a package is used only during compilation or that runtime code is independent of
it. Inspect runtime usage and the produced package before making that claim.

## Integrations and existing exceptions

- LangChain's document loaders, database integrations, and provider adapters are
  expected to depend on the libraries they integrate with. Keep those dependencies
  explicit in their respective packages and documentation. Do not describe these
  packages or a meta-package including them as having no external dependencies.
- The Google HTTP transport adapter in AutoSDK is a separate package,
  `tryAGI.Extensions.HttpClientFactory`. Its `Google.Apis.Core` dependency is
  permitted by the Google integration rule. The generator does not need to acquire
  that dependency, nor should generated clients acquire it implicitly.
- SIPSorcery in DId.Realtime and Simli is an existing dependency being replaced in
  separate work. This policy does not authorize adding it to other SDKs.
- Other existing third-party dependencies, including Gonka's cryptography package
  and native libraries in OpusSharp, SpeexDspSharp, and HeifSharp, remain explicit
  migration or review items. Their presence is not an approval for new uses.

Before adding an exception, record its package or upstream source, purpose,
version or source revision, complete transitive graph, license, review owner,
and reason the permitted alternatives do not meet the requirement. Obtain the
maintainer's approval. A favorable license alone does not establish security.

## Build, generation, analyzers, and tests

Track these dependencies separately from consumer runtime dependencies. Existing
tools such as MinVer, PolySharp, Grpc.Tools, Testcontainers, and assertion/test
libraries are tooling dependencies, not evidence that every SDK passes the
runtime rule. Keep the tooling set minimal and explicitly document additions
and their provenance. Avoid moving a runtime dependency into this category only
by changing its NuGet metadata.

Third-party build or test tooling remains in the workspace. Do not claim the
entire build or supply chain is free of external dependencies.

## Verification and public claims

Evaluate imported and central package declarations for every supported target
framework. Inspect a freshly restored transitive graph and the produced NuGet
package, including native runtime assets. Report missing resolution, stale assets,
and unknown provenance as gaps rather than a successful compliance result.

This is the adopted development policy. Automated enforcement is future work;
the existence of this document does not certify that every existing package is
compliant or that any dependency has passed a security audit.

## Retired repositories

Remove Dependabot configuration and resolve open bot update PRs before archiving
an unused repository. Disable its maintenance and publishing workflows. Preserve
the repository and published packages for historical consumers, mark retirement
in its README and workspace catalog, and leave external human proposals for
explicit maintainer review.

## Recorded reviews and native baselines

Gonka's [cryptography dependency review](Gonka/DEPENDENCY_REVIEW.md) explains
why platform cryptography is not currently a portable drop-in replacement and
records the no-cost capability/vector checks.

OpusSharp, SpeexDspSharp, and HeifSharp each retain `NATIVE_PROVENANCE.json` and
`NATIVE_PROVENANCE.md` in their repository and NuGet package. Verify their binary
and source-input baselines from this workspace with:

```sh
python3 scripts/verify-native-provenance.py OpusSharp SpeexDspSharp HeifSharp
```

Use `--require-complete` to also fail on historical build-attestation gaps. A
matching recorded hash is an integrity result, not proof of a reviewed or
reproducible upstream build. These checks have not been added to CI yet.
