//%attributes = {"invisible":true}
var $parameter; $stream : Text
var $ignored : Integer
var $tool : cs.QuickDraw.Converter
var $status : 4D.File
var $report; $options; $result : Object
var $value : Variant
var HOST_StatusFile : 4D.File
var HOST_Phase; HOST_PreviousHandler : Text
$ignored:=Get database parameter(User param value; $parameter)
If (Is Windows)
	$status:=File($parameter; fk platform path)
Else
	$status:=File($parameter; fk posix path)
End if
$status.setText("{\"finished\":false}")
HOST_StatusFile:=$status
HOST_Phase:="binding unit"
HOST_PreviousHandler:=Method called on error(ek local)
ON ERR CALL("Host_error"; ek local)
$tool:=cs.QuickDraw.Converter.new("")
$report:=New object("finished"; False; "compiled"; $tool._cli.compiled; "argumentFailures"; New collection; "protocolFailures"; New collection)
For each ($value; New collection(123; 1.25; True; False; Current date; Current time; New collection))
	$report.argumentFailures.push($tool._arguments("inspect"; $status; Null; $value))
End for each
For each ($value; New collection(123; 1.25; True; False; Null; Current date; Current time; New collection; New object; $status.parent))
	$report.argumentFailures.push($tool._arguments("inspect"; $value; Null; Null))
End for each
For each ($value; New collection(123; 1.25; True; False; Null; Current date; Current time; New collection; New object))
	$report.argumentFailures.push($tool._arguments("convert"; $status; $value; Null))
End for each
$report.argumentFailures.push($tool._arguments("inspect"; $status; Null; New object("fidelity"; "approximate")))
$report.argumentFailures.push($tool._arguments("inspect"; $status; Null; New object("data-fork"; "true")))
$report.argumentFailures.push($tool._arguments("inspect"; "a"+Char(0)+"b"; Null; Null))
$report.argumentFailures.push($tool._arguments("convert"; $status; $status; New object("dpi"; True)))
$report.argumentFailures.push($tool._arguments("convert"; $status; $status; New object("font-map"; $status.parent)))
$report.argumentFailures.push($tool._arguments("convert"; $status; $status; New object("width"; 1.5)))
$report.argumentFailures.push($tool._arguments("convert"; $status; $status; New object("format"; "p"+Char(0)+"ng")))
$report.defaultArguments:=$tool._arguments("inspect"; "/tmp/space 日本語 \" quote.pict"; Null; Null)
$options:=New object("container"; "raw"; "resource-id"; -128; "data-fork"; False; "format"; "png"; "fidelity"; "approximate"; "printer-comments"; "apple-portable"; "vector-policy"; "reject"; "width"; 16; "height"; 24; "dpi"; 144.5; "background"; "112233"; "highlight"; "abcdef"; "font-map"; "/tmp/font map.json"; "overwrite"; True)
$options["max-input-bytes"]:="18446744073709551615"
$options["max-pixels"]:=16000000
$options["max-decoded-bytes"]:=134217728
$options["max-operations"]:=100000
$options["max-work"]:=100000000
$report.options:=$tool._arguments("convert"; "/tmp/input.pict"; "/tmp/output.png"; $options)
For each ($stream; New collection("not json"; "true\n"; "null\n"; "[]\n"; "{\"protocol\":true,\"version\":\"x\"}\n"; "{\"protocol\":null,\"version\":\"x\"}\n"; "{\"protocol\":2,\"version\":\"x\"}\n"; "{\"protocol\":1,\"version\":3}\n"; "{\"protocol\":1,\"version\":\"x\"}"; "{\"protocol\":1,\"version\":\"x\"}\n{}\n"))
	$report.protocolFailures.push($tool._decode(New object("ok"; True; "stdout"; $stream; "stderr"; ""; "exitCode"; 0); "version"))
End for each
$report.version:=$tool._decode(New object("ok"; True; "stdout"; "{\"protocol\":1,\"version\":\"0.1.0\",\"future\":\"preserved\"}\n"; "stderr"; ""; "exitCode"; 0); "version")
$report.converterFailure:=$tool._decode(New object("ok"; False; "error"; New object("code"; "cli_error"); "stdout"; ""; "stderr"; "{\"protocol\":1,\"error\":{\"code\":\"unsupported\",\"message\":\"matte\",\"offset\":40,\"opcode\":33280,\"future\":\"retained\"}}\n"; "exitCode"; 5); "convert")
$report.mismatchedFailure:=$tool._decode(New object("ok"; False; "error"; New object("code"; "cli_error"); "stdout"; ""; "stderr"; "{\"protocol\":1,\"error\":{\"code\":\"malformed\",\"message\":\"bad\"}}\n"; "exitCode"; 5); "convert")
If (Is macOS)
	HOST_Phase:="real SystemWorker timeout"
	$report.timeout:=cs.QuickDraw._Process.new().execute(File("/bin/sleep"; fk posix path); New collection("31"))
End if
$report.finished:=True
ON ERR CALL(HOST_PreviousHandler; ek local)
$status.setText(JSON Stringify($report))
QUIT 4D
