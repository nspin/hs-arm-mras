module Main (main) where

import Values
import ReadLogic

import ARM.MRAS

import Language.Haskell.Exts
import System.Directory
import System.Environment
import System.Exit
import System.FilePath
import System.IO


main :: IO ()
main = do
    args <- getArgs
    case args of
        [inDir, outDir] -> generate inDir outDir
        _ -> die $ "Usage: gen-harm-tables <inDir> <outDir>"

test :: IO ()
test = generate "../harm-tables/src/Harm/Tables/Logic" "."


generate :: FilePath -> FilePath -> IO ()
generate inDir outDir = do
    createDirectoryIfMissing True basePath
    logic <- (++)
        <$> withFile (inDir </> "Base.hs") ReadMode readLogic
        <*> withFile (inDir </> "FpSimd.hs") ReadMode readLogic
    let out builder name = writeFile (pathOf name) . prettyPrint $
            Module () (Just head) exts
                [basicImport ("Harm.Tables.Internal." ++ name)]
                (builder logic)
              where
                head = ModuleHead () (ModuleName () ("Harm.Tables.Gen." ++ name)) Nothing Nothing
                exts = [LanguagePragma () (map (Ident ()) ["DataKinds"])]
    out modInsn "Insn"
    out modDecode "Decode"
    out modEncode "Encode"
    out modParse "Parse"
    out modShow "Show"
  where
    basePath = outDir </> "gen" </> "Harm" </> "Tables" </> "Gen"
    pathOf name = basePath </> name <.> ".hs"


modInsn :: Logic -> [Decl ()]
modInsn logic = [ty] ++ tys ++ fns ++ [eidFnSig, eidFnVal]
  where
    ty = buildType "Insn" [ (mnem, [h mnem]) | mnem <- bigTy ] ["Eq", "Read", "Show"]
    tys = [ buildType mnem [ (eid, tys) | (eid, tys) <- encs ] ["Eq", "Read", "Show"]
          | (mnem, encs) <- littleTys logic
          ]
    h = TyCon () . UnQual () . Ident ()
    fns = concat
        [ [ TypeSig () [Ident () (lower eid)]
                (foldr (TyFun ()) (TyCon () (UnQual () (Ident () "Insn"))) ts)
          , FunBind ()
                [ Match () (Ident () (lower eid))
                    [ PVar () (Ident () ('x':show i)) | i <- [1..length ts] ]
                    (UnGuardedRhs ()
                        (App ()
                            (Con () (UnQual () (Ident () mnem)))
                            (foldl (App ()) 
                                (Con () (UnQual () (Ident () eid)))
                                [ Var () (UnQual () (Ident () ('x':show i))) | i <- [1..length ts] ])))
                    Nothing
                ]
          ]
        | (mnem, eid, ts) <- littleFns logic
        ]
    eidFnSig = TypeSig () [Ident () "encodingId"]
        (TyFun ()
            (TyCon () (UnQual () (Ident () "Insn")))
            (TyCon () (UnQual () (Ident () "String"))))
    eidFnVal = FunBind ()
        [ Match () (Ident () "encodingId") [PVar () (Ident () "insn")]
            (UnGuardedRhs ()
                (Case ()
                    (Var () (UnQual () (Ident () "insn")))
                    [ Alt ()
                        (PApp ()
                            (UnQual () (Ident () mnem))
                            [PApp ()
                                (UnQual () (Ident () eid))
                                (replicate nargs (PWildCard ()))])
                        (UnGuardedRhs ()
                            (Lit () (String () eid eid)))
                        Nothing
                    | (mnem, eid, nargs, _, _) <- encodeFn logic
                    ]))
            Nothing
        ]

modDecode :: Logic -> [Decl ()]
modDecode logic = [sig, val] ++ fns
  where
    sig = TypeSig () [Ident () "decodeTable"]
        (TyList ()
            (TyTuple () Boxed
                [ TyCon () (UnQual () (Ident () "Pattern"))
                , TyFun ()
                    (TyCon () (UnQual () (Ident () "Word32")))
                    (TyApp ()
                        (TyCon () (UnQual () (Ident () "Decode")))
                        (TyCon () (UnQual () (Ident () "Insn"))))
                ]))
    val = FunBind ()
        [ Match () (Ident () "decodeTable") []
            (UnGuardedRhs ()
                (List () elems))
            Nothing
        ]
    elems =
        [ Tuple () Boxed
            [ () <$ fromParseResult (parseExp (show patt))
            , App ()
                (Var () (UnQual () (Ident () ("decode_inner_" ++ gid))))
                (Con () (UnQual () (Ident () (lower eid))))
            ]
        | (patt, gid, eid) <- decodeTable logic
        ]
    fns = concat
        [ [ TypeSig () [Ident () ("decode_inner_" ++ gid)]
                (TyFun ()
                    (foldr (TyFun ())
                        (TyCon () (UnQual () (Ident () "Insn")))
                        tys)
                    (TyFun ()
                        (TyCon () (UnQual () (Ident () "Word32")))
                        (TyApp ()
                            (TyCon () (UnQual () (Ident () "Decode")))
                            (TyCon () (UnQual () (Ident () "Insn"))))))
          , FunBind ()
                [ Match () (Ident () ("decode_inner_" ++ gid))
                    [ PVar () (Ident () "f")
                    , PVar () (Ident () "w")
                    ]
                    (UnGuardedRhs ()
                        (foldl (App ()) 
                            (App ()
                                (Var () (UnQual () (Ident () ("decode_" ++ gid))))
                                (Var () (UnQual () (Ident () "f"))))
                            exps))
                    Nothing
                ]
          ]
        | (gid, tys, exps) <- decodeFns logic
        ]

modEncode :: Logic -> [Decl ()]
modEncode logic = [sig, val] ++ fns
  where
    sig = TypeSig () [Ident () "encode"]
        (TyFun ()
            (TyCon () (UnQual () (Ident () "Insn")))
            (TyApp ()
                (TyCon () (UnQual () (Ident () "Encode")))
                (TyCon () (UnQual () (Ident () "Word32")))))
    val = FunBind ()
        [ Match () (Ident () "encode") [PVar () (Ident () "insn")]
            (UnGuardedRhs ()
                (Case ()
                    (Var () (UnQual () (Ident () "insn")))
                    [ Alt ()
                        (PApp ()
                            (UnQual () (Ident () mnem))
                            [PApp ()
                                (UnQual () (Ident () eid))
                                [ PVar () (Ident () ('x':show i)) | i <- [1..nargs] ]])
                        (UnGuardedRhs ()
                            (foldl
                                (App ())
                                (App ()
                                    (Var () (UnQual () (Ident () ("encode_" ++ gid))))
                                    (App ()
                                        (Var () (UnQual () (Ident () ("encode_inner_" ++ gid))))
                                        (Lit () (Int () (toInteger spec) (show spec)))))
                                [ Var () (UnQual () (Ident () ('x':show i))) | i <- [1..nargs] ]))
                        Nothing
                    | (mnem, eid, nargs, gid, spec) <- encodeFn logic
                    ]))
            Nothing
        ]
    fns = concat
        [ [ TypeSig () [Ident () ("encode_inner_" ++ gid)]
                (TyFun ()
                    (TyCon () (UnQual () (Ident () "Word32")))
                    (TyApp ()
                        (TyApp ()
                            (TyCon () (UnQual () (Ident () "FnW")))
                            (TyCon () (UnQual () (Ident () ("Binary_" ++ gid)))))
                        (TyCon () (UnQual () (Ident () "Word32")))))
          , FunBind ()
                [ Match () (Ident () ("encode_inner_" ++ gid))
                    ( PVar () (Ident () "w")
                    : [ PVar () (Ident () ('x':show i)) | i <- [1..nargs] ]
                    )
                    (UnGuardedRhs () body)
                    Nothing
                ]
          ]
        | (gid, nargs, body) <- encodeFns logic
        ]

modParse :: Logic -> [Decl ()]
modParse logic = [sig, val]
  where
    sig = TypeSig () [Ident () "parseTable"]
        (TyList () (TyTuple () Boxed
            [ TyCon () (UnQual () (Ident () "String"))
            , (TyApp ()
                (TyCon () (UnQual () (Ident () "Parser")))
                (TyCon () (UnQual () (Ident () "Insn"))))
            ]))
    val = FunBind ()
        [ Match () (Ident () "parseTable") []
            (UnGuardedRhs () (List () elems))
            Nothing
        ]
    elems =
        [ Tuple () Boxed
            [ (Lit () (String () mnem mnem))
            , App ()
                (Var () (UnQual () (Ident () ("parse_" ++ gid))))
                (Var () (UnQual () (Ident () (lower eid))))
            ]
        | (mnem, eid, gid) <- parseTable logic
        ]

modShow :: Logic -> [Decl ()]
modShow logic = [sig, val]
  where
    sig = TypeSig () [Ident () "showAsm"]
        (TyFun ()
            (TyCon () (UnQual () (Ident () "Insn")))
            (TyTuple () Boxed
                [ TyCon () (UnQual () (Ident () "String"))
                , TyCon () (UnQual () (Ident () "String"))
                ]))
    val = FunBind ()
        [ Match () (Ident () "showAsm") [PVar () (Ident () "insn")]
            (UnGuardedRhs ()
                (Case ()
                    (Var () (UnQual () (Ident () "insn")))
                    [ Alt ()
                        (PApp ()
                            (UnQual () (Ident () mnem))
                            [PApp ()
                                (UnQual () (Ident () eid))
                                [ PVar () (Ident () ('x':show i)) | i <- [1..nargs] ]])
                        (UnGuardedRhs ()
                            (App ()
                                (App ()
                                    (Var () (UnQual () (Ident () "withMnem")))
                                    (Lit () (String () (lower mnem) (lower mnem))))
                                (foldl
                                    (App ())
                                    (Var () (UnQual () (Ident () ("show_" ++ gid))))
                                    [ Var () (UnQual () (Ident () ('x':show i))) | i <- [1..nargs] ])))
                        Nothing
                    | (mnem, eid, nargs, gid, _) <- encodeFn logic
                    ]))
            Nothing
        ]


basicImport :: String -> ImportDecl ()
basicImport name = ImportDecl
    { importAnn = ()
    , importModule = ModuleName () name
    , importQualified = False
    , importSrc = False
    , importSafe = False
    , importPkg = Nothing
    , importAs = Nothing
    , importSpecs = Nothing
    }

buildType :: String -> [(String, [Type ()])] -> [String] -> Decl ()
buildType name vals deriv = DataDecl () (DataType ()) Nothing
    (DHead () (Ident () name))
    (map f vals)
    (Just (Deriving () (map g deriv)))
  where
    f (cons, args) = QualConDecl () Nothing Nothing (ConDecl () (Ident () cons) args)
    g cl = IRule () Nothing Nothing (IHCon () (UnQual () (Ident () cl)))
