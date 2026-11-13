property _cli : cs._CLI
property _capabilities : Object

Class constructor($target : Text)
	This._cli:=cs._CLI.new("quickdraw"; $target)

Function version()->$result : Object
	$result:=This._invoke(New collection("--version"); "version")

Function capabilities()->$result : Object
	$result:=This._invoke(New collection("capabilities"); "capabilities")
	If ($result.ok)
		This._capabilities:=$result.value
	End if

Function inspect($input : Variant; $options : Variant)->$result : Object
	$result:=This._run("inspect"; $input; Null; $options)

Function listPictures($input : Variant; $options : Variant)->$result : Object
	$result:=This._run("list-pictures"; $input; Null; $options)

Function listFonts($input : Variant; $options : Variant)->$result : Object
	$result:=This._run("list-fonts"; $input; Null; $options)

Function convert($input : Variant; $output : Variant; $options : Variant)->$result : Object
	$result:=This._run("convert"; $input; $output; $options)

Function _run($command : Text; $input : Variant; $output : Variant; $options : Variant)->$result : Object
	var $probe : Object
	$result:=This._arguments($command; $input; $output; $options)
	If ($result.ok)
		If (This._capabilities=Null)
			$probe:=This.version()
			If (Not($probe.ok))
				return $probe
			End if
			$probe:=This.capabilities()
			If (Not($probe.ok))
				return $probe
			End if
		End if
		$result:=This._invoke($result.arguments; $command)
	End if

Function _invoke($arguments : Collection; $command : Text)->$result : Object
	var $resolved; $checked : Object
	$resolved:=This._cli.resolve()
	If (Not($resolved.ok))
		$resolved.failureKind:="process"
		return $resolved
	End if
	$checked:=This._checkAsset($resolved.file; Folder("/RESOURCES").file("quickdraw-assets.json"))
	If (Not($checked.ok))
		return $checked
	End if
	$result:=This._decode(cs._Process.new().execute($resolved.file; $arguments); $command)
	If ($result.ok & (($command="version") | ($command="capabilities")))
		If ($result.value.version#$checked.version)
			$result.ok:=False
			$result.failureKind:="asset"
			$result.error:=New object("code"; "asset_mismatch"; "message"; "CLI version differs from verified release metadata")
		End if
	End if

Function _checkAsset($binary : 4D.File; $metadata : 4D.File)->$result : Object
	var $lock; $entry : Variant
	var $previous; $digest; $platform : Text
	var $errors : Collection
	var CLI_LastErrors : Collection
	$result:=New object("ok"; False; "failureKind"; "asset"; "error"; New object("code"; "asset_mismatch"; "message"; "Missing or mismatched verified CLI asset metadata"))
	If (Not($metadata.exists))
		return
	End if
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	$lock:=JSON Parse($metadata.getText())
	$digest:=Lowercase(Generate digest($binary.getContent(); SHA256 digest))
	ON ERR CALL($previous; ek local)
	$errors:=CLI_LastErrors
	CLI_LastErrors:=Null
	If (($errors#Null) | (Value type($lock)#Is object))
		$result.error.details:=$errors
		return
	End if
	If ((Value type($lock.assets)#Is object) | (Value type($lock.version)#Is text) | (Value type($lock.source_revision)#Is text))
		return
	End if
	If (Not(Match regex("^[0-9a-f]{40}$"; $lock.source_revision)))
		return
	End if
	$platform:="macos"
	If (Is Windows)
		$platform:="windows"
	End if
	$entry:=$lock.assets[$platform]
	If (Value type($entry)#Is object)
		return
	End if
	If (Value type($entry.binary_sha256)#Is text)
		return
	End if
	If ($entry.binary_sha256#$digest)
		return
	End if
	$result:=New object("ok"; True; "version"; $lock.version)

Function _argumentError($message : Text)->$result : Object
	$result:=New object("ok"; False; "failureKind"; "argument"; "error"; New object("code"; "invalid_argument"; "message"; $message))

Function _path($value : Variant)->$result : Object
	var $path : Text
	Case of
		: (Value type($value)=Is text)
			$path:=$value
		: (Value type($value)=Is object)
			If (Not(OB Instance of($value; 4D.File)))
				return This._argumentError("Paths must be Text or File")
			End if
			$path:=File($value.platformPath; fk platform path).path
			If (Is Windows)
				$path:=$value.platformPath
			End if
		Else
			return This._argumentError("Paths must be Text or File")
	End case
	If (($path="") | (Position(Char(0); $path; *)>0))
		return This._argumentError("Paths must be nonempty and contain no NUL")
	End if
	$result:=New object("ok"; True; "path"; $path)

Function _arguments($command : Text; $input : Variant; $output : Variant; $options : Variant)->$result : Object
	var $args; $allowed; $flags; $numbers; $texts : Collection
	var $key; $text : Text
	var $value : Variant
	var $path : Object
	$allowed:=New collection("container"; "max-input-bytes"; "max-pixels"; "max-decoded-bytes"; "max-operations"; "max-work")
	$flags:=New collection("data-fork"; "overwrite")
	$numbers:=New collection("max-input-bytes"; "max-pixels"; "max-decoded-bytes"; "max-operations"; "max-work"; "width"; "height"; "resource-id"; "dpi")
	$texts:=New collection("container"; "format"; "fidelity"; "printer-comments"; "vector-policy"; "background"; "highlight")
	If (($command="inspect") | ($command="convert"))
		$allowed.push("resource-id"; "data-fork")
	End if
	If ($command="convert")
		$allowed.push("format"; "fidelity"; "printer-comments"; "vector-policy"; "width"; "height"; "dpi"; "background"; "highlight"; "font-map"; "overwrite")
	End if
	If (New collection("inspect"; "convert"; "list-pictures"; "list-fonts").indexOf($command)<0)
		return This._argumentError("Unsupported operation")
	End if
	$path:=This._path($input)
	If (Not($path.ok))
		return $path
	End if
	$args:=New collection($command; "--input"; $path.path)
	If ($command="convert")
		$path:=This._path($output)
		If (Not($path.ok))
			return $path
		End if
		$args.push("--output"; $path.path)
	End if
	If (($options=Null) | (Value type($options)=Is undefined))
		return New object("ok"; True; "arguments"; $args)
	End if
	If (Value type($options)#Is object)
		return This._argumentError("Options must be an Object")
	End if
	For each ($key; OB Keys($options))
		If ($allowed.indexOf($key)<0)
			return This._argumentError("Unsupported option for "+$command+": "+$key)
		End if
		$value:=$options[$key]
		Case of
			: ($flags.indexOf($key)>=0)
				If (Value type($value)#Is boolean)
					return This._argumentError($key+" must be Boolean")
				End if
				If ($value)
					$args.push("--"+$key)
				End if
			: ($key="font-map")
				$path:=This._path($value)
				If (Not($path.ok))
					return $path
				End if
				$args.push("--"+$key; $path.path)
			: ($numbers.indexOf($key)>=0)
				Case of
					: (Value type($value)=Is text)
						$text:=$value
					: ((Value type($value)=Is real) | (Value type($value)=Is longint))
						$text:=JSON Stringify($value)
					Else
						return This._argumentError($key+" must be a Number or decimal Text")
				End case
				If ($key="dpi")
					If (Not(Match regex("^[+]?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$"; $text)))
						return This._argumentError("dpi must be finite decimal Text or Number")
					End if
				Else
					If (Not(Match regex("^-?[0-9]+$"; $text)))
						return This._argumentError($key+" must be an integer")
					End if
				End if
				$args.push("--"+$key; $text)
			: ($texts.indexOf($key)>=0)
				If (Value type($value)#Is text)
					return This._argumentError($key+" must be Text")
				End if
				If (Position(Char(0); $value; *)>0)
					return This._argumentError("NUL is not permitted in options")
				End if
				$args.push("--"+$key; $value)
		End case
	End for each
	$result:=New object("ok"; True; "arguments"; $args)

Function _protocolError($result : Object; $message : Text)->$decoded : Object
	$result.ok:=False
	$result.failureKind:="protocol"
	$result.error:=New object("code"; "invalid_protocol"; "message"; $message)
	$decoded:=$result

Function _diagnostics($value : Variant)->$valid : Boolean
	var $item : Variant
	$valid:=False
	If (Value type($value)#Is collection)
		return
	End if
	For each ($item; $value)
		If (Value type($item)#Is object)
			return
		End if
		If ((Value type($item.code)#Is text) | (Value type($item.message)#Is text))
			return
		End if
	End for each
	$valid:=True

Function _decode($result : Object; $command : Text)->$decoded : Object
	var $payload : Variant
	var $previous; $stream; $field; $expectedCode : Text
	var $parseErrors : Collection
	var CLI_LastErrors : Collection
	var $conversionFailure : Boolean
	$conversionFailure:=False
	If (Not($result.ok))
		If ($result.error.code#"cli_error")
			$result.failureKind:="process"
			return $result
		End if
		$conversionFailure:=True
	End if
	If ((Value type($result.stdout)#Is text) | (Value type($result.stderr)#Is text))
		return This._protocolError($result; "CLI streams must be Text")
	End if
	$stream:=$result.stdout
	If ($conversionFailure)
		$stream:=$result.stderr
		If ($result.stdout#"")
			return This._protocolError($result; "Converter failures must have empty stdout")
		End if
	Else
		If (($result.stderr#"") | ($result.exitCode#0))
			return This._protocolError($result; "Success requires exit zero and empty stderr")
		End if
	End if
	If (Not(Match regex("^[^\r\n]+\n$"; $stream)))
		return This._protocolError($result; "CLI response must be one JSON line ending in LF")
	End if
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	$payload:=JSON Parse($stream)
	ON ERR CALL($previous; ek local)
	$parseErrors:=CLI_LastErrors
	CLI_LastErrors:=Null
	If (($parseErrors#Null) | (Value type($payload)#Is object))
		return This._protocolError($result; "CLI response must be a JSON object")
	End if
	If ((Value type($payload.protocol)#Is real) & (Value type($payload.protocol)#Is longint))
		return This._protocolError($result; "Unsupported CLI protocol version")
	End if
	If ($payload.protocol#1)
		return This._protocolError($result; "Unsupported CLI protocol version")
	End if
	If ($conversionFailure)
		If (Value type($payload.error)#Is object)
			return This._protocolError($result; "Missing converter error")
		End if
		If ((Value type($payload.error.code)#Is text) | (Value type($payload.error.message)#Is text))
			return This._protocolError($result; "Invalid converter error")
		End if
		Case of
			: ($result.exitCode=2)
				$expectedCode:="invalid_arguments"
			: ($result.exitCode=3)
				If (New collection("io"; "output_exists"; "output_conflict").indexOf($payload.error.code)>=0)
					$expectedCode:=$payload.error.code
				End if
			: ($result.exitCode=4)
				$expectedCode:="malformed"
			: ($result.exitCode=5)
				$expectedCode:="unsupported"
			: ($result.exitCode=6)
				$expectedCode:="resource_limit"
			: ($result.exitCode=7)
				$expectedCode:="encoding"
		End case
		If (($expectedCode="") | ($payload.error.code#$expectedCode))
			return This._protocolError($result; "Converter status and error code disagree")
		End if
		$result.failureKind:="converter"
		$result.error:=$payload.error
		$result.value:=$payload
		return $result
	End if
	If (OB Is defined($payload; "error"))
		return This._protocolError($result; "Success cannot contain an error")
	End if
	Case of
		: ($command="version")
			If (Value type($payload.version)#Is text)
				return This._protocolError($result; "Missing CLI version")
			End if
		: ($command="capabilities")
			If ((Value type($payload.version)#Is text) | (Value type($payload.formats)#Is collection) | (Value type($payload.containers)#Is collection) | (Value type($payload.fidelity)#Is object))
				return This._protocolError($result; "Invalid capabilities")
			End if
		: (($command="list-pictures") | ($command="list-fonts"))
			If (Value type($payload.inventory)#Is object)
				return This._protocolError($result; "Missing inventory")
			End if
			$field:="pictures"
			If ($command="list-fonts")
				$field:="resources"
			End if
			If ((Value type($payload.inventory.container)#Is text) | (Value type($payload.inventory[$field])#Is collection))
				return This._protocolError($result; "Invalid inventory")
			End if
		: ($command="inspect")
			If (Value type($payload.inspection)#Is object)
				return This._protocolError($result; "Missing inspection")
			End if
			If ((Value type($payload.inspection.operations)#Is collection) | Not(This._diagnostics($payload.inspection.diagnostics)))
				return This._protocolError($result; "Invalid inspection")
			End if
		: ($command="convert")
			For each ($field; New collection("output"; "format"; "sha256"; "input_sha256"))
				If (Value type($payload[$field])#Is text)
					return This._protocolError($result; "Missing conversion field: "+$field)
				End if
			End for each
			For each ($field; New collection("width"; "height"; "bytes"; "dpi"))
				If ((Value type($payload[$field])#Is real) & (Value type($payload[$field])#Is longint))
					return This._protocolError($result; "Invalid conversion field: "+$field)
				End if
				If ($payload[$field]<=0)
					return This._protocolError($result; "Nonpositive conversion field: "+$field)
				End if
			End for each
			If ((New collection("png"; "svg"; "pdf").indexOf($payload.format)<0) | Not(Match regex("^[0-9a-f]{64}$"; $payload.sha256)) | Not(Match regex("^[0-9a-f]{64}$"; $payload.input_sha256)) | Not(This._diagnostics($payload.diagnostics)))
				return This._protocolError($result; "Invalid conversion metadata")
			End if
			If ($payload.diagnostics.query("code = :1"; "unverified_fidelity").length=0)
				return This._protocolError($result; "Missing fidelity diagnostic")
			End if
		Else
			return This._protocolError($result; "Unknown response operation")
	End case
	$result.value:=$payload
	$decoded:=$result
