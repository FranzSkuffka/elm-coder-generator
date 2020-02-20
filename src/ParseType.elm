module ParseType exposing
    ( extractAll
    , extractAllWithDefs
    , extractBasic
    , grabRawTypes
    , grabTypeDefs

    -- exposed for testing only
    , typeOf
    , extractHelp
    )
    
import AnonymousTypes exposing (grabAnonymousTypes)
import Destructuring exposing 
    ( bracketIfSpaced
    , civilize
    , debracket
    , decomment
    , derecord
    , detuple
    , deunion
    , dropWord
    , regex
    , replaceColons
    , removeNothings
    , removeStringLiterals
    , singleLine
    )
import List exposing (filter, map)
import String exposing (dropRight, join, trim, words)
import Types exposing (RawType, Type(..), TypeDef)
import List.Extra
import Generate.Type
import Dict
import Graph


anonymousType : Type -> TypeDef
anonymousType a =
    { name = replaceColons <| Generate.Type.nick a, theType = a }


anonymousTypes : Bool -> List TypeDef -> List TypeDef
anonymousTypes encoding typeList =
    map anonymousType <| grabAnonymousTypes encoding typeList


extractAll : Bool -> String -> List TypeDef
extractAll encoding txt =
    let            
        (declared, anonymous) =
            extractHelp encoding txt
    in
    filter (not << Types.isExtensible) (declared ++ anonymous)


--includes type defs for anonymous types, like the record inside this:
    -- type Role = User { name : String, email: String }
extractAllWithDefs : Bool -> String -> { topLevel : List TypeDef, anonymous : List (List String), toLazify : List String}
extractAllWithDefs encoding txt =
    let
        ( declared, anonymous ) =
            extractHelp encoding txt
        adjacencies : List (Graph.VertexAndAdjacencies String)
        adjacencies =
            declared ++ anonymous
            |> List.map (\type_ -> (type_.name , Graph.dependencies type_) )

        toBreak = Graph.breakingVertices adjacencies

        nonEmptyRecord a =
            Types.isRecord a && not (Types.isEmptyRecord a)

        needToDefine =
            filter nonEmptyRecord anonymous
                ++ filter Types.isNonemptyExtended (declared ++ anonymous)

        filtered =
            filter (not << Types.isExtensible) (declared ++ anonymous)
    in
    { topLevel = filtered, anonymous = Generate.Type.aliasDefinitions needToDefine, toLazify = toBreak}

--ignore anonymous tyoes
extractBasic : Bool -> String -> List TypeDef
extractBasic encoding txt =
    let
        declared =
            grabTypeDefs txt
    in
    map (detectExtendedRecord declared) declared



{-| Help the extractor do it's thing

    import Types exposing (RawType, Type(..), TypeDef)

    extractHelp True "type Either a b = Left a | Right b"
    --> ([{ name = "Either", theType = TypeUnion [("Left",[TypeImported "a"]),("Right",[TypeImported "b"])] }],[])

    extractHelp True "type Parent a = ParentOf (Parent a)"
    --> ([{ name = "Parent", theType = TypeProduct ("ParentOf",[TypeProduct ("(Parent",[TypeImported "a)"])]) }],[])
-}
extractHelp : Bool -> String -> ( List TypeDef, List TypeDef )
extractHelp encoding txt =
    let
        scannedDeclared =
            extractBasic encoding txt

        anonymous =
            anonymousTypes encoding scannedDeclared
    in
    ( scannedDeclared, anonymous )

{-|

    grabTypeDefs : "type alias B = Int"
    --> []

-}
grabTypeDefs : String -> List TypeDef
grabTypeDefs txt =
    let
        toTypeDef a =
            { name = a.name, theType = typeOf a.extensible a.def }
        rawTypes = grabRawTypes txt

    in
    map toTypeDef <| rawTypes



grabRawType : List (Maybe String) -> Maybe RawType
grabRawType submatches =
    case submatches of
        (Just a) :: (Just b) :: _ ->
            case String.words (trim a) of
                x :: y :: _ ->
                    -- means that the name is something like "LineSegment a", i.e. an extensible record
                    Just { name = x, def = trim <| singleLine b, extensible = True }

                x :: _ ->
                    Just { name = x, def = trim <| singleLine b, extensible = False }

                [] ->
                    Nothing

        _ ->
            Nothing


{-| parse a type definition

    import Types exposing (RawType, Type(..), TypeDef)

    grabRawTypes "type Either a b = Left a | Right b"
    --> [{ def = "Left a | Right b", extensible = True, name = "Either" }]
-}
grabRawTypes : String -> List RawType
grabRawTypes txt =
    removeStringLiterals txt
    |> decomment
    |> regex typeRegex
    |> map .submatches
    |> map grabRawType
    |> removeNothings


typeRegex =
    "type\\s+(?:alias\\s+)?([\\w_]+[\\w_\\s]*)=([\\w(){},|.:_ \\r\\n]+)(?=(?:\\r\\w|\\n\\w)|$)"



--== Recognize types ==--


{-| parse a type definition without name

    import Types exposing (RawType, Type(..), TypeDef)

    typeOf False "List String" --> TypeList TypeString
    typeOf False "MyType | String" --> TypeUnion [("MyType",[]),("String",[])]
    typeOf False "MyType" --> TypeImported "MyType"
    typeOf False "String" --> TypeString
    typeOf False "{age : Int}" --> TypeRecord [{ name = "age", theType = TypeInt }]
    typeOf True "{generic : generic}" --> TypeExtensible [{ name = "generic", theType = TypeImported "generic" }]
    typeOf False "(String, Int)" --> TypeTuple [TypeString, TypeInt]
    typeOf False "(String, Int, Bool)" --> TypeTuple [TypeString, TypeInt, TypeBool]
-}
typeOf : Bool -> String -> Type
typeOf extensible def =
    let
        subType x =
            typeOf False x
    in
    case detuple def of
        a :: bs ->
            TypeTuple <| map subType (a :: bs)

        [] ->
            case derecord def of
                ( a1, a2 ) :: bs ->
                    let
                        makeField ( x, y ) =
                            TypeDef x (subType y)

                        fields =
                            case a1 == "" of
                                True ->
                                    []

                                False ->
                                    map makeField (( a1, a2 ) :: bs)
                    in
                    case extensible of
                        True ->
                            TypeExtensible fields

                        False ->
                            TypeRecord fields

                [] ->
                    case words (debracket def) of
                        [] ->
                            TypeError "Type conversion error: empty string"

                        a :: bs ->
                            case a of
                                "Array" ->
                                    TypeArray (subType <| dropWord a <| debracket def)

                                "Bool" ->
                                    TypeBool

                                "Dict" ->
                                    case deunion (debracket def) of
                                        ( _, c :: d :: es ) :: fs ->
                                            TypeDict ( subType c, subType d )

                                        _ ->
                                            TypeError "Error parsing def as a Dict"

                                "Dict.Dict" ->
                                    case deunion (debracket def) of
                                        ( _, c :: d :: es ) :: fs ->
                                            TypeDict ( subType c, subType d )

                                        _ ->
                                            TypeError "Error parsing def as a Dict"

                                "Float" ->
                                    TypeFloat

                                "Int" ->
                                    TypeInt

                                "List" ->
                                    TypeList (subType <| dropWord a <| debracket def)

                                "Maybe" ->
                                    TypeMaybe (subType <| dropWord a <| debracket def)

                                "String" ->
                                    TypeString

                                _ ->
                                    let
                                        constructor ( x, y ) =
                                            case y of
                                                [ "" ] ->
                                                    ( x, [] )

                                                _ ->
                                                    ( x, map subType y )
                                    in
                                    case deunion def of
                                        ( x, y ) :: [] ->
                                            case y of
                                                [ "" ] ->
                                                    TypeImported x

                                                _ ->
                                                    TypeProduct ( x, map subType y )

                                        c :: ds ->
                                            TypeUnion <| map constructor (c :: ds)

                                        [] ->
                                            TypeError "Union type conversion error: empty"


--== Extensible records ==--


detectExtendedRecord : List TypeDef -> TypeDef -> TypeDef
detectExtendedRecord declaredTypes input =
    let
        newType =
            detectExtendedRecordHelp declaredTypes [] input.theType
    in
    { input | theType = newType }


detectExtendedRecordHelp : List TypeDef -> List TypeDef -> Type -> Type
detectExtendedRecordHelp declaredTypes fieldsSoFar input =
    let
        extensiblesFor a =
            extensibleFields declaredTypes a

        recursion a b =
            detectExtendedRecordHelp declaredTypes a b

        lookAt a =
            detectExtendedRecordHelp declaredTypes [] a

        lookInto a =
            detectExtendedRecord declaredTypes a
    in
    case input of
        TypeArray ofType ->
            TypeArray (lookAt ofType)

        TypeDict ( key, val ) ->
            TypeDict ( key, lookAt val )

        TypeExtendedRecord fields ->
            TypeExtendedRecord (map lookInto fields)

        TypeExtensible fields ->
            TypeExtensible (map lookInto fields)

        TypeList ofType ->
            TypeList (lookAt ofType)

        TypeMaybe ofType ->
            TypeMaybe (lookAt ofType)

        TypeProduct ( constructor, [ subType ] ) ->
            case extensiblesFor constructor of
                Just extensibles ->
                    case subType of
                        TypeRecord newFields ->
                            TypeExtendedRecord (fieldsSoFar ++ map lookInto (extensibles ++ newFields))

                        TypeProduct _ ->
                            recursion (fieldsSoFar ++ extensibles) subType

                        _ ->
                            input

                Nothing ->
                    input

        TypeRecord newFields ->
            case fieldsSoFar of
                [] ->
                    TypeRecord (map lookInto newFields)

                _ ->
                    TypeExtendedRecord (fieldsSoFar ++ map lookInto newFields)

        TypeTuple typeList ->
            TypeTuple (map lookAt typeList)

        TypeUnion list ->
            let
                mapper ( constructor, subTypes ) =
                    ( constructor, map lookAt subTypes )
            in
            TypeUnion (map mapper list)

        _ ->
            input


extensibleFields : List TypeDef -> String -> Maybe (List TypeDef)
extensibleFields allTypDefs name =
    let
        candidate x =
            x.name == name
    in
    case List.filter candidate allTypDefs of
        x :: _ ->
            case x.theType of
                TypeExtensible fields ->
                    Just fields

                _ ->
                    Nothing

        [] ->
            Nothing
