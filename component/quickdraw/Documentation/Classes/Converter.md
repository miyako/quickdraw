# Converter

`cs.QuickDraw.Converter.new(target)` wraps the independently versioned, pinned
Rust quickdraw-cli executable. This is not a plug-in.
`target` is `"macOS-universal"` (or omitted on macOS) or explicitly
`"Windows-x64"` on Windows. Native Windows ARM64 is unsupported.

| Method | Protocol-1 value |
| --- | --- |
| `version()` | `{protocol:1,version:"0.1.0"}` (CLI version, not component version) |
| `capabilities()` | Entire capability object, including fidelity and unsupported boundaries |
| `inspect(input; options)` | `{protocol:1,inspection:{...}}` |
| `listPictures(input; options)` | `{protocol:1,inventory:{container,pictures:[...]}}` |
| `listFonts(input; options)` | `{protocol:1,inventory:{container,resources:[...]}}` |
| `convert(input; output; options)` | Complete output metadata, hashes, profiles and diagnostics |

Inputs/outputs/font-map paths are nonempty Text or `4D.File`, never Folder or
plain Object. File objects are expanded to native paths. **Use File objects or
absolute paths**: relative Text paths resolve in the bundled executable's parent,
not the host data directory. Unicode, quotes and shell punctuation are literal
arguments. NUL is rejected before launching. Options are an optional Object
(omitted/Null means no options). Property names are the exact CLI long-option
names **without `--`**. Unknown keys, wrong types and wrong operation scope fail.
Options are not silently renamed, dropped, defaulted or coerced.

| Options | Type and operations |
| --- | --- |
| `container` | Text: auto/raw/file/resource-fork/macbinary/appledouble/applesingle; every input operation |
| `max-input-bytes`, `max-pixels`, `max-decoded-bytes`, `max-operations`, `max-work` | Integer Number or decimal integer Text; every input operation |
| `resource-id` | Signed integer Number/Text; inspect/convert |
| `data-fork` | Boolean; inspect/convert; mutually exclusive with resource-id in the CLI |
| `format` | Text png/svg/pdf; convert |
| `fidelity` | Text strict/approximate; convert |
| `printer-comments` | Text ignore/apple-portable; convert |
| `vector-policy` | Text reject/preserve/raster; convert |
| `width`, `height` | Positive integer Number/Text; convert |
| `dpi` | Finite decimal Number/Text; convert |
| `background`, `highlight` | Six hexadecimal digits as Text, without #; convert |
| `font-map` | Text/File path to schema-1 map; convert |
| `overwrite` | Boolean; convert; false does not pass the flag |

Decimal Text avoids precision loss when expressing large CLI integer budgets.
Numeric serialization is locale-independent JSON, never localized `String()`.
The CLI validates positive limits, signed ID ranges, enums, DPI, mutually
exclusive options, format suffixes and incompatible policy combinations.
Invalid CLI semantics retain their genuine converter error instead of being
invented by the wrapper. No extra precision is promised for a rounded 4D Number.

```4d
$options:=New object("format"; "svg"; "vector-policy"; "preserve")
$result:=$converter.convert($inputFile; $svgFile; $options)

$options:=New object("container"; "macbinary"; "resource-id"; -128)
$result:=$converter.inspect($archiveFile; $options)

$options:=New object("fidelity"; "approximate"; "font-map"; $mapFile)
$options["printer-comments"]:="apple-portable"
$result:=$converter.convert($inputFile; $pngFile; $options)
```

No options means the CLI's defaults: auto container, strict fidelity, ignored
printer comments, vector reject, no overwrite, dimensions from the frame,
72 DPI and white background. Budgets default to 67108864 input bytes, 16000000
pixels, 134217728 decoded bytes, 100000 operations and 100000000 work units.
These are CLI defaults, not a component RSS limit. Font maps are supplied
explicitly; the component does not generate, rewrite, download or guess fonts,
encodings, styles or map bindings.

## Results and failures

Success: `{ok:true,stdout:Text,stderr:"",exitCode:0,value:Object}`.
`value` retains the **entire** JSON object and every additive field and diagnostic.
Conversion results include `output`, `format`, positive dimensions/bytes/DPI,
`input_sha256`, `sha256`, raster/vector/outline profiles, `resource_id`,
`printer_comments` and `diagnostics`.
Display and preserve `unverified_fidelity` even in strict mode.
Raster fallback and approximation require explicit user options; no automatic
retry, pixel-equivalence promise, alternate font or encoding exists.

Failures have `ok:false`, `error:{code,message,...}` and `failureKind`:

| failureKind | Meaning |
| --- | --- |
| `argument` | Invalid 4D argument/path/option type or unsupported option key; no launch or exitCode |
| `asset` | Packaged provenance is absent or executable/version mismatches the lock |
| `process` | Missing resource/platform, launch, system error or abnormal termination/timeout |
| `protocol` | Malformed envelope/framing/required field/status-code pairing; never success |
| `converter` | Valid nonzero CLI outcome, with the exact error, offset/opcode and additive fields retained in `error` and `value` |

Process stdout/stderr/exitCode are retained when available. Prelaunch failures
never fabricate exit codes. Converter exit codes: 2 invalid_arguments;
3 io/output_exists/output_conflict; 4 malformed; 5 unsupported; 6 resource_limit;
7 encoding. A malformed stderr error envelope is a protocol failure, not a
converter success. There is no automatic recovery. Original output/no-clobber
and source/font/hard-link alias safeguards remain the CLI's responsibility.

Every process closes stdin and has a finite 30-second timeout. This API is
synchronous; no cancellation or shared PID state is exposed. A process failure
may occur after an output commit; inspect retained evidence before any manual retry.
Do not infer that inspection success implies renderability. Nonzero lineJustify
and separate QuickTime mattes remain unsupported. Portable NFNT/TrueType/CFF and
Apple printer interpretation are not classic Mac pixel equivalence.

The class verifies the native executable's SHA256 against
`Resources/quickdraw-assets.json` before invocation; a fresh converter also
probes version/capabilities before an input operation. Resource installation and
packaging separately authenticate the full upstream archive and notices.
`_cli`, `_decode`, `_checkAsset`, `_arguments` and other underscore members
are internal by convention, not an access-control boundary.
