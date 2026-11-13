# _CLI (internal convention)

`resolve()` returns `{ok:true,file:4D.File}` for the validated bundled resource,
or the same prelaunch error envelope as `execute()`. It never starts a process.
The feature class uses this to verify the external executable hash before launch. (internal convention)

`cs._CLI.new(executableName : Text; target : Text)` is the reusable bundled
executable resolver. The host can technically access `cs.QuickDraw._CLI`;
underscore naming is not true private access in 4D.

This resolves a standalone CLI for separate-process execution, not a native
4D plug-in. A plug-in must be installed in the host; this resolver and component
packaging cannot privately load/deploy it or satisfy that installation requirement.

`execute(arguments : Collection) : Object` selects `/RESOURCES/bin/macOS/<name>`
or `/RESOURCES/bin/Windows/<name>.exe`, checks existence, expands the virtual
File to a physical path using `File(file.platformPath; fk platform path)`, then
delegates to `_Process`. There is deliberately no PATH search, permission repair,
shell, download, copied PDF algorithm or queue.

macOS default/`macOS-universal` uses the two-slice executable. Windows requires
explicit `Windows-x64`. Unknown selection or OS returns an explicit error;
Windows ARM64 native execution is not implemented. See [Converter](Converter.md)
for the common result/error shape.

The read-only `compiled` Boolean evaluates `Is compiled mode` inside the
component. The release host fixture uses it to reject an interpreted fallback.
