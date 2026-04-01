# AutoSDK + .NET 10 Upgrade Guide

This document describes the process for upgrading AutoSDK-generated repositories to the new AutoSDK version and .NET 10.

## Overview

The upgrade involves:
1. Target Framework: `net9.0` → `net10.0`
2. AutoSDK: `0.28.1-dev.75` → `0.28.1-dev.114`
3. Microsoft.OpenApi: v1.x → v3.x (with new API patterns)
4. Simplified library targeting (single TFM)
5. Removal of legacy polyfill packages

---

## Step-by-Step Changes

### 1. GitHub Actions Workflows

Update `.github/workflows/*.yml` files:

```diff
- dotnet-version: 9.0.x
+ dotnet-version: 10.0.x
```

**Files to check:**
- `.github/workflows/auto-update.yml`
- `.github/workflows/mkdocs.yml`
- `.github/workflows/dotnet.yml`

---

### 2. Helper Projects (FixOpenApiSpec, GenerateDocs, TrimmingHelper)

#### 2.1 Update Target Framework

```diff
- <TargetFramework>net9.0</TargetFramework>
+ <TargetFramework>net10.0</TargetFramework>
```

#### 2.2 Update FixOpenApiSpec Package References

```diff
- <PackageReference Include="Microsoft.OpenApi.Readers" Version="1.6.28" />
- <PackageReference Include="AutoSDK" Version="0.28.1-dev.75" />
+ <PackageReference Include="Microsoft.OpenApi" Version="3.3.0" />
+ <PackageReference Include="Microsoft.OpenApi.YamlReader" Version="3.3.0" />
+ <PackageReference Include="AutoSDK" Version="0.28.1-dev.114" />
```

#### 2.3 Update FixOpenApiSpec Program.cs

The Microsoft.OpenApi v3 has breaking API changes:

```diff
- using AutoSDK.Helpers;
+ using AutoSDK.Extensions;
+ using AutoSDK.Models;
  using Microsoft.OpenApi;
- using Microsoft.OpenApi.Extensions;
- using Microsoft.OpenApi.Models;
- using Microsoft.OpenApi.Readers;

  var path = args[0];
  var yamlOrJson = await File.ReadAllTextAsync(path);

- if (OpenApi31Support.IsOpenApi31(yamlOrJson))
- {
-     yamlOrJson = OpenApi31Support.ConvertToOpenApi30(yamlOrJson);
- }
-
- var openApiDocument = new OpenApiStringReader().Read(yamlOrJson, out var diagnostics);
+ var openApiDocument = yamlOrJson.GetOpenApiDocument(Settings.Default);
```

**Server configuration:**
```diff
- openApiDocument.Servers.Clear();
- openApiDocument.Servers.Add(new OpenApiServer
+ openApiDocument.Servers?.Clear();
+ openApiDocument.Servers?.Add(new OpenApiServer
```

**Security configuration (major change):**
```diff
- openApiDocument.SecurityRequirements = new List<OpenApiSecurityRequirement>
+ openApiDocument.Security = new List<OpenApiSecurityRequirement>
  {
      new()
      {
          {
-             new OpenApiSecurityScheme
-             {
-                 Reference = new OpenApiReference
-                 {
-                     Type = ReferenceType.SecurityScheme,
-                     Id = "APIKeyHeader"
-                 }
-             },
+             new OpenApiSecuritySchemeReference(referenceId: "APIKeyHeader", hostDocument: openApiDocument),
              new List<string>()
          }
      }
  };
```

**Serialization (now async, new spec version):**
```diff
- yamlOrJson = openApiDocument.SerializeAsYaml(OpenApiSpecVersion.OpenApi3_0);
- _ = new OpenApiStringReader().Read(yamlOrJson, out diagnostics);
-
- if (diagnostics.Errors.Count > 0)
- {
-     foreach (var error in diagnostics.Errors)
-     {
-         Console.WriteLine(error.Message);
-     }
-     Environment.Exit(1);
- }
+ yamlOrJson = await openApiDocument.SerializeAsYamlAsync(OpenApiSpecVersion.OpenApi3_2);
```

#### 2.4 TrimmingHelper - Remove ILLink Package

```diff
  <ItemGroup>
    <TrimmerRootAssembly Include="YourLib" />
  </ItemGroup>
```

---

### 3. Main Library Project

#### 3.1 Simplify Target Framework (Major Change)

Remove multi-targeting and switch to single .NET 10 target:

```diff
- <TargetFrameworks>netstandard2.0;net4.6.2;net8.0;net9.0</TargetFrameworks>
+ <TargetFramework>net10.0</TargetFramework>
```

#### 3.2 Remove Legacy Polyfill Packages

These are no longer needed with .NET 10:

```diff
- <ItemGroup>
-   <PackageReference Include="PolySharp" Version="1.15.0">
-     <PrivateAssets>all</PrivateAssets>
-     <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
-   </PackageReference>
-   <PackageReference Include="System.Text.Json" Version="10.0.2" />
- </ItemGroup>
```

---

### 4. Code Generation Script

Update `src/libs/{LibName}/generate.sh`:

```diff
  autosdk generate openapi.yaml \
    --namespace YourNamespace \
    --clientClassName YourClient \
-   --targetFramework net8.0 \
+   --targetFramework net10.0 \
    --output Generated \
    --exclude-deprecated-operations \
    --methodNamingConvention Summary
```

---

### 5. Test Projects

#### 5.1 Update Target Framework

```diff
- <TargetFramework>net9.0</TargetFramework>
+ <TargetFramework>net10.0</TargetFramework>
```

#### 5.2 Update FluentAssertions → AwesomeAssertions

```diff
  <ItemGroup Label="GlobalUsings">
    <Using Include="Microsoft.VisualStudio.TestTools.UnitTesting" />
-   <Using Include="FluentAssertions" />
+   <Using Include="AwesomeAssertions" />
  </ItemGroup>
```

#### 5.3 Add Parallel Test Execution (Optional)

```csharp
[assembly: Parallelize]
```

---

### 6. Documentation Updates

#### README.md

Remove .NET Framework/.NET Standard support mention if applicable:

```diff
  - All modern .NET features - nullability, trimming, NativeAOT, etc.
- - Support .Net Framework/.Net Standard 2.0
```

#### LICENSE

Update copyright year if needed.

---

## Checklist

Use this checklist when applying the upgrade:

- [ ] `.github/workflows/*.yml` - Update dotnet-version to 10.0.x
- [ ] `src/helpers/FixOpenApiSpec/FixOpenApiSpec.csproj` - Update TFM and packages
- [ ] `src/helpers/FixOpenApiSpec/Program.cs` - Update to new Microsoft.OpenApi v3 API
- [ ] `src/helpers/GenerateDocs/GenerateDocs.csproj` - Update TFM
- [ ] `src/helpers/TrimmingHelper/TrimmingHelper.csproj` - Update TFM, remove ILLink
- [ ] `src/libs/{LibName}/{LibName}.csproj` - Single TFM, remove polyfills
- [ ] `src/libs/{LibName}/generate.sh` - Update targetFramework
- [ ] `src/tests/IntegrationTests/*.csproj` - Update TFM and assertions library
- [ ] `README.md` - Remove legacy .NET support mention
- [ ] `LICENSE` - Update year if needed

---

## Breaking Changes Summary

| Component | Before | After |
|-----------|--------|-------|
| Library TFM | Multi-target (netstandard2.0, net4.6.2, net8.0, net9.0) | Single (net10.0) |
| Microsoft.OpenApi | v1.6.x (Readers package) | v3.3.0 (separate YamlReader) |
| OpenAPI Spec Output | OpenApi3_0 | OpenApi3_2 |
| OpenApiStringReader | Sync, manual diagnostics | Extension method, Settings-based |
| SecurityRequirements | Property with OpenApiSecurityScheme | Security property with OpenApiSecuritySchemeReference |
| SerializeAsYaml | Sync method | Async method (SerializeAsYamlAsync) |
| PolySharp | Required for polyfills | Not needed |
| System.Text.Json | Explicit package reference | Built into runtime |
| FluentAssertions | Used in tests | AwesomeAssertions |

---

## Notes

- The OpenApi31Support helper is no longer needed - the new Microsoft.OpenApi v3 handles all versions natively
- Diagnostic error checking is now internal to the library
- The `hostDocument` parameter is required for security scheme references in v3
- Consider running tests after upgrade to verify API compatibility
