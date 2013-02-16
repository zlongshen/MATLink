(* :Title: MATLink *)
(* :Context: MATLink` *)
(* :Authors:
	R. Menon (rsmenon@icloud.com)
	Sz. Horvát (szhorvat@gmail.com)
*)
(* :Package Version: 0.1 *)
(* :Mathematica Version: 9.0 *)

BeginPackage["MATLink`"]

ConnectMATLAB::usage = "Establish connection with the MATLAB engine"
DisconnectMATLAB::usage = "Close connection with the MATLAB engine"
OpenMATLAB::usage = "Open MATLAB workspace"
CloseMATLAB::usage = "Close MATLAB workspace"
MGet::usage = "Import MATLAB variable into Mathematica."
MSet::usage = "Define variable in MATLAB workspace."
MEvaluate::usage = "Evaluates a valid MATLAB expression"
MScript::usage = "Create a MATLAB script file"
MFunction::usage = "Create a link to a MATLAB function for use from Mathematica."
$ReturnLogicalsAs0And1::usage = "If set to True, MATLAB logicals will be returned as 0 or 1, and True or False otherwise."
$DefaultMATLABDirectory::usage = ""
mcell::usage = ""

Begin["`Developer`"]
$ApplicationDirectory = DirectoryName@$InputFileName;
$mEngineSourceDirectory = FileNameJoin[{$ApplicationDirectory, "mEngine","src"}];
$DefaultMATLABDirectory = "/Applications/MATLAB_R2012b.app/";

CompileMEngine[] :=
	Block[{dir = Directory[]},
		SetDirectory[$mEngineSourceDirectory];
		PrintTemporary["Compiling mEngine from source...\n"];
		Run["make"];
		DeleteFile@FileNames@"*.o";
		Run["mv mEngine ../"];
		SetDirectory@dir
	]

CleanupTemporaryDirectories[] :=
	Module[{},
		DeleteDirectory[#, DeleteContents -> True] & /@ FileNames@FileNameJoin[{$TemporaryDirectory,"MATLink*"}];
	]

End[]

Begin["`Private`"]
AppendTo[$ContextPath, "MATLink`Developer`"];

(* Directories and helper functions/variables *)
mEngineBinaryExistsQ[] := FileExistsQ@FileNameJoin[{$ApplicationDirectory, "mEngine", "mEngine"}];

If[!TrueQ[MATLABInstalledQ[]],
	MATLABInstalledQ[] = False;
	$openLink = {};
	$sessionID = "";
	$temporaryVariablePrefix = "";
	$sessionTemporaryDirectory = "";,

	General::needs = "MATLink is already loaded. Remember to use Needs instead of Get.";
	Message[General::needs]
]

mEngineLinkQ[LinkObject[link_String, _, _]] := ! StringFreeQ[link, "mEngine.sh"];

cleanupOldLinks[] :=
	Module[{},
		LinkClose /@ Select[Links[], mEngineLinkQ];
		MATLABInstalledQ[] = False;
	]

MScriptQ[name_String] /; MATLABInstalledQ[] :=
	FileExistsQ[FileNameJoin[{$sessionTemporaryDirectory, name <> ".m"}]]

convertToMATLAB[expr_] :=
	Which[
		ArrayQ[expr, _, NumericQ], Transpose[
			expr, Range@ArrayDepth@expr /. {k___, i_, j_} :> {i, j}~Join~Reverse@{k}],
		True, expr
	]

randomString[n_Integer:50] :=
	StringJoin@RandomSample[Join[#, ToLowerCase@#] &@CharacterRange["A", "Z"], n]

mLintErrorFreeQ[cmd_String] :=
	Module[
		{
			file = MScript[randomString[], cmd],
			config = FileNameJoin[{$ApplicationDirectory, "Kernel","MLintErrors.txt"}],
			result
		},
		eval@ToString@StringForm[
			"`1` = checkcode('`2`','-id','-config=`3`')",
			First@file, file["AbsolutePath"],config
		];
		result = List@@MGet@First@file;
		eval@ToString@StringForm["clear `1`", First@file];
		DeleteFile@file["AbsolutePath"];
		If[result =!= {}, MATLink`DataTypes`MException["message" /. Flatten@result], True]
	]

(* Common error messages *)
General::wspo = "The MATLAB workspace is already open."
General::wspc = "The MATLAB workspace is already closed."
General::engo = "There is an existing connection to the MATLAB engine."
General::engc = "Not connected to the MATLAB engine."
General::nofn = "The `1` \"`2`\" does not exist."
General::owrt = "An `1` by that name already exists. Use \"Overwrite\" \[Rule] True to overwrite."

(* Connect/Disconnect MATLAB engine *)
ConnectMATLAB[] /; mEngineBinaryExistsQ[] && !MATLABInstalledQ[] :=
	Module[{},
		cleanupOldLinks[];
		$openLink = Install@FileNameJoin[{$ApplicationDirectory, "mEngine", "mEngine.sh"}];
		$sessionID = StringJoin[
			 IntegerString[{Most@DateList[]}, 10, 2],
			 IntegerString[List @@ Rest@$openLink]
		];
		$temporaryVariablePrefix = "MATLink" <> $sessionID;
		$sessionTemporaryDirectory = FileNameJoin[{$TemporaryDirectory, "MATLink" <> $sessionID}];
		CreateDirectory@$sessionTemporaryDirectory;
		MATLABInstalledQ[] = True;
	]
ConnectMATLAB[] /; mEngineBinaryExistsQ[] && MATLABInstalledQ[] := Message[ConnectMATLAB::engo]
ConnectMATLAB[] /; !mEngineBinaryExistsQ[] :=
	Module[{},
		CompileMEngine[];
		ConnectMATLAB[];
	]

DisconnectMATLAB[] /; MATLABInstalledQ[] :=
	Module[{},
		LinkClose@$openLink;
		$openLink = {};
		DeleteDirectory[$sessionTemporaryDirectory, DeleteContents -> True];
		MATLABInstalledQ[] = False;
	]
DisconnectMATLAB[] /; !MATLABInstalledQ[] := Message[DisconnectMATLAB::engc]

(* Open/Close MATLAB Workspace *)
OpenMATLAB[] /; MATLABInstalledQ[] := openEngine[] /; !engineOpenQ[];
OpenMATLAB[] /; MATLABInstalledQ[] := Message[OpenMATLAB::wspo] /; engineOpenQ[];
OpenMATLAB[] /; !MATLABInstalledQ[] :=
	Module[{},
		ConnectMATLAB[];
		OpenMATLAB[];
		MEvaluate["addpath('" <> $sessionTemporaryDirectory <> "')"];
	]

CloseMATLAB[] /; MATLABInstalledQ[] := closeEngine[] /; engineOpenQ[] ;
CloseMATLAB[] /; MATLABInstalledQ[] := Message[CloseMATLAB::wspc] /; !engineOpenQ[];
CloseMATLAB[] /; !MATLABInstalledQ[] := Message[CloseMATLAB::engc];

(*  High-level commands *)
$ReturnLogicalsAs0And1 = False;

SyntaxInformation[MGet] = {"ArgumentsPattern" -> {_}};
SetAttributes[MGet,Listable]
MGet[var_String] /; MATLABInstalledQ[] :=
	convertToMathematica@get[var] /; engineOpenQ[]
MGet[_String] /; MATLABInstalledQ[] := Message[MGet::wspc] /; !engineOpenQ[]
MGet[_String] /; !MATLABInstalledQ[] := Message[MGet::engc]

SyntaxInformation[MSet] = {"ArgumentsPattern" -> {_, _}};
MSet[var_String, expr_] /; MATLABInstalledQ[] :=
	set[var, convertToMATLAB@expr] /; engineOpenQ[]
MSet[___] /; MATLABInstalledQ[] := Message[MSet::wspc] /; !engineOpenQ[]
MSet[___] /; !MATLABInstalledQ[] := Message[MSet::engc]

SyntaxInformation[MEvaluate] = {"ArgumentsPattern" -> {_}};
MEvaluate[cmd_String] /; MATLABInstalledQ[] :=
	Module[{result, error, id = randomString[]},
		If[
			TrueQ[error = mLintErrorFreeQ@cmd],
			result = eval@StringJoin["
				try
					", cmd, "
				catch ex
					sprintf('%s%s%s', '", id, "', ex.getReport,'", id, "')
				end
			"],
			error
		];
		If[StringFreeQ[result,id],
			StringReplace[result, StartOfString~~">> " -> ""],
			First@StringCases[result, __ ~~ id ~~ x__ ~~ id ~~ ___ :> MATLink`DataTypes`MException@x]
		]
	] /; engineOpenQ[]
MEvaluate[MScript[name_String]] /; MATLABInstalledQ[] && MScriptQ[name] :=
	eval[name] /; engineOpenQ[]
MEvaluate[MScript[name_String]] /; MATLABInstalledQ[] && !MScriptQ[name] :=
	Message[MEvaluate::nofn,"MScript", name]
MEvaluate[___] /; MATLABInstalledQ[] := Message[MEvaluate::wspc] /; !engineOpenQ[]
MEvaluate[___] /; !MATLABInstalledQ[] := Message[MEvaluate::engc]

Options[MScript] = {"Overwrite" -> False};
MScript[name_String, cmd_String, OptionsPattern[]] /; MATLABInstalledQ[] :=
	Module[{file},
		file = OpenWrite[FileNameJoin[{$sessionTemporaryDirectory, name <> ".m"}]];
		WriteString[file, cmd];
		Close[file];
		MScript[name]
	] /; (!MScriptQ[name] || OptionValue["Overwrite"])
MScript[name_String, cmd_String, OptionsPattern[]] /; MATLABInstalledQ[] :=
	Message[MScript::owrt, "MScript"] /; MScriptQ[name] && !OptionValue["Overwrite"]
MScript[name_String, cmd_String, OptionsPattern[]] /; !MATLABInstalledQ[] := Message[MScript::engc]
MScript[name_String]["AbsolutePath"] /; MScriptQ[name] :=
	FileNameJoin[{$sessionTemporaryDirectory, name <> ".m"}]

Options[MFunction] = {"Output" -> True, "OutputArguments" -> 1};
MFunction[name_String, OptionsPattern[]][args___] /; MATLABInstalledQ[] :=
	Module[{nIn = Length[{args}], nOut = OptionValue["OutputArguments"], vars, output},
		vars = Table[ToString@Unique[$temporaryVariablePrefix], {nIn + nOut}];
		Thread[MSet[vars[[;;nIn]], {args}]];
		MEvaluate[StringJoin["[", Riffle[vars[[-nOut;;]], ","], "]=", name, "(", Riffle[vars[[;;nIn]], ","], ")"]];
		output = MGet /@ vars[[-nOut;;]];
		MEvaluate[StringJoin["clear ", Riffle[vars, " "]]];
		If[nOut == 1, First@output, output]
	] /; OptionValue["Output"]
MFunction[name_String, OptionsPattern[]][args___] /; MATLABInstalledQ[] :=
	With[{vars = Table[ToString@Unique[$temporaryVariablePrefix], {Length[{args}]}]},
		Thread[MSet[vars, {args}]];
		MEvaluate[StringJoin[name, "(", Riffle[vars, ","], ")"]];
		MEvaluate[StringJoin["clear ", Riffle[vars, " "]]];
	] /; !OptionValue["Output"]

MFunction[name_String, OptionsPattern[]][args___] /; MATLABInstalledQ[] := Message[MFunction::wspc] /; !engineOpenQ[]
MFunction[name_String, OptionsPattern[]][args___] /; !MATLABInstalledQ[] := Message[MFunction::engc]

mcell[] :=
	Module[{},
		CellPrint@Cell[
			TextData[""],
			"Program",
			Evaluatable->True,
			CellEvaluationFunction -> (MEvaluate[ToString@#]&),
			CellFrameLabels -> {{None,"MATLAB"},{None,None}}
		];
		SelectionMove[EvaluationNotebook[], All, EvaluationCell];
		NotebookDelete[];
		SelectionMove[EvaluationNotebook[], Next, CellContents]
	]

End[]

(* Low level functions strongly tied with the C code are part of this context *)
Begin["`mEngine`"]
AppendTo[$ContextPath, "MATLink`Private`"]
Needs["MATLink`DataTypes`"]

(* Assign to symbols defined in `Private` *)
engineOpenQ[] /; MATLABInstalledQ[] := engIsOpen[]
engineOpenQ[] /; !MATLABInstalledQ[] := (Message[engineOpenQ::engc];False)
openEngine = engOpen;
closeEngine = engClose;
eval = engCmd;
get = engGet;
set = engSet;

engGet::unimpl = "Translating the MATLAB type \"`1`\" is not supported"

(* The following mat* heads are inert and indicate the type of the MATLAB data returned
   by mEngine. Evaluation is only allowed inside the convertToMathematica
   function, which converts it to their final Mathematica form.  engGet[] will always return
   either $Failed, or an expression wrapped in one of the below heads.
   Note that structs and cells may contain subxpressions of other types.
*)

convertToMathematica[expr_] :=
	With[
		{
			reshape = Switch[#2,
				{_,1}, #[[All, 1]],
				_, Transpose[#, Reverse@Range@ArrayDepth@#]
			]&,
			listToArray = First@Fold[Partition, #, Reverse[#2]]&
		},
		Block[{matCell,matArray,matStruct,matSparseArray,matLogical,matString,matUnknown},

			matCell[list_, dim_] := MCell@@ listToArray[list,dim] ~reshape~ dim;
			matStruct[list_, dim_] := MStruct@@ listToArray[list,dim] ~reshape~ dim;
			matSparseArray[jc_, ir_, vals_, dims_] := Transpose@SparseArray[Automatic, dims, 0, {1, {jc, List /@ ir + 1}, vals}];

			matLogical[list_, dim_] := matLogical[list ~reshape~ dim];
			matLogical[list_] /; $ReturnLogicalsAs0And1 := list;
			matLogical[list_] /; !$ReturnLogicalsAs0And1 := list /. {1 -> True, 0 -> False};

			matArray[list_, {1,1}] := list[[1,1]];
			matArray[list_, dim_] := list ~reshape~ dim;
			matString[str_] := str;
			matUnknown[u_] := (Message[engGet::unimpl, u]; $Failed);

			expr
		]
	]

End[]

EndPackage[]
