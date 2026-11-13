# quickdraw

A real 4D component for the supported QuickDraw PICT conversion and inspection
contract of [miyako/quickdraw-cli](https://github.com/miyako/quickdraw-cli).
The component starts a bundled **standalone executable**, not a 4D plug-in.
It does not implement a second interpreter, discover fonts, or use PATH tools.

```4d
var $converter : cs.QuickDraw.Converter
var $target : Text
$target:="macOS-universal"
If (Is Windows)
  $target:="Windows-x64"
End if
$converter:=cs.QuickDraw.Converter.new($target)
$result:=$converter.convert(File("/DATA/drawing.pict"); File("/DATA/drawing.png"))
If ($result.ok)
  // Retain/display every diagnostic, including unverified_fidelity.
  $diagnostics:=$result.value.diagnostics
Else
  ALERT($result.error.code+": "+$result.error.message)
End if
```

## API and fidelity

Namespace **QuickDraw**, class **Converter**, executable **quickdraw**.
`version()`, `capabilities()`, `inspect(input; options)`,
`listPictures(input; options)`, `listFonts(input; options)` and
`convert(input; output; options)` return structured process and protocol results.
See the [complete binding contract](component/quickdraw/Documentation/Classes/Converter.md).
The namespace is an independent choice; check collisions with other host components.

PNG, SVG and PDF outputs are supported within the CLI's documented limits.
Raw/standalone PICT, resource forks, MacBinary and AppleSingle/AppleDouble v2
have explicit input/selection controls. Vector preserve/raster policy, font map,
resource budgets, approximation and portable printer interpretation are explicit
options; no fallback or retry enables them automatically.

**Successful conversion is not classic pixel equivalence.** Preserve the original
PICT, exact fonts/maps, input/output hashes and all diagnostics. Portable NFNT,
TrueType/CFF outlines and the limited Apple printer profile are not historical
Mac rendering. Nonzero lineJustify, separate QuickTime mattes and other documented
unsupported semantics remain errors. Inspection is not a renderability promise.

Calls are synchronous with a **30-second process timeout** and closed stdin.
There is no cancellation, batch, interactive, stdin-image or background-worker API.
Do not assume failure proves no output was committed: the CLI can fail while
reporting after an atomic file commit. Never automatically retry a failed conversion.
The component never writes image bytes itself; the CLI enforces no-clobber and
input/font/source-alias protection, including with explicit `overwrite:true`.

## External asset provenance

`cli/asset-lock.json` is the sole upstream pin: exact source commit, independent
CLI version/tag, canonical release ZIP URLs and SHA256 digests for each ZIP,
manifest and executable. No expiring Actions artifact URL is a distribution pin.
**Until verified published pins are populated, acquisition fails explicitly.**
The initial development CI baseline is not accepted as a signed release.

The bounded `external-quickdraw-v1` adapter validates archive/member paths,
duplicates, file types, size budgets, complete inventories, every member hash,
source revision, protocol and Mach-O/PE executable architecture before extraction.
It carries all upstream licenses, runtime/dependency notices, Cargo.lock and
contract docs under `Resources/licenses/quickdraw-cli/{macos,windows}/`.
The macOS executable is a verified Developer ID-signed universal binary copied
byte-for-byte: **no lipo or re-signing**. Windows is x64, not ARM64.
Runtime calls check the selected executable hash against packaged provenance,
and first use probes CLI version/capabilities. Missing/mismatched assets fail;
there is no runtime download or alternative executable/revision.

Component versions are independent of CLI versions. Bump version changes only
component source metadata; it never rewrites upstream lockfiles or protocol
version assertions. `language:rust` records the upstream implementation language,
not a Rust build in this repository. The initializer-selected starter was removed.

## Build and acceptance

Python 3.10+ and the pinned workflow parser are developer requirements.
Install `tooling/requirements-workflow.txt` for `workflow-contract.json` validation.
Native component CI runs the locked executable and independent contract tests on
macOS ARM64, macOS x64 and Windows x64; it installs no Rust compiler.
`build-manifest.json` binds each native execution to component revision/input digest,
binary hash and the separate upstream revision. Universal assembly copies the
identical signed macOS input; altered or mixed-source manifests fail.

```sh
python3 scripts/workflow_contract.py --root .
python3 scripts/build_cli.py --root . --target macos-arm64
python3 -m unittest discover -s tests -p test_cli.py -v
python3 scripts/ci_config.py download-tool4d --root .
python3 scripts/accept_local.py --root . --repository miyako/quickdraw \
  --tool4d .tools/tool4d.app/Contents/MacOS/tool4d
```

Choose the actual native target for the import/test command. Local acceptance
imports all pinned assets, but foreign native execution remains `not_run`.
`--cross` is not supported for this adapter. Free pinned tool4d 20.7/101905
compiles the component on Apple Silicon without license activation or credentials.
The final ZIP is source-stripped and tested after unpacking through a real host;
compilation alone is not acceptance. Output is `dist/quickdraw.zip` with adjacent
`dist/quickdraw.acceptance.json`. Preserve this pair and fetched ZIP inputs outside
disposable worktrees before archiving.

Local acceptance is always `result:partial`, `release_ready:false`: it does not
establish native Intel/Windows 4D, IDE/Server loading or Dependency Manager
installation. The bundled CLI's signature does **not** sign or notarize the
component or compiler-generated Libraries. Component re-signing is deliberately
blocked rather than altering the pinned upstream executable.

CI remains nonpublishing. Optional hosted 4D inspection retains compiled ZIP and
evidence for 30 days with `FOURD_ENABLED=true`. Inherited **Bump version** and
**Build** retain source-only bump and immutable-SHA publication gates.
No component release, tags, PRs or signing configuration are authorized by this work.
Do not choose Follow 4D version for ordinary component SemVer.
Component tags are prefix-free (`"tag": "0.1.0"`), never `v0.1.0`;
upstream CLI tags are independent. The official
[Follow 4D convention](https://blog.4d.com/follow-4d-version-a-smarter-way-to-manage-your-dependencies/)
instead uses host-aligned LTS `20.2.3` or R `20R3.2`.
The inherited [user-owned credential guide](AGENTS.md#user-owned-credential-setup-and-reuse)
documents `scripts/set-release-secrets.sh`; do not run it for this unsigned
component acceptance or alter the already-signed upstream executable.

The original [MIT license](LICENSE) and [template playbook](AGENTS.md) are retained.
The external-asset adaptation above supersedes only the template's local
CLI-source build/lipo/version-coupling instructions, not its compilation,
package integrity, native testing, provenance or publication requirements.
