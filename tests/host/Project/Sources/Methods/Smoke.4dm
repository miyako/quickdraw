//%attributes = {"invisible":true}
var $ignored : Integer
var $parameter; $name; $target; $folderPath; $format; $policy : Text
var $inputHash : Text
var $request; $result; $report; $options : Object
var $tool : cs.QuickDraw.Converter
var $requestFile; $statusFile; $renamedExecutable; $input; $output : 4D.File
var $fixtures : 4D.Folder
var $invalid : Variant
var HOST_StatusFile : 4D.File
var HOST_Phase : Text
var HOST_PreviousHandler : Text
$ignored:=Get database parameter(User param value; $parameter)
If (Is Windows)
	$requestFile:=File($parameter; fk platform path)
Else
	$requestFile:=File($parameter; fk posix path)
End if
$request:=JSON Parse($requestFile.getText())
If (Is Windows)
	$statusFile:=File($request.status; fk platform path)
	$renamedExecutable:=File($request.executable; fk platform path)
Else
	$statusFile:=File($request.status; fk posix path)
	$renamedExecutable:=File($request.executable; fk posix path)
End if
$statusFile.setText("{\"success\":false,\"phase\":\"starting\"}")
HOST_StatusFile:=$statusFile
HOST_Phase:="constructor"
HOST_PreviousHandler:=Method called on error(ek local)
ON ERR CALL("Host_error"; ek local)
$target:="macOS-universal"
If (Is Windows)
	$target:="Windows-x64"
End if
$tool:=cs.QuickDraw.Converter.new($target)
$fixtures:=$requestFile.parent.folder("Resources")
$input:=$fixtures.file("rectangle.pict")
$inputHash:=Lowercase(Generate digest($input.getContent(); SHA256 digest))
$report:=New object("success"; True; "finished"; False; "cases"; New collection)
$report.outputChecks:=New collection
$report.compiled:=$tool._cli.compiled
$report.renamedExecutable:=cs.QuickDraw._Process.new().execute($renamedExecutable; New collection("--version"))
HOST_Phase:="feature cases"
For each ($name; New collection("png"; "svg-preserve"; "pdf-preserve"; "svg-raster"; "pdf-raster"))
	$format:=Substring($name; 1; 3)
	$options:=New object("format"; $format)
	If ($format#"png")
		$options["vector-policy"]:=Substring($name; 5)
	End if
	$output:=$requestFile.parent.file($name+" 日本語 ' ; & output."+ $format)
	$result:=$tool.convert($input; $output; $options)
	$report.cases.push($result)
	If ($result.ok)
		$report.outputChecks.push(Lowercase(Generate digest($output.getContent(); SHA256 digest))=$result.value.sha256)
	Else
		$report.outputChecks.push(False)
	End if
End for each
$report.version:=$tool.version()
$report.capabilities:=$tool.capabilities()
$report.inspection:=$tool.inspect($input; New object("container"; "raw"; "data-fork"; True))
$report.inventory:=$tool.listPictures($input)
$report.fontInventory:=$tool.listFonts($fixtures.file("fonts.rsrc"); New object("container"; "resource-fork"))
$report.invalid:=$tool.convert($input; $requestFile.parent.file("bad.png"); New object("dpi"; 0))
$report.unsupportedFeature:=$tool.convert($fixtures.file("text.pict"); $requestFile.parent.file("text.png"))
$report.malformed:=$tool.inspect($fixtures.file("malformed.pict"))
$report.limit:=$tool.convert($input; $requestFile.parent.file("limit.png"); New object("max-pixels"; 1))
$report.strict:=$tool.convert($fixtures.file("oval.pict"); $requestFile.parent.file("strict.png"))
$report.approximate:=$tool.convert($fixtures.file("oval.pict"); $requestFile.parent.file("oval.png"); New object("fidelity"; "approximate"))
If ($report.approximate.ok)
	$report.approximationWarning:=$report.approximate.value.diagnostics.query("code = :1"; "approximation").length>0
End if
$report.noClobber:=$tool.convert($input; $output; $options)
$report.alias:=$tool.convert($input; $input; New object("format"; "png"; "overwrite"; True))
$report.selection:=$tool.inspect($input; New object("data-fork"; True; "resource-id"; 1))
$report.missingInput:=$tool.inspect(Null)
$report.assetMissing:=$tool._checkAsset($renamedExecutable; $fixtures.file("missing-asset-metadata.json"))
$report.assetMismatch:=$tool._checkAsset($requestFile; $tool._cli.resolve().file.parent.parent.parent.file("quickdraw-assets.json"))
$report.badOption:=$tool.inspect($input; New object("fidelity"; "approximate"))
$options:=New object("container"; "raw"; "width"; 16; "height"; 24; "dpi"; 144.5; "background"; "112233"; "highlight"; "abcdef"; "font-map"; $fixtures.file("font-map.json"); "printer-comments"; "ignore")
$options["max-input-bytes"]:="67108864"
$options["max-pixels"]:=16000000
$options["max-decoded-bytes"]:=134217728
$options["max-operations"]:=100000
$options["max-work"]:=100000000
$report.options:=$tool.convert($input; $requestFile.parent.file("options.png"); $options)
HOST_Phase:="missing executable"
$report.missing:=cs.QuickDraw._CLI.new("missing-cli"; $target).execute(New collection("--version"))
$report.unsupported:=cs.QuickDraw.Converter.new("unsupported-arm-target").version()
HOST_Phase:="launch failure"
$report.launch:=cs.QuickDraw._Process.new().execute($requestFile; New collection)
HOST_Phase:="malformed protocol"
$report.protocol:=$tool._decode(New object("ok"; True; "stdout"; "not json"; "stderr"; ""; "exitCode"; 0); "version")
$report.protocolTypes:=New collection
For each ($name; New collection("{\"protocol\":true,\"version\":\"invalid\"}\n"; "{\"protocol\":false,\"version\":\"invalid\"}\n"))
	$report.protocolTypes.push($tool._decode(New object("ok"; True; "stdout"; $name; "stderr"; ""; "exitCode"; 0); "version"))
End for each
$report.protocolNull:=$tool._decode(New object("ok"; True; "stdout"; "{\"protocol\":null,\"version\":\"invalid\"}\n"; "stderr"; ""; "exitCode"; 0); "version")
$report.protocolScalars:=New collection
For each ($name; New collection("true\n"; "false\n"; "null\n"; "1\n"; "[]\n"))
	$report.protocolScalars.push($tool._decode(New object("ok"; True; "stdout"; $name; "stderr"; ""; "exitCode"; 0); "version"))
End for each
$report.protocolFailure:=$tool._decode(New object("ok"; False; "error"; New object("code"; "cli_error"); "stdout"; ""; "stderr"; "{\"protocol\":1,\"error\":{\"code\":\"malformed\",\"message\":\"bad\"}}\n"; "exitCode"; 5); "convert")
$report.preservedError:=$tool._decode(New object("ok"; False; "error"; New object("code"; "cli_error"); "stdout"; ""; "stderr"; "{\"protocol\":1,\"error\":{\"code\":\"unsupported\",\"message\":\"matte\",\"offset\":40,\"opcode\":33280,\"future\":\"retained\"}}\n"; "exitCode"; 5); "convert")
$report.terminated:=$tool._decode(New object("ok"; False; "stdout"; ""; "stderr"; ""; "error"; New object("code"; "process_terminated"; "message"; "timeout")); "convert")
HOST_Phase:="File argument"
$report.fileArgument:=cs.QuickDraw._CLI.new("quickdraw"; $target).execute(New collection("inspect"; "--input"; $input))
$report.rejectedArguments:=New collection
$report.rejectedOptions:=New collection
HOST_Phase:="scalar arguments"
For each ($invalid; New collection(123; 1.25; True; False; Null; Current date; Current time; New collection; New object))
	$result:=cs.QuickDraw._Process.new().execute($requestFile; New collection($invalid))
	$report.rejectedArguments.push(New object("type"; Value type($invalid); "result"; $result))
End for each
For each ($invalid; New collection(123; True; "text"; New collection))
	$report.rejectedOptions.push($tool.inspect($input; $invalid))
End for each
$report.rejectedNul:=New collection
HOST_Phase:="NUL arguments"
For each ($name; New collection(Char(0)+"prefix"; "middle"+Char(0)+"suffix"; "trailing"+Char(0)))
	$report.rejectedNul.push(cs.QuickDraw._Process.new().execute($requestFile; New collection($name)))
End for each
$report.missingFile:=cs.QuickDraw._Process.new().execute(Null; New collection)
$report.missingArguments:=cs.QuickDraw._Process.new().execute($requestFile; Null)
HOST_Phase:="Folder argument"
$report.folderArgument:=cs.QuickDraw._CLI.new("quickdraw"; $target).execute(New collection("convert"; "--input"; $input; "--output"; $output; "--dpi"; $requestFile.parent))
$folderPath:=$requestFile.parent.path
If (Is Windows)
	$folderPath:=$requestFile.parent.platformPath
End if
$report.folderRoundTrip:=Position($folderPath; $report.folderArgument.stderr; *)>0
$report.inputPreserved:=Lowercase(Generate digest($input.getContent(); SHA256 digest))=$inputHash
$report.finished:=True
ON ERR CALL(HOST_PreviousHandler; ek local)
$statusFile.setText(JSON Stringify($report))
HOST_StatusFile:=Null
HOST_Phase:=""
HOST_PreviousHandler:=""
QUIT 4D
